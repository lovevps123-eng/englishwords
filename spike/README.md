# SpeechSpike — SFSpeechRecognizer 口音验证（真机）

目的：验证 iOS 本地离线识别对中式口音的宽容度，产出三选一结论（详见 [spike 计划](../docs/plans/2026-07-25-ios-speech-spike.md)）。

## 步骤

1. Xcode → New Project → iOS App，Product Name `SpeechSpike`，Interface SwiftUI，Bundle ID `com.masf.speechspike`，保存到本目录（`spike/`）。
2. 把 `Sources/` 下三个 .swift 文件拖进工程（替换默认 ContentView.swift）。
3. Target → Info 添加两条权限描述：
   - `Privacy - Microphone Usage Description` = 录音用于发音跟读评分测试
   - `Privacy - Speech Recognition Usage Description` = 本地识别你的跟读发音
4. 真机运行（Team 9H47USBKK4 签名），授权麦克风+语音识别。
5. 按计划 Task 3 的测试矩阵采集数据：5 句 × 3 种读法（认真读/中式口音/故意漏 2 词），每次记录得分；再开飞行模式测一轮确认离线可用。
6. 判定标准：认真读 ≥85 分且漏词能标红 → 方案可用；70~85 → 宽松策略；<70 或漏词检不出 → 降级。结果告诉 Claude 写入 `docs/spike-results.md`。
