import AVFoundation

/// 语音播报测试（对应安卓版的 TTS），锁屏时也要能响。
final class SpeechService {
    static let shared = SpeechService()

    private let synth = AVSpeechSynthesizer()
    private var sessionReady = false

    func prepareSession() {
        guard !sessionReady else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
            sessionReady = true
        } catch {
            AppLog.shared.add("TTS", "音频会话失败: \(error.localizedDescription)")
        }
    }

    func speak(_ text: String) {
        prepareSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        synth.speak(utterance)
        AppLog.shared.add("TTS", "播报: \(text)")
    }
}
