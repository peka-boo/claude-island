# Findings

## Previous Performance Issues (Resolved)
- Root cause 1: [MainContentView] previously called `sidebarVM.loadData()` every time `chatVM.threadInfo?.updatedAt` changes, which turned ordinary thread activity into repeated full sidebar reloads.
- Root cause 2: [SidebarViewModel] previously built sidebar groups by fetching threads project-by-project, creating an N+1 pattern that scales poorly as session/project counts rise.
- Supporting evidence: `SidebarView` already receives live monitor updates directly, so removing the `updatedAt -> loadData()` path does not cut off live status refreshes.
- Optimization direction: keep full reloads for initial load/import/global-monitor refresh, but switch thread activity updates to targeted in-memory sidebar snapshot refreshes.

## Current Observations
- MainContentView now uses `refreshThreadSnapshot` (line 66) instead of `loadData` for thread updates - optimization already applied.
- SidebarProjectGroupingSupport provides efficient grouping logic with O(n) complexity for thread grouping.
- The app uses SwiftUI with @Observable pattern for state management.
- Data persistence uses SwiftData (Core Data wrapper) with BackgroundDataActor for background threading.
- Heavy use of async/await for data operations.
- SidebarViewModel maintains in-memory indexes (threadsById, globalSessionsByNormalizedId) for fast lookups.

## Areas for Further Analysis
1. **Memory Management**: Potential retain cycles in closures, lazy loading efficiency
2. **UI Performance**: SwiftUI view recomputation patterns, animation performance
3. **Data Loading**: Batch loading strategies, pagination for large datasets
4. **Concurrency**: Actor isolation overhead, task cancellation patterns
5. **Code Organization**: ViewModel responsibilities, support file naming conventions

## Architecture Analysis Results (2026-03-23)
**Overall Rating**: 7.5/10

### Key Findings:
1. **架构一致性良好**：清晰的分层结构，良好的模块组织
2. **SwiftUI模式优秀**：使用NavigationSplitView，符合Apple HIG
3. **状态管理混合**：同时使用@Observable和ObservableObject，需要统一
4. **代码组织问题**：
   - ChatView.swift过大（1388行），需要拆分
   - ViewModel支持文件过多（12个），职责不够明确
   - 缺少协议抽象，影响可测试性
5. **并发安全性优秀**：正确的actor使用，线程安全的SessionStore

### 优先级改进建议：
- **P0**: 拆分ChatView.swift，添加协议抽象，统一状态管理模式
- **P1**: 重构ChatViewModel，添加单元测试，创建依赖注入容器
- **P2**: 重构ViewModel支持文件，添加集成测试，性能优化

## Performance Analysis Results (2026-03-23)
**Overall Rating**: 7/10

### Key Performance Findings:
1. **内存管理风险**：
   - ClaudeSessionMonitor中的Combine订阅需要确保清理
   - AgentFileWatcher的文件句柄管理需要改进
   - 使用weak self避免循环引用，但任务取消管理需加强

2. **UI性能热点**：
   - SidebarViewModel.applySearch()高频调用，需要防抖机制
   - ChatViewModel.displayedStructuredItems每次渲染可能调用
   - 列表滚动性能在大量会话时可能受影响

3. **数据加载效率**：
   - fetchAllThreads()可能加载所有线程到内存，需要分页
   - 大型JSONL文件同步解析可能阻塞主线程
   - 缓存策略简单，需要LRU淘汰机制

4. **并发性能优化点**：
   - SessionStore.process()高频事件处理可能阻塞
   - BackgroundDataActor每个ViewModel创建新实例，可能导致过多并发上下文
   - 文件系统事件处理可优化为@MainActor调度

### Specific Hotspot Analysis:
1. **SidebarViewModel.refreshThreadSnapshot**:
   - 每次调用都触发applySearch()，需要增量更新优化
   - 建议：添加shouldUpdateProjects检查，避免不必要的重新计算

2. **ChatViewModel消息加载**:
   - mergeOlderPage中的Set创建和遍历开销
   - 建议：使用增量更新而非全量替换

3. **AgentFileWatcher性能影响**:
   - 同步文件解析可能阻塞GCD队列
   - 建议：使用Task.detached进行异步解析

### Performance Data Estimates:
- **启动时间**: 200-500ms（应用）+ 100-300ms（数据库）+ 100-500ms（首次加载）
- **内存使用**: 空闲50-80MB，活跃监控80-150MB，大量会话150-300MB
- **响应延迟目标**: UI交互<16ms，搜索响应<300ms（防抖后），消息加载<500ms

### High Priority Performance Fixes:
1. **内存泄漏预防**: 在ClaudeSessionMonitor.deinit中取消所有Combine订阅
2. **主线程阻塞**: 将大型JSONL文件解析移到后台
3. **搜索防抖**: 为SidebarViewModel.applySearch()添加300ms防抖
