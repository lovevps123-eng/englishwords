# EnglishWords 实施计划路线图

依据 spec：[2026-07-25-english-app-refocus-design.md](../specs/2026-07-25-english-app-refocus-design.md)

按子系统拆分为 4 个计划，每个计划独立交付可测试的软件：

| # | 计划 | 仓库 | 状态 | 前置 |
|---|------|------|------|------|
| 1 | [iOS 语音识别 Spike](2026-07-25-ios-speech-spike.md) — SFSpeechRecognizer 中式口音真机验证 | englishwords | **源码已备好（spike/Sources），待用户真机执行 Task 3** | 无 |
| 2 | [后端词汇模块](2026-07-25-backend-vocab-module.md) — 队列/SRS/幂等提交/统计/例句富化 | senior-platform | **✅ 完成并已上生产（2026-07-26，例句 3677 词全量富化）** | — |
| 3 | 后端听力模块 — listening_sets/题目生成/判分 | senior-platform | 待写计划 | #2 落地后 |
| 4 | iOS App v1 — 五 Tab 完整应用 | englishwords | 待写计划 | #1 结论 + #2 API 可用 |

**现状勘察结论（影响计划的重要事实）：**
- 生产库 `dictionary_entries` 已有 13,644 词（ECDICT 导入，其中高考标签 3,677 词），`import_ecdict.py`、`enrich_dictionary.py`（Free Dictionary API 补英文释义/音频）已存在 → 计划 2 只补缺口：系统背词进度表、每日队列、幂等提交、例句富化。
- 现有 `vocab_entries` 是用户手动生词本（简单 SRS），保留不动；App 的系统背词走新表 `user_word_progress`（关联 `dictionary_entries`，不复制词条数据）。
- 例句来源按 spec 优先级：真题语料 → Tatoeba → 词典 API → LLM 兜底；词典 API 用已集成的 Free Dictionary API（无需注册 key），Merriam-Webster 作为可选增强（需注册 key）。
