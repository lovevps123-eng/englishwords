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
- App Store Connect 登录已恢复；Love English 1.0 为 `Prepare for Submission`。中文推广文本、512 字描述、关键词、支持 URL、版权和审核联系邮箱已成功保存为草稿，页面无错误。
- Apple 上已有 2026-09-02 上传的旧 `1.0 (1)`，不能代表本次账号生命周期版本。本次构建号已递增为 `2`，`build/LoveEnglish-1.0-2.xcarchive` 归档成功，正在上传；上传成功和 Apple 处理完成须另行记录。

## 剩余门禁

- 截图尚未上传；Build 2 上传进行中，尚未提交 App Review；当前已完成部分元数据草稿保存。
- 隔离 HTTP／PostgreSQL／Redis／worker 生命周期验证已通过（后端提交 `682cbae`，25 个 PostgreSQL 用例及 live smoke 通过）；iOS 相关测试和构建也已通过。生产注销开关仍为 `false`，待确认 SLA、服务端数据留存及备份处理规则并完成 worker 启用。
- 隐私政策生效日期和最终留存文案仍待定稿。
- 文章等内容的使用与截图展示授权仍待明确，不能推断已有授权。
- App Privacy、年龄分级、销售地区、价格及审核信息仍须在 App Store Connect 最终核对。
