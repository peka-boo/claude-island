# Claude Island - 动画技术与最佳实践

> 本文档总结 Claude Island 项目的 UI 动画技术栈和实现细节，可用于其他 macOS/SwiftUI 项目参考。

## 目录

- [技术栈概览](#技术栈概览)
- [核心动画原理](#核心动画原理)
- [关键组件实现](#关键组件实现)
- [动画参数速查表](#动画参数速查表)
- [最佳实践](#最佳实践)
- [代码示例](#代码示例)

---

## 技术栈概览

| 技术 | 用途 |
|------|------|
| **SwiftUI** | UI 框架 |
| **AppKit (NSPanel)** | 窗口管理、透明窗口、点击穿透 |
| **Combine** | 响应式状态管理、事件流 |
| **CGEvent** | 全局鼠标事件模拟 |
| **QuartzCore** | 阴影、形状渲染 |

### 系统要求
- macOS 15.6+
- Xcode 15+

---

## 核心动画原理

### 1. Spring 动画 - 丝滑感的秘诀

Spring 动画是 Apple 生态中最自然的动画类型，通过 `response` 和 `dampingFraction` 参数控制。

```swift
// 基础 Spring 动画
Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)

// 参数说明:
// - response: 弹簧响应时间（秒），值越小动画越快
// - dampingFraction: 阻尼系数 (0-1)
//   - 1.0 = 无弹跳，直接到位
//   - 0.5 = 明显弹跳效果
//   - 0.7-0.8 = 丝滑感最佳区间
// - blendDuration: 过渡时间，通常设为 0
```

**Claude Island 使用的 Spring 配置：**

| 场景 | Response | Damping | 效果描述 |
|------|----------|---------|----------|
| 打开动画 | 0.42 | 0.8 | 略带弹性的打开 |
| 关闭动画 | 0.45 | 1.0 | 无弹性的干净关闭 |
| 内容切换 | 0.3 | 0.8 | 快速响应的切换 |
| 按钮动画 | 0.2 | 0.7 | 明显弹性的交互反馈 |
| 悬停效果 | 0.38 | 0.8 | 柔和的悬停过渡 |

### 2. `.smooth` 动画 - 柔和过渡

```swift
// 适用于不需要弹性的状态变化
.animation(.smooth, value: someState)

// 等效于:
.animation(.easeInOut(duration: 0.3), value: someState)
```

### 3. Asymmetric Transitions - 非对称转场

进入和退出使用不同的动画效果：

```swift
.transition(
    .asymmetric(
        insertion: .scale(scale: 0.8, anchor: .top)
            .combined(with: .opacity)
            .animation(.smooth(duration: 0.35)),
        removal: .opacity.animation(.easeOut(duration: 0.15))
    )
)
```

**关键点：**
- 插入使用 `scale + opacity` 组合，有「弹出」感
- 移除仅使用 `opacity`，快速消失不拖沓
- 插入动画时间 > 移除动画时间（0.35 vs 0.15）

### 4. 延迟动画（Staggered Animation）

多个元素依次出现的动画：

```swift
// 三个按钮依次出现
withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
    showChatButton = true
}
withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
    showDenyButton = true
}
withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
    showAllowButton = true
}
```

---

## 关键组件实现

### 1. 自定义形状 - NotchShape

使用二次贝塞尔曲线绘制圆角缺口形状：

```swift
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    // 支持动画
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 使用 addQuadCurve 创建平滑的圆角
        // 关键：控制点决定了曲线的「弯曲程度」

        // 左上角曲线
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // ... 其他路径

        return path
    }
}
```

**形状动画化：**
```swift
// 圆角半径从关闭状态过渡到打开状态
NotchShape(
    topCornerRadius: viewModel.status == .opened ? 19 : 6,
    bottomCornerRadius: viewModel.status == .opened ? 24 : 14
)
```

### 2. Matched Geometry Effect - 元素位置过渡

实现元素在不同位置间的平滑移动：

```swift
@Namespace private var activityNamespace

// 在第一个位置
ClaudeCrabIcon(size: 14)
    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: true)

// 在第二个位置（同一个 id）
ClaudeCrabIcon(size: 14)
    .matchedGeometryEffect(id: "crab", in: activityNamespace, isSource: false)
```

### 3. 悬停动画

```swift
@State private var isHovered = false

// 方式 1: onHover + withAnimation
.onHover { hovering in
    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
        isHovered = hovering
    }
}

// 方式 2: 声明式（更简洁）
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
)
.onHover { isHovered = $0 }
```

### 4. 脉冲动画

用于表示处理中的状态：

```swift
@State private var pulseOpacity: Double = 0.6

private func startPulsing() {
    withAnimation(
        .easeInOut(duration: 0.6)
        .repeatForever(autoreverses: true)
    ) {
        pulseOpacity = 0.15
    }
}

// 使用
Circle()
    .fill(statusColor.opacity(pulseOpacity))
    .frame(width: 6, height: 6)
```

### 5. 旋转动画

```swift
@State private var rotation: Double = 0

// 持续旋转
.onAppear {
    withAnimation(
        .linear(duration: 2.0)
        .repeatForever(autoreverses: false)
    ) {
        rotation = 360
    }
}

.rotationEffect(.degrees(rotation))
```

### 6. 符号切换动画（Spinner）

```swift
private let symbols = ["·", "✢", "✳", "∗", "✻", "✽"]
@State private var phase: Int = 0

private let timer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

var body: some View {
    Text(symbols[phase % symbols.count])
        .font(.system(size: 12, weight: .bold))
        .onReceive(timer) { _ in
            phase = (phase + 1) % symbols.count
        }
}
```

---

## 动画参数速查表

### Spring 参数选择指南

| 预期效果 | Response | Damping | 示例场景 |
|----------|----------|---------|----------|
| 快速响应 | 0.2-0.25 | 0.7-0.8 | 按钮点击 |
| 标准过渡 | 0.3-0.35 | 0.8 | 内容切换 |
| 柔和展开 | 0.4-0.45 | 0.75-0.85 | 面板打开 |
| 干净收起 | 0.4-0.5 | 0.95-1.0 | 面板关闭 |
| 弹性反馈 | 0.25-0.3 | 0.5-0.6 | 弹跳效果 |

### 动画时长参考

| 类型 | 推荐时长 | 说明 |
|------|----------|------|
| 微交互 | 0.1-0.2s | 按钮状态变化 |
| 标准过渡 | 0.25-0.35s | 大多数 UI 变化 |
| 强调动画 | 0.35-0.5s | 面板展开、重要通知 |
| 快速消失 | 0.1-0.15s | 元素移除 |

---

## 最佳实践

### 1. 状态驱动的动画

```swift
// ✅ 好的做法：使用 .animation(value:) 让动画跟随状态
.frame(width: isOpen ? 200 : 100)
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOpen)

// ❌ 避免：手动触发动画
// withAnimation { ... } 应该在用户交互时使用，而非渲染时
```

### 2. 避免过度动画

```swift
// ✅ 好的做法：只在需要的属性上应用动画
.animation(.spring(response: 0.3), value: specificState)

// ❌ 避免：对所有变化应用动画
.animation(.default, value: viewModel) // 太宽泛
```

### 3. 使用 `animation(nil, value:)` 禁用特定动画

```swift
.animation(.spring(response: 0.35), value: isWaitingForApproval)
.animation(nil, value: viewModel.status) // 这个状态变化不要动画
```

### 4. 交错动画增加层次感

```swift
// 元素按顺序出现
.onAppear {
    withAnimation(.spring(response: 0.3).delay(0.0)) { showTitle = true }
    withAnimation(.spring(response: 0.3).delay(0.05)) { showSubtitle = true }
    withAnimation(.spring(response: 0.3).delay(0.1)) { showButtons = true }
}
```

### 5. 使用 `contentShape` 确保点击区域

```swift
// 透明区域也能响应点击
.background(Color.clear)
.contentShape(Rectangle())
.onTapGesture { ... }
```

### 6. 按钮样式统一

```swift
// 自定义按钮样式避免默认动画冲突
Button { ... } label: { ... }
    .buttonStyle(.plain)  // 重要！移除默认按钮动画
```

---

## 代码示例

### 完整的丝滑按钮组件

```swift
struct SmoothButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isHovered ? Color.white : Color.white.opacity(0.15))
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                isHovered = hovering
            }
        }
        .pressEvents {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                isPressed = false
            }
        }
    }
}
```

### 展开/收起面板

```swift
struct ExpandablePanel: View {
    @Binding var isExpanded: Bool

    private let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

    var body: some View {
        VStack {
            header

            if isExpanded {
                content
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.95, anchor: .top)
                            .combined(with: .opacity)
                            .animation(.smooth(duration: 0.35)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))
                    ))
            }
        }
        .frame(width: isExpanded ? 400 : 200,
               height: isExpanded ? 300 : 50)
        .animation(isExpanded ? openAnimation : closeAnimation, value: isExpanded)
    }
}
```

### 处理状态指示器

```swift
struct ProcessingIndicator: View {
    @State private var phase = 0
    private let symbols = ["○", "◐", "◑", "●"]

    var body: some View {
        Text(symbols[phase])
            .font(.system(size: 16))
            .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = (phase + 1) % symbols.count
                }
            }
    }
}
```

---

## 颜色系统

Claude Island 使用的终端风格配色：

```swift
struct TerminalColors {
    static let green = Color(red: 0.4, green: 0.75, blue: 0.45)   // 成功/就绪
    static let amber = Color(red: 1.0, green: 0.7, blue: 0.0)     // 警告/等待
    static let red = Color(red: 1.0, green: 0.3, blue: 0.3)       // 错误
    static let cyan = Color(red: 0.0, green: 0.8, blue: 0.8)      // 处理中
    static let blue = Color(red: 0.4, green: 0.6, blue: 1.0)      // 信息
    static let magenta = Color(red: 0.8, green: 0.4, blue: 0.8)   // 高亮
    static let prompt = Color(red: 0.85, green: 0.47, blue: 0.34) // Claude 橙色
    static let dim = Color.white.opacity(0.4)                      // 次要文本
    static let dimmer = Color.white.opacity(0.2)                   // 更次要
    static let background = Color.white.opacity(0.05)              // 卡片背景
    static let backgroundHover = Color.white.opacity(0.1)          // 悬停背景
}
```

---

## 窗口配置

创建置顶透明窗口的关键设置：

```swift
class NotchPanel: NSPanel {
    override init(...) {
        super.init(...)

        // 透明配置
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // 窗口层级
        level = .mainMenu + 3  // 高于菜单栏

        // 空间行为
        collectionBehavior = [
            .fullScreenAuxiliary,  // 全屏时也显示
            .stationary,           // 空间切换时保持位置
            .canJoinAllSpaces,     // 所有桌面空间可见
            .ignoresCycle          // 不在 Cmd+` 循环中
        ]

        // 鼠标穿透
        ignoresMouseEvents = true
    }
}
```

---

## 总结

### 丝滑动画的三个关键

1. **Spring 动画** - 使用 `response: 0.3-0.4, dampingFraction: 0.7-0.85` 的 Spring 动画
2. **非对称转场** - 插入用 scale+opacity，移除只用 opacity
3. **交错延迟** - 多个元素依次出现，间隔 0.05s

### 核心代码模式

```swift
// 1. 状态变化动画
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: myState)

// 2. 悬停效果
.onHover { withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = $0 } }

// 3. 转场动画
.transition(.asymmetric(
    insertion: .scale(scale: 0.95).combined(with: .opacity),
    removal: .opacity
))
```

---

*生成自 Claude Island 项目分析*
