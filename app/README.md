# EnglishWords App — 构建与发布

v1 客户端工程，SwiftUI + SwiftData，iOS 17+。工程文件由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从
`project.yml` 生成，**不要直接改 `EnglishWords.xcodeproj`**——改 `project.yml` 后重新 `xcodegen generate`。

## 本地构建

```bash
brew install xcodegen   # 只需一次
cd app
xcodegen generate
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

跑单元测试：

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 真机安装

签名已在 `project.yml` 配好 `DEVELOPMENT_TEAM: 9H47USBKK4`（Team: shaofei Ma）+ `CODE_SIGN_STYLE: Automatic`，
Xcode 会自动用开发者账号 `lovevps123@gmail.com` 的证书签名，无需手动改签名设置。

1. 打开 `app/EnglishWords.xcodeproj`（或先 `xcodegen generate` 保证工程与 `project.yml` 同步）。
2. 数据线接入 iPhone，Xcode 顶部设备选择器选中该真机。
3. 首次运行前，在真机「设置 → 通用 → VPN 与设备管理」里信任一次开发者证书。
4. ⌘R 运行；首次登录会请求麦克风/语音识别权限（跟读模块用），需允许。

## TestFlight 上传（概述）

App Store Connect API Key 已在本机配好，用于命令行上传（无需在 Xcode 里额外登录账号）：

- Key ID: `LVF9LT3HU2`
- Issuer ID: `bb586938-750d-49ef-936f-51903772e111`
- `.p8` 私钥路径：`~/.appstoreconnect/private_keys/AuthKey_LVF9LT3HU2.p8`

⚠️ 该账号登录邮箱是 `lovevps123@gmail.com`（Team ID `9H47USBKK4`），**不是**环境默认邮箱
`admin@nisshintokin.com`——两者是不同的 Apple ID，App Store Connect 相关操作一律认 `lovevps123@gmail.com`。

上传步骤（首次需要在 App Store Connect 网页端建好 App 记录，Bundle ID `com.masf.englishwords`；
这一步及后续「提交审核」需要用户本人在网页操作，此处只覆盖命令行归档+上传）：

```bash
cd app
xcodegen generate

# 1. 归档（Release 配置，真机架构）
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/EnglishWords.xcarchive archive

# 2. 导出 .ipa（exportOptions.plist 需指定 method: app-store，teamID: 9H47USBKK4）
xcodebuild -exportArchive -archivePath build/EnglishWords.xcarchive \
  -exportPath build/export -exportOptionsPlist exportOptions.plist

# 3. 上传到 App Store Connect
xcrun altool --upload-app -f build/export/EnglishWords.ipa -t ios \
  --apiKey LVF9LT3HU2 --apiIssuer bb586938-750d-49ef-936f-51903772e111
```

上传成功后，构建版本处理（几分钟到十几分钟）完成的通知邮件会发到 `lovevps123@gmail.com`；
之后在 App Store Connect 网页端把该构建加入 TestFlight 内部测试组，即可推送给测试设备——这一步
（以及正式提交审核）留给用户本人在网页操作，不在本仓库自动化范围内。

## 服务器与冒烟测试账号

Release 固定使用生产服务器 `https://senior.dafang-edu.com`，不会读取或应用本地服务器覆盖。
只有 Debug 构建会在「我的」页公开经过校验的服务器设置；它接受 HTTPS 地址，HTTP 仅允许
`localhost`、`127.0.0.1` 或 `[::1]`。Release 不提供服务器设置入口。

生产环境预置了一个专供 App 冒烟测试的账号。该账号的标识和密码仅保存在私有仓库的受控配置中，
不适合写入公开源码、测试脚本或文档；请向项目维护者取得授权的测试配置。`app/Tests/` 目录下的
单元测试全部跑在内存态 SwiftData + 假 URLProtocol 上，不依赖这个账号。该账号仅用于获授权的人工
或模拟器全流程冒烟（连接生产真实数据）。

登录请求中的 `X-App-Client` 仅是与 Turnstile 兼容的标记；它不是秘密，也不是授权凭据。

## 冒烟自动化（SMOKE_AUTO，仅 DEBUG 构建）

`SMOKE_AUTO=1` 时（见 `Sources/Core/SmokeAuto.swift`，整个文件包在 `#if DEBUG`，Release 不含这段代码），
App 会自动完成：填入获授权的私有冒烟测试配置（可用 `SMOKE_PHONE`/`SMOKE_PASSWORD` 提供）→ 提交登录
→ 依次切到 单词/阅读/我的 Tab → 背 3 词 → 打开第一篇文章详情。每完成一步会把步骤名写入 App 沙盒
`Documents/smoke_marker.txt`，外部脚本轮询这个文件判断"数据/界面已就绪、可以截图"，而不是猜固定的
睡眠时长（生产网络延迟不定）。

用法（模拟器）：

```bash
UDID=<simulator udid>
xcrun simctl uninstall $UDID com.masf.englishwords   # 清掉旧 Keychain token，保证从登录页开始
xcrun simctl keychain $UDID reset                    # 模拟器 Keychain 在重装后可能仍保留旧 token，需显式 reset
xcrun simctl install $UDID <path-to>/EnglishWords.app
SIMCTL_CHILD_SMOKE_AUTO=1 xcrun simctl launch $UDID com.masf.englishwords
# 轮询 $(xcrun simctl get_app_container $UDID com.masf.englishwords data)/Documents/smoke_marker.txt
# 依次出现 login_filled/today_ready/vocab_unanswered/vocab_answered/
# reading_list_ready/reading_detail_ready/settings_ready 时各截一张图
```

注意：给 `simctl launch` 传环境变量必须用 `SIMCTL_CHILD_<KEY>=value` 前缀设在调用者 shell 里，
直接跟在 launch 参数后面的 `KEY=value` 会被当成 argv 而不是环境变量。
