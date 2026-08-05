import Foundation

enum SchoolScheduleSource: String, Codable, CaseIterable, Equatable {
    case manual
    case mailAssisted
}

enum SchoolCalendarExceptionKind: String, Codable, Equatable {
    case holiday
    case schoolDay
}

struct SchoolWeekdayRule: Codable, Equatable, Identifiable {
    var weekday: Int
    var isEnabled: Bool
    var startMinutes: Int
    var endMinutes: Int

    var id: Int { weekday }

    var hasValidWindow: Bool {
        (0..<1_440).contains(startMinutes) && (1...1_440).contains(endMinutes) && startMinutes < endMinutes
    }
}

struct SchoolCalendarException: Codable, Equatable, Identifiable {
    var id: UUID
    /// 家庭当前时区里的 yyyy-MM-dd；避免把“放假日”错误换算到相邻日期。
    var dateKey: String
    var kind: SchoolCalendarExceptionKind
    var title: String
    var startMinutes: Int?
    var endMinutes: Int?
    var source: SchoolScheduleSource
    var guardianConfirmed: Bool

    var hasExplicitWindow: Bool {
        guard let startMinutes, let endMinutes else { return false }
        return (0..<1_440).contains(startMinutes) && (1...1_440).contains(endMinutes) && startMinutes < endMinutes
    }
}

struct ChildSchoolModeProfile: Codable, Equatable {
    var childID: UUID
    var isEnabled: Bool
    var source: SchoolScheduleSource
    var defaultStartMinutes: Int
    var defaultEndMinutes: Int
    var weekdayRules: [SchoolWeekdayRule]
    var exceptions: [SchoolCalendarException]
    var updatedAt: Date

    static func initial(childID: UUID, now: Date = Date()) -> ChildSchoolModeProfile {
        ChildSchoolModeProfile(
            childID: childID,
            isEnabled: false,
            source: .manual,
            defaultStartMinutes: 8 * 60,
            defaultEndMinutes: 15 * 60,
            weekdayRules: (1...7).map { weekday in
                SchoolWeekdayRule(
                    weekday: weekday,
                    isEnabled: (2...6).contains(weekday),
                    startMinutes: 8 * 60,
                    endMinutes: 15 * 60
                )
            },
            exceptions: [],
            updatedAt: now
        )
    }
}

enum SchoolDynamicCategory: String, Codable, CaseIterable, Equatable {
    case schedule
    case holiday
    case grade
    case teacherFeedback
    case attendance
    case activity
}

struct SchoolDynamicRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var childID: UUID
    var category: SchoolDynamicCategory
    var title: String
    /// 只保留结构化摘要；邮件原文永不进入家庭快照。
    var summary: String
    var eventDateKey: String?
    var schoolName: String? = nil
    var source: SchoolScheduleSource
    var createdAt: Date
}

struct SchoolModeEvaluation: Equatable {
    var isActive: Bool
    var startsAt: Date?
    var endsAt: Date?
    var reason: String
}

enum SchoolModeRuleEngine {
    static func evaluate(
        profile: ChildSchoolModeProfile,
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SchoolModeEvaluation {
        guard profile.isEnabled else {
            return SchoolModeEvaluation(isActive: false, startsAt: nil, endsAt: nil, reason: "disabled")
        }

        let dateKey = SchoolModeDateKey.string(from: date, calendar: calendar)
        if let exception = profile.exceptions.first(where: { $0.guardianConfirmed && $0.dateKey == dateKey }) {
            if exception.kind == .holiday {
                return SchoolModeEvaluation(isActive: false, startsAt: nil, endsAt: nil, reason: "holiday")
            }
            let start = exception.hasExplicitWindow ? exception.startMinutes! : profile.defaultStartMinutes
            let end = exception.hasExplicitWindow ? exception.endMinutes! : profile.defaultEndMinutes
            return evaluation(for: date, startMinutes: start, endMinutes: end, reason: "school-day-exception", calendar: calendar)
        }

        let weekday = calendar.component(.weekday, from: date)
        guard let rule = profile.weekdayRules.first(where: { $0.weekday == weekday && $0.isEnabled }),
              rule.hasValidWindow else {
            return SchoolModeEvaluation(isActive: false, startsAt: nil, endsAt: nil, reason: "no-school-rule")
        }
        return evaluation(
            for: date,
            startMinutes: rule.startMinutes,
            endMinutes: rule.endMinutes,
            reason: "weekly-rule",
            calendar: calendar
        )
    }

    private static func evaluation(
        for date: Date,
        startMinutes: Int,
        endMinutes: Int,
        reason: String,
        calendar: Calendar
    ) -> SchoolModeEvaluation {
        let day = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .minute, value: startMinutes, to: day),
              let end = calendar.date(byAdding: .minute, value: endMinutes, to: day) else {
            return SchoolModeEvaluation(isActive: false, startsAt: nil, endsAt: nil, reason: "invalid-window")
        }
        return SchoolModeEvaluation(
            isActive: date >= start && date < end,
            startsAt: start,
            endsAt: end,
            reason: reason
        )
    }
}

enum SchoolModeDateKey {
    static func string(from date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
