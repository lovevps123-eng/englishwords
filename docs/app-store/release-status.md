# Love English 发布状态

更新日期：2026-09-06。此页只记录已经验证的发布事实和仍未完成的门禁。

## 已完成

- 生产已部署提交 `98139df`，Alembic 版本为 `20260905_0002`；核对时有 5 个 active users，注销开关保持 `false`。
- 容器内 `/health` 的 `status`、`db`、`redis` 均为 `ok`。
- `https://senior.dafang-edu.com/privacy` 与 `https://senior.dafang-edu.com/support` 已在未登录浏览器中完成渲染验证。
- `AppStoreExport/EnglishWords.ipa` 已本地导出；`codesign --verify --deep --strict` 在可访问证书链的提升权限环境中通过。
- IPA 使用 Apple Distribution `shaofei Ma`、Team ID `9H47USBKK4`，版本 1.0（build 1）。
- 隐私清单的 UserDefaults 理由 `CA92.1` 已验证。
- 运营主体使用 `shaofei Ma（韶飞 麻）`，App Store 版权字段使用 `2026 shaofei Ma`。
- App Store Connect 中 Love English 1.0 为 `Prepare for Submission`。新版推广文本、594 字描述、关键词、副标题和 Education 分类已保存。
- Apple 上已有 2026-09-02 上传的旧 `1.0 (1)`，不能代表本次账号生命周期版本。本次构建号已递增为 `2`，`build/LoveEnglish-1.0-2.xcarchive` 归档成功；2026-09-06 22:08 JST 上传成功，Apple 返回 `Uploaded package is processing`。Apple 处理完成须另行记录。
- 审核联系人与用户指定的 Brick Smash 8x8 一致，审核凭据已保存在 Apple 的审核资料中。生产只读查询确认审核专用账号活跃且注销申请数为 0；公开材料不记录电话或凭据。
- 用户已明确同意注销处理期限为 7 个自然日内、完成后回执可查询 30 天。该批准已记录，生产配置尚未因此自动启用。
- 用户已确认首版保留阅读，内容固定为 App bundle 中 `original-reading.json` 的六篇独立创作双语学习短文；不请求后端文章列表／详情，也没有网络回退，点词收藏继续使用后端词汇接口。
- 五个 Tab 和每日阅读已恢复；`ReadingStore` 9 个测试通过，Release 截图测试 1 个测试通过并覆盖五个 Tab、内置阅读列表和 `A Small Notebook` 详情。
- 六篇短文已逐篇核对英中对应，来源记录已核对，独立审阅无阻塞；此结论不作为版权或人工法务审核证明。
- 五张 Build 3 新截图已替换并逐张查看为 1320 × 2868；前三图对应真实界面未变化，阅读列表和详情为内置短文新图。
- `build/LoveEnglish-1.0-3-bundled-reading.xcarchive` 已成功归档为 1.0（build 3），归档内 `original-reading.json` 与源码相同。
- 当前源码提交为 `db4e6bd991aa64539ac7c34e6d55bee95d7bcc8d`。`ReadingStore` 红灯 xcresult 为 `/private/tmp/englishwords-original-reading-tests/Logs/Test/Test-EnglishWords-2026.09.06_22-40-06-+0900.xcresult`，绿灯 xcresult 为 `/private/tmp/englishwords-original-reading-tests/Logs/Test/Test-EnglishWords-2026.09.06_22-47-15-+0900.xcresult`；截图测试 xcresult 为 `/private/tmp/englishwords-store-capture.1vQp0n/Capture-build3-bundled-reading-retry.xcresult`。
- 2026-09-06 23:03:23 JST，Build 3 上传命令以 0 退出并返回 `Upload succeeded`、`Uploaded package is processing`；Apple 尚未确认处理完成。
- 五张截图已上传至 6.9 英寸槽位，6.5 英寸槽位自动沿用；回到页面后已验证 01 今日、02 单词、03 跟读、04 阅读列表、05 阅读详情共 5 项，顺序正确且无重复。

## 剩余门禁

- 等待 Apple 完成 Build 3 处理，并在 Love English 1.0 版本中选定该构建；尚未提交 App Review。
- 隔离 HTTP／PostgreSQL／Redis／worker 生命周期验证已通过（后端提交 `682cbae`，25 个 PostgreSQL 用例及 live smoke 通过）；iOS 相关测试和构建也已通过。生产注销开关仍为 `false`，SLA 7 天和完成后回执查询 30 天已获批准；服务端其他数据留存及备份处理规则仍须确定，并完成 worker 配置与启用。
- 隐私政策生效日期和最终留存文案仍待定稿。
- 词典释义、例句等既有内容的来源与截图展示依据仍待核对；内置短文核对完成不证明其他内容已获授权。
- App Privacy、年龄分级、销售地区、价格及审核信息仍须在 App Store Connect 最终核对。
