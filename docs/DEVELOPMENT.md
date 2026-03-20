# Claude Island - 开发指南

> 本文档为 Claude Island 的开发者提供构建、调试和贡献指南。

## 目录

- [环境准备](#环境准备)
- [构建与运行](#构建与运行)
- [项目配置](#项目配置)
- [调试指南](#调试指南)
- [Hook 系统开发](#hook-系统开发)
- [添加新功能](#添加新功能)
- [发布流程](#发布流程)
- [常见问题](#常见问题)

---

## 环境准备

### 前提条件

| 工具 | 版本 | 必需 |
|------|------|------|
| macOS | 15.6+ | ✅ |
| Xcode | 15+ | ✅ |
| Claude Code CLI | 最新版 | ✅ (运行时) |
| Python 3 | 3.x | ✅ (Hook 脚本) |
| Sparkle Key | — | ❌ (仅发布需要) |

### 获取代码

```bash
git clone https://github.com/farouqaldori/claude-island.git
cd claude-island
```

---

## 构建与运行

### Xcode 构建

1. 打开 `ClaudeIsland.xcodeproj`
2. 选择 **ClaudeIsland** Scheme
3. 按 `⌘R` 运行

### 命令行构建

```bash
# 开发构建
xcodebuild -scheme ClaudeIsland -configuration Debug build

# 发布构建
xcodebuild -scheme ClaudeIsland -configuration Release build

# 使用 build.sh 脚本
./scripts/build.sh
```

### 应用行为

启动后，应用会执行以下操作：

1. **单实例检查** — 如果已有实例运行，激活现有窗口并退出
2. **Mixpanel 初始化** — 匿名使用分析
3. **Hook 安装** — 自动安装 `claude-island-state.py` 到 `~/.claude/hooks/`
4. **窗口创建** — 创建透明的 Notch 覆盖窗口
5. **更新检查** — 通过 Sparkle 检查应用更新
6. **Socket 服务器** — 启动 Unix Domain Socket 监听 Hook 事件

---

## 项目配置

### Info.plist

| 键 | 值 | 说明 |
|----|-----|------|
| `LSUIElement` | `true` | 不显示 Dock 图标 |
| `SUFeedURL` | `https://claudeisland.com/appcast.xml` | Sparkle 更新源 |
| `SUEnableAutomaticChecks` | `true` | 自动检查更新 |

### 沙盒权限 (Entitlements)

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- 不使用 App Sandbox -->
```

应用需要以下系统访问：
- 读写 `~/.claude/` 目录
- 创建 Unix Domain Socket (`/tmp/claude-island.sock`)
- 全局鼠标事件监控
- 进程树查询

### Socket 路径

```
/tmp/claude-island.sock
```

---

## 调试指南

### 日志系统

项目使用 Apple 的 `os.log` 统一日志框架：

```swift
import os.log

// 不同子系统的 Logger
Logger(subsystem: "com.claudeisland", category: "Hooks")
Logger(subsystem: "com.claudeisland", category: "Session")
Logger(subsystem: "com.claudeisland", category: "Window")
```

#### 查看日志

```bash
# 实时查看所有 Claude Island 日志
log stream --predicate 'subsystem == "com.claudeisland"' --level debug

# 仅查看 Hook 相关日志
log stream --predicate 'subsystem == "com.claudeisland" AND category == "Hooks"' --level debug

# 仅查看会话状态变更
log stream --predicate 'subsystem == "com.claudeisland" AND category == "Session"' --level debug
```

### 关键调试点

#### 1. Hook 事件未到达？

检查步骤：
1. 确认 Hook 脚本已安装：`ls -la ~/.claude/hooks/claude-island-state.py`
2. 确认 `settings.json` 已配置：`cat ~/.claude/settings.json | python3 -m json.tool`
3. 确认 Socket 存在：`ls -la /tmp/claude-island.sock`
4. 手动测试 Socket：
   ```bash
   echo '{"session_id":"test","cwd":"/tmp","event":"Test","status":"idle"}' | socat - UNIX-CONNECT:/tmp/claude-island.sock
   ```

#### 2. 权限请求未显示？

检查步骤：
1. 确认 `PermissionRequest` 事件已注册（`settings.json` 中 timeout 应为 86400）
2. 查看日志中是否有 "Permission request missing tool_use_id"
3. 检查 `tool_use_id` 缓存是否命中

#### 3. Notch 不可见？

检查步骤：
1. 确认当前屏幕有物理 Notch（或非 Notch 屏也可使用）
2. 查看 `isVisible` 状态
3. 检查窗口层级和位置：
   ```bash
   # 列出所有 Claude Island 窗口
   osascript -e 'tell application "System Events" to get properties of every window of process "ClaudeIsland"'
   ```

### 状态追踪

`SessionEvent` 实现了 `CustomStringConvertible`，所有事件都有可读的描述：

```
Processing: hookReceived(PreToolUse, session: abc12345)
Processing: permissionApproved(session: abc12345, tool: toolu_01Abc)
Processing: fileUpdated(session: abc12345, messages: 5)
```

---

## Hook 系统开发

### Hook 脚本 (`claude-island-state.py`)

Hook 脚本是 Claude Code 和 Claude Island 之间的桥梁。

#### 数据格式

**输入** (stdin，来自 Claude Code)：
```json
{
  "session_id": "uuid",
  "hook_event_name": "PreToolUse",
  "cwd": "/path/to/project",
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" },
  "tool_use_id": "toolu_xxx"
}
```

**输出到 App** (Unix Socket JSON)：
```json
{
  "session_id": "uuid",
  "cwd": "/path/to/project",
  "event": "PreToolUse",
  "status": "running_tool",
  "pid": 12345,
  "tty": "/dev/ttys001",
  "tool": "Bash",
  "tool_input": { "command": "ls -la" },
  "tool_use_id": "toolu_xxx"
}
```

**权限响应** (App → Hook，仅 PermissionRequest)：
```json
{ "decision": "allow", "reason": null }
```

**Hook 输出** (stdout，返回 Claude Code，仅 PermissionRequest)：
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": { "behavior": "allow" }
  }
}
```

### 添加新的 Hook 事件

1. **更新 Python 脚本** (`Resources/claude-island-state.py`)
   - 在 `main()` 中添加新的 `elif event == "NewEvent"` 分支
   - 设置 `state["status"]` 映射

2. **更新 Swift 事件模型** (`Models/SessionEvent.swift`)
   - 在 `SessionEvent` 枚举中添加新 case

3. **更新 Hook 安装** (`Services/Hooks/HookInstaller.swift`)
   - 在 `hookEvents` 数组中添加新事件的配置

4. **更新 SessionStore** (`Services/State/SessionStore.swift`)
   - 在 `process(_:)` 方法中添加新事件的处理逻辑

5. **更新状态规则** (`Models/SessionPhase.swift`)
   - 如需新状态，添加到 `SessionPhase` 枚举
   - 更新 `canTransition(to:)` 转换规则

---

## 添加新功能

### 添加新的工具结果视图

1. 在 `Models/ToolResultData.swift` 中定义新的结果类型：
   ```swift
   struct NewToolResult: Equatable, Sendable {
       let someField: String
   }
   ```

2. 在 `ToolResultData` 枚举中添加新 case：
   ```swift
   case newTool(NewToolResult)
   ```

3. 在 `ConversationParser.swift` 中添加解析逻辑

4. 在 `ToolResultViews.swift` 中添加视图：
   ```swift
   struct NewToolResultView: View {
       let result: NewToolResult
       var body: some View { ... }
   }
   ```

5. 在 `ToolStatusDisplay` 中添加运行和完成状态文本

### 添加新的设置项

1. 在 `Core/Settings.swift` 中添加：
   ```swift
   enum AppSettings {
       private enum Keys {
           static let newSetting = "newSetting"
       }

       static var newSetting: Bool {
           get { defaults.bool(forKey: Keys.newSetting) }
           set { defaults.set(newValue, forKey: Keys.newSetting) }
       }
   }
   ```

2. 在 `UI/Views/NotchMenuView.swift` 中添加 UI 控件

### 添加新的 UI 组件

遵循以下约定：
- 可复用组件放在 `UI/Components/`
- 页面级视图放在 `UI/Views/`
- 使用 `TerminalColors` 调色板的颜色
- 按钮统一使用 `.buttonStyle(.plain)` 移除默认动画
- 悬停使用 Spring 动画：`response: 0.2, dampingFraction: 0.7`

---

## 发布流程

### 1. 生成 Sparkle 签名密钥（首次）

```bash
./scripts/generate-keys.sh
```

这会在 `.sparkle-keys/` 目录中生成 EdDSA 密钥对。**此目录已在 `.gitignore` 中排除，切勿提交。**

### 2. 创建发布

```bash
./scripts/create-release.sh
```

该脚本执行以下步骤：
1. 构建 Release 版本
2. 创建 `.dmg` 磁盘映像
3. 用 Sparkle 密钥签名
4. 生成 `appcast.xml` 更新信息
5. 输出到 `releases/` 目录

### 3. 发布到 GitHub

1. 在 GitHub 创建新的 Release
2. 上传 `.dmg` 文件
3. 更新 `appcast.xml` 并部署到 `https://claudeisland.com/appcast.xml`

---

## 常见问题

### Q: 如何卸载 Hook？

```swift
// 编程方式
HookInstaller.uninstall()

// 手动方式
rm ~/.claude/hooks/claude-island-state.py
// 然后编辑 ~/.claude/settings.json 移除相关 hooks 配置
```

### Q: 为什么 Notch 在外接显示器上不显示？

Claude Island 默认使用内建显示器。如果您使用外接显示器：
1. 打开 Notch → 设置菜单
2. 在屏幕选择器中选择目标显示器

### Q: 支持非 Notch 设备吗？

是的。对于没有物理 Notch 的 Mac（如 Mac Mini、老款 MacBook），应用会：
- 在屏幕顶部中央模拟一个 Notch 区域
- 始终保持可见（不会自动隐藏，因为用户需要一个交互目标）
- Notch 尺寸使用默认值 `224 × 38`

### Q: Hook 脚本超时怎么办？

PermissionRequest 的 Hook 配置了 `timeout: 86400`（24 小时）。如果超过此时间用户未响应，Claude Code 会回落到终端内的默认权限 UI。

### Q: 如何禁用 Mixpanel 分析？

目前没有内置的 UI 开关。如需禁用，可以注释掉 `AppDelegate.swift` 中的 Mixpanel 初始化代码：

```swift
// Mixpanel.initialize(token: "...")
```

### Q: 为什么使用 `.accessory` 激活策略？

```swift
NSApplication.shared.setActivationPolicy(.accessory)
```

这确保应用：
- 不显示 Dock 图标
- 不出现在 `⌘Tab` 应用切换器中
- 行为类似菜单栏工具

---

## 代码规范

### Swift 风格

- 使用 MARK 注释分割代码区域：`// MARK: - Section Name`
- 使用 `nonisolated` 标记不需要 actor 隔离的方法
- 优先使用值类型（struct）而非引用类型（class）
- 使用 `Sendable` 协议确保跨隔离域安全

### 命名约定

| 类型 | 约定 | 示例 |
|------|------|------|
| 视图 | `*View` | `NotchView`, `ChatView` |
| 视图模型 | `*ViewModel` | `NotchViewModel` |
| 服务 | 描述性名词 | `SessionStore`, `HookSocketServer` |
| 事件 | 过去式动词 | `hookReceived`, `permissionApproved` |
| 状态 | 形容词/动名词 | `processing`, `waitingForInput` |

### 文件组织

- 每个文件只包含一个主要类型
- 相关的小类型可以放在同一文件中（如 `SessionState.swift` 包含 `ToolTracker` 和 `SubagentState`）
- 扩展使用 `Ext+TypeName.swift` 命名

---

*生成自 Claude Island 项目分析*
