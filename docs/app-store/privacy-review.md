# App Store 隐私申报核对表

核对日期：2026-09-05。范围：Love English iOS 1.0 客户端，以及本机 senior-platform 中被该客户端调用的后端路径。此表是本地审阅材料，不是已发布的 Apple 隐私声明。

## 建议回答与证据

| 数据 | 建议分类 | 用途 | 与账号关联 | 当前结论 |
| --- | --- | --- | --- | --- |
| 手机号／登录账号标识 | Contact Info → Phone Number | App Functionality：认证与安全 | 是 | `AuthStore.swift`、`DTO.swift` 发送；服务端 `User` 存储手机号 |
| 账号 UUID | Identifiers → User ID | App Functionality：认证、关联学习数据 | 是 | JWT 及服务端用户／学习记录使用账号 ID |
| 答题反馈、掌握程度、收藏及时间 | Usage Data → Product Interaction | App Functionality；Product Personalization：安排复习队列 | 是 | `VocabStore` 同步；`UserWordProgress` 和结果日志保存 |
| 认证事件、IP、User-Agent、限流信息 | 暂拟 Other Data Types；最终按实际日志用途确认 | App Functionality：防滥用、账号安全与运行维护 | 账号相关审计记录：是 | 不可因其为技术数据而漏报；未发现基于 IP 推断地理位置的路径 |
| 录音、语音识别文本和匹配得分 | 本版本不作为离开设备收集的 Audio Data 申报 | 本地跟读 | 本地 | `requiresOnDeviceRecognition = true`，无服务器上传路径 |
| 阅读／跟读任务勾选、每日新词量、难度设置 | 本地保存；难度／词量作为获取队列请求参数传输 | 本地界面偏好及请求服务 | 视字段而定 | 不把纯本地勾选误写成云端记录；参数的日志留存需确认 |
| 登录密码、认证令牌 | 在政策中解释认证处理；不机械增加一个不存在的“密码”标签分类 | App Functionality | 账号相关 | 当前登录路径使用密码哈希验证；Keychain 保存令牌 |

“用于追踪”暂拟否：已检查的 App 源码未集成广告、IDFA、ATT、第三方统计或崩溃 SDK，也未发现广告归因或跨公司用户画像用途。这个判断只覆盖已核查的实现；发布前仍须确认线上网络／托管服务商不会以其他目的使用数据。

不能选择“本 App 不收集数据”：账号相关学习数据和认证审计记录确实持久化在服务端。纯设备处理、短暂请求处理、长期保存和第三方处理需要区分。Apple 的分类口径见 [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)。

## 关键源码证据

客户端路径均相对仓库根目录；后端位于同级 `senior-platform` 仓库。

- `app/Sources/Features/Auth/AuthStore.swift:35`：手机号／密码登录及 Token 保存。
- `app/Sources/Core/DTO.swift:10`：登录请求字段；`:22` 起为刷新及认证响应。
- `app/Sources/Core/KeychainStore.swift:54`：Keychain 写入与设备锁定可访问性。
- `app/Sources/Features/Vocab/VocabStore.swift:27`：队列拉取；`:60` 答题记录；`:76` 同步。
- `app/Sources/Features/Vocab/VocabModels.swift:50`：逐条结果随机 UUID，不是持久设备 ID。
- `app/Sources/Features/Reading/ReadingStore.swift`：文章请求与词汇收藏。
- `app/Sources/Features/Speaking/Recognizer.swift:30`：离线能力检查与设备端识别要求。
- `app/Sources/Features/Speaking/ScoringStrategy.swift`：识别文字匹配得分，不是专业音素级评分。
- `app/Sources/Features/Vocab/WordCardView.swift:10`：系统语音合成，不调用平台 TTS API。
- `app/Sources/Features/Today/TodayView.swift:120`：本地阅读／跟读任务状态。
- `app/Sources/Features/Auth/LoginView.swift`、`Features/Account/RegistrationView.swift`：App 内提交注册申请，账号在管理员审批通过前不能进入学习功能。
- `app/Sources/Features/Settings/SettingsView.swift`：提供“账号与隐私”、隐私政策和联系我们入口；登出清理本地记录，但不等于注销服务端账号。
- `app/Sources/Features/Account/AccountManagementView.swift`：重新验证后查看账号状态、提交或撤回注销申请，并通过回执查询处理进度。
- `app/Resources/PrivacyInfo.xcprivacy`：声明 UserDefaults 所需理由，且声明不用于追踪。
- `senior-platform/backend/app/models/user.py:24`：账号字段和密码哈希。
- `senior-platform/backend/app/core/security.py:6`：bcrypt 密码校验。
- `senior-platform/backend/app/api/auth.py:150`：认证失败审计；`:164` 起更新登录时间及成功审计。
- `senior-platform/backend/app/core/audit.py:22`、`models/audit_log.py:14`：IP、User-Agent、账号、事件详情及时间持久化。
- `senior-platform/backend/app/core/rate_limit.py:24`：Redis 保存 IP 限流计数，代码配置有 TTL；不代表数据库日志采用相同时限。
- `senior-platform/backend/app/models/vocab.py:28`、`api/vocab.py:30`：账号关联的进度和个性化复习队列。
- `senior-platform/backend/app/api/articles.py:62`：读取文章，不单独写入阅读历史；不排除基础设施日志记录请求。

## 不可直接照搬的内容

1. `Brick Smash 8x8` 的审核联系人可经授权复用，但游戏的隐私声明不能证明英语 App 的数据实践。
2. 平台网页的 AI 辅导、图片生成等功能不等于本 App 也上传相同数据。需要按实际调用链判断。
3. Cloudflare 的原生 App 登录兼容标记仅针对登录；不能描述为 App 内嵌了 Turnstile 验证组件。
4. 没有第三方统计 SDK 不等于没有服务端日志，也不等于所有数据都留在设备。
5. 备份脚本的七天清理规则不证明生产环境、所有副本或审计表都遵循七天保留。

## 发布阻塞与后续处理

### 必须补齐／验证

- [x] 已在未登录浏览器验证 `https://senior.dafang-edu.com/privacy` 和 `https://senior.dafang-edu.com/support` 可公开渲染；App 在注册页和设置页提供入口。政策内容仍须在 SLA／留存规则确认后定稿。依据：[审核指南 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy)。
- [ ] 在隔离环境验证已实现的账号生命周期全流程：App 内注册申请、管理员审批、账号重新验证、注销申请／撤回、回执查询及完成后的本地清理。生产删除策略未启用前，不能把代码存在写成线上已可用。依据：[Apple 账号删除指引](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。
- [ ] 核对注销清单覆盖的账号关联数据，并确认审计、支付、备份等数据的保留／清理规则；当前已实现注销队列和后台处理流程，但保留规则与生产执行结果仍须确认，不能承诺未验证的彻底删除范围。
- [x] 导出 IPA 已核对 `PrivacyInfo.xcprivacy`，UserDefaults 所需理由为 `CA92.1`；依赖发生变化时仍须重新检查。参考：[Apple Required Reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。
- [ ] 运营主体和版权已按用户确认使用 `shaofei Ma（韶飞 麻）`；仍须确认政策生效日期及最终正式联系信息。
- [ ] 核对实际生产服务商、处理地区、访问日志用途／期限、数据库保留策略和备份生命周期，再定稿安全日志的隐私分类。
- [ ] 核实词典、例句、文章和译文的使用及商店截图展示权。服务端能返回内容不等于已证明出版或展示授权。

### 本轮不执行

仍不填写／发布 Apple 隐私标签，不开启生产注销、不实际删除账号，不上传构建或提交 App Review，不更改销售地区和价格。

## 定稿条件

技术缺口处理后，重新核对最终构建与数据流；把政策里的内部待确认说明替换为经验证的正式内容。之后由用户确认对外文案及 Apple 隐私回答，再分别执行保存、发布和提交审核。
