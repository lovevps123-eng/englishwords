# SpeechSpike — SFSpeechRecognizer 口音验证（真机）

目的：验证 iOS 本地离线识别对中式口音的宽容度，产出三选一结论（详见 [spike 计划](../docs/plans/2026-07-25-ios-speech-spike.md)）。

**工程已生成并通过模拟器编译/运行验证**，无需手动创建：

1. 打开 `spike/SpeechSpike.xcodeproj`（签名已配 Team 9H47USBKK4 / Automatic）。
2. 插上 iPhone，选中设备，⌘R 运行，授权麦克风+语音识别。
3. 按计划 Task 3 测试矩阵采集数据：5 句 × 3 种读法（认真读 / 中式口音 / 故意漏 2 词），记录每次得分；再开飞行模式测一轮确认离线可用。
4. 判定标准：认真读 ≥85 分且漏词能标红 → 方案可用；70~85 → 宽松策略；<70 或漏词检不出 → 降级为示范朗读+自评。测试结果告诉 Claude，写入 `docs/spike-results.md` 定跟读模块路线。

> 注：模拟器上 `supportsOnDeviceRecognition` 通常为 false（会提示"本机不支持离线识别"），离线识别必须真机验证。
> 工程由 `project.yml` 经 XcodeGen 生成；改工程配置请改 project.yml 后重新 `xcodegen generate`。
