import SwiftUI
import SwiftData
import EventKit

struct CalendarImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]
    @Query private var existingLessons: [Lesson]

    private let syncService = CalendarSyncService.shared

    @State private var step: ImportStep = .selectCalendars
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarIds: Set<String> = []
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    @State private var eventGroups: [EventGroup] = []

    enum ImportStep {
        case selectCalendars
        case mapAndImport
    }

    struct EventGroup: Identifiable {
        let id = UUID()
        let title: String
        let events: [EKEvent]
        var courseMapping: CourseMapping = .skip

        enum CourseMapping: Hashable {
            case existingCourse(Course)
            case createNew
            case skip

            static func == (lhs: CourseMapping, rhs: CourseMapping) -> Bool {
                switch (lhs, rhs) {
                case (.skip, .skip): return true
                case (.createNew, .createNew): return true
                case (.existingCourse(let a), .existingCourse(let b)): return a.id == b.id
                default: return false
                }
            }

            func hash(into hasher: inout Hasher) {
                switch self {
                case .skip: hasher.combine(0)
                case .createNew: hasher.combine(1)
                case .existingCourse(let c): hasher.combine(2); hasher.combine(c.id)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .selectCalendars:
                    calendarSelectionView
                case .mapAndImport:
                    mappingView
                }
            }
            .navigationTitle("从日历导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                availableCalendars = syncService.fetchCalendars()
            }
        }
    }

    // MARK: - Step 1: Calendar Selection

    private var calendarSelectionView: some View {
        List {
            Section("选择日历") {
                ForEach(Array(availableCalendars.indices), id: \.self) { i in
                    calendarRow(availableCalendars[i])
                }
            }

            Section("时间范围") {
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
            }

            Section {
                Button("查看日程") {
                    loadEvents()
                }
                .disabled(selectedCalendarIds.isEmpty)
            }
        }
    }

    // MARK: - Step 2: Mapping & Import

    private var mappingView: some View {
        List {
            Section {
                Text("共 \(eventGroups.flatMap(\.events).count) 个事件，\(eventGroups.count) 个分组")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(eventGroups.indices), id: \.self) { index in
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(eventGroups[index].title)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(eventGroups[index].events.count) 个事件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Picker("映射到", selection: $eventGroups[index].courseMapping) {
                            Text("跳过不导入").tag(EventGroup.CourseMapping.skip)
                            Text("新建课程「\(eventGroups[index].title)」").tag(EventGroup.CourseMapping.createNew)
                            ForEach(courses) { course in
                                Text(course.name).tag(EventGroup.CourseMapping.existingCourse(course))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            Section {
                Button("确认导入") {
                    performImport()
                }
                .disabled(!eventGroups.contains(where: { $0.courseMapping != .skip }))
            }
        }
    }

    @ViewBuilder
    private func calendarRow(_ cal: EKCalendar) -> some View {
        Button {
            toggleCalendar(cal)
        } label: {
            HStack {
                Circle()
                    .fill(Color(cgColor: cal.cgColor))
                    .frame(width: 12, height: 12)
                Text(cal.title)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedCalendarIds.contains(cal.calendarIdentifier) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleCalendar(_ calendar: EKCalendar) {
        if selectedCalendarIds.contains(calendar.calendarIdentifier) {
            selectedCalendarIds.remove(calendar.calendarIdentifier)
        } else {
            selectedCalendarIds.insert(calendar.calendarIdentifier)
        }
    }

    private func loadEvents() {
        let calendars = availableCalendars.filter { selectedCalendarIds.contains($0.calendarIdentifier) }
        let events = syncService.fetchEvents(from: calendars, start: startDate, end: endDate)

        // Group by title
        var grouped: [String: [EKEvent]] = [:]
        for event in events {
            let key = event.title ?? "未命名"
            grouped[key, default: []].append(event)
        }

        eventGroups = grouped.map { title, events in
            var group = EventGroup(title: title, events: events)
            // Auto-match by name
            if let match = courses.first(where: { $0.name == title }) {
                group.courseMapping = .existingCourse(match)
            }
            return group
        }.sorted { $0.title < $1.title }

        step = .mapAndImport
    }

    private func performImport() {
        var importedCount = 0

        for group in eventGroups {
            let course: Course?
            switch group.courseMapping {
            case .skip:
                continue
            case .existingCourse(let c):
                course = c
            case .createNew:
                let newCourse = Course(name: group.title)
                modelContext.insert(newCourse)
                course = newCourse
            }

            guard let course else { continue }

            for event in group.events {
                // Dedup check
                let eventDate = DateHelper.startOfDay(event.startDate)
                let isDuplicate = existingLessons.contains { lesson in
                    lesson.course?.id == course.id &&
                    DateHelper.isSameDay(lesson.date, eventDate) &&
                    abs(lesson.startTime.timeIntervalSince(event.startDate)) < 60
                }
                if isDuplicate { continue }

                let lesson = Lesson(
                    course: course,
                    date: eventDate,
                    startTime: event.startDate,
                    endTime: event.endDate,
                    notes: event.notes ?? "",
                    location: event.location ?? ""
                )
                modelContext.insert(lesson)
                importedCount += 1
            }
        }

        try? modelContext.save()
        dismiss()
    }
}
