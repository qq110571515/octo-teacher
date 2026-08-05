import AVFoundation
import Foundation
import Observation

/// 孩子语音证明录音器：录一段短音频到临时目录，供云端转写后立即删除。
///
/// 边界：
/// - 录音文件只写 tmp 目录，绝不进入家庭数据、相册或 proof-photos。
/// - 转写成功后由 ParentAIProviderStore 删除文件；取消/失败时这里负责清理。
/// - 上限 120 秒，避免误录长音频产生大流量与大转写费用。
@MainActor
@Observable
final class ProofAudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case denied
        case recording
        case finished(fileURL: URL)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private var recorder: AVAudioRecorder?
    static let maxDurationSeconds: TimeInterval = 120

    /// 请求麦克风权限并开始录音。权限被拒时进入 denied 态，由 UI 引导去系统设置。
    func startRecording() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.state = .denied
                    return
                }
                self.beginRecording()
            }
        }
    }

    /// 停止录音；成功时进入 finished 并携带文件 URL。
    func stopRecording() {
        recorder?.stop()
    }

    /// 放弃当前录音并清理文件。
    func discard() {
        recorder?.stop()
        if case .finished(let url) = state {
            try? FileManager.default.removeItem(at: url)
        }
        recorder = nil
        state = .idle
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .record + .spokenAudio 是非法组合（曾导致录音静默失败）。
            // playAndRecord + defaultToSpeaker：能录也能随后回放。
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("proof-audio-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: Self.maxDurationSeconds)
            self.recorder = recorder
            state = .recording
        } catch {
            state = .idle
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let fileURL = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if flag {
                self.state = .finished(fileURL: fileURL)
            } else {
                try? FileManager.default.removeItem(at: fileURL)
                self.state = .idle
            }
            self.recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
