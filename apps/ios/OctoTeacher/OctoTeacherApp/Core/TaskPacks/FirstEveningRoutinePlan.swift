import Foundation

/// 「首日晚间节律包」（少刷手机替代计划）。
///
/// 面向真实家庭痛点：孩子沉迷手机短视频、晚上不睡、不做家务。
/// 家长首晚一键布置 4 件小事：家务 1、阅读 1、户外 1、睡前放手机 1，
/// 完成后发成长积分，用「积分可兑换屏幕时间/零花钱/愿望」替代吼叫和没收。
///
/// 文案约束：幼儿模式可点小喇叭朗读任务标题和说明（半识字画像），
/// 所以标题必须是读出来就懂的短句，说明必须是口语短文案。
/// 一键布置没有编辑步骤，因此模板不允许出现「（布置时填写…）」占位，
/// 也不附带 ReadingSpec，避免占位书名直接漏到孩子端。
enum FirstEveningRoutinePlan {
    static let title = "首日晚间节律包"
    static let subtitle = "家务、阅读、户外、睡前放手机各一件，让孩子今晚就有比刷手机更想做的事。"

    /// 布置时挂靠的包类型：晚间节律属于基础生活习惯。
    static let packType: PackType = .basicHabits

    static let templates: [PackTaskTemplate] = [
        PackTaskTemplate(
            id: "first-evening-chore-tidy-toys",
            title: "把玩具送回家",
            instructions: "睡觉前，把地上的玩具和书送回它们自己的家，拍张照片给爸爸妈妈看。",
            category: .home,
            suggestedRewardMinutes: 10,
            requiredProof: .photo
        ),
        PackTaskTemplate(
            id: "first-evening-reading-cozy",
            title: "睡前读小书",
            instructions: "选一本你喜欢的书，自己读，或者请大人读给你听，再说一说你最喜欢哪里。",
            category: .learning,
            suggestedRewardMinutes: 15,
            requiredProof: .text
        ),
        PackTaskTemplate(
            id: "first-evening-outdoor-play",
            title: "出门玩一会儿",
            instructions: "和大人一起下楼或者去公园，跑一跑跳一跳，玩一会儿再回家。",
            category: .health,
            suggestedRewardMinutes: 15,
            requiredProof: .photo,
            adultSupervisionRequired: true
        ),
        PackTaskTemplate(
            id: "first-evening-phone-goodnight",
            title: "手机去睡觉",
            instructions: "睡觉前，把手机放到和爸爸妈妈说好的充电的地方，跟它说晚安。",
            category: .health,
            suggestedRewardMinutes: 20,
            requiredProof: .photo
        )
    ]
}
