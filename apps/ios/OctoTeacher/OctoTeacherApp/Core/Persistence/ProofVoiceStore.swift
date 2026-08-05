import AVFoundation
import Foundation

/// 语音证明存储：孩子录的完成说明音频，只存 App 沙盒 Documents/proof-audio/，
/// 绝不上传网络；家长审核时本机回放。与照片证明（ProofPhotoStore）同一套边界。
final class ProofVoiceStore: Sendable {
    static let shared = ProofVoiceStore()

    private let directory: URL

    init(directory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? documents.appendingPathComponent("proof-audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    /// 把录音临时文件收进证明库，返回文件名。
    func save(fromTemporary tmpURL: URL) -> String? {
        let fileName = "proof-voice-\(UUID().uuidString).m4a"
        let target = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.copyItem(at: tmpURL, to: target)
            try? FileManager.default.removeItem(at: tmpURL)
            return fileName
        } catch {
            return nil
        }
    }

    func url(fileName: String) -> URL? {
        let target = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: target.path) ? target : nil
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}

/// 简单本机回放器：家长听孩子的语音证明。
@MainActor
final class VoicePlayer {
    static let shared = VoicePlayer()
    private var player: AVAudioPlayer?

    func play(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func stop() {
        player?.stop()
    }
}
