import Foundation

/// 移动同步 mock snapshot：移动同步客户端消费壳的本地数据源。
///
/// snapshot 对应 mobile-sync-api 在某一时刻对一个家庭返回的脱敏聚合结果。
/// 客户端把它当作只读初始态消费，并在本地对提交/审批/奖励做有限的状态推导，
/// **不会**把它当成生产同步协议，也不写回任何远端。
struct MobileSyncSnapshot: Codable, Equatable {
    struct Family: Codable, Equatable {
        var publicRef: String
        var displayName: String
        var locale: String
        var childCount: Int
        var guardianCount: Int
    }

    struct Child: Codable, Equatable, Identifiable {
        var publicRef: String
        var familyPublicRef: String
        var displayName: String
        var ageBand: String
        var taskCount: Int
        var availableCredits: Int

        var id: String { publicRef }
    }

    var schemaVersion: Int
    var generatedAt: String
    var family: Family
    var children: [Child]
    var tasks: [MobileSyncTask]
    var submissions: [MobileSyncSubmission]
    var approvals: [MobileSyncApproval]
    var creditBalances: [MobileSyncCreditBalance]
    var rewardSessions: [MobileSyncRewardSession]
    var growthFeed: [MobileSyncGrowthFeedItem]
    var capabilities: [String]
}

extension MobileSyncSnapshot {
    /// 当前消费壳支持的 schema 版本，对齐共享契约的 schemaVersion = 1。
    static let supportedSchemaVersion = 1

    /// 从 JSON 数据解析 snapshot。解析失败抛 `MobileSyncError.contractInvalid`。
    static func decode(from data: Data) throws -> MobileSyncSnapshot {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(MobileSyncSnapshot.self, from: data)
        } catch {
            throw MobileSyncError.contractInvalid
        }
    }

    /// 从内置 mock JSON 文本解析得到 snapshot。这是消费壳默认的本地数据源。
    static func mock() throws -> MobileSyncSnapshot {
        guard let data = mockJSON.data(using: .utf8) else {
            throw MobileSyncError.contractInvalid
        }
        return try decode(from: data)
    }

    /// 空 snapshot：解析失败时的安全回退，绝不携带任何数据。
    static let empty = MobileSyncSnapshot(
        schemaVersion: supportedSchemaVersion,
        generatedAt: "",
        family: Family(publicRef: "", displayName: "", locale: "", childCount: 0, guardianCount: 0),
        children: [],
        tasks: [],
        submissions: [],
        approvals: [],
        creditBalances: [],
        rewardSessions: [],
        growthFeed: [],
        capabilities: []
    )

    /// 内置 mock snapshot JSON。所有引用都是脱敏公开引用，绝不含真实
    /// 孩子/家庭/学校/设备标识、token、本地路径或局域网地址。
    static let mockJSON = """
    {
      "schemaVersion": 1,
      "generatedAt": "2026-06-23T21:00:00Z",
      "family": {
        "publicRef": "family:fam7a1c2",
        "displayName": "向阳小家",
        "locale": "zh-CN",
        "childCount": 2,
        "guardianCount": 2
      },
      "children": [
        {
          "publicRef": "child:c0a1b2c",
          "familyPublicRef": "family:fam7a1c2",
          "displayName": "小阳",
          "ageBand": "8_to_10",
          "taskCount": 4,
          "availableCredits": 8
        },
        {
          "publicRef": "child:c9z8y7x",
          "familyPublicRef": "family:fam7a1c2",
          "displayName": "小禾",
          "ageBand": "11_to_13",
          "taskCount": 1,
          "availableCredits": 60
        }
      ],
      "tasks": [
        {
          "clientTaskRef": "task:t100001",
          "childPublicRef": "child:c0a1b2c",
          "title": "完成今天的数学作业",
          "category": "homework",
          "status": "available",
          "plannedFor": "2026-06-23",
          "dueAt": "2026-06-23T20:00:00Z",
          "evidenceRequired": ["photo_ref", "text_summary"],
          "priority": "must_do",
          "hasSubmittedProof": false
        },
        {
          "clientTaskRef": "task:t100002",
          "childPublicRef": "child:c0a1b2c",
          "title": "朗读绘本十分钟",
          "category": "learning",
          "status": "available",
          "plannedFor": "2026-06-23",
          "evidenceRequired": ["text_summary"],
          "priority": "recommended",
          "hasSubmittedProof": false
        },
        {
          "clientTaskRef": "task:t100003",
          "childPublicRef": "child:c0a1b2c",
          "title": "整理书桌",
          "category": "routine",
          "status": "scheduled",
          "plannedFor": "2026-06-23",
          "evidenceRequired": ["none"],
          "priority": "optional",
          "hasSubmittedProof": false
        },
        {
          "clientTaskRef": "task:t100004",
          "childPublicRef": "child:c0a1b2c",
          "title": "昨天的阅读打卡",
          "category": "learning",
          "status": "available",
          "plannedFor": "2026-06-22",
          "evidenceRequired": ["text_summary"],
          "priority": "recommended",
          "hasSubmittedProof": false
        },
        {
          "clientTaskRef": "task:t100005",
          "childPublicRef": "child:c0a1b2c",
          "title": "跳绳两百个",
          "category": "exercise",
          "status": "submitted",
          "plannedFor": "2026-06-23",
          "evidenceRequired": ["text_summary"],
          "priority": "recommended",
          "hasSubmittedProof": true
        },
        {
          "clientTaskRef": "task:t100006",
          "childPublicRef": "child:c0a1b2c",
          "title": "练字一页",
          "category": "chore",
          "status": "verified",
          "plannedFor": "2026-06-23",
          "evidenceRequired": ["photo_ref"],
          "priority": "optional",
          "hasSubmittedProof": true
        },
        {
          "clientTaskRef": "task:t200001",
          "childPublicRef": "child:c9z8y7x",
          "title": "户外运动三十分钟",
          "category": "exercise",
          "status": "available",
          "plannedFor": "2026-06-23",
          "evidenceRequired": ["text_summary"],
          "priority": "recommended",
          "hasSubmittedProof": false
        }
      ],
      "submissions": [
        {
          "clientProofRef": "proof:p300005",
          "clientTaskRef": "task:t100005",
          "childPublicRef": "child:c0a1b2c",
          "status": "submitted",
          "submittedAt": "2026-06-23T18:30:00Z",
          "evidenceSummaryPreview": "已完成两百个跳绳"
        },
        {
          "clientProofRef": "proof:p300006",
          "clientTaskRef": "task:t100006",
          "childPublicRef": "child:c0a1b2c",
          "status": "accepted",
          "submittedAt": "2026-06-23T17:10:00Z",
          "evidenceSummaryPreview": "练字一页照片记录"
        }
      ],
      "approvals": [
        {
          "clientDecisionRef": "decision:d400006",
          "clientProofRef": "proof:p300006",
          "clientTaskRef": "task:t100006",
          "childPublicRef": "child:c0a1b2c",
          "decision": "approved",
          "reasonCode": "quality_ok",
          "decidedAt": "2026-06-23T17:30:00Z",
          "creditGrantSuggested": 4
        }
      ],
      "creditBalances": [
        {
          "childPublicRef": "child:c0a1b2c",
          "availableCredits": 8,
          "heldCredits": 0,
          "spentCredits": 2,
          "totalEarnedCredits": 10,
          "expiringSoonCredits": 0,
          "usableScopes": ["parent_approval_required"],
          "capturedAt": "2026-06-23T21:00:00Z"
        },
        {
          "childPublicRef": "child:c9z8y7x",
          "availableCredits": 60,
          "heldCredits": 0,
          "spentCredits": 0,
          "totalEarnedCredits": 60,
          "expiringSoonCredits": 0,
          "usableScopes": ["parent_approval_required"],
          "capturedAt": "2026-06-23T21:00:00Z"
        }
      ],
      "rewardSessions": [
        {
          "clientRewardSessionRef": "reward:r500001",
          "childPublicRef": "child:c0a1b2c",
          "rewardType": "screen_time",
          "plannedMinutes": 20,
          "status": "active",
          "creditHoldPublicRef": "hold:h600001",
          "deviceCommandQueued": true
        },
        {
          "clientRewardSessionRef": "reward:r500002",
          "childPublicRef": "child:c9z8y7x",
          "rewardType": "app_unlock",
          "plannedMinutes": 30,
          "status": "ended",
          "creditHoldPublicRef": "hold:h600002",
          "deviceCommandQueued": false
        }
      ],
      "growthFeed": [
        {
          "clientFeedItemRef": "feed:f700001",
          "childPublicRef": "child:c0a1b2c",
          "title": "完成阅读任务",
          "summary": "小阳今天坚持朗读绘本，进步很大。",
          "visibility": "family",
          "occurredAt": "2026-06-23T16:00:00Z",
          "tags": ["learning", "streak"]
        },
        {
          "clientFeedItemRef": "feed:f700002",
          "childPublicRef": "child:c0a1b2c",
          "title": "情绪小日记",
          "summary": "今天心情不错，和家人一起做了晚饭。",
          "visibility": "private",
          "occurredAt": "2026-06-23T19:00:00Z",
          "tags": ["mood"]
        },
        {
          "clientFeedItemRef": "feed:f700003",
          "childPublicRef": "child:c9z8y7x",
          "title": "运动达标",
          "summary": "小禾完成了三十分钟户外运动。",
          "visibility": "care_team",
          "occurredAt": "2026-06-23T15:30:00Z",
          "tags": ["exercise"]
        }
      ],
      "capabilities": [
        "today_tasks",
        "task_submission",
        "guardian_approval",
        "credit_balance",
        "reward_session",
        "growth_feed"
      ]
    }
    """
}

/// 提交/审批负载的脱敏守卫。
///
/// 与 mobile-sync-api 的 `blockedPayloadPatterns` 对齐：阻止把 token、密钥、
/// 本地文件路径、`file://`、`data:image/`、局域网地址或 `.local` 主机名带进同步负载。
/// 移动消费壳只接受已脱敏的引用与摘要。
enum MobileSyncPayloadGuard {
    /// 不安全负载的正则模式（不区分大小写处单独标注）。
    private static let patterns: [String] = [
        "(?i)\\bBearer\\s+",
        "(?i)\\bapi[_-]?key\\b",
        "(?i)\\bdevice-token\\b",
        "(?i)\\bserver-secret\\b",
        "(?i)\\bsk-[a-z0-9_-]{8,}\\b",
        "(?i)data:image/",
        "[A-Z]:\\\\",
        "(?i)file://",
        "\\b(?:192\\.168|10\\.[0-9]{1,3}|172\\.(?:1[6-9]|2[0-9]|3[01]))\\.[0-9]{1,3}\\.[0-9]{1,3}\\b",
        "(?i)\\b[a-z0-9-]+\\.local(?::|/|\\b)"
    ]

    /// 单个字符串是否命中任一不安全模式。
    static func isUnsafe(_ value: String) -> Bool {
        for pattern in patterns where value.range(of: pattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// 一组字符串中是否存在不安全负载。
    static func isUnsafe(_ values: [String]) -> Bool {
        values.contains(where: isUnsafe)
    }
}
