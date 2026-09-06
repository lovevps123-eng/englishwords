# 本地上架材料验收记录

日期：2026-09-06。检查范围为本目录的草稿与截图，不是真机麦克风测试或发布批准。

## 截图来源与测试

- Build 1/2 的旧五图展示后端文章内容，已被本轮五张 Build 3 新图替换。
- Release 截图测试 1 个测试通过，确认五个 Tab、每日阅读、含一篇内置短文的阅读列表，以及 `A Small Notebook` 详情可见。
- 截图测试结果：`/private/tmp/englishwords-store-capture.1vQp0n/Capture-build3-bundled-reading-retry.xcresult`。
- 截图从 XCTest 附件导出为五张 JPEG，没有导出登录界面、测试结果包或凭据。

## 图像检查

五张新图均已逐张查看，且 `sips` 确认尺寸为 1320 × 2868。前三图因对应真实界面未变化而与旧图 SHA-256 相同；阅读列表和详情为内置 AI 辅助创作短文的新图。

尺寸对照：[Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。规格匹配仅代表文件尺寸满足该槽位要求，不代表内容和授权已获 Apple 认可。

阅读详情截图默认显示英文正文，只展开中文标题；段落中文译文需要点击后显示，截图不证明已展示全文译文。六篇短文已逐篇阅读核对英中对应，独立审阅无阻塞；这不证明词典释义或例句的来源授权。

## 文案与隐私核对

Build 3 新描述为 594 字，推广文本、关键词、副标题和 Education 分类均已保存至 App Store Connect。支持／隐私 URL 已与 App 配置一致，版权已按用户确认填写为 `2026 shaofei Ma`。

恢复五个 Tab 和每日阅读已完成，源码提交为 `db4e6bd991aa64539ac7c34e6d55bee95d7bcc8d`。`ReadingStore` 的红灯结果为 9 个测试中 5 个失败（`/private/tmp/englishwords-original-reading-tests/Logs/Test/Test-EnglishWords-2026.09.06_22-40-06-+0900.xcresult`）；实现后的绿灯结果为 9 个测试、0 个失败（`/private/tmp/englishwords-original-reading-tests/Logs/Test/Test-EnglishWords-2026.09.06_22-47-15-+0900.xcresult`）。材料仍区分“登出”与“注销”，这些证据不等于生产注销已启用。

## 生产与导出验证

- 生产已部署提交 `98139df`，数据库迁移为 `20260905_0002`；核对时有 5 个 active users，账号注销开关保持 `false`。
- 容器内 `/health` 返回的 `status`、`db`、`redis` 均为 `ok`。
- 公网 `/privacy` 与 `/support` 已通过未登录浏览器完成渲染验证；SLA／回执期限已确认，隐私政策中的其他留存规则仍待定稿。
- `AppStoreExport/EnglishWords.ipa` 已在本地成功导出。可访问证书链的提升权限环境中，`codesign --verify --deep --strict` 通过；签名为 Apple Distribution `shaofei Ma`，Team ID `9H47USBKK4`。
- 导出包版本为 1.0（build 1）；`PrivacyInfo.xcprivacy` 中 UserDefaults 理由 `CA92.1` 已核对。
- `build/LoveEnglish-1.0-3-bundled-reading.xcarchive` 已成功归档为 1.0（build 3），归档内 `original-reading.json` 与源码资源相同。
- 2026-09-06 23:03:23 JST，Build 3 上传命令以 0 退出，并返回 `Upload succeeded`、`Uploaded package is processing`。这证明上传完成，不代表 Apple 已处理完成。
- App Store Connect 中 Love English 1.0 为 `Prepare for Submission`。新版推广文本、594 字描述、关键词、副标题和 Education 分类已保存。
- 五张截图已上传到 6.9 英寸槽位，6.5 英寸槽位自动沿用；页面返回后确认顺序为 01 今日、02 单词、03 跟读、04 阅读列表、05 阅读详情，共 5 项且无重复。

隐私政策属于技术事实草稿，不是法律意见或最终正式政策。阻塞项完整列于 `privacy-review.md`，需结合最终生产配置与发布地区完成确认。

## 可重复检查

在仓库根目录运行：

```sh
node docs/app-store/verify-materials.mjs
git diff --exit-code -- app
git diff --check
```

校验脚本只读取本地材料：检查 JSON、文案长度／一致性、截图数量、SHA-256、格式、尺寸、透明通道，以及明显的私钥／令牌文本。不访问网络，不包含或读取审核密码，不上传材料。敏感信息自动检查不能替代人工逐张检查。

## 未执行

Build 2 已于 2026-09-06 22:08 JST 上传成功，但不再作为首版最终材料。Build 3 已上传成功，仍在等待 Apple 处理并在版本中选定；未发布 Apple 隐私标签，也未提交 App Review。生产注销开关仍为 `false`，未执行真实账号删除。
