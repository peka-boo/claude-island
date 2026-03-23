# Progress

- 2026-03-22: Started investigating lag with many sessions. Looking at sidebar loading, search/group recomputation, and transcript loading/rendering paths first.
- 2026-03-22: Identified full sidebar reloads on every active thread update plus per-project thread fetches as the most likely high-impact bottlenecks.
- 2026-03-22: Added `SidebarProjectGroupingSupport` and switched the active-thread sidebar refresh path to an in-memory update instead of a full `loadData()`.
- 2026-03-23: Starting comprehensive project analysis for performance, architecture, code quality, and maintainability optimizations.
- 2026-03-23: Observing that MainContentView now uses `refreshThreadSnapshot` instead of `loadData` for thread updates (optimization already applied).
