import SwiftUI
import SwiftData

struct WeekScheduleView: View {
    @State private var weekStart: Date = DateHelper.weekRange(for: .now).start
    @State private var showingAddLesson = false
    @State private var editingLesson: Lesson?
    @State private var selectedDayForAdd: Date = .now

    @Query private var allLessons: [Lesson]

    private var weekDays: [Date] {
        (0..<7).compactMap {
            DateHelper.calendar.date(byAdding: .day, value: $0, to: weekStart)
        }
    }

    private func lessons(for date: Date) -> [Lesson] {
        allLessons
            .filter { DateHelper.isSameDay($0.date, date) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { moveWeek(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(weekTitle)
                        .font(.headline)
                        .onTapGesture { goToThisWeek() }
                    Spacer()
                    Button { moveWeek(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding()

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(weekDays, id: \.self) { day in
                            dayRow(day)
                            if day != weekDays.last {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }
            }
            .navigationTitle("周视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedDayForAdd = .now
                        showingAddLesson = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("本周") { goToThisWeek() }
                }
            }
            .sheet(isPresented: $showingAddLesson) {
                LessonFormView(initialDate: selectedDayForAdd)
            }
            .sheet(item: $editingLesson) { lesson in
                LessonFormView(lesson: lesson, initialDate: lesson.date)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ day: Date) -> some View {
        let dayLessons = lessons(for: day)
        let isToday = DateHelper.isSameDay(day, .now)

        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(DateHelper.weekdaySymbol(day))
                    .font(.caption2)
                    .foregroundStyle(isToday ? .white : .secondary)
                Text("\(DateHelper.calendar.component(.day, from: day))")
                    .font(.title3)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? .white : .primary)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isToday ? Color.accentColor : Color.clear)
            )

            if dayLessons.isEmpty {
                Text("无课程")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedDayForAdd = day
                        showingAddLesson = true
                    }
            } else {
                VStack(spacing: 4) {
                    ForEach(dayLessons) { lesson in
                        LessonCardView(lesson: lesson, compact: true)
                            .onTapGesture { editingLesson = lesson }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var weekTitle: String {
        let end = DateHelper.calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(DateHelper.dateString(weekStart)) - \(DateHelper.dateString(end))"
    }

    private func moveWeek(_ offset: Int) {
        if let newStart = DateHelper.calendar.date(byAdding: .weekOfYear, value: offset, to: weekStart) {
            weekStart = newStart
        }
    }

    private func goToThisWeek() {
        weekStart = DateHelper.weekRange(for: .now).start
    }
}
