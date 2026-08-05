import Foundation

enum AIReviewStatus: String, Codable {
    case notReviewed
    case looksGood
    case needsParentReview
}

struct MockAIReviewService {
    func review(text: String) -> AIReviewStatus {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 8 ? .looksGood : .needsParentReview
    }
}
