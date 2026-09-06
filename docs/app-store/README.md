# Love English 上架材料（本地草稿）

编制日期：2026-09-05。App：Love English 每日学英语，iOS 1.0，Bundle ID `com.masf.englishwords`。

App Store Connect 中 Love English 1.0 当前为 `Prepare for Submission`。新版推广文本、594 字描述、关键词、副标题及 Education 分类均已保存，五张新截图已按顺序上传。保留五个 Tab 和每日阅读任务的 Build 3 已于 2026-09-06 23:03:23 JST 上传成功；Apple 正在处理包，尚未选定构建，也未提交 App Review。生产注销开关仍关闭，已确认注销处理期限为 7 个自然日内、完成后回执可查询 30 天，其他留存规则仍待定稿。**材料齐备不代表已经满足上架条件。**

## 文案与核对材料

- [中文商店文案](zh-Hans/store-listing.md)：名称、副标题、推广文本、描述、关键词及表述边界。
- [结构化文案](zh-Hans/store-listing.json)：记录已确认字段及 App Store Connect 草稿状态；并非已提交审核状态。
- [隐私政策草稿](zh-Hans/privacy-policy.draft.md)：基于客户端和相关后端的数据流核对，内部待确认内容不可直接公开。
- [支持页文案草稿](zh-Hans/support.draft.md)：联系邮箱、登录与学习 FAQ、隐私及删除说明。
- [隐私申报核对表与发布阻塞](privacy-review.md)：含代码证据及 Apple 官方依据。
- [验收记录](verification.md)：截图来源、测试结果、尺寸及核对边界。
- [发布状态](release-status.md)：生产部署、公开页面、IPA 验证及剩余门禁。

## 五张截图

Build 3 使用今日、单词、跟读、阅读列表和阅读详情五张新截图，均已替换并逐张查看为 1320 × 2868。文件校验值见 [manifest.json](screenshots/manifest.json)。

| 顺序 | 截图 | 内容与注意事项 |
| --- | --- | --- |
| 1 | [今日](screenshots/01-today.jpeg) | 实际新账号每日任务和零进度 |
| 2 | [单词](screenshots/02-vocabulary.jpeg) | 真实词条、英文释义及例句；没有承诺全量中文释义 |
| 3 | [跟读](screenshots/03-speaking.jpeg) | 未练习状态，原界面显示 0 分和空识别结果；没有制造高分 |
| 4 | [阅读列表](screenshots/04-reading-list.jpeg) | 随 App 内置的英语学习短文列表，不宣传外刊实时更新 |
| 5 | [阅读详情](screenshots/05-reading-detail.jpeg) | 默认显示英文正文，已展开中文标题；段落译文需点击后显示 |

前三张因对应真实界面未变化而与旧图 SHA-256 相同；阅读列表和详情为内置 AI 辅助创作短文的新截图。六篇短文已逐篇核对英中对应，独立审阅无阻塞；这不证明词典释义或例句的来源授权。

## 发布前下一阶段

1. 确认词典释义、例句等既有内容来源，核对服务商及除已确认 SLA／回执期限外的数据留存规则，定稿政策生效日期。
2. 隔离后端生命周期验证和 iOS 测试已通过；完成保留策略与 worker 配置后启用生产注销。
3. 根据最终实现填写隐私申报、年龄分级、地区及价格，核对审核信息。
4. 等待 Apple 完成 Build 3 处理并在版本中选定该构建，完成 App Store Connect 校验后再提交审核。

审核账号及密码不在此目录；个人审核联系电话也不包含在公开材料中。公开文案不应复制原始测试日志。
