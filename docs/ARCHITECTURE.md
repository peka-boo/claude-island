# Claude Island - 系统架构文档

> 本文档详细描述 Claude Island 的整体架构设计、核心模块、数据流和关键设计决策。

## 目录

- [项目概述](#项目概述)
- [系统架构图](#系统架构图)
- [模块分层](#模块分层)
- [核心数据流](#核心数据流)
- [会话状态机](#会话状态机)
- [Hook 通信机制](#hook-通信机制)
- [窗口系统](#窗口系统)
- [关键设计决策](#关键设计决策)
- [第三方依赖](#第三方依赖)

---

## 项目概述

Claude Island 是一款 macOS 菜单栏应用，将 **Dynamic Island 风格的通知** 带到 Claude Code CLI 会话中。它通过 Claude Code 的 Hooks 系统与 CLI 实时通信，在 MacBook 的 Notch（刘海）区域展示会话状态、权限请求和聊天历史。

### 核心特性
- **Notch UI** — 从 MacBook 刘海区域展开的动态覆盖层
- **实时会话监控** — 同时跟踪多个 Claude Code 会话
- **权限审批** — 直接从 Notch 批准或拒绝工具执行
- **聊天历史** — 支持 Markdown 渲染的完整对话历史
- **自动安装** — 首次启动时自动安装 Hooks

### 系统要求
- macOS 15.6+
- Claude Code CLI

---

## 系统架构图

```
┌─────────────────────────────────────────────────────────┐
│                    Claude Island App                     │
├─────────────┬───────────────────────────┬───────────────┤
│   UI 层     │       Core 层             │   Services 层  │
│             │                           │               │
│ NotchView   │  NotchViewModel           │ SessionStore   │
│ ChatView    │  NotchGeometry            │ HookSocket     │
│ InstancesV  │  NotchActivityCoordinator │ HookInstaller  │
│ MenuView    │  ScreenSelector           │ ConversationP  │
│ Components  │  Settings                 │ ClaudeSession  │
│             │                           │ TmuxController │
├─────────────┴───────────────────────────┴───────────────┤
│                      Models 层                           │
│  SessionState  SessionPhase  SessionEvent  ChatMessage  │
│  ToolResultData  TmuxTarget                              │
├─────────────────────────────────────────────────────────┤
│               App 层 (应用入口与生命周期)                  │
│  ClaudeIslandApp  AppDelegate  WindowManager             │
└─────────────────────────────────────────────────────────┘
       │                    ▲
       │  Unix Socket       │  Hook Events (JSON)
       ▼                    │
┌─────────────────────────────────────────────────────────┐
│              claude-island-state.py (Hook 脚本)          │
│  安装在 ~/.claude/hooks/                                 │
│  接收 Claude Code 事件 → 转发到 Unix Socket              │
│  处理 PermissionRequest → 等待用户决策 → 返回结果         │
└─────────────────────────────────────────────────────────┘
       │                    ▲
       │  stdin/stdout      │  Hook Protocol
       ▼                    │
┌─────────────────────────────────────────────────────────┐
│                   Claude Code CLI                        │
│  触发 Hooks: UserPromptSubmit, PreToolUse, PostToolUse   │
│  PermissionRequest, Stop, Notification, Session*         │
└─────────────────────────────────────────────────────────┘
```

---

## 模块分层

### App 层 (`ClaudeIsland/App/`)

应用入口和生命周期管理：

| 文件 | 职责 |
|------|------|
| `ClaudeIslandApp.swift` | SwiftUI 应用入口，使用 `@NSApplicationDelegateAdaptor` |
| `AppDelegate.swift` | 核心初始化：单实例保障、Hook 安装、Mixpanel 分析、Sparkle 更新 |
| `WindowManager.swift` | Notch 窗口的创建与重建（屏幕切换时） |
| `ScreenObserver.swift` | 监听屏幕配置变化（外接显示器等） |

**关键设计点：**
- 使用 `NSApplication.setActivationPolicy(.accessory)` 隐藏 Dock 图标
- `LSUIElement = true`（在 Info.plist 中）确保应用不出现在应用切换器中
- 通过 `ensureSingleInstance()` 防止多实例运行

### Core 层 (`ClaudeIsland/Core/`)

Notch 核心逻辑和状态管理：

| 文件 | 职责 |
|------|------|
| `NotchViewModel.swift` | Notch 状态机（closed/opened/popping）、鼠标事件处理、悬停/点击逻辑 |
| `NotchGeometry.swift` | Notch 几何计算：命中检测、面板位置、屏幕坐标转换 |
| `NotchActivityCoordinator.swift` | 活动指示器状态管理（处理中/空闲） |
| `ScreenSelector.swift` | 多屏幕选择逻辑，支持内建屏和外接屏 |
| `SoundSelector.swift` | 通知音效选择 |
| `Settings.swift` | 应用设置（通知音等），使用 UserDefaults |
| `Ext+NSScreen.swift` | NSScreen 扩展：Notch 尺寸检测、内建屏幕判断 |

### Models 层 (`ClaudeIsland/Models/`)

纯数据模型和类型定义：

| 文件 | 职责 |
|------|------|
| `SessionState.swift` | 会话的完整状态模型（单一来源 of truth），包含 `ToolTracker`、`SubagentState` |
| `SessionPhase.swift` | 会话状态机枚举和转换规则验证 |
| `SessionEvent.swift` | 事件定义，所有状态变更通过 `SessionStore.process(event)` |
| `ChatMessage.swift` | 对话消息模型：`ChatMessage`、`MessageBlock`、`ToolUseBlock` |
| `ToolResultData.swift` | 工具执行结果的结构化模型（20+ 工具类型） |
| `TmuxTarget.swift` | Tmux 会话目标匹配 |

### Services 层 (`ClaudeIsland/Services/`)

业务逻辑和系统集成：

#### State (`Services/State/`)
| 文件 | 职责 |
|------|------|
| `SessionStore.swift` | **核心：** Swift Actor，所有状态变更的唯一入口，事件驱动的状态管理 |
| `ToolEventProcessor.swift` | 工具事件处理和状态更新 |
| `FileSyncScheduler.swift` | JSONL 文件同步调度 |

#### Hooks (`Services/Hooks/`)
| 文件 | 职责 |
|------|------|
| `HookSocketServer.swift` | Unix Domain Socket 服务器，接收 Hook 事件，管理权限请求队列 |
| `HookInstaller.swift` | Hook 脚本和 `settings.json` 的自动安装/卸载 |

#### Session (`Services/Session/`)
| 文件 | 职责 |
|------|------|
| `ClaudeSessionMonitor.swift` | MainActor 包装器，桥接 `SessionStore` 和 SwiftUI |
| `ConversationParser.swift` | JSONL 对话日志解析，提取消息、工具调用、子代理等 |
| `AgentFileWatcher.swift` | 监控代理文件变化 |
| `JSONLInterruptWatcher.swift` | 监控用户中断事件 |

#### Shared (`Services/Shared/`)
| 文件 | 职责 |
|------|------|
| `ProcessExecutor.swift` | 外部进程执行器 |
| `ProcessTreeBuilder.swift` | 进程树构建，用于 Tmux 检测 |
| `TerminalAppRegistry.swift` | 终端应用注册表 |

#### Tmux (`Services/Tmux/`)
| 文件 | 职责 |
|------|------|
| `TmuxController.swift` | Tmux 命令执行 |
| `TmuxPathFinder.swift` | Tmux 可执行文件路径查找 |
| `TmuxSessionMatcher.swift` | 会话匹配逻辑 |
| `TmuxTargetFinder.swift` | 目标窗格查找 |
| `ToolApprovalHandler.swift` | 通过 Tmux 发送按键审批工具 |

#### Window (`Services/Window/`)
| 文件 | 职责 |
|------|------|
| `WindowFinder.swift` | 查找特定窗口（用于焦点检测） |
| `WindowFocuser.swift` | 窗口聚焦控制 |
| `YabaiController.swift` | Yabai 窗口管理器集成 |

#### Chat (`Services/Chat/`)
| 文件 | 职责 |
|------|------|
| `ChatHistoryManager.swift` | 聊天历史管理 |

#### Update (`Services/Update/`)
| 文件 | 职责 |
|------|------|
| `NotchUserDriver.swift` | Sparkle 更新 SDK 的自定义 UI 驱动 |

### UI 层 (`ClaudeIsland/UI/`)

#### Views (`UI/Views/`)
| 文件 | 职责 |
|------|------|
| `NotchView.swift` | **主视图：** 完整的 Notch UI，状态切换、活动指示器、悬停/弹跳动画 |
| `NotchHeaderView.swift` | 顶部头部栏 |
| `ClaudeInstancesView.swift` | 会话实例列表视图 |
| `ChatView.swift` | 聊天对话详情视图 |
| `NotchMenuView.swift` | 设置菜单视图 |
| `ToolResultViews.swift` | 工具执行结果的各种展示视图 |

#### Components (`UI/Components/`)
| 文件 | 职责 |
|------|------|
| `NotchShape.swift` | 自定义 Notch 形状（贝塞尔曲线） |
| `ProcessingSpinner.swift` | 处理中旋转动画 |
| `StatusIcons.swift` | 各种状态图标组件 |
| `ActionButton.swift` | 操作按钮组件 |
| `TerminalColors.swift` | 终端风格调色板 |
| `MarkdownRenderer.swift` | Markdown 渲染器 |
| `ScreenPickerRow.swift` | 屏幕选择行 |
| `SoundPickerRow.swift` | 音效选择行 |

#### Window (`UI/Window/`)
| 文件 | 职责 |
|------|------|
| `NotchWindow.swift` | `NSPanel` 子类，透明/置顶/点击穿透窗口 |
| `NotchWindowController.swift` | 窗口控制器，管理窗口生命周期 |
| `NotchViewController.swift` | 视图控制器，桥接 AppKit 和 SwiftUI |

### Utilities 层 (`ClaudeIsland/Utilities/`)

| 文件 | 职责 |
|------|------|
| `MCPToolFormatter.swift` | MCP 工具名称格式化 |
| `SessionPhaseHelpers.swift` | 会话阶段辅助函数 |
| `TerminalVisibilityDetector.swift` | 检测终端窗口是否可见（决定是否播放通知音） |

---

## 核心数据流

### 1. Hook 事件流（实时）

```
Claude Code CLI
    │
    ├─ 触发 Hook 事件 (stdin → claude-island-state.py)
    │
    ├─ Python 脚本解析事件
    │   ├─ 非权限事件: 发送到 Unix Socket → 关闭连接
    │   └─ PermissionRequest: 发送到 Socket → 保持连接等待响应
    │
    ├─ HookSocketServer 接收事件 (GCD DispatchSource)
    │   ├─ 解码 JSON → HookEvent
    │   ├─ PreToolUse: 缓存 tool_use_id（用于关联后续 PermissionRequest）
    │   ├─ PermissionRequest: 保持 socket 打开 → 存入 pendingPermissions
    │   └─ 调用 eventHandler 回调
    │
    ├─ ClaudeSessionMonitor.startMonitoring() 注册回调
    │   └─ 收到事件 → SessionStore.process(.hookReceived(event))
    │
    ├─ SessionStore (actor) 处理事件
    │   ├─ 创建或更新 SessionState
    │   ├─ 验证状态转换合法性 (SessionPhase.canTransition)
    │   ├─ 更新工具追踪器 (ToolTracker)
    │   ├─ 更新子代理状态 (SubagentState)
    │   └─ publishState() → sessionsSubject
    │
    └─ UI 层收到 Combine 更新 → 重新渲染
```

### 2. JSONL 文件同步流（延迟/周期性）

```
Hook 事件触发文件同步
    │
    ├─ SessionStore.scheduleFileSync() (100ms 防抖)
    │
    ├─ ConversationParser.parse()
    │   ├─ 读取 ~/.claude/projects/<project>/<session>.jsonl
    │   ├─ 解析消息、工具调用、工具结果
    │   ├─ 提取 conversationInfo（摘要、最后消息等）
    │   └─ 支持增量解析（记录 offset）
    │
    ├─ SessionStore.process(.fileUpdated(payload))
    │   ├─ 合并新消息到 chatItems
    │   ├─ 处理 /clear 指令（清除旧历史）
    │   ├─ 填充子代理工具信息
    │   └─ 发射工具完成事件
    │
    └─ UI 更新聊天历史
```

### 3. 权限审批流

```
用户点击 Approve / Deny
    │
    ├─ ClaudeSessionMonitor.approvePermission(sessionId:)
    │
    ├─ HookSocketServer.respondToPermission(toolUseId:, decision:)
    │   ├─ 查找 pendingPermissions[toolUseId]
    │   ├─ 编码 HookResponse { decision: "allow", reason: nil }
    │   ├─ 写回到保持打开的 client socket
    │   └─ 关闭 socket
    │
    ├─ Python 脚本收到响应
    │   ├─ decision == "allow" → 输出 {"hookSpecificOutput": ...} → exit(0)
    │   └─ decision == "deny"  → 输出拒绝理由 → exit(0)
    │
    ├─ Claude Code 收到 Hook 输出
    │   ├─ allow → 执行工具
    │   └─ deny  → 跳过工具
    │
    └─ SessionStore.process(.permissionApproved/Denied)
        └─ 更新状态 → 检查是否有其他待审批工具
```

---

## 会话状态机

`SessionPhase` 定义了会话的完整生命周期：

```
                    ┌──────────┐
                    │   idle   │ ◀─── 初始状态
                    └────┬─────┘
                         │
            ┌────────────┼────────────────┐
            ▼            ▼                ▼
     ┌────────────┐ ┌──────────┐ ┌───────────────────┐
     │ processing │ │compacting│ │waitingForApproval  │
     └─────┬──────┘ └────┬─────┘ └────────┬──────────┘
           │              │                │
     ┌─────┼──────┐  ┌───┼────┐    ┌──────┼──────┐
     ▼     ▼      ▼  ▼   ▼    ▼    ▼      ▼      ▼
  idle  waiting waiting idle proc  wait  proc   idle  waiting
        ForInput ForApp         ForInput        ForInput
           │
           ▼
     ┌────────────┐
     │   ended    │ ◀─── 终止状态（不可逆）
     └────────────┘
```

### 状态说明

| 状态 | 说明 | 需用户关注 |
|------|------|------------|
| `idle` | 空闲，等待新活动 | ❌ |
| `processing` | Claude 正在处理（运行工具/生成响应） | ❌ |
| `waitingForInput` | Claude 完成，等待用户输入 | ✅ |
| `waitingForApproval` | 工具等待用户权限审批 | ✅ |
| `compacting` | 上下文正在压缩 | ❌ |
| `ended` | 会话已结束（终止状态） | ❌ |

### 转换验证

所有状态转换都通过 `SessionPhase.canTransition(to:)` 验证合法性。非法转换会被忽略并记录日志。

---

## Hook 通信机制

### 安装流程

```
应用启动
    │
    └─ HookInstaller.installIfNeeded()
        ├─ 创建 ~/.claude/hooks/ 目录
        ├─ 复制 claude-island-state.py 到 hooks 目录
        ├─ 设置执行权限 (0o755)
        └─ 更新 ~/.claude/settings.json
            └─ 注册 9 种 Hook 事件:
                UserPromptSubmit, PreToolUse, PostToolUse,
                PermissionRequest (timeout: 86400),
                Notification, Stop, SubagentStop,
                SessionStart, SessionEnd, PreCompact
```

### Hook 事件类型

| 事件 | 方向 | 说明 |
|------|------|------|
| `UserPromptSubmit` | CLI → App | 用户提交了新的 prompt |
| `PreToolUse` | CLI → App | 工具即将执行（包含 tool_use_id） |
| `PostToolUse` | CLI → App | 工具执行完成 |
| `PermissionRequest` | CLI ↔ App | 工具需要权限（双向通信） |
| `Notification` | CLI → App | 通知事件（如 idle_prompt） |
| `Stop` | CLI → App | Claude 停止处理 |
| `SubagentStop` | CLI → App | 子代理完成 |
| `SessionStart` | CLI → App | 新会话开始 |
| `SessionEnd` | CLI → App | 会话结束 |
| `PreCompact` | CLI → App | 上下文压缩开始 |

### tool_use_id 关联机制

PermissionRequest 事件不总是包含 `tool_use_id`，因此 `HookSocketServer` 实现了一个 FIFO 缓存来关联：

```
PreToolUse (包含 tool_use_id)
    → cacheToolUseId(event)  // 缓存到 "sessionId:toolName:serializedInput" 键

PermissionRequest (可能不含 tool_use_id)
    → popCachedToolUseId(event)  // 从缓存取出对应的 tool_use_id
```

---

## 窗口系统

### NotchPanel (NSPanel 子类)

Claude Island 使用 `NSPanel` 而非 `NSWindow`，获得以下能力：

| 配置 | 值 | 用途 |
|------|-----|------|
| `styleMask` | `.borderless, .nonactivatingPanel` | 无边框、不抢焦点 |
| `isFloatingPanel` | `true` | 浮动面板 |
| `isOpaque` | `false` | 透明窗口 |
| `level` | `.mainMenu + 3` | 高于菜单栏 |
| `collectionBehavior` | `fullScreenAuxiliary, stationary, canJoinAllSpaces, ignoresCycle` | 全空间可见 |
| `ignoresMouseEvents` | `true` | 鼠标事件穿透 |

### 鼠标事件处理

由于窗口设置了 `ignoresMouseEvents = true`，应用使用 **全局事件监控** 来检测 Notch 区域的交互：

1. **EventMonitors** - 全局鼠标事件监控（移动、点击）
2. **NotchViewModel** - 50ms 节流处理鼠标位置
3. **NotchGeometry** - 命中检测（Notch 区域扩展 ±10px/±5px 的容差）
4. **点击穿透** - 面板外点击通过 `CGEvent.post()` 转发到下层窗口

### 动态尺寸

Notch 面板根据内容类型动态调整大小：

| 内容类型 | 宽度 | 高度 |
|----------|------|------|
| 实例列表 | 480px (最大) | 320px |
| 设置菜单 | 480px (最大) | 420px + 展开器高度 |
| 聊天视图 | 600px (最大) | 580px |

---

## 关键设计决策

### 1. 为什么使用 Swift Actor (`SessionStore`)？

`SessionStore` 使用 Swift Actor 而非传统的锁/队列：
- **编译时安全** — Actor 隔离确保所有状态访问都在同一个执行上下文中
- **避免数据竞争** — 无需手动管理 `NSLock` 或 `DispatchQueue`
- **单一入口** — 所有状态变更通过 `process(_:)` 方法，便于调试和追踪

### 2. 为什么使用事件驱动架构 (`SessionEvent`)？

- **可追溯性** — 每个状态变更都有明确的事件来源
- **解耦** — Hook 服务、文件解析器、UI 操作都通过事件与状态交互
- **可扩展** — 添加新的事件类型不影响现有逻辑

### 3. 为什么使用 NSPanel 而非 NSWindow？

- **不抢焦点** — `nonactivatingPanel` 样式不会将焦点从终端窗口抢走
- **浮动行为** — 始终浮在其他窗口之上
- **更好的 UI 体验** — 用户可以在终端中工作的同时与 Notch 交互

### 4. 为什么 Hook 使用 Python 而非 Shell？

- **JSON 处理** — Python 内置 JSON 解析，Shell 需要 `jq` 等外部依赖
- **Socket 通信** — Python 的 `socket` 模块比 Shell 更可靠
- **跨平台兼容** — macOS 预装 Python，无需额外安装

### 5. 为什么使用 Unix Domain Socket 而非 HTTP？

- **低延迟** — 本地进程间通信，无网络开销
- **双向通信** — PermissionRequest 需要保持连接等待响应
- **简单高效** — 无需 HTTP 协议开销

---

## 第三方依赖

| 依赖 | 用途 | 集成方式 |
|------|------|----------|
| **Sparkle** | 应用自动更新（通过 appcast.xml） | Swift Package Manager |
| **Mixpanel** | 匿名使用分析（App Launched, Session Started） | Swift Package Manager |

### 分析数据

Mixpanel 仅收集以下匿名数据：
- 应用版本和构建号
- macOS 版本
- Claude Code 版本
- 新会话启动事件

**不收集**用户对话内容或个人信息。

---

*生成自 Claude Island v1.x 源码分析*
