# Claude Island - 项目结构

> 本文档描述 Claude Island 项目的目录结构和文件组织。

## 目录树

```
claude-island/
├── ClaudeIsland/                    # 主要源代码
│   ├── App/                         # 应用入口与生命周期
│   │   ├── ClaudeIslandApp.swift    # @main 入口，SwiftUI App 定义
│   │   ├── AppDelegate.swift        # 核心初始化、Mixpanel、Sparkle、Hook 安装
│   │   ├── WindowManager.swift      # Notch 窗口的创建与屏幕切换管理
│   │   └── ScreenObserver.swift     # CGDisplayRegisterReconfigurationCallback 监听
│   │
│   ├── Core/                        # 核心逻辑与状态管理
│   │   ├── NotchViewModel.swift     # Notch 状态机 (closed/opened/popping)
│   │   ├── NotchGeometry.swift      # 几何计算：命中检测、面板位置
│   │   ├── NotchActivityCoordinator.swift  # 活动指示器状态管理
│   │   ├── ScreenSelector.swift     # 多屏幕选择逻辑
│   │   ├── SoundSelector.swift      # 通知音效选择
│   │   ├── Settings.swift           # UserDefaults 设置管理
│   │   └── Ext+NSScreen.swift       # NSScreen 扩展：Notch 检测
│   │
│   ├── Models/                      # 数据模型（纯值类型）
│   │   ├── SessionState.swift       # 会话完整状态 + ToolTracker + SubagentState
│   │   ├── SessionPhase.swift       # 状态机枚举 + 转换规则
│   │   ├── SessionEvent.swift       # 事件类型定义
│   │   ├── ChatMessage.swift        # 消息模型 + MessageBlock
│   │   ├── ToolResultData.swift     # 20+ 种工具结果的结构化模型
│   │   └── TmuxTarget.swift         # Tmux 目标匹配
│   │
│   ├── Services/                    # 业务逻辑与系统集成
│   │   ├── State/                   # 状态管理
│   │   │   ├── SessionStore.swift   # ★ 核心 Actor，所有状态变更的唯一入口
│   │   │   ├── ToolEventProcessor.swift
│   │   │   └── FileSyncScheduler.swift
│   │   │
│   │   ├── Hooks/                   # Claude Code Hook 通信
│   │   │   ├── HookSocketServer.swift  # Unix Socket 服务器
│   │   │   └── HookInstaller.swift     # Hook 脚本自动安装
│   │   │
│   │   ├── Session/                 # 会话监控
│   │   │   ├── ClaudeSessionMonitor.swift  # UI 层的 SessionStore 包装器
│   │   │   ├── ConversationParser.swift    # JSONL 文件解析器
│   │   │   ├── AgentFileWatcher.swift      # 代理文件监控
│   │   │   └── JSONLInterruptWatcher.swift # 中断检测
│   │   │
│   │   ├── Shared/                  # 共享服务
│   │   │   ├── ProcessExecutor.swift       # 外部进程执行
│   │   │   ├── ProcessTreeBuilder.swift    # 进程树（Tmux 检测）
│   │   │   └── TerminalAppRegistry.swift   # 终端应用注册
│   │   │
│   │   ├── Tmux/                    # Tmux 集成
│   │   │   ├── TmuxController.swift
│   │   │   ├── TmuxPathFinder.swift
│   │   │   ├── TmuxSessionMatcher.swift
│   │   │   ├── TmuxTargetFinder.swift
│   │   │   └── ToolApprovalHandler.swift
│   │   │
│   │   ├── Chat/                    # 聊天服务
│   │   │   └── ChatHistoryManager.swift
│   │   │
│   │   ├── Window/                  # 窗口服务
│   │   │   ├── WindowFinder.swift
│   │   │   ├── WindowFocuser.swift
│   │   │   └── YabaiController.swift
│   │   │
│   │   └── Update/                  # 更新服务
│   │       └── NotchUserDriver.swift  # Sparkle 自定义 UI
│   │
│   ├── UI/                          # 用户界面
│   │   ├── Views/                   # 页面视图
│   │   │   ├── NotchView.swift          # ★ 主 Notch 视图
│   │   │   ├── NotchHeaderView.swift    # 头部栏
│   │   │   ├── ClaudeInstancesView.swift # 会话列表
│   │   │   ├── ChatView.swift           # 聊天详情
│   │   │   ├── NotchMenuView.swift      # 设置菜单
│   │   │   └── ToolResultViews.swift    # 工具结果展示
│   │   │
│   │   ├── Components/              # 可复用组件
│   │   │   ├── NotchShape.swift         # Notch 形状（贝塞尔曲线）
│   │   │   ├── ProcessingSpinner.swift  # 加载旋转器
│   │   │   ├── StatusIcons.swift        # 状态图标
│   │   │   ├── ActionButton.swift       # 操作按钮
│   │   │   ├── TerminalColors.swift     # 调色板
│   │   │   ├── MarkdownRenderer.swift   # Markdown 渲染
│   │   │   ├── ScreenPickerRow.swift    # 屏幕选择行
│   │   │   └── SoundPickerRow.swift     # 音效选择行
│   │   │
│   │   └── Window/                  # AppKit 窗口
│   │       ├── NotchWindow.swift        # NSPanel 子类（透明/置顶/穿透）
│   │       ├── NotchWindowController.swift
│   │       └── NotchViewController.swift
│   │
│   ├── Utilities/                   # 工具函数
│   │   ├── MCPToolFormatter.swift
│   │   ├── SessionPhaseHelpers.swift
│   │   └── TerminalVisibilityDetector.swift
│   │
│   ├── Resources/                   # 资源文件
│   │   ├── ClaudeIsland.entitlements   # 应用沙盒权限
│   │   └── claude-island-state.py      # ★ Hook Python 脚本
│   │
│   ├── Assets.xcassets/             # 图片资源
│   └── Info.plist                   # 应用配置
│
├── ClaudeIsland.xcodeproj/          # Xcode 项目文件
│
├── docs/                            # 文档
│   ├── ARCHITECTURE.md              # 系统架构文档
│   ├── ANIMATION_TECHNIQUES.md      # 动画技术文档
│   ├── PROJECT_STRUCTURE.md         # 项目结构（本文件）
│   └── DEVELOPMENT.md              # 开发指南
│
├── scripts/                         # 构建脚本
│   ├── build.sh                     # 构建脚本
│   ├── create-release.sh            # 发布创建脚本
│   └── generate-keys.sh             # Sparkle 签名密钥生成
│
├── README.md                        # 项目说明
├── LICENSE.md                       # Apache 2.0 许可证
└── .gitignore                       # Git 忽略规则
```

## 文件统计

| 分类 | 文件数 | 说明 |
|------|--------|------|
| **App** | 4 | 应用入口和生命周期 |
| **Core** | 7 | 核心逻辑和状态管理 |
| **Models** | 6 | 数据模型 |
| **Services** | 19 | 业务逻辑（8 个子目录） |
| **UI** | 17 | 用户界面（3 个子目录） |
| **Utilities** | 3 | 工具函数 |
| **Resources** | 2 | 资源文件 |
| **Scripts** | 3 | 构建和发布脚本 |
| **总计** | **~61** | Swift + Python 文件 |

## 关键文件（★ 标记）

以下是理解项目的核心文件：

1. **`SessionStore.swift`** (991 行) — 所有状态变更的唯一入口
2. **`NotchView.swift`** (504 行) — 主 UI 视图
3. **`HookSocketServer.swift`** (616 行) — Hook 通信服务器
4. **`ConversationParser.swift`** (42760 字节) — JSONL 文件解析
5. **`claude-island-state.py`** (202 行) — Hook Python 脚本
6. **`SessionState.swift`** (346 行) — 核心数据模型
7. **`ChatView.swift`** (41342 字节) — 聊天界面

---

*生成自 Claude Island 项目结构分析*
