import Foundation

struct SchoolMailFinding: Codable, Equatable, Identifiable {
    var id: UUID
    var category: SchoolDynamicCategory
    var title: String
    var summary: String
    var dateKey: String?
    var startMinutes: Int?
    var endMinutes: Int?
    var childNameHint: String? = nil
    var schoolName: String? = nil

    var canChangeSchedule: Bool {
        category == .holiday || category == .schedule
    }
}

enum SchoolMailAnalyzer {
    private struct Payload: Decodable {
        var findings: [Finding]
    }

    private struct Finding: Decodable {
        var category: String
        var title: String
        var summary: String
        var date: String?
        var startTime: String?
        var endTime: String?
        var child: String?
        var school: String?
    }

    static let maximumCharacters = 12_000

    static func systemPrompt(language: AppInterfaceLanguage, childNames: [String] = []) -> String {
        let childContext = childNames.isEmpty
            ? "No child roster was supplied. Use null for child when the email does not state it."
            : "Known children in this family: \(childNames.joined(separator: ", ")). Match only when the email provides evidence; otherwise use null."
        return """
        You extract structured school information from one or more emails supplied by a guardian. Return JSON only:
        {"findings":[{"category":"holiday|schedule|grade|teacher_feedback|attendance|activity","title":"...","summary":"...","date":"YYYY-MM-DD or null","startTime":"HH:mm or null","endTime":"HH:mm or null","child":"known child name or null","school":"school name or null"}]}
        \(childContext)
        Never invent a date, school start time, or school end time. Missing values must be null. Keep title and summary in \(language == .english ? "English" : "Simplified Chinese"). Do not include names, email addresses, phone numbers, message IDs, signatures, or the original email body. Grades and teacher feedback may be summarized factually without diagnosis. An ordinary school day is category schedule; a closure or vacation is holiday.
        """
    }

    static func userPrompt(emailText: String) -> String {
        let clipped = String(emailText.prefix(maximumCharacters))
        return "Extract only confirmed school facts from this email. EMAIL START\n\(clipped)\nEMAIL END"
    }

    static func parse(_ raw: String) -> [SchoolMailFinding] {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return [] }

        return payload.findings.prefix(20).compactMap { item in
            guard let category = category(from: item.category) else { return nil }
            let title = sanitized(item.title, limit: 90)
            let summary = sanitized(item.summary, limit: 360)
            guard !title.isEmpty, !summary.isEmpty else { return nil }
            let date = validDateKey(item.date)
            let start = minutes(from: item.startTime)
            let end = minutes(from: item.endTime)
            let validWindow = start != nil && end != nil && start! < end!
            return SchoolMailFinding(
                id: UUID(),
                category: category,
                title: title,
                summary: summary,
                dateKey: date,
                startMinutes: validWindow ? start : nil,
                endMinutes: validWindow ? end : nil,
                childNameHint: optionalSanitized(item.child, limit: 40),
                schoolName: optionalSanitized(item.school, limit: 80)
            )
        }
    }

    private static func category(from raw: String) -> SchoolDynamicCategory? {
        switch raw.lowercased().replacingOccurrences(of: "-", with: "_") {
        case "holiday": return .holiday
        case "schedule", "school_day": return .schedule
        case "grade": return .grade
        case "teacher_feedback": return .teacherFeedback
        case "attendance": return .attendance
        case "activity": return .activity
        default: return nil
        }
    }

    private static func validDateKey(_ raw: String?) -> String? {
        guard let raw, raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: raw) == nil ? nil : raw
    }

    private static func minutes(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func sanitized(_ raw: String, limit: Int) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
            .replacingOccurrences(of: #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, with: "", options: .regularExpression)
    }

    private static func optionalSanitized(_ raw: String?, limit: Int) -> String? {
        guard let raw else { return nil }
        let value = sanitized(raw, limit: limit)
        return value.isEmpty ? nil : value
    }
}
