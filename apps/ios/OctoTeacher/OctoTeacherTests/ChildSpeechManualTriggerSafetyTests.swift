import XCTest

final class ChildSpeechManualTriggerSafetyTests: XCTestCase {
    func testChildFacingViewsDoNotAutoSpeakOnLifecycle() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OctoTeacherApp")
        let scannedRoots = [
            "Features/ChildHome",
            "Features/Tasks",
            "Features/AICompanion",
            "Features/Rewards",
            "Features/ChildCreditWallet",
            "Core/Accessibility"
        ]

        var violations: [String] = []
        for root in scannedRoots {
            let directory = sourceRoot.appendingPathComponent(root)
            for file in try swiftFiles(under: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for lifecycleBlock in lifecycleBlocks(in: source) where lifecycleBlock.body.contains("SpeechReader.shared.speak") {
                    let relativePath = file.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
                    violations.append("\(relativePath): \(lifecycleBlock.modifier) lifecycle block calls SpeechReader.shared.speak")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            孩子端/幼儿模式的语音只能由小喇叭、试听或明确按钮触发，不能在 onAppear/.task 自动播放。
            违规项:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    /// 孩子端奖励/钱包页面里的操作反馈（feedback 状态）必须有对应的手动小喇叭，
    /// 否则不识字的孩子做完操作后看不懂结果。播报仍只由点击触发。
    func testChildRewardFeedbackStatesHaveManualSpeaker() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OctoTeacherApp")
        let scannedRoots = [
            "Features/Rewards",
            "Features/ChildCreditWallet"
        ]
        let feedbackPattern = try NSRegularExpression(
            pattern: #"@State\s+private\s+var\s+(\w*[Ff]eedback)\s*:"#
        )

        var violations: [String] = []
        for root in scannedRoots {
            let directory = sourceRoot.appendingPathComponent(root)
            for file in try swiftFiles(under: directory) {
                let source = try String(contentsOf: file, encoding: .utf8)
                let nsSource = source as NSString
                let matches = feedbackPattern.matches(
                    in: source,
                    range: NSRange(location: 0, length: nsSource.length)
                )
                for match in matches {
                    let name = nsSource.substring(with: match.range(at: 1))
                    if !source.contains("SpeakButton(text: \(name)") {
                        let relativePath = file.path.replacingOccurrences(of: sourceRoot.path + "/", with: "")
                        violations.append("\(relativePath): feedback 状态 \(name) 没有对应的 SpeakButton")
                    }
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            """
            孩子端操作反馈必须能通过小喇叭手动播报。
            违规项:
            \(violations.joined(separator: "\n"))
            """
        )
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return try enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }

    private func lifecycleBlocks(in source: String) -> [(modifier: String, body: String)] {
        let pattern = #"\.(onAppear|task)\s*(?:\([^)]*\))?\s*\{"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsSource = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
        return matches.compactMap { match in
            guard let modifierRange = Range(match.range(at: 1), in: source),
                  let matchRange = Range(match.range, in: source),
                  let openBraceIndex = source[matchRange].lastIndex(of: "{"),
                  let closeBraceIndex = matchingBrace(in: source, openBraceIndex: openBraceIndex) else {
                return nil
            }
            let bodyStart = source.index(after: openBraceIndex)
            let body = String(source[bodyStart..<closeBraceIndex])
            return (String(source[modifierRange]), body)
        }
    }

    private func matchingBrace(in source: String, openBraceIndex: String.Index) -> String.Index? {
        var depth = 0
        var index = openBraceIndex
        while index < source.endIndex {
            let character = source[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
