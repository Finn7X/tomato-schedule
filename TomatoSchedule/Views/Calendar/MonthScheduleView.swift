import SwiftUI
import SwiftData

struct MonthScheduleView: View {
    @State private var displayedMonth = Date.now
    @State private var selectedDate = Date.now
    @State private var showingAddLesson = false
    @State private var editingLesson: Lesson?

    @Query private var allLessons: [Lesson]

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    private func lessonsForDay(_ date: Date) -> [Lesson] {
        allLessons
            .filter { DateHelper.isSameDay($0.date, date) }
            .sorted { $0.startTime < $1.startTime }
    }

    private var calendarDays: [Date?] {
        let days = DateHelper.daysInMonth(for: displayedMonth)
        guard let firstDay = days.first else { return [] }

        let weekday = DateHelper.calendar.component(.weekday, from: firstDay)
        let offset = (weekday + 5) % 7

        var result: [Date?] = Array(repeating: nil, count: offset)
        result.append(contentsOf: days.map { Optional($0) })
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(DateHelper.monthString(displayedMonth))
                        .font(.headline)
                        .onTapGesture {
                            displayedMonth = .now
                            selectedDate = .now
                        }
                    Spacer()
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .padding()

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(weekdayHeaders, id: \.self) { header in
                        Text(header)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(height: 30)
                    }
                }
                .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(height: 48)
                        }
                    }
                }
                .padding(.horizontal)

                Divider().padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(DateHelper.dateString(selectedDate)) \(DateHelper.weekdaySymbol(selectedDate))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            showingAddLesson = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    let dayLessons = lessonsForDay(selectedDate)
                    if dayLessons.isEmpty {
                        Text("暂无课程")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(dayLessons) { lesson in
                                    LessonCardView(lesson: lesson)
                                        .onTapGesture { editingLesson = lesson }
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle("月视图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") {
                        displayedMonth = .now
                        selectedDate = .now
                    }
                }
            }
            .sheet(isPresented: $showingAddLesson) {
                LessonFormView(initialDate: selectedDate)
            }
            .sheet(item: $editingLesson) { lesson in
                LessonFormView(lesson: lesson, initialDate: lesson.date)
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let isSelected = DateHelper.isSameDay(date, selectedDate)
        let isToday = DateHelper.isSameDay(date, .now)
        let hasLessons = !lessonsForDay(date).isEmpty
        let lessonCount = lessonsForDay(date).count

        VStack(spacing: 2) {
            Text("\(DateHelper.calendar.component(.day, from: date))")
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(isSelected ? .white : isToday ? Color.accentColor : .primary)

            if hasLessons {
                Text("\(lessonCount)节")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .onTapGesture { selectedDate = date }
    }

    private func moveMonth(_ offset: Int) {
        if let newMonth = DateHelper.calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
            displayedMonth = newMonth
            let range = DateHelper.monthRange(for: newMonth)
            if selectedDate < range.start || selectedDate >= range.end {
                selectedDate = range.start
            }
        }
    }
}
