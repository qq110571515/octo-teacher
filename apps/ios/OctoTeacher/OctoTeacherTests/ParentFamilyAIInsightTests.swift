import XCTest
@testable import OctoTeacher

final class ParentFamilyAIInsightTests: XCTestCase {
    func testInsightSurfacesReviewAndUsesEnglishCopy() {
        let child = ChildProfile.sample
        let assignment = TaskAssignment(
            id: UUID(),
            childId: child.id,
            task: TaskTemplate(
                id: UUID(),
                title: "Read together",
                category: .learning,
                difficulty: .easy,
                rewardMinutes: 15,
                instructions: "Read for ten minutes.",
                requiredProof: .text
            ),
            date: Date(),
            status: .submitted,
            proof: .empty
        )
        let insight = ParentFamilyAIInsight.build(
            childName: "Alex",
            assignments: [assignment],
            growthDigest: .empty(childId: child.id),
            creditBalance: CreditBalance(availableMinutes: 20, pendingMinutes: 15, lifetimeEarnedMinutes: 40),
            language: .english
        )

        XCTAssertTrue(insight.todaySummary.contains("Alex"))
        XCTAssertTrue(insight.attentionItems.contains { $0.contains("waiting for your review") })
        XCTAssertEqual(insight.recommendedGoal, ParentAIPlanGoal.reading)
    }

    func testInsightProvidesCalmDefaultWhenNothingNeedsReview() {
        let child = ChildProfile.sample
        let insight = ParentFamilyAIInsight.build(
            childName: child.name,
            assignments: [],
            growthDigest: .empty(childId: child.id),
            creditBalance: CreditBalance(availableMinutes: 0, pendingMinutes: 0, lifetimeEarnedMinutes: 0),
            language: .chinese
        )

        XCTAssertEqual(insight.attentionItems.count, 1)
        XCTAssertTrue(insight.attentionItems[0].contains("没有紧急待办"))
    }
}
