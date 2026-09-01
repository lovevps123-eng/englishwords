# iOS App 发布前加固设计

**日期：** 2026-09-01  
**状态：** 待用户最终审阅  
**范围：** `englishwords` iOS 客户端；不修改 `senior-platform` 后端接口或部署

## 背景

Love English v1 已完成主要学习流程，但客户端仍默认请求
`http://202.182.116.2`，并通过 `NSAllowsArbitraryLoads` 放行全部 HTTP 流量。
生产服务已经可通过 `https://senior.dafang-edu.com` 访问；HTTP 域名会 301
跳转到 HTTPS，`/api/*` 路径可正常到达后端。因此客户端可以直接使用 HTTPS
域名并收紧网络边界。

本阶段的目标是让 Release 构建使用固定、安全的生产配置，同时保留 Debug
构建连接开发服务器的能力，并改善网络错误反馈与回归测试。

## 目标

- Release 构建始终连接 `https://senior.dafang-edu.com`。
- 删除全局 `NSAllowsArbitraryLoads`，正式流量只走 HTTPS。
- Debug 构建允许配置 HTTPS 测试服务器，以及本机开发使用的 localhost HTTP。
- 集中管理运行环境和 URL 校验，不再由 `APIClient` 直接读取未经校验的
  `UserDefaults`。
- 为网络错误提供稳定、可理解的中文提示。
- 将 `X-App-Client` 请求头限制在登录请求，减少不必要的暴露。
- 更新过时的项目状态和服务器说明。

## 非目标

- 不在本阶段修改后端认证、Turnstile 或部署配置。
- 不引入 App Attest、DeviceCheck、证书锁定或新的密钥分发系统。
- 不把 `X-App-Client` 描述成可保密的客户端密钥；安装包内的常量可以被提取。
- 不开发跟读真机验证或听力模块。

## 方案选择

采用“生产安全、开发可配置”的构建环境方案：Release 固定 HTTPS 生产地址，
Debug 保留经过校验的服务器覆盖。相比所有构建固定生产地址，该方案保留本地调试
能力；相比只替换默认 URL，该方案能实际移除任意 HTTP 放行并防止 Release 误配。

## 架构

### AppConfiguration

新增集中式 `AppConfiguration`，负责：

- 提供生产地址常量 `https://senior.dafang-edu.com`。
- 根据构建环境决定有效 base URL。
- 在 Debug 中读取和校验服务器覆盖值。
- 在 Release 中忽略所有持久化覆盖值并返回生产地址。

服务器覆盖的校验规则：

- 必须是绝对 URL，包含 scheme 和 host。
- 默认只接受 `https`。
- Debug 中允许 `http://localhost`、`http://127.0.0.1` 和
  `http://[::1]`，用于本地开发。
- 拒绝包含用户名、密码、query 或 fragment 的 base URL。
- 规范化尾部斜杠，避免相对 URL 拼接语义变化。

`APIClient` 通过注入的配置获取 base URL。默认实例使用生产/当前 Debug 配置，测试
可以注入固定配置，避免依赖全局 `UserDefaults`。

### Settings

Release 的“我的”页不显示服务器地址编辑区。Debug 中保留该区域：

- 用户输入先保存在视图草稿中，不在每次按键时写入有效配置。
- 点击“应用”后进行校验；成功后持久化并立即用于后续请求。
- 失败时显示具体原因，保留上一次有效地址。
- 提供“恢复生产服务器”操作。

学习难度、每日新词量和登出行为保持不变。

### APIClient 请求边界

`APIClient` 继续接收以 `/api/` 开头的相对路径，并在发送前确认最终 URL 的 scheme、
host 和 port 与配置的 base URL 一致。绝对 URL、非 API 路径或越过主机边界的路径
返回 `APIError.invalidURL`。

URLSession 的单次请求超时设为 30 秒、资源超时设为 60 秒，并由测试覆盖；请求不会
无限等待。

`X-App-Client` 仅在 `/api/auth/login` 请求中附加。它继续兼容现有后端的 App 登录
Turnstile 豁免，但不用于授权、用户识别或其他接口。JWT 仍是授权的唯一客户端凭证，
并继续保存在 Keychain。

### ATS 配置

从 `project.yml` 删除 `NSAllowsArbitraryLoads: true`。不为生产域名或公网 IP 添加
HTTP 例外。Debug 配置若需要 localhost HTTP，仅使用 `NSAllowsLocalNetworking` 或
等效的 localhost 最小例外，并通过构建配置保证该例外不进入 Release；不恢复全局放行。

## 错误处理

扩展 `APIError`，稳定映射以下情况：

- URL 或配置无效：提示检查服务器配置。
- 无网络连接：提示检查网络后重试。
- 请求超时：提示服务器响应超时。
- TLS/安全连接失败：提示无法建立安全连接，不回退到 HTTP。
- 非 HTTP 响应或解码失败：保留现有通用提示。
- HTTP 错误：优先展示后端 `detail`，否则展示状态码通用提示。
- 401 刷新失败：保持清理 Token 并返回登录页的现有行为。

Store 和 View 继续通过 `LocalizedError` 展示消息，不分别判断底层
`URLError`，保证网络错误转换集中在 `APIClient`。

## 测试

新增或扩展单元测试，至少覆盖：

- Release/生产配置始终返回 HTTPS 生产域名。
- Debug 覆盖接受 HTTPS 和 localhost HTTP，拒绝公网 HTTP、凭证、query 与 fragment。
- 无效的新设置不会覆盖上一次有效设置，恢复操作返回生产地址。
- APIClient 接受合法 `/api/` 相对路径，拒绝绝对 URL、非 API 路径和跨主机路径。
- `X-App-Client` 只出现在登录请求，不出现在词汇、阅读或 refresh 请求。
- 断网、超时和 TLS 错误映射为对应 `APIError` 与中文提示。
- 现有 401 single-flight refresh、DTO、Store 和离线队列测试继续通过。

验证分为三层：

1. Xcode 单元测试。
2. Debug 模拟器登录与单词/阅读冒烟。
3. Release 配置检查，确认生成的 Info.plist 不包含全局任意 HTTP 放行，且生产
   base URL 为 HTTPS 域名。

## 文档更新

- 根 `README.md` 状态更新为 v1 已完成并进入发布加固。
- `app/README.md` 的默认服务器由 HTTP IP 更新为 HTTPS 域名。
- 说明服务器地址编辑仅存在于 Debug 构建。
- 保留私有仓库的专用冒烟测试账号，同时明确不得用于公开仓库或生产用户。
- 不在文档中声称 `X-App-Client` 是秘密或安全认证凭证。

## 风险与后续工作

- `X-App-Client` 可从安装包中提取。当前风险通过“仅登录发送、后端仅豁免
  Turnstile、JWT 才授权”限制，但公开发行前仍应单独设计登录限流与 App Attest。
- 切换域名后，需要执行一次真实账号登录、Token refresh、单词同步和阅读加载冒烟，
  确认 Cloudflare 未对 App 请求施加额外挑战。
- 本阶段完成后，按既定顺序进入跟读真机验证，再规划听力模块。

## 完成标准

- Release 构建不包含全局 ATS 放行或可编辑服务器地址。
- App 的全部正式 API 请求使用 `https://senior.dafang-edu.com/api/...`。
- 非登录请求不携带 `X-App-Client`。
- 新增配置、URL 边界和网络错误测试通过，现有测试无回归。
- Debug 与 Release 冒烟验证均有可复现记录。
