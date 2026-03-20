# Claude Island v2 — 主窗口 + 全局监控 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为 Claude Island 添加主窗口（双模式：我的会话 + 全局监控）、CLI 子进程通信、SQLite 持久化、HTTP Hook Server、会话导入和接管功能。

**Architecture:** 主窗口使用标准 NSWindow + SwiftUI，通过 CLI 子进程 (`claude -p --output-format stream-json`) 与 Claude Code 通信。Hook 系统从 Unix Socket + Python 切换为 HTTP Server + Bash 脚本（参考 Masko）。数据使用 SQLite 持久化。Notch 和 Hook Monitor 均可通过开关控制。

**Tech Stack:** Swift/SwiftUI, AppKit (NSWindow + NSPanel), SQLite (直接使用 sqlite3 C API), NWListener (HTTP Server), Process (CLI 子进程)

**参考项目：**
- [CodePilot](https://github.com/op7418/CodePilot) — Electron+Next.js Claude GUI，使用 Claude Agent SDK + SQLite
- [Masko Code](https://github.com/RousselPaul/masko-code) — Swift 原生，HTTP Hook Server + Bash 脚本

---

## Phase 1: 基础设施 — SQLite 数据库

### Task 1.1: SQLite 数据库管理器

**Files:**
- Create: `ClaudeIsland/Database/DatabaseManager.swift`

**说明：** 使用 macOS 自带的 `sqlite3` C API（无需第三方依赖），创建数据库管理器。

**Schema 设计**（5 张表）：

```sql
-- 项目/文件夹
CREATE TABLE projects (
    id TEXT PRIMARY KEY,           -- UUID
    name TEXT NOT NULL,            -- 项目名（如 "katana-server"）
    path TEXT NOT NULL UNIQUE,     -- 工作目录绝对路径
    created_at REAL NOT NULL,      -- Unix timestamp
    updated_at REAL NOT NULL
);

-- 会话/线程
CREATE TABLE threads (
    id TEXT PRIMARY KEY,           -- UUID（对应 claude session_id）
    project_id TEXT NOT NULL REFERENCES projects(id),
    title TEXT,                    -- 会话标题（首条消息摘要）
    source TEXT NOT NULL DEFAULT 'app',  -- 'app' | 'imported' | 'takeover'
    cli_session_id TEXT,           -- Claude CLI 的 session_id（用于 --resume）
    git_branch TEXT,               -- 当前 Git 分支
    status TEXT NOT NULL DEFAULT 'idle', -- idle/active/ended
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);

-- 消息
CREATE TABLE messages (
    id TEXT PRIMARY KEY,           -- UUID
    thread_id TEXT NOT NULL REFERENCES threads(id),
    role TEXT NOT NULL,            -- 'user' | 'assistant' | 'system'
    content TEXT NOT NULL,         -- JSON 格式（支持多种 block）
    thinking TEXT,                 -- thinking 内容
    tool_name TEXT,                -- 工具名（如有）
    tool_input TEXT,               -- 工具输入 JSON
    tool_result TEXT,              -- 工具结果 JSON
    cost_usd REAL,                -- 本条消息费用
    tokens_in INTEGER,
    tokens_out INTEGER,
    created_at REAL NOT NULL
);

-- 应用设置
CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- 导入记录（避免重复导入）
CREATE TABLE import_history (
    cli_session_id TEXT PRIMARY KEY,
    imported_at REAL NOT NULL,
    thread_id TEXT REFERENCES threads(id)
);
```

**Step 1:** 创建 `DatabaseManager.swift`，包含：
- `init()` — 在 `~/.claude-island/` 创建 `data.db`，启用 WAL 模式
- `migrate()` — 执行建表 SQL
- 基础 CRUD 方法：`insertProject`, `insertThread`, `insertMessage`, `fetchThreads`, `fetchMessages`

**Step 2:** 验证数据库创建和迁移正常

**Step 3:** Commit: `feat: add SQLite database manager with schema`

---

### Task 1.2: 数据模型

**Files:**
- Create: `ClaudeIsland/Database/DBModels.swift`

**说明：** 定义 Swift 层面的数据模型，与 SQLite 表一一对应。

```swift
struct DBProject: Identifiable, Equatable {
    let id: String
    var name: String
    var path: String
    var createdAt: Date
    var updatedAt: Date
}

struct DBThread: Identifiable, Equatable {
    let id: String
    var projectId: String
    var title: String?
    var source: ThreadSource
    var cliSessionId: String?
    var gitBranch: String?
    var status: ThreadStatus
    var createdAt: Date
    var updatedAt: Date
    
    enum ThreadSource: String { case app, imported, takeover }
    enum ThreadStatus: String { case idle, active, ended }
}

struct DBMessage: Identifiable, Equatable {
    let id: String
    var threadId: String
    var role: MessageRole
    var content: String
    var thinking: String?
    var toolName: String?
    var toolInput: String?
    var toolResult: String?
    var costUsd: Double?
    var tokensIn: Int?
    var tokensOut: Int?
    var createdAt: Date
    
    enum MessageRole: String { case user, assistant, system }
}
```

**Step 1:** 创建模型文件
**Step 2:** Commit: `feat: add database models`

---

## Phase 2: HTTP Hook Server（替换 Unix Socket）

### Task 2.1: 本地 HTTP Server

**Files:**
- Create: `ClaudeIsland/Services/Hooks/LocalHTTPServer.swift`
- Modify: `ClaudeIsland/Core/Settings.swift` — 添加 hookMonitorEnabled, serverPort 设置

**说明：** 参考 Masko 的 `LocalServer.swift`，使用 `NWListener` 实现 HTTP 服务器。

核心端点：
- `GET /health` — 健康检查（Hook 脚本用来快速判断 App 是否在运行）
- `POST /hook` — 接收 Hook 事件 JSON
  - 非权限事件：200 OK + 关闭连接
  - PermissionRequest：保持连接等待用户决策

端口策略：从 49152 开始，失败则 +1，最多试 10 个端口。

**Step 1:** 实现 `LocalHTTPServer`
**Step 2:** 在 `Settings.swift` 添加 `hookMonitorEnabled` 和 `serverPort`
**Step 3:** 验证 Server 能启动并响应 health check
**Step 4:** Commit: `feat: add local HTTP server for hook events`

---

### Task 2.2: Bash Hook 脚本

**Files:**
- Create: `ClaudeIsland/Resources/hook-sender.sh`
- Modify: `ClaudeIsland/Services/Hooks/HookInstaller.swift` — 改为 Bash 脚本 + HTTP

**说明：** 替换 Python 脚本为 Bash（参考 Masko 的 hook-sender.sh）。

脚本核心逻辑：
1. `curl GET /health` 检查 App 是否运行，不运行立刻退出
2. 读取 stdin JSON
3. 进程树遍历获取 terminal_pid、shell_pid
4. PermissionRequest → 阻塞等待 curl 响应
5. 其他事件 → fire-and-forget curl POST

**Step 1:** 创建 `hook-sender.sh` 脚本
**Step 2:** 更新 `HookInstaller.swift`，改为安装 Bash 脚本到 `~/.claude-island/hooks/`
**Step 3:** 添加 install/uninstall 与 Hook Monitor 开关联动
**Step 4:** Commit: `feat: switch hook system to bash + HTTP`

---

### Task 2.3: 整合 Hook 事件处理

**Files:**
- Modify: `ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift`
- Modify: `ClaudeIsland/Services/State/SessionStore.swift`

**说明：** 将 `ClaudeSessionMonitor.startMonitoring()` 从 `HookSocketServer` 切换到 `LocalHTTPServer`。保持 `SessionStore` 的事件处理逻辑不变。

**Step 1:** 修改 `ClaudeSessionMonitor` 使用 `LocalHTTPServer`
**Step 2:** 确保现有 Notch 功能正常工作
**Step 3:** Commit: `refactor: connect session monitor to HTTP server`

---

## Phase 3: CLI 子进程通信

### Task 3.1: CLI Stream Parser

**Files:**
- Create: `ClaudeIsland/CLI/CLIStreamParser.swift`

**说明：** 解析 `claude -p --output-format stream-json --verbose` 的流式输出。

每行是一个 JSON 对象，类型包括：
```json
{"type": "assistant", "message": {"content": [{"type": "thinking", "thinking": "..."}]}, "session_id": "..."}
{"type": "assistant", "message": {"content": [{"type": "text", "text": "..."}]}, "session_id": "..."}
{"type": "result", "subtype": "success", "result": "...", "session_id": "...", "total_cost_usd": 0.14}
```

```swift
enum CLIStreamEvent {
    case thinking(String)
    case text(String)
    case toolUse(name: String, input: [String: Any])
    case toolResult(name: String, result: String)
    case result(CLIResult)
    case error(String)
}

struct CLIResult {
    let sessionId: String
    let result: String
    let costUsd: Double
    let tokensIn: Int
    let tokensOut: Int
    let durationMs: Int
}
```

**Step 1:** 实现 `CLIStreamParser`，逐行解析 JSON
**Step 2:** Commit: `feat: add CLI stream JSON parser`

---

### Task 3.2: CLI Session Manager

**Files:**
- Create: `ClaudeIsland/CLI/CLISessionManager.swift`

**说明：** 管理 Claude CLI 子进程的生命周期。

```swift
actor CLISessionManager {
    // 启动新会话
    func startSession(cwd: String, prompt: String) async -> String  // returns threadId
    
    // 在现有会话中发送消息
    func sendMessage(threadId: String, message: String) async
    
    // 接管 CLI 会话
    func takeoverSession(cliSessionId: String, cwd: String) async -> String
    
    // 停止会话
    func stopSession(threadId: String) async
    
    // 中断当前处理
    func interruptSession(threadId: String) async
}
```

核心实现：
- 使用 `Process()` 启动 `claude` 命令
- 参数：`-p --output-format stream-json --verbose --input-format stream-json`
- 接管时：添加 `--resume <session_id>`
- stdout → `CLIStreamParser` → 消息事件 → SQLite 持久化 + UI 更新
- stdin ← 用户输入（stream-json 格式）

**Step 1:** 实现进程启动、stdout 读取、stdin 写入
**Step 2:** 实现 `--resume` 接管逻辑
**Step 3:** 实现进程中断和清理
**Step 4:** Commit: `feat: add CLI session manager`

---

## Phase 4: 主窗口 UI

### Task 4.1: 主窗口控制器

**Files:**
- Create: `ClaudeIsland/MainWindow/MainWindowController.swift`
- Modify: `ClaudeIsland/App/AppDelegate.swift` — 启动时创建主窗口，改激活策略

**说明：** 创建标准 NSWindow，SwiftUI 内容。

关键改变：
- `NSApplication.setActivationPolicy(.regular)` — 显示 Dock 图标
- 去掉 `LSUIElement = true`（或根据设置动态切换）
- 主窗口 `minSize: 900x600`

**Step 1:** 创建 `MainWindowController`
**Step 2:** 修改 `AppDelegate`，启动时显示主窗口
**Step 3:** Commit: `feat: add main window controller`

---

### Task 4.2: 侧边栏视图

**Files:**
- Create: `ClaudeIsland/MainWindow/Views/SidebarView.swift`
- Create: `ClaudeIsland/MainWindow/Views/ThreadRowView.swift`
- Create: `ClaudeIsland/MainWindow/ViewModels/SidebarViewModel.swift`

**说明：** 侧边栏包含模式切换、搜索框、项目分组的会话列表。

UI 结构：
```
┌──────────────────────┐
│ [💬 我的会话|🌐 全局]  │  ← SegmentedControl 模式切换
│                      │
│ + New Conversation   │  ← 仅「我的会话」模式显示
│ 🔍 Search sessions   │
│ 📥 Import from CLI   │
│                      │
│ ── THREADS ──────── │
│ ▼ 📁 katana-server   │
│   💬 New Chat    1m  │  ← ThreadRowView
│   💬 Fix bug     3h  │
│ ▼ 📁 claude-island   │
│   💬 Docs        4h  │
│                      │
│ ── ──────────────── │
│ ⚙ Settings           │
└──────────────────────┘
```

**Step 1:** 创建 `SidebarViewModel` — 数据加载、搜索过滤、模式切换
**Step 2:** 创建 `ThreadRowView` — 单条会话行（标题、时间、状态指示器）
**Step 3:** 创建 `SidebarView` — 组合所有元素
**Step 4:** Commit: `feat: add sidebar view with dual mode`

---

### Task 4.3: 聊天内容视图

**Files:**
- Create: `ClaudeIsland/MainWindow/Views/ChatContentView.swift`
- Create: `ClaudeIsland/MainWindow/Views/MessageBubbleView.swift`
- Create: `ClaudeIsland/MainWindow/Views/MessageInputView.swift`
- Create: `ClaudeIsland/MainWindow/Views/WelcomeView.swift`
- Create: `ClaudeIsland/MainWindow/ViewModels/ChatViewModel.swift`

**说明：** 聊天主内容区。

```
┌──────────────────────────────────┐
│  New Chat ✏ / katana-server      │  ← 标题栏 + Git 分支
│  🔀 feat/KAT-1085...            │
├──────────────────────────────────┤
│                                  │
│  ┌─ User ────────────────────┐  │
│  │ 帮我修复这个 bug           │  │
│  └───────────────────────────┘  │
│                                  │
│  ┌─ Assistant ───────────────┐  │
│  │ 💭 thinking...             │  │ ← 可折叠
│  │ 我来分析一下...             │  │
│  │ 🔧 Read: src/main.swift   │  │ ← 工具调用
│  └───────────────────────────┘  │
│                                  │
├──────────────────────────────────┤
│  Message Claude...               │  ← 输入框
│  [+] [⚡] [>_] Default ▼ High ▼ │  ← 工具栏
│                             [→]  │  ← 发送按钮
└──────────────────────────────────┘
```

**Step 1:** 创建 `WelcomeView` — 空状态页
**Step 2:** 创建 `MessageBubbleView` — 消息气泡（支持 text/thinking/tool）
**Step 3:** 创建 `MessageInputView` — 输入框 + 工具栏
**Step 4:** 创建 `ChatViewModel` — 消息加载、发送、流式渲染
**Step 5:** 创建 `ChatContentView` — 组合所有元素
**Step 6:** Commit: `feat: add chat content view`

---

### Task 4.4: 设置面板

**Files:**
- Create: `ClaudeIsland/MainWindow/Views/SettingsView.swift`
- Modify: `ClaudeIsland/Core/Settings.swift` — 添加新设置项

**说明：** 设置面板包含三个核心开关。

```
🏝️ Dynamic Island (Notch)     [ON/OFF]
🌐 Hook Monitor                [ON/OFF]
🔔 Notification Sound          [Pop ▼]
🖥️ Notch Screen                [Built-in ▼]
```

开关联动逻辑：
- Notch ON → 创建 NotchWindow，OFF → 销毁
- Hook Monitor ON → 安装 Hook + 启动 HTTP Server，OFF → 卸载 + 停止

**Step 1:** 扩展 `Settings.swift` 添加 `notchEnabled`, `hookMonitorEnabled`
**Step 2:** 创建 `SettingsView`
**Step 3:** 实现开关联动逻辑
**Step 4:** Commit: `feat: add settings panel with toggles`

---

## Phase 5: 导入和接管

### Task 5.1: CLI 会话扫描器

**Files:**
- Create: `ClaudeIsland/CLI/CLISessionScanner.swift`

**说明：** 扫描 `~/.claude/projects/` 目录，发现可导入的会话。

提取信息：项目名、JSONL 路径、消息数、文件大小、最后修改时间、首条消息摘要、Git 分支（从项目 `.git/HEAD` 读取）、Claude 版本。

**Step 1:** 实现目录扫描和 JSONL 元数据提取
**Step 2:** Commit: `feat: add CLI session scanner`

---

### Task 5.2: 导入对话框

**Files:**
- Create: `ClaudeIsland/MainWindow/Views/ImportSessionView.swift`

**说明：** 模态弹窗，显示可导入的会话列表。

包含：搜索框、会话卡片（项目名、Git 分支徽章、首条消息、路径、消息数、时间、大小、版本）、Import 按钮。

导入流程：选择会话 → 解析 JSONL → 创建 Project + Thread + Messages → 写入 SQLite。

**Step 1:** 创建 ImportSessionView UI
**Step 2:** 实现导入逻辑（JSONL 解析 + SQLite 写入）
**Step 3:** Commit: `feat: add import session dialog`

---

### Task 5.3: 会话接管

**Files:**
- Modify: `ClaudeIsland/CLI/CLISessionManager.swift` — 添加 `takeoverSession`
- Modify: `ClaudeIsland/MainWindow/ViewModels/SidebarViewModel.swift` — 添加接管按钮

**说明：** 从「全局监控」接管到「我的会话」。

接管条件：会话状态为 `waitingForInput` 或 `ended`。

流程：
1. 用户点击 [▶ 继续对话]
2. 创建新 Thread（source = 'takeover'，cli_session_id = 原 session_id）
3. 导入历史消息到 SQLite
4. 启动 CLI 子进程 `claude --resume <session_id> -p --output-format stream-json`
5. 切换到「我的会话」模式

**Step 1:** 实现接管逻辑
**Step 2:** 添加 UI 按钮和状态判断
**Step 3:** Commit: `feat: add session takeover from global monitor`

---

## Phase 6: 整合与优化

### Task 6.1: App 生命周期整合

**Files:**
- Modify: `ClaudeIsland/App/AppDelegate.swift`
- Modify: `ClaudeIsland/App/ClaudeIslandApp.swift`

**说明：** 整合所有模块的启动顺序。

启动顺序：
1. 单实例检查
2. 初始化 SQLite 数据库
3. 创建主窗口
4. 如果 Notch 开关 ON → 创建 NotchWindow
5. 如果 Hook Monitor ON → 安装 Hook + 启动 HTTP Server
6. 检查更新

**Step 1:** 重构 AppDelegate 启动流程
**Step 2:** 添加 Dock 图标 / accessory 模式切换
**Step 3:** Commit: `refactor: integrate main window into app lifecycle`

---

### Task 6.2: Notch ↔ 主窗口联动

**Files:**
- Modify: `ClaudeIsland/Core/NotchViewModel.swift`
- Modify: `ClaudeIsland/UI/Views/NotchView.swift`

**说明：** Notch 点击可打开主窗口对应会话。主窗口设置可控制 Notch。

**Step 1:** 实现 Notch 点击 → 主窗口跳转
**Step 2:** 实现设置面板 Notch 开关
**Step 3:** Commit: `feat: connect notch and main window`

---

## 实施阶段（推荐顺序）

| 阶段 | 内容 | 预估工作量 |
|------|------|-----------|
| **Phase 1** | SQLite 数据库 | 1-2 天 |
| **Phase 2** | HTTP Hook Server + Bash 脚本 | 2-3 天 |
| **Phase 3** | CLI 子进程通信 | 2-3 天 |
| **Phase 4** | 主窗口 UI | 3-5 天 |
| **Phase 5** | 导入和接管 | 2-3 天 |
| **Phase 6** | 整合与优化 | 2-3 天 |
| **合计** | | **12-19 天** |

---

## 文件清单总览

### 新建文件（~20 个）

```
ClaudeIsland/
├── Database/
│   ├── DatabaseManager.swift          ← SQLite 管理器
│   └── DBModels.swift                 ← 数据模型
├── CLI/
│   ├── CLISessionManager.swift        ← CLI 子进程生命周期
│   ├── CLIStreamParser.swift          ← stream-json 解析器
│   └── CLISessionScanner.swift        ← ~/.claude/projects/ 扫描
├── MainWindow/
│   ├── MainWindowController.swift     ← NSWindow 控制器
│   ├── Views/
│   │   ├── SidebarView.swift          ← 侧边栏
│   │   ├── ThreadRowView.swift        ← 会话行
│   │   ├── ChatContentView.swift      ← 聊天主区域
│   │   ├── MessageBubbleView.swift    ← 消息气泡
│   │   ├── MessageInputView.swift     ← 输入框
│   │   ├── WelcomeView.swift          ← 空状态页
│   │   ├── ImportSessionView.swift    ← 导入对话框
│   │   └── SettingsView.swift         ← 设置面板
│   └── ViewModels/
│       ├── SidebarViewModel.swift     ← 侧边栏逻辑
│       └── ChatViewModel.swift        ← 聊天逻辑
├── Services/Hooks/
│   └── LocalHTTPServer.swift          ← HTTP 服务器
└── Resources/
    └── hook-sender.sh                 ← Bash Hook 脚本
```

### 修改文件（~6 个）

```
ClaudeIsland/App/AppDelegate.swift           ← 启动流程
ClaudeIsland/App/ClaudeIslandApp.swift       ← 激活策略
ClaudeIsland/Core/Settings.swift             ← 新设置项
ClaudeIsland/Core/NotchViewModel.swift       ← Notch 开关
ClaudeIsland/Services/Hooks/HookInstaller.swift  ← Bash 脚本安装
ClaudeIsland/Services/Session/ClaudeSessionMonitor.swift  ← HTTP 切换
```
