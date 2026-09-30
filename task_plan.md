# Task Plan: Unify Notch and Settings Hook Logic

## Goal
Make Notch hook controls and Settings hook controls use the same source of truth and the same side effects so hook installation/monitoring behavior stays consistent.

## Current Phase
Phase 5

## Phases

### Phase 1: Requirements & Discovery
- [x] Understand user intent
- [x] Identify the split source of truth between Notch and Settings hook toggles
- [x] Document findings in findings.md
- **Status:** complete

### Phase 2: Planning & Structure
- [x] Define the shared coordinator approach
- [x] Choose the safest integration points
- [x] Document decisions with rationale
- **Status:** complete

### Phase 3: Implementation
- [x] Add or update focused tests first where behavior changes are practical to verify
- [x] Implement unified hook logic
- [x] Test incrementally
- **Status:** complete

### Phase 4: Testing & Verification
- [x] Verify focused tests and build paths relevant to the changes
- [x] Document test results in progress.md
- [x] Fix any issues found
- **Status:** complete

### Phase 5: Delivery
- [x] Review changed files and summarize outcomes
- [x] Ensure deliverables are complete
- [ ] Deliver to user
- **Status:** in_progress

## Key Questions
1. Which state should be the source of truth for hook enablement?
2. Which code paths currently toggle hooks without going through that shared state?

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| Treat `AppSettings.hookMonitorEnabled` as the user-facing source of truth | Settings, sidebar, popup visibility, and monitor startup logic already key off this value. |
| Centralize side effects in `HookMonitorCoordinator` | Notch, Settings, and launch observers now all run the same enable/disable behavior. |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| New main-actor warnings after the first coordinator wiring | 1 | Replaced direct method references with explicit closures in the SwiftUI call sites. |

## Notes
- Re-read this plan before major decisions.
- Prefer changes that improve both perceived performance and clarity of interaction.
