# MASF English：英语学习 iOS App 设计

日期：2026-07-25
状态：已与用户确认方向，待实施计划

## 背景与目标

senior-platform（MASF）目前是全科网页平台，用户反馈网页方式不便使用。本次重新聚焦：面向北京高中生的**英语学习 iOS App**，覆盖单词、发音、听力、阅读（写作保留在网页版），在高考要求基础上支持难度拔高。

**关键决策（已确认）：**
- 分发：自用/小范围，TestFlight 分发，不上架国内 App Store（无 ICP/教育类备案问题）
- 目标设备：iPhone，SwiftUI 原生开发
- v1 范围：单词 + 发音跟读 + 听力练习 + 外刊阅读
- 现有网页平台和后端保持运行，后端只做加法

## 仓库布局

- **本仓库 `project/englishwords`**：iOS App（SwiftUI）+ 本项目文档。独立于 senior-platform。
- **`project/senior-platform`**：共用后端。vocab/listening 的新增表、API 与入库脚本在该仓库实现（只做加法，不影响网页版）。

## 总体架构

```
iOS App (SwiftUI, iOS 17+, SwiftData 本地缓存)
   ├── 复用 API: /api/auth, /api/articles, /api/tts（听力材料生成）
   └── 新增 API: /api/vocab/*, /api/listening/*
后端 (现有 FastAPI + PostgreSQL + Redis，不改动已有功能)
   └── 新增表: words, user_word_progress, listening_sets, listening_records
网页版 (React PWA) — 保持现状，写作/作文引导等大屏功能继续使用
```

- 账号体系：与网页版共用 JWT（access + refresh），App 内登录走现有 /api/auth。
- 服务器（1 CPU / 1.9GB）无新增重负载：发音与单词朗读走 iOS 本地能力，不经服务端。

## 模块设计

### 1. 单词（最大新建量）

**词库数据（分层取材，词典优先，LLM 兜底）：**

| 数据 | 来源 | 说明 |
|------|------|------|
| 词条基础（音标/释义/词频/考试标签） | **ECDICT**（开源，MIT） | 用考试标签筛出高考 3500 为基础层；CET4/6、托福标签构成拔高层 |
| 例句（优先级从高到低） | ① 库内高考英语真题语料 ② Tatoeba（CC-BY，带中文翻译） ③ Merriam-Webster Learner's API（免费非商用，批量抓取入库） ④ LLM 生成（标记来源，日后可替换） | 真实语料优先；每词 1~3 句 |
| 例句中文翻译、记忆提示、例句适龄筛选 | LLM（一次性入库脚本） | LLM 只做筛选/翻译/提示，不做主要例句来源 |

- 入库脚本（senior-platform 已实现）：`scripts/import_ecdict.py`（词条基础数据，已在生产执行过）+ `scripts/enrich_examples.py`（例句富化，--tier/--limit/--tatoeba 参数，幂等可重跑）；来源字段（source）记录每条例句出处。
- **难度分层**：`dictionary_entries.tier` 字段（1=高考基础层，2=拔高层）。学生在 App"我的"页切档，各模块跟随。

**背词逻辑：**
- 简化版 SM-2 间隔重复：三档反馈驱动间隔调整。**wire 常量（App↔后端契约）：`know`（认识）/ `fuzzy`（模糊）/ `unknown`（不认识）**；间隔 `{1:1, 2:3, 3:7, 4:14, 5:30}` 天，stage≥5 视为掌握。
- 每日队列 = 新词 N（默认 50，可调）+ 到期复习词；服务端生成队列，App 启动时预取当天全量。
- 发音朗读：AVSpeechSynthesizer 本地合成（免费、离线、零延迟），不走服务端 TTS。
- 离线：队列与词条缓存在 SwiftData；答题结果本地排队，联网后批量同步（App 为准，服务端 merge）。

**表结构（senior-platform 已实现，如实记录）：**
- `dictionary_entries`（复用现有 ECDICT 词典表）+ 新列：`tier: int`（1/2）、`examples: JSONB`，结构 `[{"en": str, "cn": str, "source": "gaokao"|"tatoeba"|"freedict"|"llm"}]`，每词最多 3 条
- `user_word_progress`: user_id, word_id, stage(0=收藏未学, 1-5=SRS), collected(bool), next_review_at, correct_count, wrong_count；唯一约束 (user_id, word_id)
- `vocab_result_logs`: client_id(str, 全局主键，App 端生成 UUID), user_id —— 幂等去重依据

**API 契约（senior-platform 已实现并有测试锁定）：**
- `GET /api/vocab/queue?new_limit=50&tier=1` → `{"new": [word...], "review": [word...]}`；word = `{"id","word","phonetic","definitions","examples","stage"}`；new_limit 服务端钳制到 [0,200]
- `POST /api/vocab/results` body `{"results":[{"client_id","word_id","feedback"}]}` → `{"processed","skipped"}`；幂等键为全局 client_id，重放安全（离线补交可整批重发）；任一条目非法整批 400 无副作用
- `POST /api/vocab/collect` body `{"word": str}` → `{"status":"collected"|"exists","word_id"}` / 404（词典无此词）
- `GET /api/vocab/study-stats` → `{"learning","mastered","due_today","days_active","streak"}`；streak 与站内 quiz 一致采用"宽限一天"语义。各层（tier）进度拆分为后续可加性扩展，App"我的"页规划时再定

### 2. 发音跟读

- 流程：展示目标文本 → 录音（AVAudioEngine）→ **SFSpeechRecognizer 本地识别**（免费离线）→ 识别文本与目标文本逐词对齐比对 → 词级对错高亮 + 百分比得分。
- 材料来源：背词例句、北京听说机考题型（短文朗读、听后转述）。
- 明确不做音素级评分（需 Azure Speech 等付费服务）；词级比对对听说机考够用，接口层预留 provider 抽象以便日后替换。
- 跟读记录仅存本地（SwiftData），不上传音频。

### 3. 听力练习

- 材料：① 服务端 TTS 生成题目化材料（语速可控，入库缓存音频复用）② 外刊文章音频化（本地 AVSpeech 朗读，零成本）。
- 题型：听后选择、听后填空，对标北京听说机考；AI 生成题目复用现有 exam_generator 模式。
- 难度档 = 语速 × 材料层级。
- **新增表**：`listening_sets`（材料文本、音频 URL、题目 JSONB、难度档）、`listening_records`（user_id, set_id, score, answers）。
- **新增 API**：`GET /api/listening/sets`、`GET /api/listening/sets/{id}`、`POST /api/listening/sets/{id}/submit`。

### 4. 外刊阅读

- 完全复用现有 articles API 与每日抓取（18 源、三档难度）。
- 移动端体验：分段双语对照（默认只显英文，点段落显中文）、点词查释义（本地 ECDICT 精简词典）、**生词一键加入背词队列**（调 /api/vocab/collect，打通模块 1）。

## App 结构

Tab：**今日 / 单词 / 听说 / 阅读 / 我的**

- **今日**：每日固定动作清单（背词、跟读、听力 1 组、阅读 1 篇）+ 完成打卡 + 连续天数。是复习方案"每日固定动作"的执行载体。
- **我的**：难度档切换（基础/拔高）、每日新词量设置、统计（复用 /api/vocab/study-stats + listening 记录）。

## 错误处理

- 网络失败：单词模块全离线可用（预取+补交）；阅读/听力显示缓存内容或友好空态。
- 同步冲突：results 提交幂等（client 生成 UUID），服务端按全局 client_id 主键去重；进度行并发冲突走重试消歧，不丢反馈。
- SFSpeechRecognizer 不可用/权限拒绝：跟读模块降级为"仅朗读示范"，明确提示。

## 测试

- 后端：pytest 覆盖 vocab 队列生成、SRS 间隔计算、results 幂等、listening 提交判分。
- iOS：SRS 本地逻辑与文本对齐比对的单元测试；真机验证 SFSpeechRecognizer 对中式口音的宽容度（**排在实施计划最前面，是 v1 最大技术不确定点**）。

## 风险

| 风险 | 应对 |
|------|------|
| SFSpeechRecognizer 对口音识别过严/过松 | 计划第一步真机 spike 验证；不行则调整为"识别出即给分"的宽松策略或预留付费 provider |
| ECDICT 高考标签覆盖不全 | 用北京考试院 3500 词表交叉校验，缺口词条 LLM 补释义 |
| iOS UI 工程量（React 不复用） | v1 界面从简，功能闭环优先 |

## 明确不做（v1）

- 写作模块（留在网页版）
- Android / 上架 App Store / 商业化
- 音素级发音评分
- 全科入口改造（网页版保持原样，不删功能）
