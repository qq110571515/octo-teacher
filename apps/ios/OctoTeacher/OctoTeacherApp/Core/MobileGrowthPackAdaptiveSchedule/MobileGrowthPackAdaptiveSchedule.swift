import Foundation

/// iOS 成长包自适应日程的纯本地只读投影。
///
/// 这一层把成长包执行中心、证据时间线、学校作业、基础习惯/家务、家庭日历、
/// 睡眠/安静窗口、成长积分兑换窗口和复核节奏整理成孩子/家长可读的“今日计划”。
/// 它不读取真实 schedule/calendar/homework/reward/ledger/device/ref，不打开系统日历，
/// 不写账本、不发成长积分、不兑换奖励，也不触发任何设备或屏幕时间动作。
enum MobileGrowthPackAdaptiveScheduleSlotKind: String, CaseIterable, Equatable {
    case growthPackStep = "growth_pack_step"
    case schoolHomework = "school_homework"
    case habitChore = "habit_chore"
    case evidenceReview = "evidence_review"
    case familyCalendar = "family_calendar"
    case sleepQuietWindow = "sleep_quiet_window"
    case rewardWindow = "reward_window"
    case reviewCadence = "review_cadence"

    var title: String {
        switch self {
        case .growthPackStep: return "成长包步骤"
        case .schoolHomework: return "学校作业"
        case .habitChore: return "习惯与家务"
        case .evidenceReview: return "证据复核"
        case .familyCalendar: return "家庭日历"
        case .sleepQuietWindow: return "睡眠安静窗口"
        case .rewardWindow: return "成长积分兑换窗口"
        case .reviewCadence: return "复核节奏"
        }
    }
}

enum MobileGrowthPackAdaptiveScheduleSlotStatus: String, Equatable {
    case suitableNow = "suitable_now"
    case later
    case notNow = "not_now"
    case waitingReview = "waiting_review"
    case blocked

    var label: String {
        switch self {
        case .suitableNow: return "现在适合"
        case .later: return "稍后再做"
        case .notNow: return "现在不适合"
        case .waitingReview: return "等复核"
        case .blocked: return "已阻断"
        }
    }
}

enum MobileGrowthPackAdaptiveScheduleFindingCode: String, Equatable {
    case readOnlySchedule = "READ_ONLY_SCHEDULE"
    case sleepWindowProtected = "SLEEP_WINDOW_PROTECTED"
    case homeworkPriorityConflict = "HOMEWORK_PRIORITY_CONFLICT"
    case rewardWindowReview = "REWARD_WINDOW_REVIEW"
    case evidenceGap = "EVIDENCE_GAP"
    case guardianReviewRequired = "GUARDIAN_REVIEW_REQUIRED"
    case unsafePayloadBlocked = "UNSAFE_PAYLOAD_BLOCKED"
}

struct MobileGrowthPackAdaptiveScheduleSlot: Identifiable, Equatable {
    var publicSlotRef: String
    var kind: MobileGrowthPackAdaptiveScheduleSlotKind
    var status: MobileGrowthPackAdaptiveScheduleSlotStatus
    var title: String
    var windowLabel: String
    var detail: String
    var reasonNotNow: String
    var nextStep: String
    var safetyNote: String
    var visibleToChild: Bool
    var visibleToGuardian: Bool
    var sleepConflict: Bool
    var homeworkConflict: Bool
    var rewardConflict: Bool
    var requiresGuardianReview: Bool
    var hasEvidenceGap: Bool
    var sortOrder: Int

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let opensSystemCalendar = false
    let readsHealthKit = false
    let controlsScreenTime = false
    let uploadsMedia = false
    let publishesContent = false
    let createsOrder = false
    let writesEntitlement = false

    var id: String { publicSlotRef }

    var displayValues: [String] {
        [
            publicSlotRef,
            kind.rawValue,
            kind.title,
            status.rawValue,
            status.label,
            title,
            windowLabel,
            detail,
            reasonNotNow,
            nextStep,
            safetyNote
        ]
    }

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || opensSystemCalendar
            || readsHealthKit || controlsScreenTime || uploadsMedia || publishesContent
            || createsOrder || writesEntitlement
    }
}

struct MobileGrowthPackAdaptiveScheduleFinding: Identifiable, Equatable {
    var code: MobileGrowthPackAdaptiveScheduleFindingCode
    var message: String
    var actionRequired: Bool
    var visibleToChild: Bool

    var id: String { code.rawValue }
    var displayValues: [String] { [code.rawValue, message] }
}

struct MobileGrowthPackAdaptiveSchedulePublicSummary: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var slotCount: Int
    var visibleSlotCount: Int
    var suitableNowCount: Int
    var notNowCount: Int
    var sleepConflictCount: Int
    var homeworkConflictCount: Int
    var rewardConflictCount: Int
    var evidenceGapCount: Int
    var guardianReviewCount: Int
    var findingCodes: [MobileGrowthPackAdaptiveScheduleFindingCode]

    let callsNetwork = false
    let callsAiProvider = false
    let callsLocalModel = false
    let callsLms = false
    let writesSchoolSystem = false
    let writesLedger = false
    let grantsCredit = false
    let unlocksDevice = false
    let sendsNotification = false
    let opensExternalLink = false
    let opensCamera = false
    let opensPhotoLibrary = false
    let opensFilePicker = false
    let opensSystemCalendar = false
    let readsHealthKit = false
    let controlsScreenTime = false
    let uploadsMedia = false
    let publishesContent = false
    let createsOrder = false
    let writesEntitlement = false

    var hasTriggeredSideEffect: Bool {
        callsNetwork || callsAiProvider || callsLocalModel || callsLms || writesSchoolSystem
            || writesLedger || grantsCredit || unlocksDevice || sendsNotification || opensExternalLink
            || opensCamera || opensPhotoLibrary || opensFilePicker || opensSystemCalendar
            || readsHealthKit || controlsScreenTime || uploadsMedia || publishesContent
            || createsOrder || writesEntitlement
    }
}

struct MobileGrowthPackAdaptiveSchedule: Equatable {
    var role: MobileGrowthPackExecutionHubRole
    var title: String
    var subtitle: String
    var audienceNote: String
    var slots: [MobileGrowthPackAdaptiveScheduleSlot]
    var findings: [MobileGrowthPackAdaptiveScheduleFinding]
    var publicSummary: MobileGrowthPackAdaptiveSchedulePublicSummary

    var displayValues: [String] {
        [role.rawValue, title, subtitle, audienceNote]
            + slots.flatMap(\.displayValues)
            + findings.flatMap(\.displayValues)
    }

    var hasUnsafeDisplayPayload: Bool {
        MobileGrowthPackAdaptiveScheduleBuilder.hasUnsafeDisplayPayload(displayValues)
    }
}

struct MobileGrowthPackAdaptiveScheduleInput: Equatable {
    var generatedAt: String
    var unsafePayload: String?

    static let mock = MobileGrowthPackAdaptiveScheduleInput(
        generatedAt: "2026-06-25T01:10:00.000Z",
        unsafePayload: nil
    )
}

struct MobileGrowthPackAdaptiveScheduleBuilder {
    private static let redactionSalt = "mobile-growth-pack-adaptive-schedule-v1"
    private static let sensitiveMarkers = [
        "child:", "family:", "school:", "teacher:", "guardian:", "relative:", "creator:",
        "pack:", "homework:", "quiz:", "question:", "answer key", "answerkey", "答案键",
        "proof:", "media:", "photo:", "screenshot:", "transcript", "provider:", "model:",
        "resource:", "link:", "url:", "showcase:", "reward:", "order:", "inventory:",
        "address:", "ledger:", "device:", "entitlement:", "calendar:", "schedule:",
        "event:", "publicref", "task:", "claim:", "token", "api_key", "apikey", "secret",
        "credit amount", "成长积分金额", "账本明细", "设备命令", "复核策略", "日历id", "calendarid",
        "http://", "https://", "file://", "/users/", "/volumes/", "192.168.", ".local"
    ]

    func build(
        role: MobileGrowthPackExecutionHubRole,
        input: MobileGrowthPackAdaptiveScheduleInput = .mock
    ) -> MobileGrowthPackAdaptiveSchedule {
        if let unsafePayload = input.unsafePayload, Self.hasUnsafeDisplayPayload([unsafePayload]) {
            return blockedSchedule(role: role)
        }

        let allSlots = makeSlots(for: role)
        let visibleSlots = allSlots.filter { slot in
            switch role {
            case .child: return slot.visibleToChild
            case .guardian: return slot.visibleToGuardian
            }
        }
        .sorted { left, right in
            if left.sortOrder == right.sortOrder {
                return left.publicSlotRef < right.publicSlotRef
            }
            return left.sortOrder < right.sortOrder
        }
        let findings = makeFindings(role: role, slots: visibleSlots)

        return MobileGrowthPackAdaptiveSchedule(
            role: role,
            title: role == .child ? "成长包今日计划" : "成长包日程复核",
            subtitle: role == .child
                ? "按顺序看今天适合做什么、为什么现在先不做；这里只读，不会自动安排或发奖励。"
                : "只读复核排期冲突、睡眠/作业/家务/奖励窗口风险、证据缺口和人工复核边界。",
            audienceNote: role == .child
                ? "这里只显示安全提示和下一步；先休息、先作业、奖励等家长确认都是为你好。"
                : "这里只读整理今日节奏；真正改日程、发任务、履约奖励或发成长积分仍走正式流程。",
            slots: visibleSlots,
            findings: findings,
            publicSummary: summary(role: role, allSlots: allSlots, visibleSlots: visibleSlots, findings: findings)
        )
    }

    static func hasUnsafeDisplayPayload(_ values: [String]) -> Bool {
        let joined = values.joined(separator: " ").lowercased()
        return sensitiveMarkers.contains { joined.contains($0) }
    }

    private func blockedSchedule(role: MobileGrowthPackExecutionHubRole) -> MobileGrowthPackAdaptiveSchedule {
        let finding = MobileGrowthPackAdaptiveScheduleFinding(
            code: .unsafePayloadBlocked,
            message: "今日计划发现不安全字段，已隐藏排期，等待家长在正式流程复核。",
            actionRequired: true,
            visibleToChild: true
        )
        return MobileGrowthPackAdaptiveSchedule(
            role: role,
            title: role == .child ? "成长包今日计划" : "成长包日程复核",
            subtitle: "内容已安全隐藏；本地页面不会继续展示原始字段。",
            audienceNote: role == .child
                ? "这里只显示安全提示和下一步；先休息、先作业、奖励等家长确认都是为你好。"
                : "这里只读整理今日节奏；真正改日程或发成长积分仍走正式流程。",
            slots: [],
            findings: [finding],
            publicSummary: MobileGrowthPackAdaptiveSchedulePublicSummary(
                role: role,
                slotCount: 0,
                visibleSlotCount: 0,
                suitableNowCount: 0,
                notNowCount: 0,
                sleepConflictCount: 0,
                homeworkConflictCount: 0,
                rewardConflictCount: 0,
                evidenceGapCount: 1,
                guardianReviewCount: 1,
                findingCodes: [.unsafePayloadBlocked]
            )
        )
    }

    private func makeSlots(for role: MobileGrowthPackExecutionHubRole) -> [MobileGrowthPackAdaptiveScheduleSlot] {
        [
            slot(
                kind: .schoolHomework,
                role: role,
                status: .suitableNow,
                windowLabel: "放学后",
                childDetail: "先把今天的作业目标完成，再去玩成长包里的其他步骤。",
                guardianDetail: "作业排在最前；逾期/退回和老师确认仍走学校作业安全壳，不在这里提交。",
                reasonNotNow: "",
                nextStep: role == .child ? "先做作业，做完再看下一步。" : "确认作业优先级和逾期风险是否需要人工跟进。",
                safetyNote: "不提交作业、不判分、不写学校系统。",
                sortOrder: 10,
                sleepConflict: false,
                homeworkConflict: true,
                rewardConflict: false,
                requiresGuardianReview: false,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .growthPackStep,
                role: role,
                status: .suitableNow,
                windowLabel: "作业后",
                childDetail: "作业完成后，这是今天适合做的成长包步骤。",
                guardianDetail: "成长包步骤排在作业之后；具体步骤仍在执行中心安全壳里查看。",
                reasonNotNow: "",
                nextStep: role == .child ? "做完作业再回执行中心，按顺序完成。" : "复核步骤节奏是否和作业、睡眠冲突。",
                safetyNote: "不自动完成、不发奖励、不解锁设备。",
                sortOrder: 20,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: false,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .habitChore,
                role: role,
                status: .suitableNow,
                windowLabel: "傍晚",
                childDetail: "傍晚适合打卡基础习惯和小家务，做完心情更轻松。",
                guardianDetail: "习惯/家务窗口与成长包并行；打卡仍在习惯家务安全壳里完成。",
                reasonNotNow: "",
                nextStep: role == .child ? "完成习惯打卡和今天的小家务。" : "确认习惯/家务窗口是否与作业、睡眠重叠。",
                safetyNote: "不发成长积分、不发通知、不写账本。",
                sortOrder: 30,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: false,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .familyCalendar,
                role: role,
                status: .later,
                windowLabel: "今天稍晚",
                childDetail: "今天家里还有安排，到点会一起行动，先做手头的事。",
                guardianDetail: "家庭日历只读提示窗口名称，不展示日历内部 ID、地点或原始事件。",
                reasonNotNow: "家庭活动还没到时间，先做现在适合的事。",
                nextStep: role == .child ? "到点跟着家人一起行动。" : "确认家庭安排是否挤压作业或睡眠窗口。",
                safetyNote: "不打开系统日历、不读取地点、不发通知。",
                sortOrder: 40,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: role == .guardian,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .evidenceReview,
                role: role,
                status: .waitingReview,
                windowLabel: "完成后",
                childDetail: "有的成果还要补一点说明，准备好后等家长或老师看。",
                guardianDetail: "证据复核存在缺口；定稿前不能进入成长积分或奖励履约。",
                reasonNotNow: "证明还没准备好，先把说明补齐。",
                nextStep: role == .child ? "把今天做的事写清楚，再请大人看。" : "查看证据时间线，确认缺口和人工复核需求。",
                safetyNote: "不上传媒体、不写账本、不发成长积分。",
                sortOrder: 50,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: true,
                hasEvidenceGap: true,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .rewardWindow,
                role: role,
                status: .notNow,
                windowLabel: "复核后",
                childDetail: "想换的奖励要等证明和家长确认都好了才行，现在先不急。",
                guardianDetail: "成长积分兑换窗口未开放；证据链定稿前不能消耗成长积分、下单或解锁设备。",
                reasonNotNow: "奖励要等证明完成和家长确认，现在还不能换。",
                nextStep: role == .child ? "先完成今天的事，再和家长商量奖励。" : "确认成长积分、库存和履约风险后再走正式流程。",
                safetyNote: "不扣成长积分、不下单、不解锁设备。",
                sortOrder: 60,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: true,
                requiresGuardianReview: true,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .sleepQuietWindow,
                role: role,
                status: .notNow,
                windowLabel: "睡前",
                childDetail: "快到睡觉时间了，现在是安静时间，先放松、准备休息。",
                guardianDetail: "睡眠/安静窗口受保护；这之后不安排成长包、奖励或屏幕任务。",
                reasonNotNow: "现在是睡前安静时间，先休息更重要。",
                nextStep: role == .child ? "收拾好，安静下来准备睡觉。" : "确认睡眠窗口没有被作业或奖励挤占。",
                safetyNote: "不控制屏幕时间、不读取睡眠数据、不发通知。",
                sortOrder: 70,
                sleepConflict: true,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: false,
                hasEvidenceGap: false,
                visibleToChild: true,
                visibleToGuardian: true
            ),
            slot(
                kind: .reviewCadence,
                role: role,
                status: .waitingReview,
                windowLabel: "每周复核",
                childDetail: "",
                guardianDetail: "复核节奏只读提示：按周回看证据缺口、奖励窗口和睡眠保护是否需要调整。",
                reasonNotNow: "",
                nextStep: role == .child ? "" : "到正式复核流程调整节奏，本页不改规则。",
                safetyNote: "不改复核规则、不写账本、不发成长积分。",
                sortOrder: 80,
                sleepConflict: false,
                homeworkConflict: false,
                rewardConflict: false,
                requiresGuardianReview: true,
                hasEvidenceGap: false,
                visibleToChild: false,
                visibleToGuardian: true
            )
        ]
    }

    private func slot(
        kind: MobileGrowthPackAdaptiveScheduleSlotKind,
        role: MobileGrowthPackExecutionHubRole,
        status: MobileGrowthPackAdaptiveScheduleSlotStatus,
        windowLabel: String,
        childDetail: String,
        guardianDetail: String,
        reasonNotNow: String,
        nextStep: String,
        safetyNote: String,
        sortOrder: Int,
        sleepConflict: Bool,
        homeworkConflict: Bool,
        rewardConflict: Bool,
        requiresGuardianReview: Bool,
        hasEvidenceGap: Bool,
        visibleToChild: Bool,
        visibleToGuardian: Bool
    ) -> MobileGrowthPackAdaptiveScheduleSlot {
        MobileGrowthPackAdaptiveScheduleSlot(
            publicSlotRef: publicRef("slot:\(kind.rawValue):\(role.rawValue):\(sortOrder)"),
            kind: kind,
            status: status,
            title: kind.title,
            windowLabel: windowLabel,
            detail: role == .child ? childDetail : guardianDetail,
            reasonNotNow: reasonNotNow,
            nextStep: nextStep,
            safetyNote: safetyNote,
            visibleToChild: visibleToChild,
            visibleToGuardian: visibleToGuardian,
            sleepConflict: sleepConflict,
            homeworkConflict: homeworkConflict,
            rewardConflict: rewardConflict,
            requiresGuardianReview: requiresGuardianReview,
            hasEvidenceGap: hasEvidenceGap,
            sortOrder: sortOrder
        )
    }

    private func makeFindings(
        role: MobileGrowthPackExecutionHubRole,
        slots: [MobileGrowthPackAdaptiveScheduleSlot]
    ) -> [MobileGrowthPackAdaptiveScheduleFinding] {
        var findings: [MobileGrowthPackAdaptiveScheduleFinding] = [
            MobileGrowthPackAdaptiveScheduleFinding(
                code: .readOnlySchedule,
                message: "今日计划只读整理本地安全摘要，不会自动安排、发任务、发成长积分或解锁设备。",
                actionRequired: false,
                visibleToChild: true
            )
        ]
        if slots.contains(where: \.sleepConflict) {
            findings.append(
                MobileGrowthPackAdaptiveScheduleFinding(
                    code: .sleepWindowProtected,
                    message: role == .child ? "睡前是安静时间，先休息。" : "睡眠/安静窗口受保护，不能被成长包或奖励挤占。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if slots.contains(where: \.homeworkConflict) {
            findings.append(
                MobileGrowthPackAdaptiveScheduleFinding(
                    code: .homeworkPriorityConflict,
                    message: role == .child ? "先完成作业，再做其他步骤。" : "作业优先级高于成长包和奖励，注意逾期风险。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if slots.contains(where: \.hasEvidenceGap) {
            findings.append(
                MobileGrowthPackAdaptiveScheduleFinding(
                    code: .evidenceGap,
                    message: role == .child ? "有成果还要补一点说明。" : "存在证据缺口，定稿前不能进入成长积分或奖励履约。",
                    actionRequired: true,
                    visibleToChild: true
                )
            )
        }
        if role == .guardian, slots.contains(where: \.rewardConflict) {
            findings.append(
                MobileGrowthPackAdaptiveScheduleFinding(
                    code: .rewardWindowReview,
                    message: "成长积分兑换窗口只读提示；证据链定稿前不能消耗成长积分、下单或解锁设备。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        if role == .guardian, slots.contains(where: \.requiresGuardianReview) {
            findings.append(
                MobileGrowthPackAdaptiveScheduleFinding(
                    code: .guardianReviewRequired,
                    message: "家长需复核排期冲突、证据缺口、奖励窗口和睡眠保护边界。",
                    actionRequired: true,
                    visibleToChild: false
                )
            )
        }
        return findings.filter { role == .guardian || $0.visibleToChild }
    }

    private func summary(
        role: MobileGrowthPackExecutionHubRole,
        allSlots: [MobileGrowthPackAdaptiveScheduleSlot],
        visibleSlots: [MobileGrowthPackAdaptiveScheduleSlot],
        findings: [MobileGrowthPackAdaptiveScheduleFinding]
    ) -> MobileGrowthPackAdaptiveSchedulePublicSummary {
        MobileGrowthPackAdaptiveSchedulePublicSummary(
            role: role,
            slotCount: allSlots.count,
            visibleSlotCount: visibleSlots.count,
            suitableNowCount: visibleSlots.filter { $0.status == .suitableNow }.count,
            notNowCount: visibleSlots.filter { $0.status == .notNow }.count,
            sleepConflictCount: visibleSlots.filter(\.sleepConflict).count,
            homeworkConflictCount: visibleSlots.filter(\.homeworkConflict).count,
            rewardConflictCount: visibleSlots.filter(\.rewardConflict).count,
            evidenceGapCount: visibleSlots.filter(\.hasEvidenceGap).count,
            guardianReviewCount: visibleSlots.filter(\.requiresGuardianReview).count,
            findingCodes: findings.map(\.code)
        )
    }

    private func publicRef(_ seed: String) -> String {
        "gpas-\(Self.stableHash("\(Self.redactionSalt):\(seed)"))"
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
