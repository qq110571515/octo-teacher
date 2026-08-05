import Foundation

/// 学校作业科目。仅作展示分类，脱敏，不绑定真实学校、班级或老师账号。
enum HomeworkSubject: String, Codable, CaseIterable, Equatable {
    case math
    case chinese
    case english
    case science
    case reading
    case other

    var label: String {
        switch self {
        case .math: return "数学"
        case .chinese: return "语文"
        case .english: return "英语"
        case .science: return "科学"
        case .reading: return "阅读"
        case .other: return "其他"
        }
    }

    var systemImage: String {
        switch self {
        case .math: return "function"
        case .chinese: return "character.book.closed"
        case .english: return "textformat.abc"
        case .science: return "atom"
        case .reading: return "book"
        case .other: return "square.grid.2x2"
        }
    }
}

/// 学校作业完成状态。
/// - assigned: 已布置，尚未开始。
/// - inProgress: 孩子已经开始但还没提交。
/// - submitted: 已提交证明，等待老师/家长验证（本壳不替代真实验证，只展示等待态）。
/// - verified: 已被验证完成（由外部验证流程决定，本壳只展示）。
/// - returned: 被退回需要重做。
enum HomeworkStatus: String, Codable, Equatable {
    case assigned
    case inProgress
    case submitted
    case verified
    case returned

    var label: String {
        switch self {
        case .assigned: return "待开始"
        case .inProgress: return "进行中"
        case .submitted: return "已提交·待验证"
        case .verified: return "已完成"
        case .returned: return "需重做"
        }
    }

    /// 是否还允许孩子提交证明。
    var acceptsSubmission: Bool {
        switch self {
        case .assigned, .inProgress, .returned:
            return true
        case .submitted, .verified:
            return false
        }
    }
}

/// AI 引导式作业辅导内容。
///
/// 安全边界（与 CLAUDE.md 一致）：AI 导师只给引导、提示、自检清单和下一步建议，
/// **绝不**直接给作业答案。本结构体从模型层保证这一点——它根本没有 `answer`
/// 字段，也没有任何可以塞进最终答案的自由结果字段，只有引导式内容。
struct AIHomeworkGuidance: Codable, Equatable {
    /// 引导式提示：用提问/思路引导孩子自己想，不给结论。
    var hints: [String]
    /// 自检清单：孩子提交前可逐项核对。
    var checklist: [String]
    /// 下一步建议：引导孩子接下来做什么，而不是替孩子完成。
    var nextStep: String

    static let empty = AIHomeworkGuidance(hints: [], checklist: [], nextStep: "")

    /// 是否具备可展示的引导内容。
    var hasContent: Bool {
        !hints.isEmpty || !checklist.isEmpty
            || !nextStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// 一条学校作业。complies with 隐私边界：不含真实学校、老师姓名、班级编号或孩子身份证号，
/// 只保留脱敏后的展示文本。证明复用平台通用 `ProofDraft`，真实照片只存本机沙盒。
struct SchoolHomework: Identifiable, Codable, Equatable {
    let id: UUID
    var subject: HomeworkSubject
    var title: String
    /// 老师布置说明（脱敏后的展示文本）。
    var instructions: String
    /// 截止展示文本（如「今天 20:00 前」），不含真实精确日期或外部系统时间。
    var dueLabel: String
    var status: HomeworkStatus
    var requiredProof: ProofKind
    var proof: ProofDraft
    /// AI 引导式辅导（只引导不给答案）。
    var guidance: AIHomeworkGuidance

    init(
        id: UUID,
        subject: HomeworkSubject,
        title: String,
        instructions: String,
        dueLabel: String,
        status: HomeworkStatus,
        requiredProof: ProofKind,
        proof: ProofDraft = .empty,
        guidance: AIHomeworkGuidance = .empty
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.instructions = instructions
        self.dueLabel = dueLabel
        self.status = status
        self.requiredProof = requiredProof
        self.proof = proof
        self.guidance = guidance
    }
}
