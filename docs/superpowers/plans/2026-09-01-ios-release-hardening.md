# iOS App Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Love English Release builds use a fixed HTTPS production API with strict request boundaries, Debug-only server overrides, useful network errors, configuration-specific ATS, and verified documentation.

**Architecture:** `AppConfiguration` is the single source of truth for build environment and effective base URL. `APIClient` reads that configuration for every request, validates the final API URL, and owns transport-error mapping; `SettingsStore` exposes validated Debug-only apply/reset operations. Debug and Release use separate Info.plist files so localhost access cannot leak into the production build.

**Tech Stack:** Swift 5.9, SwiftUI, Observation (`@Observable`), Foundation/URLSession, XCTest, XcodeGen 2.45+, Xcode 26+

**Spec:** `docs/superpowers/specs/2026-09-01-ios-release-hardening-design.md`

## Global Constraints

- Deployment target remains iOS 17.0 and the production URL is exactly `https://senior.dafang-edu.com`.
- Release ignores every persisted server override and exposes no server-editing UI.
- Debug accepts HTTPS overrides and HTTP only for `localhost`, `127.0.0.1`, and `::1`.
- Base URLs containing credentials, query, or fragment are rejected; invalid apply never replaces the last valid override.
- API requests must remain on the configured scheme, host, and port and their normalized path must begin `/api/`.
- `X-App-Client` is sent only to `/api/auth/login`; JWT remains the only authorization credential.
- URLSession request timeout is 30 seconds and resource timeout is 60 seconds; TLS failures never fall back to HTTP.
- Release Info.plist contains neither `NSAllowsArbitraryLoads` nor `NSAllowsLocalNetworking`.
- Do not edit `EnglishWords.xcodeproj` by hand; regenerate it from `app/project.yml`.
- Follow TDD: observe each new test fail before implementing, preserve the existing 401 single-flight behavior, and commit each task independently.

## File Map and Parallel Waves

| Wave | Task | Files owned | Dependency |
|---|---|---|---|
| 1 | Task 1 — configuration core | `AppConfiguration.swift`, `AppConfigurationTests.swift` | none |
| 2A | Task 2 — API security/errors | `APIClient.swift`, `APIClientSecurityTests.swift`, existing API client tests | Task 1 |
| 2B | Task 3 — Debug settings | `SettingsStore.swift`, `SettingsView.swift`, `SettingsStoreTests.swift` | Task 1 |
| 2C | Task 4 — ATS/build split | `project.yml`, plist files, generated xcodeproj | Task 1 interface fixed |
| 3 | Task 5 — docs and integrated verification | READMEs and verification record | Tasks 2–4 |

Wave 2 tasks have disjoint source ownership and may run in parallel in separate git worktrees. The main agent merges their commits, resolves only integration conflicts, and sends each merged diff through task review before Wave 3.

---

### Task 1: Centralized App Configuration

**Files:**
- Create: `app/Sources/Core/AppConfiguration.swift`
- Create: `app/Tests/AppConfigurationTests.swift`

**Interfaces:**
- Produces: `BuildEnvironment.current`, `.debug`, `.release`
- Produces: `ConfigurationError: LocalizedError, Equatable`
- Produces: `AppConfiguration.productionBaseURL`, `baseURL`, `storedOverride`, `validateServerOverride(_:)`, `applyServerOverride(_:)`, and `resetServerOverride()`
- Consumes later: Task 2 stores `AppConfiguration`; Task 3 calls its apply/reset API.

- [ ] **Step 1: Add failing production and override tests**

Create `AppConfigurationTests.swift` with isolated `UserDefaults` suites and these tests:

```swift
func testReleaseAlwaysUsesProductionHTTPSURL() throws {
    defaults.set("https://staging.example.com", forKey: AppConfiguration.serverOverrideKey)
    let subject = AppConfiguration(defaults: defaults, environment: .release)
    XCTAssertEqual(subject.baseURL, URL(string: "https://senior.dafang-edu.com")!)
}

func testDebugAcceptsAndNormalizesHTTPSOverride() throws {
    let subject = AppConfiguration(defaults: defaults, environment: .debug)
    try subject.applyServerOverride("  https://staging.example.com///  ")
    XCTAssertEqual(subject.baseURL.absoluteString, "https://staging.example.com")
}

func testDebugAcceptsOnlyLocalHTTPHosts() throws {
    let subject = AppConfiguration(defaults: defaults, environment: .debug)
    for value in ["http://localhost:8000", "http://127.0.0.1:8000", "http://[::1]:8000"] {
        try subject.applyServerOverride(value)
        XCTAssertEqual(subject.baseURL.scheme, "http")
    }
    XCTAssertThrowsError(try subject.applyServerOverride("http://example.com"))
}
```

Also add `testRejectsCredentialsQueryAndFragment`, `testInvalidApplyPreservesLastValidOverride`, and `testResetReturnsToProductionURL`. Assert the exact `ConfigurationError` case in every rejection test.

- [ ] **Step 2: Run the focused test target and verify failure**

Run:

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EnglishWordsTests/AppConfigurationTests test
```

Expected: compile failure because `AppConfiguration`, `BuildEnvironment`, and `ConfigurationError` do not exist.

- [ ] **Step 3: Implement the configuration types**

Implement the following public-to-module shape:

```swift
enum BuildEnvironment: Sendable {
    case debug
    case release

    static var current: Self {
        #if DEBUG
        .debug
        #else
        .release
        #endif
    }
}

enum ConfigurationError: Error, LocalizedError, Equatable {
    case invalidURL
    case httpsRequired
    case credentialsNotAllowed
    case queryOrFragmentNotAllowed
}

struct AppConfiguration {
    static let productionBaseURL = URL(string: "https://senior.dafang-edu.com")!
    static let serverOverrideKey = "serverBaseURL"

    let defaults: UserDefaults
    let environment: BuildEnvironment

    init(defaults: UserDefaults = .standard, environment: BuildEnvironment = .current)
    var storedOverride: String? { get }
    var baseURL: URL { get }
    func validateServerOverride(_ rawValue: String) throws -> URL
    func applyServerOverride(_ rawValue: String) throws
    func resetServerOverride()
}
```

Use `URLComponents`, trim whitespace, reject user/password/query/fragment, accept only the allowed schemes/hosts, and normalize `/` or repeated trailing slashes to no trailing slash. `baseURL` must ignore the key in `.release`; in `.debug`, an invalid legacy value must safely fall back to production without deleting it during a read.

Return these exact descriptions: `.invalidURL` → `"服务器地址无效"`, `.httpsRequired` →
`"服务器必须使用 HTTPS（本机调试除外）"`, `.credentialsNotAllowed` →
`"服务器地址不能包含用户名或密码"`, and `.queryOrFragmentNotAllowed` →
`"服务器地址不能包含查询参数或片段"`.

- [ ] **Step 4: Run focused tests and verify pass**

Run the Step 2 command. Expected: all `AppConfigurationTests` pass.

- [ ] **Step 5: Run existing tests for compile compatibility**

Run:

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Expected: the existing suite and new configuration tests pass.

- [ ] **Step 6: Commit Task 1**

```bash
git add app/Sources/Core/AppConfiguration.swift app/Tests/AppConfigurationTests.swift
git commit -m "feat(app): centralize environment configuration"
```

---

### Task 2: Secure API URL Construction, Headers, Timeouts, and Errors

**Files:**
- Modify: `app/Sources/Core/APIClient.swift:9-183`
- Create: `app/Tests/APIClientSecurityTests.swift`
- Modify: `app/Tests/APIClientRefreshTests.swift:62-88`
- Modify only if compilation requires configuration injection: `app/Tests/VocabStoreTests.swift`, `app/Tests/ReadingStoreTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration.baseURL`
- Produces: `APIClient.init(session:keychain:configuration:appClientKey:)`
- Produces: `APIError.networkUnavailable`, `.timeout`, `.secureConnectionFailed`, and `.transport(Error)` with stable Chinese descriptions
- Preserves: `request`, `get`, `post`, 401 refresh single-flight, and `.authDidLogout`

- [ ] **Step 1: Add failing URL-boundary and header tests**

Build a recording `URLProtocol` in `APIClientSecurityTests.swift`. Create the client with an isolated Debug `AppConfiguration` whose override is `https://api.example.com` and an injected `appClientKey: "test-app-key"`.

Add:

```swift
func testValidAPIPathUsesConfiguredOrigin() async throws
func testAbsoluteURLIsRejected() async
func testNonAPIPathIsRejected() async
func testNormalizedPathCannotEscapeAPIRoot() async
func testLoginAloneIncludesAppClientHeader() async throws
func testVocabAndRefreshRequestsOmitAppClientHeader() async throws
```

The valid request must resolve to `https://api.example.com/api/vocab/queue`. Rejection tests must catch `.invalidURL` before `URLProtocol` receives a request. Header tests assert exactly `"test-app-key"` for login and `nil` for other endpoints.

- [ ] **Step 2: Add failing transport-mapping and timeout tests**

Have the mock protocol fail with `URLError(.notConnectedToInternet)`, `.timedOut`, and `.secureConnectionFailed`. Assert the matching `APIError` case and exact messages:

```swift
"网络不可用，请检查网络后重试"
"服务器响应超时，请稍后重试"
"无法与服务器建立安全连接"
```

Expose internal `static func makeDefaultSession() -> URLSession`, then assert
`makeDefaultSession().configuration.timeoutIntervalForRequest == 30` and
`timeoutIntervalForResource == 60`.

- [ ] **Step 3: Run security tests and verify failure**

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EnglishWordsTests/APIClientSecurityTests test
```

Expected: compile/test failures for the missing initializer, URL checks, error cases, and timeout policy.

- [ ] **Step 4: Implement the minimal APIClient changes**

Add stored `configuration` and injected `appClientKey` with this initializer:

```swift
init(
    session: URLSession? = nil,
    keychain: KeychainStore = .shared,
    configuration: AppConfiguration = AppConfiguration(),
    appClientKey: String = "3da352b803d086be8ba6d1cc7bb400829a3acb322476df5f"
)
```

When `session` is nil, use `APIClient.makeDefaultSession()`. Replace direct `UserDefaults`
access with `configuration.baseURL` on every request so a valid Debug setting applies
immediately.

Before making `URLRequest`, require the raw string and normalized result to remain an API path and the resolved URL to match base scheme/host/port. Add `X-App-Client` only when the normalized path equals `/api/auth/login`.

Map `URLError` codes centrally:

- `.notConnectedToInternet`, `.networkConnectionLost`, `.dataNotAllowed` → `.networkUnavailable`
- `.timedOut` → `.timeout`
- TLS/certificate codes → `.secureConnectionFailed`
- other transport errors → `.transport(error)`

`.transport` returns the stable description `"网络请求失败，请稍后重试"`. Do not retry HTTPS
failures over HTTP.

- [ ] **Step 5: Update existing API client construction and rerun focused tests**

Inject an isolated configuration into existing URLProtocol tests where necessary. Run the Step 3 command. Expected: all security tests pass.

- [ ] **Step 6: Prove single-flight refresh still passes**

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EnglishWordsTests/APIClientRefreshTests test
```

Expected: `testConcurrent401sTriggerOnlyOneRefreshCall` passes, and the refresh request has no `X-App-Client` header.

- [ ] **Step 7: Commit Task 2**

```bash
git add app/Sources/Core/APIClient.swift app/Tests/APIClientSecurityTests.swift \
  app/Tests/APIClientRefreshTests.swift app/Tests/VocabStoreTests.swift app/Tests/ReadingStoreTests.swift
git commit -m "feat(app): harden API transport boundaries"
```

Only stage files actually changed.

---

### Task 3: Validated Debug Server Settings

**Files:**
- Modify: `app/Sources/Features/Settings/SettingsStore.swift:1-46`
- Modify: `app/Sources/Features/Settings/SettingsView.swift:7-143`
- Create: `app/Tests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: `AppConfiguration`, `ConfigurationError`
- Produces: `SettingsStore.serverBaseURL`, `applyServerBaseURL(_:)`, and `resetServerBaseURL()`
- Preserves: tier, daily new-word limit, queue refresh, logout data clearing

- [ ] **Step 1: Add failing SettingsStore tests**

Create isolated defaults for every test and inject `AppConfiguration(defaults:environment:.debug)` into `SettingsStore`.

```swift
func testApplyingValidServerPersistsAndChangesEffectiveURL() throws
func testApplyingInvalidServerPreservesPreviousValue() throws
func testResetServerReturnsToProduction() throws
```

Assert both `settings.serverBaseURL` and `configuration.baseURL`; after a rejected public HTTP address, both must still represent the previous valid HTTPS override.

- [ ] **Step 2: Run SettingsStore tests and verify failure**

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EnglishWordsTests/SettingsStoreTests test
```

Expected: compile failure because the validated apply/reset API does not exist.

- [ ] **Step 3: Refactor SettingsStore around AppConfiguration**

Keep existing learning settings unchanged. Replace the writable `didSet` server property with:

```swift
private let configuration: AppConfiguration
var serverBaseURL: String { configuration.storedOverride ?? "" }

init(
    defaults: UserDefaults = .standard,
    configuration: AppConfiguration? = nil
)

func applyServerBaseURL(_ rawValue: String) throws {
    try configuration.applyServerOverride(rawValue)
}

func resetServerBaseURL() {
    configuration.resetServerOverride()
}
```

When `configuration` is nil, construct it from the same `defaults` argument so the Store and API client share the same persisted key.

- [ ] **Step 4: Replace SettingsView's immediate binding with an apply/reset flow**

Wrap the entire server section and its state/helper methods in `#if DEBUG`. Initialize `serverURLDraft` from `settings.serverBaseURL` in `.task` or `.onAppear`. The section contains:

- URL TextField bound only to `serverURLDraft`
- “应用” button calling `settings.applyServerBaseURL(serverURLDraft)`
- “恢复生产服务器” button calling reset and clearing the draft
- success text “已应用，后续请求立即生效”
- validation error text from `ConfigurationError.localizedDescription`

Delete the old `serverBaseURLBinding` and “重启 App 后生效” copy. Do not change learning setting or logout code.

- [ ] **Step 5: Run focused and compile tests**

Run the Step 2 command, then:

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Release -sdk iphonesimulator build
```

Expected: Store tests pass and Release compiles without the Debug server section.

- [ ] **Step 6: Commit Task 3**

```bash
git add app/Sources/Features/Settings/SettingsStore.swift \
  app/Sources/Features/Settings/SettingsView.swift app/Tests/SettingsStoreTests.swift
git commit -m "feat(app): validate debug server settings"
```

---

### Task 4: Split Debug and Release ATS Configuration

**Files:**
- Modify: `app/project.yml:7-28`
- Modify: `app/Info.plist`
- Create: `app/Info-Debug.plist`
- Regenerate: `app/EnglishWords.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Debug permits only local HTTP in `AppConfiguration`.
- Produces: Debug app plist with `NSAllowsLocalNetworking = true`; Release app plist with no ATS exception.

- [ ] **Step 1: Record the failing security assertions**

Run from `app`:

```bash
rg -n 'NSAllowsArbitraryLoads|202\.182\.116\.2' project.yml Info.plist EnglishWords.xcodeproj/project.pbxproj
```

Expected before implementation: matches show `NSAllowsArbitraryLoads` in project/plist artifacts.

- [ ] **Step 2: Create configuration-specific plist sources**

Keep `Info.plist` as the Release plist and remove its entire `NSAppTransportSecurity` dictionary. Create `Info-Debug.plist` with the same bundle/display/privacy/orientation keys plus only:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

Neither plist may contain `NSAllowsArbitraryLoads`.

- [ ] **Step 3: Configure XcodeGen and regenerate**

Remove the ATS property from `info.properties`. Add configuration settings under the App target:

```yaml
settings:
  base:
    # existing settings unchanged
  configs:
    Debug:
      INFOPLIST_FILE: Info-Debug.plist
    Release:
      INFOPLIST_FILE: Info.plist
```

Run `xcodegen generate`. Review the generated pbxproj only for the expected plist path/build-setting changes.

- [ ] **Step 4: Build both configurations into isolated DerivedData**

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath build/DerivedData-Debug build
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Release -sdk iphonesimulator \
  -derivedDataPath build/DerivedData-Release build
```

Expected: both builds succeed.

- [ ] **Step 5: Assert the built plist security boundary**

```bash
DBG=build/DerivedData-Debug/Build/Products/Debug-iphonesimulator/EnglishWords.app/Info.plist
REL=build/DerivedData-Release/Build/Products/Release-iphonesimulator/EnglishWords.app/Info.plist
plutil -extract NSAppTransportSecurity.NSAllowsLocalNetworking raw -o - "$DBG" | grep -qx true
! plutil -p "$REL" | rg 'NSAllowsArbitraryLoads|NSAllowsLocalNetworking'
! rg -n 'NSAllowsArbitraryLoads|202\.182\.116\.2' project.yml Info.plist Info-Debug.plist
```

Expected: Debug local networking is true; Release and all source configs contain no arbitrary-load key or legacy IP.

- [ ] **Step 6: Commit Task 4**

```bash
git add app/project.yml app/Info.plist app/Info-Debug.plist \
  app/EnglishWords.xcodeproj/project.pbxproj
git commit -m "build(app): restrict ATS by configuration"
```

---

### Task 5: Documentation and Integrated Release Verification

**Files:**
- Modify: `README.md`
- Modify: `app/README.md`
- Create: `docs/verification/2026-09-01-ios-release-hardening.md`

**Interfaces:**
- Consumes: final behavior and commands from Tasks 1–4.
- Produces: accurate build, server, security, and verification documentation.

- [ ] **Step 1: Update repository status and server documentation**

Change the root status from “设计已确认，待实施计划” to v1 complete / release hardening complete. In `app/README.md`:

- replace every production `http://202.182.116.2` reference with `https://senior.dafang-edu.com`
- state that Release uses the fixed production URL
- state that only Debug exposes validated server settings and only localhost may use HTTP
- describe `X-App-Client` as a login-only Turnstile compatibility marker, not a secret or authorization credential
- label the smoke account private-repository-only and unsuitable for public source

- [ ] **Step 2: Run static checks**

```bash
git diff --check
! rg -n 'http://202\.182\.116\.2|NSAllowsArbitraryLoads|重启 App 后生效' \
  README.md app/README.md app/Sources app/project.yml app/Info*.plist
rg -n 'https://senior\.dafang-edu\.com' README.md app/README.md app/Sources/Core/AppConfiguration.swift
```

Expected: no legacy IP/arbitrary ATS/obsolete copy; production HTTPS appears in config and docs.

- [ ] **Step 3: Run the complete unit suite**

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Expected: all existing and new tests pass. Record the exact test count and xcresult path.

- [ ] **Step 4: Run final Debug and Release builds and plist assertions**

Repeat Task 4 Steps 4–5 against the integrated branch. Also run:

```bash
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords \
  -configuration Release -showBuildSettings | \
  rg 'INFOPLIST_FILE|PRODUCT_BUNDLE_IDENTIFIER'
```

Expected: Release selects `Info.plist`, bundle ID remains `com.masf.englishwords`, and built Release plist contains no HTTP exception.

- [ ] **Step 5: Perform production API smoke without credentials**

```bash
curl -sS -o /tmp/englishwords-release-api.json -w '%{http_code}\n' \
  https://senior.dafang-edu.com/api/vocab/queue
```

Expected: HTTP `403` with `{"detail":"Not authenticated"}`, proving HTTPS reaches the backend. Do not place credentials or JWTs in the verification file.

- [ ] **Step 6: Write the verification record**

Record date/time, git commit, exact commands, pass/fail, test count, build configurations, built-plist assertions, and the unauthenticated HTTPS smoke result in `docs/verification/2026-09-01-ios-release-hardening.md`. If simulator services are unavailable, record that command as blocked with its exact error and do not claim tests passed; complete the remaining static/build checks that are available.

- [ ] **Step 7: Commit Task 5**

```bash
git add README.md app/README.md docs/verification/2026-09-01-ios-release-hardening.md
git commit -m "docs: record iOS release hardening verification"
```

---

## Orchestration and Review Gates

1. Main agent creates/verifies an isolated `codex/ios-release-hardening` worktree and initializes the SDD ledger.
2. Task 1 is implemented and receives both spec-compliance and code-quality review.
3. After Task 1 is clean, Tasks 2, 3, and 4 are dispatched in parallel to separate worktrees from the Task 1 commit. Each agent owns only the files listed for its task, runs its focused tests, commits, and writes a report.
4. Main agent reviews and integrates the three commits; independent task reviewers inspect each task's brief/report/diff package. Any Critical or Important finding returns to that task's implementer for a scoped fix and re-review.
5. Task 5 runs only after the integrated Wave 2 suite/build is coherent.
6. A final whole-branch reviewer checks the complete diff against the spec and ledger. One consolidated fix wave is allowed, followed by one scoped re-review.
7. Main agent runs verification-before-completion and then finishing-a-development-branch; no push, merge, TestFlight upload, or production mutation occurs without explicit user authorization.
