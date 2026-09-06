# 本地上架材料验收记录

日期：2026-09-05。检查范围为本目录的草稿与截图，不是全 App 回归、真机麦克风测试或发布批准。

## 截图来源与测试

- 源码提交：`4bbff23f8eca67e828f3d1b5be0abd1c4e26eadf`；制作材料时 `git diff --exit-code -- app` 通过，正式源码未改动。
- Xcode 26.2；专用 iPhone 17 Pro Max 模拟器，iOS 26.3.1。中文、浅色外观，状态栏统一为 09:41。
- 临时 XcodeGen 工程直接引用仓库 `app/Sources`、`app/Resources` 与原 Info.plist，Release 配置；不是通过 Debug 自动化入口制造状态。模拟器采用 ad-hoc 签名，不生成新上架归档。
- XCUITest 使用专用审核账号进入真实服务，依次打开单词释义、今日、跟读、阅读列表和详情。未提交答题、未收藏词条、未录音；正常认证可能产生安全日志。
- 最终运行：`ScreenshotUITests.testCaptureStoreScreenshots` 通过；1 个测试，0 个失败，用时 30.007 秒，`TEST SUCCEEDED`。
- 截图从 XCTest 附件导出。原始截图直接编码为 JPEG；只复制五张指定附件，没有导出登录界面、测试结果包或凭据。
- 前期临时工程遇到配置缺失、关闭签名导致 Keychain 保存失败及一次点击失败；补齐配置／签名并重新运行后最终测试通过。未据此声称真机全流程已验证。

## 图像检查

五张图片均逐张查看，且 `sips` 确认：1320 × 2868、JPEG、`hasAlpha: no`。没有加载错误、登录凭据、私人电话号码或调试服务地址。SHA-256 已记录在 `screenshots/manifest.json`。

尺寸对照：[Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)。规格匹配仅代表文件尺寸满足该槽位要求，不代表内容和授权已获 Apple 认可。

截图呈现限制：跟读是未练习状态，不是语音能力验证；文章为线上真实内容，版权未核验；不以截图证明不存在的功能。后续 App 界面／版本变更时应重新制作。

## 文案与隐私核对

中文文案长度：名称 18、副标题 13、推广文本 59、关键词 35；描述长度由校验脚本按当前文案重新计算。结构化 JSON 可解析，描述正文与 Markdown 分区对应。支持／隐私 URL 已与 App 配置一致，版权已按用户确认填写为 `2026 shaofei Ma`。

当前源码已包含 App 内注册审批、账号注销／撤回／回执查询、隐私／支持入口及 `PrivacyInfo.xcprivacy`。材料仍区分“登出”与“注销”，也没有承诺未知的数据保存时限。隔离 HTTP／PostgreSQL／Redis／worker 生命周期验证已通过（后端提交 `682cbae`，25 个 PostgreSQL 用例及 live smoke 通过）；iOS 全套 104 个测试与构建已通过。这些证据不等于生产注销已启用。

## 生产与导出验证

- 生产已部署提交 `98139df`，数据库迁移为 `20260905_0002`；核对时有 5 个 active users，账号注销开关保持 `false`。
- 容器内 `/health` 返回的 `status`、`db`、`redis` 均为 `ok`。
- 公网 `/privacy` 与 `/support` 已通过未登录浏览器完成渲染验证；隐私政策中的 SLA／留存规则仍待定稿。
- `AppStoreExport/EnglishWords.ipa` 已在本地成功导出。可访问证书链的提升权限环境中，`codesign --verify --deep --strict` 通过；签名为 Apple Distribution `shaofei Ma`，Team ID `9H47USBKK4`。
- 导出包版本为 1.0（build 1）；`PrivacyInfo.xcprivacy` 中 UserDefaults 理由 `CA92.1` 已核对。
- App Store Connect 登录已恢复，Love English 1.0 为 `Prepare for Submission`。中文推广文本、512 字描述、关键词、支持 URL、版权 `2026 shaofei Ma` 及审核联系邮箱已保存；最终 Save 不可用且 Add for Review 恢复可用，页面无错误。

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

截图和 IPA 尚未上传 App Store Connect，未发布 Apple 隐私标签，也未提交 App Review；当前仅保存了部分元数据草稿。生产注销开关仍为 `false`，未执行真实账号删除。
