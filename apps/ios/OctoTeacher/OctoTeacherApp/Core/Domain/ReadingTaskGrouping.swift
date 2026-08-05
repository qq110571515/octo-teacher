import Foundation

enum ReadingTaskGrouping {
    static func key(for assignment: TaskAssignment) -> String? {
        guard let reading = assignment.task.reading else { return nil }
        if let importedBookId = reading.importedBookId {
            return "book-\(importedBookId.uuidString)"
        }
        let normalizedTitle = normalizedBookTitle(reading.bookTitle)
        return normalizedTitle.isEmpty ? nil : "title-\(normalizedTitle)"
    }

    static func title(for assignment: TaskAssignment) -> String? {
        guard let reading = assignment.task.reading else { return nil }
        let title = reading.bookTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? assignment.task.title : title
    }

    static func chapterLabel(for assignment: TaskAssignment) -> String {
        guard let reading = assignment.task.reading else { return assignment.task.title }
        let chapter = reading.chapterPlanText.trimmingCharacters(in: .whitespacesAndNewlines)
        return chapter.isEmpty ? assignment.task.title : chapter
    }

    static func progressText(for assignments: [TaskAssignment]) -> String {
        let done = assignments.filter { $0.status == .approved }.count
        return "\(done)/\(assignments.count)"
    }

    static func statusSummary(for assignments: [TaskAssignment]) -> String {
        statusSummary(for: assignments, language: .chinese)
    }

    static func statusSummary(for assignments: [TaskAssignment], language: AppInterfaceLanguage) -> String {
        let open = assignments.filter { $0.status == .open || $0.status == .rejected }.count
        let waiting = assignments.filter { $0.status == .submitted }.count
        let done = assignments.filter { $0.status == .approved }.count
        var parts: [String] = []
        if open > 0 { parts.append(language.pick("待读 \(open)", "To read \(open)")) }
        if waiting > 0 { parts.append(language.pick("待确认 \(waiting)", "Waiting \(waiting)")) }
        if done > 0 { parts.append(language.pick("已完成 \(done)", "Done \(done)")) }
        return parts.isEmpty ? language.pick("暂无进展", "No progress yet") : parts.joined(separator: " · ")
    }

    static func totalReward(for assignments: [TaskAssignment]) -> Int {
        assignments.reduce(0) { $0 + $1.task.rewardMinutes }
    }

    private static func normalizedBookTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
