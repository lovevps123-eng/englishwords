# iOS 发布加固验证记录

- 验证时间：2026-09-02 00:34–00:37 JST（UTC+09:00）
- 验证提交：`941ad1d2ad00a304f33d9a88c9b7f6e6e3f7c98e`
- 范围：iOS 发布 URL 固定、Debug 服务器设置边界、ATS 配置边界，以及无需凭据的生产 HTTPS 连通性。
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
