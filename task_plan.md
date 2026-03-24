# 优化Claude Island项目的分页加载策略

## 目标
优化Claude Island项目的分页加载策略，提高性能和用户体验。

## 当前状态分析

### 1. ChatMessagePaginationSupport.swift
- 固定页面大小为80
- 提供初始可见计数、状态计算和合并旧页面的方法
- 没有动态页面大小调整

### 2. DataStore.swift
- 使用FetchDescriptor和fetchLimit进行分页查询
- 有fetchRecentMessages和fetchMessagesBefore方法
- 没有缓存机制

### 3. ChatViewModel.swift
- 使用ChatMessagePaginationSupport.defaultPageSize（80）进行分页
- loadOlderMessages()函数加载更多消息
- 没有预加载逻辑

## 优化方案

### 阶段1：分析当前实现（已完成）
- [x] 读取ChatMessagePaginationSupport.swift
- [x] 读取DataStore.swift中的分页查询
- [x] 读取ChatViewModel.swift中的分页使用

### 阶段2：设计动态页面大小策略
- [ ] 创建可配置的分页大小策略
- [ ] 实现基于消息内容长度的自适应算法
- [ ] 更新ChatMessagePaginationSupport支持动态页面大小

### 阶段3：实现预加载策略
- [ ] 在用户滚动接近底部时预加载下一页
- [ ] 实现智能预加载，避免不必要的数据加载
- [ ] 考虑网络/磁盘延迟

### 阶段4：实现缓存优化
- [ ] 缓存已加载的消息页面
- [ ] 实现页面缓存淘汰策略
- [ ] 减少重复查询

### 阶段5：优化分页查询
- [ ] 优化SwiftData查询谓词
- [ ] 添加适当的索引以提高查询性能
- [ ] 考虑使用批处理加载

### 阶段6：测试和验证
- [ ] 确保功能保持不变
- [ ] 运行构建验证
- [ ] 测试分页加载行为

## 时间表
1. 阶段2：动态页面大小策略 - 30分钟
2. 阶段3：预加载策略 - 45分钟
3. 阶段4：缓存优化 - 30分钟
4. 阶段5：查询优化 - 30分钟
5. 阶段6：测试验证 - 30分钟

总计：约3小时
