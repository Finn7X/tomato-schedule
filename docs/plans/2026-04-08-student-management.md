# 学生管理模块 实现计划

**Goal:** 将课程 Tab 升级为管理 Tab（课程+学生），实现学生列表、学生详情、改名功能

**Spec:** `docs/specs/2026-04-07-student-management.md`

**Build verify:** `cd /Users/xujifeng/dev/TomatoSchedule && xcodegen generate && xcodebuild -project TomatoSchedule.xcodeproj -scheme TomatoSchedule -destination 'generic/platform=iOS Simulator' build`

---

## Task 1: ManagementView + CourseListContent 提取 + MainTabView

**Files:**
- Create: `Views/Management/ManagementView.swift`
- Modify: `Views/Course/CourseListView.swift` → rename struct to `CourseListContent`, remove NavigationStack + add toolbar/sheet
- Modify: `Views/MainTabView.swift` → swap CourseListView for ManagementView

## Task 2: StudentListContent 学生列表

**Files:**
- Create: `Views/Management/StudentListContent.swift`

## Task 3: StudentDetailView 学生详情 + 改名

**Files:**
- Create: `Views/Management/StudentDetailView.swift`
