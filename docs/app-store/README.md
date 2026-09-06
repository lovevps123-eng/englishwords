# Love English 上架材料（本地草稿）

编制日期：2026-09-05。App：Love English 每日学英语，iOS 1.0，Bundle ID `com.masf.englishwords`。

App Store Connect 中 Love English 1.0 当前为 `Prepare for Submission`，部分中文元数据已保存为草稿；截图和新构建尚未上传，也未提交 App Review。生产后端和无需登录的隐私／支持页面已上线验证，App 源码包含注册审批、账号注销及隐私／支持入口；生产注销开关仍关闭，政策中的 SLA／留存规则仍待定稿。**材料齐备不代表已经满足上架条件。**

## 文案与核对材料

- [中文商店文案](zh-Hans/store-listing.md)：名称、副标题、推广文本、描述、关键词及表述边界。
- [结构化文案](zh-Hans/store-listing.json)：记录已确认字段及 App Store Connect 草稿状态；并非已提交审核状态。
- [隐私政策草稿](zh-Hans/privacy-policy.draft.md)：基于客户端和相关后端的数据流核对，内部待确认内容不可直接公开。
- [支持页文案草稿](zh-Hans/support.draft.md)：联系邮箱、登录与学习 FAQ、隐私及删除说明。
- [隐私申报核对表与发布阻塞](privacy-review.md)：含代码证据及 Apple 官方依据。
- [验收记录](verification.md)：截图来源、测试结果、尺寸及核对边界。
- [发布状态](release-status.md)：生产部署、公开页面、IPA 验证及剩余门禁。

## 五张截图

均为 1320 × 2868、不含透明通道的原始 JPEG，适用于 Apple 当前列出的 iPhone 6.9 英寸截图尺寸。没有拼接、缩放或虚构界面。文件校验值见 [manifest.json](screenshots/manifest.json)。

| 顺序 | 截图 | 内容与注意事项 |
| --- | --- | --- |
| 1 | [今日](screenshots/01-today.jpeg) | 实际新账号每日任务和零进度 |
| 2 | [单词](screenshots/02-vocabulary.jpeg) | 真实词条、英文释义及例句；没有承诺全量中文释义 |
| 3 | [跟读](screenshots/03-speaking.jpeg) | 未练习状态，原界面显示 0 分和空识别结果；没有制造高分 |
| 4 | [阅读列表](screenshots/04-reading-list.jpeg) | 线上实际文章，来源／内容展示权仍需确认 |
| 5 | [阅读详情](screenshots/05-reading-detail.jpeg) | 真实文章正文与中文标题；正文翻译未展开 |

阅读列表／详情保留系统底部悬浮 Tab 的正常覆盖效果，长导航标题按系统布局截断。跟读准备页目前会提前显示红色文字和 0 分，是产品现状，并非截图加工结果；可在后续 UI 优化中改善，新版变更后应重拍。

## 发布前下一阶段

1. 确认文章等内容授权、服务商及数据留存／删除规则，定稿政策生效日期和 SLA。
2. 隔离后端生命周期验证和 iOS 测试已通过；完成保留策略与 worker 配置后启用生产注销。
3. 根据最终实现填写隐私申报、年龄分级、地区及价格，核对审核信息。
4. 上传已经本地导出和验签的构建，完成 App Store Connect 校验后再提交审核。

审核账号及密码不在此目录；个人审核联系电话也不包含在公开材料中。公开文案不应复制原始测试日志。
