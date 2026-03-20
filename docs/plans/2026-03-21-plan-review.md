# 实现计划 Review 报告

> 对照需求讨论 + Apple macOS HIG/最佳实践 进行审查

---

## ✅ 需求覆盖度检查

| # | 需求 | 计划覆盖 | 备注 |
|---|------|---------|------|
| 1 | 启动时默认打开主窗口 | ✅ Task 4.1 | |
| 2 | 侧边栏 + 文件夹 + 会话列表 | ✅ Task 4.2 | |
| 3 | Notch 通过开关控制 | ✅ Task 4.4 + 6.2 | |
| 4 | 完整交互（发消息、审批权限） | ✅ Task 3.2 + 4.3 | |
| 5 | Import from Claude CLI | ✅ Task 5.1 + 5.2 | |
| 6 | 导入界面（项目名、分支、摘要、消息数等） | ✅ Task 5.2 | |
| 7 | CLI 子进程通信 (Plan A) | ✅ Task 3.1 + 3.2 | |
| 8 | Hook 全局监控（开关） | ✅ Task 2.1 + 2.2 + 4.4 | |
| 9 | 参考 Masko 技术方案（HTTP+Bash） | ✅ Task 2.1 + 2.2 | |
| 10 | 双模式（我的会话 + 全局监控） | ✅ Task 4.2 | |
| 11 | 全局监控可接管继续聊天 | ✅ Task 5.3 | |

**需求覆盖率: 11/11 = 100%** ✅

---

## ⚠️ Apple macOS 最佳实践问题（共 7 项）

### 问题 1: 🔴 应使用 SwiftData 而非原始 sqlite3 C API

**当前方案：** 直接使用 `sqlite3` C API，手写 SQL。

**问题：** App 目标是 macOS 15.6+，SwiftData 从 macOS 14 起就完全可用，是 Apple 推荐的数据持久化方案。

**推荐修改：**
```swift
// ❌ 当前计划：手写 SQL
let db: OpaquePointer?
sqlite3_open(path, &db)
sqlite3_exec(db, "CREATE TABLE projects (...)", nil, nil, nil)

// ✅ 推荐：SwiftData
@Model
class Project {
    @Attribute(.unique) var id: String
    var name: String
    var path: String
    var threads: [Thread] = []
    var createdAt: Date
    var updatedAt: Date
}

@Model
class Thread {
    @Attribute(.unique) var id: String
    var project: Project?
    var title: String?
    var source: ThreadSource
    // ...
}
```

**好处：**
- `@Query` 属性包装器自动与 SwiftUI 绑定
- 自动 schema 迁移（`VersionedSchema`）
- 线程安全（`ModelActor`）
- 无需手写 SQL，减少 bug
- 与 SwiftUI 的 `@Observable` 深度集成

**权衡：** SwiftData 对复杂查询的控制力不如原始 SQL。但本项目的查询需求（按项目分组、按时间排序、搜索标题）都很标准，SwiftData 完全胜任。

---

### 问题 2: 🔴 应使用 SwiftUI Scene 而非 NSWindowController

**当前方案：** 手动创建 `MainWindowController: NSWindowController`

**问题：** 既然项目已经使用 SwiftUI `App` 协议（`ClaudeIslandApp.swift`），应优先使用 SwiftUI 的 `Window` Scene，而非回退到 AppKit 窗口管理。

**推荐修改：**
```swift
@main
struct ClaudeIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 主窗口
        Window("Claude Island", id: "main") {
            MainContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        // 设置窗口（自动绑定到 ⌘, 快捷键）
        Settings {
            SettingsView()
        }
    }
}
```

**好处：**
- SwiftUI 自动管理窗口生命周期
- `Settings` Scene 自动添加到菜单栏的 "Claude Island > Settings..."
- `.windowToolbarStyle(.unified)` 实现现代 macOS 工具栏样式
- 不需要手动管理 `NSWindowController`

**保留 AppKit 的部分：** Notch 的 `NSPanel` 仍然需要 AppKit，这是正确的（`NSPanel` 无 SwiftUI 等价物）。

---

### 问题 3: 🟡 应使用 NavigationSplitView

**当前方案：** 自定义 `SidebarView` + `ChatContentView` 手动布局。

**推荐修改：**
```swift
struct MainContentView: View {
    @State private var selectedThread: DBThread?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedThread)
        } detail: {
            if let thread = selectedThread {
                ChatContentView(thread: thread)
            } else {
                WelcomeView()
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    }
}
```

**好处：**
- 自动处理侧边栏显示/隐藏（⌘+Option+S）
- 自动处理侧边栏宽度拖拽
- 与 `toolbar` 修饰符深度集成
- 符合 macOS HIG 的侧边栏交互规范

---

### 问题 4: 🟡 应使用 @Observable 而非 ObservableObject

**当前方案：** ViewModel 使用 `@ObservableObject`（项目现有模式）。

**推荐修改：** macOS 14+ 提供了 `@Observable` 宏（Observation 框架），更高效：

```swift
// ❌ 旧模式
class SidebarViewModel: ObservableObject {
    @Published var threads: [DBThread] = []
    @Published var searchText = ""
}

// ✅ 新模式（macOS 14+）
@Observable
class SidebarViewModel {
    var threads: [DBThread] = []     // 自动跟踪
    var searchText = ""              // 自动跟踪
}
```

**好处：**
- 无需 `@Published`，所有属性自动跟踪
- 更精细的变更跟踪（只更新访问了变更属性的视图）
- 与 SwiftData 的 `@Model` 天然兼容
- Masko Code 已经使用了这种模式（`@Observable final class LocalServer`）

**注意：** 现有代码中的 `ClaudeSessionMonitor` 等使用 `@MainActor class: ObservableObject`，新模块应使用 `@Observable`，老代码可以渐进迁移。

---

### 问题 5: 🟡 Settings 应使用 SwiftUI Settings Scene

**当前方案：** 设置面板是侧边栏底部的一个导航目标。

**Apple 规范：** macOS app 的设置应通过菜单栏 "App Name > Settings..."（⌘,）打开，使用独立的设置窗口。

**推荐：** 同时支持两种入口：
1. `Settings` Scene → ⌘, 快捷键（macOS 标准）
2. 侧边栏底部 ⚙ 图标 → 也打开设置窗口（快捷入口）

---

### 问题 6: 🟡 子进程清理策略缺失

**当前方案：** Task 3.2 提到了 `stopSession` 和 `interruptSession`，但未详细说明。

**需要补充：**
1. **App 退出时** — 向所有子进程发送 `SIGTERM`，等待 2 秒，超时发 `SIGKILL`
2. **中断操作** — 发送 `SIGINT`（等同 Ctrl+C），Claude CLI 会优雅停止
3. **僵尸进程** — 使用 `Process.waitUntilExit()` 在后台线程回收
4. **异常退出** — 注册 `atexit()` 确保清理

```swift
// 推荐实现
private func cleanupProcess(_ process: Process) {
    process.terminate()  // 发送 SIGTERM
    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
```

---

### 问题 7: 🟢 Hook 迁移兼容性

**问题：** 从 Python + Unix Socket 切换到 Bash + HTTP，现有用户的 `~/.claude/settings.json` 中已有 Python 脚本的 Hook 注册。

**建议补充：**
- 安装新 Hook 时，先清理旧的 `claude-island-state.py` Hook 注册
- 删除旧的 Python 脚本文件（如存在）
- 在计划中增加 "Migration" step

---

## 📋 修改建议总结

| # | 严重度 | 修改项 | 影响范围 |
|---|--------|--------|---------|
| 1 | 🔴 高 | sqlite3 C API → **SwiftData** | Phase 1 重写 |
| 2 | 🔴 高 | NSWindowController → **SwiftUI Window Scene** | Task 4.1 重写 |
| 3 | 🟡 中 | 自定义布局 → **NavigationSplitView** | Task 4.2-4.3 调整 |
| 4 | 🟡 中 | ObservableObject → **@Observable** | 新 ViewModel 全部使用 |
| 5 | 🟡 中 | 内嵌设置 → **Settings Scene** | Task 4.4 调整 |
| 6 | 🟡 中 | 补充 **子进程清理策略** | Task 3.2 补充 |
| 7 | 🟢 低 | 补充 **旧 Hook 迁移逻辑** | Task 2.2 补充 |

---

## ✏️ 推荐的修订后技术栈

```diff
- SQLite (直接使用 sqlite3 C API)
+ SwiftData (@Model + ModelContainer)

- AppKit (NSWindow + NSPanel)
+ SwiftUI Window Scene (主窗口) + AppKit NSPanel (Notch，保持不变)

- ObservableObject + @Published
+ @Observable 宏 (新模块) + ObservableObject (现有模块兼容)

- 自定义侧边栏布局
+ NavigationSplitView

- 内嵌设置面板
+ SwiftUI Settings Scene + 侧边栏快捷入口
```

所有其他设计决策（CLI 子进程、HTTP + Bash Hook、双模式、接管逻辑）均合理 ✅

---

*Review completed at 2026-03-21*
