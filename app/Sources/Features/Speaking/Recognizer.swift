// Recognizer.swift — 录音 + 本地离线识别（requiresOnDeviceRecognition 是核心验证点）。
// 从 spike/Sources/Recognizer.swift 逐字复制而来（spike 目录本身不动）：这是一个
// @MainActor ObservableObject 类型，本身不存在自由函数命名污染问题，故原样保留，
// 未做改动（与 WordDiff.swift 需要收进 enum 命名空间的情况不同）。
import Speech
import AVFoundation

@MainActor
final class Recognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        transcript = ""; errorMessage = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { self.errorMessage = "未授权语音识别"; return }
                self.begin()
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else { errorMessage = "识别器不可用"; return }
        guard recognizer.supportsOnDeviceRecognition else { errorMessage = "本机不支持离线识别"; return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true   // 核心验证点：纯离线
        req.shouldReportPartialResults = true
        request = req

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            req.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: req) { result, error in
            DispatchQueue.main.async {
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil || (result?.isFinal ?? false) { self.stop() }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        isRecording = false
    }

    /// 清空上一次识别结果与错误提示（不影响 isRecording/录音硬件状态）。
    /// start() 本身在开始新录音时已经会清空 transcript，这里单独暴露出来是给
    /// "换到下一句但还没重新录音"这种场景用：SpeakingView 换目标句时若不调用，
    /// 上一句残留的 transcript 会继续和新目标句拼出误导性的红绿高亮/得分，
    /// 直到用户重新点"开始跟读"才会自愈（见 task-7-report.md 修复记录）。
    func reset() {
        transcript = ""
        errorMessage = nil
    }
}
