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
}
