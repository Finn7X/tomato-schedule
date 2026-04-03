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

    // MARK: - Parsed event model

    struct ParsedEvent {
        let event: EKEvent
        let courseName: String
        let studentName: String
    }

    struct EventGroup: Identifiable {
        let id = UUID()
        let parsedCourseName: String
        let parsedEvents: [ParsedEvent]
        var courseMapping: CourseMapping = .createNew

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
                let totalEvents = eventGroups.reduce(0) { $0 + $1.parsedEvents.count }
                Text("共 \(totalEvents) 个事件，识别出 \(eventGroups.count) 门课程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(eventGroups.indices), id: \.self) { index in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        // Course name + event count
                        HStack {
                            Text(eventGroups[index].parsedCourseName)
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(eventGroups[index].parsedEvents.count) 节")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Show parsed student names
                        let students = Set(eventGroups[index].parsedEvents.map(\.studentName).filter { !$0.isEmpty })
                        if !students.isEmpty {
                            Text("学生: \(students.sorted().joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        // Course mapping picker
                        Picker("映射到", selection: $eventGroups[index].courseMapping) {
                            Text("跳过不导入").tag(EventGroup.CourseMapping.skip)
                            Text("新建课程").tag(EventGroup.CourseMapping.createNew)
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

    // MARK: - Title Parsing

    /// Split event title into (courseName, studentName).
    /// Tries common separators: " · ", " - ", "-", "—", last resort splits on last space cluster.
    private static func parseTitle(_ title: String) -> (course: String, student: String) {
        let separators = [" · ", " - ", "·", "—", "-"]
        for sep in separators {
            let parts = title.split(separator: Substring(sep), maxSplits: 1)
            if parts.count == 2 {
                let course = parts[0].trimmingCharacters(in: .whitespaces)
                let student = parts[1].trimmingCharacters(in: .whitespaces)
                // Only treat as student if the second part is short (likely a name, not a long description)
                if student.count <= 10 && !student.isEmpty {
                    return (course, student)
                }
            }
        }
        return (title.trimmingCharacters(in: .whitespaces), "")
    }

    /// Fuzzy match a parsed course name against existing courses.
    /// Priority: exact → contains → prefix.
    private func matchCourse(for name: String) -> Course? {
        // Exact
        if let exact = courses.first(where: { $0.name == name }) {
            return exact
        }
        // Course name contains the parsed name, or vice versa
        if let contains = courses.first(where: {
            $0.name.contains(name) || name.contains($0.name)
        }) {
            return contains
        }
        return nil
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

        // Parse all events
        let parsed = events.map { event -> ParsedEvent in
            let title = event.title ?? "未命名"
            let (courseName, studentName) = Self.parseTitle(title)
            return ParsedEvent(event: event, courseName: courseName, studentName: studentName)
        }

        // Group by parsed course name
        var grouped: [String: [ParsedEvent]] = [:]
        for p in parsed {
            grouped[p.courseName, default: []].append(p)
        }

        eventGroups = grouped.map { courseName, events in
            var group = EventGroup(parsedCourseName: courseName, parsedEvents: events)
            // Smart matching
            if let matched = matchCourse(for: courseName) {
                group.courseMapping = .existingCourse(matched)
            } else {
                group.courseMapping = .createNew
            }
            return group
        }.sorted { $0.parsedCourseName < $1.parsedCourseName }

        step = .mapAndImport
    }

    private func freezePrice(for lesson: Lesson) {
        guard !lesson.isPriceOverridden else { return }
        let rate = lesson.course?.hourlyRate ?? 0
        let minutes = DateHelper.calendar.dateComponents(
            [.minute], from: lesson.startTime, to: lesson.endTime
        ).minute ?? 0
        let price = rate > 0 ? (rate * Double(minutes) / 60.0 * 100).rounded() / 100 : 0
        lesson.priceOverride = price
        lesson.isPriceOverridden = true
        lesson.isManualPrice = false
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
                let newCourse = Course(name: group.parsedCourseName)
                modelContext.insert(newCourse)
                course = newCourse
            }

            guard let course else { continue }

            for parsed in group.parsedEvents {
                let event = parsed.event
                let eventDate = DateHelper.startOfDay(event.startDate)

                // Dedup
                let isDuplicate = existingLessons.contains { lesson in
                    lesson.course?.id == course.id &&
                    DateHelper.isSameDay(lesson.date, eventDate) &&
                    abs(lesson.startTime.timeIntervalSince(event.startDate)) < 60
                }
                if isDuplicate { continue }

                let lesson = Lesson(
                    course: course,
                    studentName: parsed.studentName,
                    date: eventDate,
                    startTime: event.startDate,
                    endTime: event.endDate,
                    notes: event.notes ?? "",
                    location: event.location ?? ""
                )
                freezePrice(for: lesson)
                modelContext.insert(lesson)
                importedCount += 1
            }
        }

        try? modelContext.save()
        dismiss()
    }
}
