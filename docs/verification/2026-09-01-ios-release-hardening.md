# iOS 发布加固验证记录

- 验证时间：2026-09-02 00:34–00:37 JST（UTC+09:00）
- 验证提交：`941ad1d2ad00a304f33d9a88c9b7f6e6e3f7c98e`
- 补充认证冒烟验证：2026-09-02 JST，代码提交 `2413e03`
- 范围：iOS 发布 URL 固定、Debug 服务器设置边界、ATS 配置边界，以及生产 HTTPS 连通性和认证后的最小同步路径。
- 安全说明：本记录不包含账号、密码、JWT 或其他认证材料。

## 静态检查

从仓库根目录执行：

```bash
git diff --check
! rg -n 'http://202\.182\.116\.2|NSAllowsArbitraryLoads|重启 App 后生效' \
  README.md app/README.md app/Sources app/project.yml app/Info*.plist
rg -n 'https://senior\.dafang-edu\.com' \
  README.md app/README.md app/Sources/Core/AppConfiguration.swift
```

结果：**通过**。`git diff --check` 无输出；禁止的旧 IP、任意 ATS 放行键和过时文案均无匹配。
生产 HTTPS URL 在根 README、App README 和 `AppConfiguration.swift` 中均有匹配。

## 完整单元测试

从 `app` 目录执行：

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

第一次在受限沙箱执行时，CoreSimulatorService 不可用，命令以 `70` 退出，并报告
`Unable to find a device matching the provided destination specifier`。在获准访问本机
CoreSimulator 服务后，以完全相同的命令重试。

结果：**通过，59 tests，0 failures**。

xcresult：
`/Users/masf/Library/Developer/Xcode/DerivedData/EnglishWords-bxqjtlgdusqooccluczpdalzzkai/Logs/Test/Test-EnglishWords-2026.09.02_00-35-53-+0900.xcresult`

## Debug 与 Release 构建

从 `app` 目录执行：

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath build/DerivedData-Debug build

xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Release -sdk iphonesimulator \
  -derivedDataPath build/DerivedData-Release build
```

结果：**Debug BUILD SUCCEEDED；Release BUILD SUCCEEDED**。

产物路径：

```text
build/DerivedData-Debug/Build/Products/Debug-iphonesimulator/EnglishWords.app
build/DerivedData-Release/Build/Products/Release-iphonesimulator/EnglishWords.app
```

## 内嵌 plist 与 Release 设置断言

从 `app` 目录执行：

```bash
DBG=build/DerivedData-Debug/Build/Products/Debug-iphonesimulator/EnglishWords.app/Info.plist
REL=build/DerivedData-Release/Build/Products/Release-iphonesimulator/EnglishWords.app/Info.plist
plutil -extract NSAppTransportSecurity.NSAllowsLocalNetworking raw -o - "$DBG" | grep -qx true
! plutil -p "$REL" | rg 'NSAllowsArbitraryLoads|NSAllowsLocalNetworking'
! rg -n 'NSAllowsArbitraryLoads|202\.182\.116\.2' project.yml Info.plist Info-Debug.plist

xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Release -showBuildSettings | \
  rg 'INFOPLIST_FILE|PRODUCT_BUNDLE_IDENTIFIER'
```

结果：**通过**。

- Debug 内嵌 plist 的 `NSAppTransportSecurity.NSAllowsLocalNetworking` 为 `true`。
- Release 内嵌 plist 没有 `NSAllowsArbitraryLoads` 或 `NSAllowsLocalNetworking`；直接提取
  `NSAppTransportSecurity` 返回“无该键路径”，即没有 ATS 例外字典。
- 两份源 plist 与 `project.yml` 均不含禁止键或旧 IP。
- Release build settings：`INFOPLIST_FILE = Info.plist`，
  `PRODUCT_BUNDLE_IDENTIFIER = com.masf.englishwords`。

## 无凭据生产 HTTPS 冒烟

从仓库根目录执行（未发送账号、密码或 JWT）：

```bash
curl -sS -o /tmp/englishwords-release-api.json -w '%{http_code}\n' \
  https://senior.dafang-edu.com/api/vocab/queue
```

第一次在受限网络沙箱执行时 DNS 解析失败（`curl: (6) Could not resolve host`）；在获准进行该单一
无凭据 HTTPS 请求后重试。

结果：**通过**。HTTP 状态为 `403`，响应为：

```json
{"detail":"Not authenticated"}
```

这确认 Release 固定的 HTTPS 端点可到达后端，并且未经认证的请求未获得受保护的队列数据。

## Authenticated production smoke

本节是对上述无凭据 `403` 冒烟的补充，不替代它。验证基于提交 `2413e03`，使用
iPhone 17 Pro simulator 上构建成功的当前 Debug app；未在本记录中写入账号、密码、
app client marker、JWT、refresh token 或完整响应。

### 脱敏步骤与结果

1. 干净卸载 app，重置 simulator keychain，重新安装 Debug build。
2. 使用 `SIMCTL_CHILD_SMOKE_AUTO=1` 启动 app，并由外部轮询捕获 RootView marker，顺序为：
   `vocab_unanswered` → `vocab_answered` → `reading_list_ready` →
   `reading_detail_ready` → `settings_ready`。到达这些 marker 证明登录已成功。
3. `SMOKE_AUTO` 仅向专用生产冒烟账号写入 3 个 `know` 答题。
4. 重启前查询 SwiftData `default.store` 的 `ZPENDINGRESULT`：`COUNT(*) = 3`。
5. 不使用 `SMOKE_AUTO` 重启 app；启动同步完成后再次查询，计数变为 `0`，证明 3 条本地
   结果已补交并清队。
6. 进行脱敏 API 验证：login=true、refresh=true、queue_items=0、article_items=1、
   article_detail=true。login 请求使用 `X-App-Client`；refresh 请求不使用该 header；
   随后使用刷新后的 access token 读取队列、文章列表和第一篇文章详情。token 仅在内存
   变量中处理，未记录任何认证材料。

### 结论与限制

认证冒烟补充证明生产登录、刷新、认证 API 访问、阅读列表/详情路径，以及本地待同步结果
的重启后补交流程均可用。`queue_items=0` 是本轮 3 个词已答后的合法状态，不表示队列
返回了词条。原有无凭据请求返回 `403 Not authenticated` 仍保留，作为 TLS 路由和未认证
访问受保护的证据；认证冒烟是对该证据的补充。

本轮仅覆盖专用生产冒烟账号和 3 个 `know` 答题，不代表其他账号、完整词汇覆盖或生产
流量级别验证；API 响应正文和所有认证材料均按脱敏要求省略。
