import Foundation

// MARK: - Time / Ranking Dimensions

enum Period: String, CaseIterable {
    case week = "周"
    case month = "月"
    case year = "年"
}

enum RankingMode: String, CaseIterable {
    case byCourse = "按课程"
    case byStudent = "按学生"
}

// MARK: - Aggregated Income Types

struct ChartEntry: Identifiable {
    let id = UUID()
    let label: String
    let sortOrder: Int       // for correct x-axis ordering
    let courseName: String
    let courseColor: String
    let studentKey: String
    let income: Double
}

struct CourseIncome: Identifiable {
    let id = UUID()
    let name: String
    let colorHex: String
    let count: Int
    let income: Double
    let percentage: Double
}

struct StudentIncome: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let income: Double
    let percentage: Double
}
