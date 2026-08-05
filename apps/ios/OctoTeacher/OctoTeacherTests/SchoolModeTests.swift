import XCTest
@testable import OctoTeacher

#if canImport(DeviceActivity)
import DeviceActivity
#endif

final class SchoolModeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testWeeklyRuleActivatesAtStartAndReleasesAtEnd() throws {
        let childID = UUID()
        var profile = ChildSchoolModeProfile.initial(childID: childID)
        profile.isEnabled = true
        profile.weekdayRules = [
            SchoolWeekdayRule(weekday: 2, isEnabled: true, startMinutes: 8 * 60, endMinutes: 15 * 60)
        ]

        XCTAssertFalse(SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T07:59:59Z"), calendar: calendar).isActive)
        XCTAssertTrue(SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T08:00:00Z"), calendar: calendar).isActive)
        XCTAssertTrue(SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T14:59:59Z"), calendar: calendar).isActive)
        XCTAssertFalse(SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T15:00:00Z"), calendar: calendar).isActive)
    }

    func testConfirmedHolidayOverridesWeeklySchoolDay() {
        var profile = ChildSchoolModeProfile.initial(childID: UUID())
        profile.isEnabled = true
        profile.exceptions = [
            SchoolCalendarException(
                id: UUID(),
                dateKey: "2026-07-13",
                kind: .holiday,
                title: "Summer closure",
                startMinutes: nil,
                endMinutes: nil,
                source: .mailAssisted,
                guardianConfirmed: true
            )
        ]

        let result = SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T10:00:00Z"), calendar: calendar)
        XCTAssertFalse(result.isActive)
        XCTAssertEqual(result.reason, "holiday")
    }

    func testSchoolDayWithoutHoursUsesParentConfirmedDefaults() {
        var profile = ChildSchoolModeProfile.initial(childID: UUID())
        profile.isEnabled = true
        profile.defaultStartMinutes = 9 * 60
        profile.defaultEndMinutes = 13 * 60
        profile.weekdayRules = []
        profile.exceptions = [
            SchoolCalendarException(
                id: UUID(),
                dateKey: "2026-07-18",
                kind: .schoolDay,
                title: "Saturday school",
                startMinutes: nil,
                endMinutes: nil,
                source: .mailAssisted,
                guardianConfirmed: true
            )
        ]

        let result = SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-18T10:00:00Z"), calendar: calendar)
        XCTAssertTrue(result.isActive)
        XCTAssertEqual(result.startsAt, date("2026-07-18T09:00:00Z"))
        XCTAssertEqual(result.endsAt, date("2026-07-18T13:00:00Z"))
    }

    func testUnconfirmedMailExceptionCannotChangeDeviceRule() {
        var profile = ChildSchoolModeProfile.initial(childID: UUID())
        profile.isEnabled = true
        profile.exceptions = [
            SchoolCalendarException(
                id: UUID(),
                dateKey: "2026-07-13",
                kind: .holiday,
                title: "Unconfirmed",
                startMinutes: nil,
                endMinutes: nil,
                source: .mailAssisted,
                guardianConfirmed: false
            )
        ]

        XCTAssertTrue(SchoolModeRuleEngine.evaluate(profile: profile, at: date("2026-07-13T10:00:00Z"), calendar: calendar).isActive)
    }

    func testMailParserKeepsStrictFactsAndNeverInventsMissingHours() throws {
        let raw = #"{"findings":[{"category":"holiday","title":"No school","summary":"Campus closed.","date":"2026-07-17","startTime":null,"endTime":null,"child":"Sam","school":"Lincoln Elementary"},{"category":"grade","title":"Math update","summary":"Current score is 92.","date":null,"startTime":null,"endTime":null,"child":null,"school":null}]}"#
        let findings = SchoolMailAnalyzer.parse(raw)

        XCTAssertEqual(findings.count, 2)
        XCTAssertEqual(findings[0].category, .holiday)
        XCTAssertEqual(findings[0].dateKey, "2026-07-17")
        XCTAssertNil(findings[0].startMinutes)
        XCTAssertNil(findings[0].endMinutes)
        XCTAssertEqual(findings[0].childNameHint, "Sam")
        XCTAssertEqual(findings[0].schoolName, "Lincoln Elementary")
        XCTAssertEqual(findings[1].category, .grade)
    }

    func testMailPromptUsesKnownChildrenWithoutPermittingGuesses() {
        let prompt = SchoolMailAnalyzer.systemPrompt(language: .english, childNames: ["Sam", "Alex"])
        XCTAssertTrue(prompt.contains("Sam, Alex"))
        XCTAssertTrue(prompt.contains("otherwise use null"))
        XCTAssertTrue(prompt.contains("Never invent"))
    }

    func testConfirmedFindingsPersistStructuredSummaryWithoutMailBody() throws {
        let store = LocalFamilyStore()
        let sensitiveBody = "private-body-marker parent@example.com"
        let finding = SchoolMailFinding(
            id: UUID(),
            category: .teacherFeedback,
            title: "Teacher note",
            summary: "Participated well in class.",
            dateKey: "2026-07-14",
            startMinutes: nil,
            endMinutes: nil,
            childNameHint: "Child",
            schoolName: "Lincoln Elementary"
        )
        store.confirmSchoolMailFindings([finding], for: store.activeChildId)

        let data = try JSONEncoder().encode(store.snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains(sensitiveBody))
        XCTAssertFalse(json.contains("parent@example.com"))
        XCTAssertTrue(json.contains("Participated well in class"))
        XCTAssertTrue(json.contains("Lincoln Elementary"))
        XCTAssertEqual(store.snapshot.schemaVersion, 8)
        XCTAssertTrue(store.schoolDynamicsPromptSummary(for: store.activeChildId).contains("teacherFeedback"))
        XCTAssertTrue(store.schoolDynamicsPromptSummary(for: store.activeChildId).contains("Lincoln Elementary"))
    }

    func testSchoolFindingCreatesCompactGrowthMemoryEvent() {
        let childID = UUID()
        let event = GrowthMemoryEventFactory.schoolDynamic(
            childId: childID,
            category: .teacherFeedback,
            title: "Participated thoughtfully in class",
            schoolName: "Lincoln Elementary"
        )

        XCTAssertEqual(event.childId, childID)
        XCTAssertEqual(event.kind, .schoolDynamic)
        XCTAssertEqual(event.tags, ["teacherFeedback"])
        XCTAssertTrue(event.summary.contains("Lincoln Elementary"))
        XCTAssertFalse(event.summary.contains("@"))
    }

    func testSharedRuntimeSkipsWeeklyShieldOnHolidayAndAllowsOverride() {
        let runtime = PersistedSchoolModeRuntime(
            childID: UUID(),
            isEnabled: true,
            defaultStartMinutes: 480,
            defaultEndMinutes: 900,
            rules: [PersistedSchoolModeRule(weekday: 2, startMinutes: 480, endMinutes: 900)],
            exceptions: [
                PersistedSchoolModeException(
                    dateKey: "2026-07-13",
                    isHoliday: true,
                    startMinutes: nil,
                    endMinutes: nil
                )
            ],
            activityNames: []
        )
        let monday = date("2026-07-13T10:00:00Z")

        XCTAssertFalse(runtime.shouldApplyShield(at: monday, activityName: "octoteacher.school-mode.weekly.2", calendar: calendar))
        XCTAssertFalse(runtime.shouldClearShield(at: monday, activityName: "octoteacher.school-mode.weekly.2", calendar: calendar))
    }

    #if canImport(DeviceActivity)
    func testDeviceActivityAcceptsAWeeklySchoolWindow() throws {
        var start = DateComponents()
        start.calendar = calendar
        start.weekday = 2
        start.hour = 8
        var end = DateComponents()
        end.calendar = calendar
        end.weekday = 2
        end.hour = 15
        let schedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true)
        let interval = try XCTUnwrap(schedule.nextInterval)
        let deviceCalendar = Calendar.current

        XCTAssertEqual(deviceCalendar.component(.weekday, from: interval.start), 2)
        XCTAssertEqual(deviceCalendar.component(.hour, from: interval.start), 8)
        XCTAssertEqual(deviceCalendar.component(.weekday, from: interval.end), 2)
        XCTAssertEqual(deviceCalendar.component(.hour, from: interval.end), 15)
        XCTAssertEqual(interval.duration, 7 * 60 * 60, accuracy: 1)
    }
    #endif

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
