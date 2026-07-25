# iOS 语音识别 Spike 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 真机验证 SFSpeechRecognizer 本地识别对中国高中生英语口音的宽容度，产出"可用/需调宽松策略/需付费方案"三选一结论。

**Architecture:** 单页面 SwiftUI 测试 App：展示目标句 → 录音 → 本地识别 → 词级对齐比对 → 显示逐词对错和得分。不接后端，不做持久化。

**Tech Stack:** SwiftUI (iOS 17+), Speech framework (SFSpeechRecognizer, requiresOnDeviceRecognition), AVAudioEngine

## Global Constraints

- 识别必须设 `requiresOnDeviceRecognition = true`（验证的就是离线能力，联网识别结果无效）
- 真机测试（模拟器无麦克风实况），Xcode 签名用 Team ID 9H47USBKK4
- Spike 代码放 `spike/` 目录，**不进 App 正式代码**；结论写入 `docs/spike-results.md`

---

### Task 1: 创建 Spike 工程与权限配置

**Files:**
- Create: `spike/SpeechSpike/`（Xcode 工程，App 模板，SwiftUI，Bundle ID `com.masf.speechspike`）

**Interfaces:**
- Produces: 可在真机运行的空工程，含麦克风/语音识别权限声明

- [ ] **Step 1: Xcode 新建工程**

Xcode → New Project → iOS App，Product Name `SpeechSpike`，Interface SwiftUI，保存到 `spike/`。

- [ ] **Step 2: 添加权限声明**

Target → Info 添加两条：

```
Privacy - Microphone Usage Description = 录音用于发音跟读评分测试
Privacy - Speech Recognition Usage Description = 本地识别你的跟读发音
```

- [ ] **Step 3: 真机空跑验证签名**

Run 到 iPhone 真机，App 启动显示默认界面即可。

- [ ] **Step 4: Commit**

```bash
git add spike/ && git commit -m "chore: speech spike 工程骨架"
```

### Task 2: 识别与词级比对逻辑

**Files:**
- Create: `spike/SpeechSpike/SpeechSpike/Recognizer.swift`
- Create: `spike/SpeechSpike/SpeechSpike/WordDiff.swift`
- Modify: `spike/SpeechSpike/SpeechSpike/ContentView.swift`

**Interfaces:**
- Produces: `Recognizer.start()/stop()`（录音+本地流式识别）、`wordDiff(target:recognized:) -> [(word: String, hit: Bool)]`（LCS 词对齐）。App v1 将复用这两个文件的逻辑。

- [ ] **Step 1: 词级比对（纯函数，先写）**

```swift
// WordDiff.swift
import Foundation

func normalize(_ s: String) -> [String] {
    s.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

/// LCS 对齐：返回目标句每个词是否被读中
func wordDiff(target: String, recognized: String) -> [(word: String, hit: Bool)] {
    let t = normalize(target), r = normalize(recognized)
    var dp = Array(repeating: Array(repeating: 0, count: r.count + 1), count: t.count + 1)
    for i in stride(from: t.count - 1, through: 0, by: -1) {
        for j in stride(from: r.count - 1, through: 0, by: -1) {
            dp[i][j] = t[i] == r[j] ? dp[i+1][j+1] + 1 : max(dp[i+1][j], dp[i][j+1])
        }
    }
    var result: [(String, Bool)] = []
    var i = 0, j = 0
    while i < t.count {
        if j < r.count && t[i] == r[j] { result.append((t[i], true)); i += 1; j += 1 }
        else if j < r.count && dp[i][j+1] >= dp[i+1][j] { j += 1 }
        else { result.append((t[i], false)); i += 1 }
    }
    return result
}

func score(_ diff: [(word: String, hit: Bool)]) -> Int {
    diff.isEmpty ? 0 : Int(Double(diff.filter(\.hit).count) / Double(diff.count) * 100)
}
```

- [ ] **Step 2: 录音+本地识别**

```swift
// Recognizer.swift
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
```

- [ ] **Step 3: 测试界面**

```swift
// ContentView.swift
import SwiftUI

let sentences = [
    "The little boy decided to give it a try.",
    "Scientists have discovered a new species in the ocean.",
    "Although it was raining, they continued their journey.",
    "I would rather stay at home than go shopping.",
    "The environment we live in is changing rapidly.",
]

struct ContentView: View {
    @StateObject var rec = Recognizer()
    @State var index = 0

    var target: String { sentences[index] }
    var diff: [(word: String, hit: Bool)] { wordDiff(target: target, recognized: rec.transcript) }

    var body: some View {
        VStack(spacing: 24) {
            Picker("句子", selection: $index) {
                ForEach(sentences.indices, id: \.self) { Text("句 \($0 + 1)").tag($0) }
            }.pickerStyle(.segmented)

            // 逐词高亮：绿=读中，红=漏/错
            diff.reduce(Text("")) { acc, item in
                acc + Text(item.word + " ").foregroundColor(item.hit ? .green : .red)
            }
            .font(.title2)

            Text("识别结果：\(rec.transcript)").foregroundColor(.secondary)
            Text("得分：\(score(diff))").font(.largeTitle).bold()
            if let err = rec.errorMessage { Text(err).foregroundColor(.orange) }

            Button(rec.isRecording ? "停止" : "开始跟读") {
                rec.isRecording ? rec.stop() : rec.start()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

- [ ] **Step 4: 真机运行确认能出识别文本和得分**

Run 到真机 → 授权麦克风和语音识别 → 跟读句 1 → 界面显示识别文本、逐词红绿高亮、得分。

- [ ] **Step 5: Commit**

```bash
git add spike/ && git commit -m "feat: spike 本地识别 + 词级比对评分"
```

### Task 3: 口音宽容度测试与结论（需用户/学生真人参与）

**Files:**
- Create: `docs/spike-results.md`

**Interfaces:**
- Produces: 三选一结论，决定 App v1 跟读模块的技术路线

- [ ] **Step 1: 按测试矩阵采集数据**

5 个句子 × 3 种读法（正常语速认真读 / 明显中式口音读 / 故意漏 2 个词），记录每次得分到表格。开飞行模式再测一轮，确认离线可用。

- [ ] **Step 2: 按判定标准得出结论**

| 结果 | 结论 |
|------|------|
| 认真读 ≥85 分、漏词能被标红 | ✅ 方案可用，v1 直接采用 |
| 认真读 70~85 分 | ⚠️ 采用宽松策略（≥70 即满分档，只标漏词不扣分） |
| 认真读 <70 或漏词检不出 | ❌ v1 跟读降级为"示范朗读+自评"，评分留待付费方案 |

- [ ] **Step 3: 写入 docs/spike-results.md 并提交**

```bash
git add docs/spike-results.md && git commit -m "docs: 语音识别 spike 结论"
```

## Self-Review 已执行

- 覆盖 spec"风险"节的第一条验证要求；`requiresOnDeviceRecognition` 与 spec 离线要求一致
- 无占位符；WordDiff/Recognizer 接口在 Task 2 Interfaces 中声明，供 App v1 计划引用
