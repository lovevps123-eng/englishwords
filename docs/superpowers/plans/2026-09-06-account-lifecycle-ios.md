# Account Lifecycle iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native registration, approval-state access, account deletion request/status/cancellation, and confirmed local cleanup to the Love English iOS App.

**Architecture:** Keep learning authentication unchanged and add a separate in-memory account-management credential plus a separately persisted read-only deletion receipt. A same-origin HTTPS Turnstile page supplies short-lived challenge tokens through a tightly validated WKWebView message bridge. One `AccountLifecycleStore` owns the restricted account flow and coordinates local cleanup only after the server explicitly reports `completed`.

**Tech Stack:** Swift 5.9, SwiftUI, Observation, URLSession, Security/Keychain, WebKit, SwiftData, XCTest, React/Vite for the hosted Turnstile bridge, FastAPI/Pydantic for policy metadata.

**Spec:** `docs/superpowers/specs/2026-09-05-account-lifecycle-design.md`

## Global Constraints

- Work only in `/Users/masf/develop/project/englishwords` and `/Users/masf/develop/project/senior-platform`; preserve unrelated and untracked user files.
- Release API origin remains exactly `https://senior.dafang-edu.com`.
- Never send passwords, learning tokens, management tokens, or deletion receipts in URLs or logs.
- Learning access/refresh tokens, the 10-minute account-management token, and the read-only receipt are not substitutable.
- The account-management token is memory-only; the receipt is stored separately in Keychain and survives logout/reinstall restoration when Keychain persists.
- Only an explicit server `completed` result may clear local learning data. Generic 401, timeout, decoding, or offline errors never trigger destructive cleanup.
- Registration always ends in `pending_approval`; it never enters the learning tabs or stores learning credentials.
- The confirmation copy must name the shared senior-platform account impact: web login, vocabulary, exercises, compositions, tutoring, and study plans.
- Do not enable production deletion, run production migrations, deploy, archive, upload, or submit App Store review during this plan.

---

### Task 1: Publish challenge and policy metadata contracts

**Files:**
- Create: `/Users/masf/develop/project/senior-platform/frontend/web/src/pages/AppTurnstile.tsx`
- Create: `/Users/masf/develop/project/senior-platform/frontend/web/src/pages/AppTurnstile.test.tsx`
- Modify: `/Users/masf/develop/project/senior-platform/frontend/web/src/App.tsx`
- Modify: `/Users/masf/develop/project/senior-platform/backend/app/schemas/account.py`
- Modify: `/Users/masf/develop/project/senior-platform/backend/app/api/account.py`
- Test: `/Users/masf/develop/project/senior-platform/backend/tests/test_account_status.py`

**Interfaces:**
- Consumes: existing `/api/auth/turnstile-key`, `TurnstileWidget`, account-management authentication, and deletion configuration.
- Produces: public same-origin `/app-turnstile` page and `AccountStatusResponse.deletion_policy`.

- [ ] **Step 1: Write failing policy-metadata tests**

Assert `/api/account/status` returns configuration-derived metadata only after valid account-management authentication:

```python
assert response.json()["deletion_policy"] == {
    "enabled": True,
    "policy_version": "2026-09-06",
    "sla_days": 7,
}
```

When deletion is disabled or incomplete, return `{"enabled": false, "policy_version": null, "sla_days": null}` without exposing the receipt pepper or worker configuration.

- [ ] **Step 2: Write a failing Turnstile bridge test**

Mock `TurnstileWidget`, render `/app-turnstile`, and prove a successful token is posted only to the fixed handler name:

```ts
expect(window.webkit.messageHandlers.turnstile.postMessage)
  .toHaveBeenCalledWith({ type: "turnstile-token", token: "short-lived-token" })
```

The page must not read query parameters, local storage, learning credentials, phone, or password.

- [ ] **Step 3: Run focused tests and confirm both contracts are absent**

Run:

```bash
cd /Users/masf/develop/project/senior-platform
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest tests/test_account_status.py -q
cd frontend/web
npm test -- --run src/pages/AppTurnstile.test.tsx
```

Expected: FAIL because policy metadata and the bridge page do not exist.

- [ ] **Step 4: Implement deletion policy metadata**

Add:

```python
class DeletionPolicySummary(BaseModel):
    enabled: bool
    policy_version: str | None = None
    sla_days: int | None = None
```

Populate it from `account_deletion_configuration()`, mapping disabled or invalid configuration to `enabled=False`. Do not return the receipt retention period as a user promise until release policy is confirmed.

- [ ] **Step 5: Implement the fixed Turnstile bridge route**

Render the existing Turnstile widget on `/app-turnstile` and call only `window.webkit?.messageHandlers?.turnstile?.postMessage(...)` with token events. Display a retryable Chinese error on challenge failure or expiry. Add the route outside `ProtectedLayout`; do not accept redirect URLs or arbitrary callback names.

- [ ] **Step 6: Run backend, frontend tests, and web build**

Run:

```bash
cd /Users/masf/develop/project/senior-platform
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest tests/test_account_status.py -q
cd frontend/web
npm test -- --run src/pages/AppTurnstile.test.tsx
npm run build
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit the server-side iOS contracts**

```bash
git add backend/app/schemas/account.py backend/app/api/account.py backend/tests/test_account_status.py frontend/web/src/pages/AppTurnstile.tsx frontend/web/src/pages/AppTurnstile.test.tsx frontend/web/src/App.tsx
git commit -m "feat(account): publish iOS lifecycle metadata"
```

---

### Task 2: Add credential-isolated iOS networking and secure receipt storage

**Files:**
- Modify: `app/Sources/Core/APIClient.swift`
- Modify: `app/Sources/Core/DTO.swift`
- Modify: `app/Sources/Core/KeychainStore.swift`
- Create: `app/Sources/Features/Auth/TurnstileChallengeView.swift`
- Modify: `app/Tests/APIClientSecurityTests.swift`
- Modify: `app/Tests/DTOTests.swift`
- Create: `app/Tests/KeychainStoreLifecycleTests.swift`
- Create: `app/Tests/TurnstileChallengeTests.swift`

**Interfaces:**
- Consumes: Task 1 `/app-turnstile`, backend account/session/deletion contracts, and existing `APIClient` same-origin validation.
- Produces: `request(..., credential:)`, lifecycle DTOs, receipt Keychain operations, and a validated challenge result.

- [ ] **Step 1: Write failing credential-isolation and error tests**

Add tests proving `.management(token)` attaches only that token and never refreshes; `.receipt` endpoints remain unauthenticated with receipt in JSON body; registration/account session do not receive `X-App-Client`; and object errors decode safely:

```swift
let error = try await captureAPIError(body: #"{"detail":{"code":"ACCOUNT_DELETION_NOT_ENABLED","message":"功能未启用"}}"#)
XCTAssertEqual(error.code, "ACCOUNT_DELETION_NOT_ENABLED")
XCTAssertEqual(error.errorDescription, "功能未启用")
```

- [ ] **Step 2: Write failing DTO and Keychain tests**

Cover regions; pending registration; management session; account/deletion policy/status; request, cancellation, and receipt responses with ISO-8601 fractional/non-fractional dates. Prove `clear()` removes only learning tokens while `saveDeletionReceipt`, `loadDeletionReceipt`, and `clearDeletionReceipt` are independent.

- [ ] **Step 3: Write failing bridge validation tests**

Test pure validation helpers for the expected HTTPS origin, main-frame message, fixed `turnstile` handler, `{type:"turnstile-token",token}` shape, non-empty bounded token, and rejection of off-origin navigation/messages. No real Cloudflare request belongs in unit tests.

- [ ] **Step 4: Run focused tests and confirm interfaces are absent**

Run:

```bash
cd app
xcodegen generate
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EnglishWordsTests/APIClientSecurityTests -only-testing:EnglishWordsTests/DTOTests -only-testing:EnglishWordsTests/KeychainStoreLifecycleTests -only-testing:EnglishWordsTests/TurnstileChallengeTests test
```

Expected: build/test failure for missing lifecycle interfaces.

- [ ] **Step 5: Implement explicit credential modes and safe errors**

Use an internal enum:

```swift
enum RequestCredential {
    case none
    case learning
    case management(String)
}
```

Only `.learning` may invoke refresh. Decode both string `detail` and object `{code,message}` forms into `APIError.server(status:code:message:)`. Never interpolate request bodies or credentials into errors/logs.

- [ ] **Step 6: Implement DTOs, date decoding, receipt storage, and WebKit bridge**

Use a decoder accepting ISO-8601 dates with and without fractional seconds. Add separate Keychain account `deletionReceipt`. The SwiftUI WebKit wrapper loads only `AppConfiguration.baseURL/app-turnstile`, cancels unexpected top-frame navigation, accepts messages only from the configured HTTPS origin/main frame, removes its script handler on teardown, and returns a token through a closure.

- [ ] **Step 7: Run focused tests and commit**

Run the command from Step 4, then `git diff --check`. Expected: exit 0.

```bash
git add app/Sources/Core app/Sources/Features/Auth/TurnstileChallengeView.swift app/Tests
git commit -m "feat(app): isolate account lifecycle credentials"
```

---

### Task 3: Add native registration and restricted account status

**Files:**
- Create: `app/Sources/Features/Account/AccountLifecycleStore.swift`
- Create: `app/Sources/Features/Account/RegistrationView.swift`
- Create: `app/Sources/Features/Account/AccountManagementView.swift`
- Modify: `app/Sources/Features/Auth/LoginView.swift`
- Modify: `app/Sources/Features/Auth/AuthStore.swift`
- Modify: `app/Sources/EnglishWordsApp.swift`
- Create: `app/Tests/AccountLifecycleStoreTests.swift`

**Interfaces:**
- Consumes: Task 2 API/DTO/challenge/receipt boundaries.
- Produces: registration submission, management reauthentication, and minimal approval/deletion status presentation.

- [ ] **Step 1: Write failing store flow tests**

Use a protocol-backed fake lifecycle client. Cover valid field submission, regions load, optional SMS, Turnstile token requirement, duplicate-tap suppression, pending result without learning tokens, unknown/wrong-password indistinguishability, pending/rejected/disabled/deleting status display, and network errors preserving entered non-password fields while clearing passwords/challenge tokens.

- [ ] **Step 2: Run focused tests and confirm the store is absent**

Run: `cd app && xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EnglishWordsTests/AccountLifecycleStoreTests test`

Expected: build failure because `AccountLifecycleStore` is absent.

- [ ] **Step 3: Implement the lifecycle store**

Keep `managementToken` private and memory-only. Expose value state rather than raw credentials:

```swift
enum AccountLifecycleScreenState: Equatable {
    case signedOut
    case authenticating
    case status(AccountStatusResponse)
    case submitting
    case failure(String)
}
```

Clear the token when the flow is dismissed or expires. Do not set `AuthStore.isAuthenticated` for pending/rejected/disabled/deleting accounts.

- [ ] **Step 4: Implement registration and management views**

Replace the login-page web-registration note with `申请账号` and `查看申请/管理账号`. Registration collects phone, password/confirmation, name, valid region, optional grade/school and SMS code, links to the HTTPS privacy policy, runs Turnstile before submission, and always shows pending confirmation. Management reauthenticates with password plus Turnstile and shows safe status/rejection reason/deletion progress.

- [ ] **Step 5: Inject the store and run focused tests/build**

Inject one `@State AccountLifecycleStore` from `EnglishWordsApp`. Run:

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EnglishWordsTests/AccountLifecycleStoreTests test
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit registration and status UI**

```bash
git add app/Sources/Features/Account app/Sources/Features/Auth app/Sources/EnglishWordsApp.swift app/Tests/AccountLifecycleStoreTests.swift
git commit -m "feat(app): add registration and account status"
```

---

### Task 4: Add deletion request, cancellation, receipt, and confirmed cleanup

**Files:**
- Modify: `app/Sources/Features/Account/AccountLifecycleStore.swift`
- Modify: `app/Sources/Features/Account/AccountManagementView.swift`
- Modify: `app/Sources/Features/Settings/SettingsView.swift`
- Modify: `app/Sources/Features/Settings/SettingsStore.swift`
- Modify: `app/Sources/Features/Vocab/VocabStore.swift`
- Modify: `app/Sources/Features/Auth/AuthStore.swift`
- Modify: `app/Sources/EnglishWordsApp.swift`
- Modify: `app/Tests/AccountLifecycleStoreTests.swift`
- Modify: `app/Tests/SettingsStoreTests.swift`

**Interfaces:**
- Consumes: management credential, `deletion_policy`, deletion request/cancel endpoints, persisted receipt endpoint, `VocabStore.clearAllLocalData()`.
- Produces: user-visible request status and `LocalAccountDataCleaner.clearAfterConfirmedDeletion()`.

- [ ] **Step 1: Write failing request/status safety tests**

Cover exact `DELETE_ACCOUNT` confirmation, current server policy version, optional reason, receipt persisted before success is shown, idempotent repeat response, cancellation only before processing, receipt query after learning logout, failed state without false completion, and button disabling during in-flight work.

- [ ] **Step 2: Write failing local-cleanup boundary tests**

Prove explicit `completed` clears SwiftData cached words/pending results, all `checkin.*` keys, personal settings, learning tokens, management token, and the receipt after final confirmation is retained in visible state. Prove 401, timeout, offline, unknown receipt, `requested`, `processing`, and `failed` clear nothing.

- [ ] **Step 3: Run focused tests and confirm deletion flow is absent**

Run:

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EnglishWordsTests/AccountLifecycleStoreTests -only-testing:EnglishWordsTests/SettingsStoreTests test
```

Expected: FAIL because deletion actions and coordinated cleanup are absent.

- [ ] **Step 4: Implement the user deletion flow**

Add `账号与隐私` under Settings. Require password reauthentication, show platform-wide impact and unsynced-data warning, require a second destructive confirmation, then submit with the exact policy version. Present `requested`, `processing`, `failed`, `completed`, and `cancelled` distinctly. Offer cancel only while requested and retry is never offered to the user.

- [ ] **Step 5: Implement explicit completion cleanup**

Move existing check-in cleanup into a reusable collaborator and add personal settings cleanup. The lifecycle store calls it only from the decoded receipt/status branch where `status == .completed`. Keep a final in-memory completed screen so the user sees confirmation after credentials and local data are removed.

- [ ] **Step 6: Run focused tests and a full simulator test**

Run:

```bash
cd app
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EnglishWordsTests/AccountLifecycleStoreTests -only-testing:EnglishWordsTests/SettingsStoreTests test
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit deletion and cleanup UI**

```bash
git add app/Sources app/Tests
git commit -m "feat(app): add safe account deletion flow"
```

---

### Task 5: Run release-candidate integration checks without publishing

**Files:**
- Modify only if a test reveals an in-scope defect: files already listed in Tasks 1–4.
- Record evidence: `.superpowers/sdd/2026-09-06-account-lifecycle-ios/progress.md`

**Interfaces:**
- Consumes: completed administrator plan plus Tasks 1–4.
- Produces: evidence required to start privacy/App Store release work.

- [ ] **Step 1: Run full backend and frontend verification**

```bash
cd /Users/masf/develop/project/senior-platform
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest -q
cd frontend/web
npm test
npm run build
```

Expected: every command exits 0 with only documented environment skips/xfail.

- [ ] **Step 2: Run full iOS tests and Debug/Release builds**

```bash
cd /Users/masf/develop/project/englishwords/app
xcodegen generate
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug -destination 'generic/platform=iOS Simulator' build
xcodebuild -project EnglishWords.xcodeproj -scheme EnglishWords -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

Expected: tests and both builds exit 0.

- [ ] **Step 3: Perform only synthetic non-production lifecycle smoke**

With deletion enabled only in a disposable/staging environment, verify registration → administrator approval/rejection → management status → request → administrator queue → worker → receipt completed → local cleanup. Use a synthetic user and owned fixture files; never use the App Store reviewer account or a real user.

- [ ] **Step 4: Verify security and product boundaries**

Confirm no credential appears in URL/log output, off-origin Turnstile navigation is rejected, generic network/auth failures preserve local data, direct administrator deletion controls are absent, and production deletion remains disabled.

- [ ] **Step 5: Commit only evidence or in-scope fixes**

If no source fix is needed, record exact command results without an empty commit. If an in-scope defect is found, use a failing regression test, make the minimum fix, rerun the affected full command, and commit with a precise `fix(...)` message.

## Completion Gate

- A new user can register natively and receives only pending state.
- Pending/rejected/disabled/deleting users can securely authenticate to the restricted account-management flow but cannot enter learning APIs.
- A user can request/cancel before processing, retain a read-only receipt, and see completed/failed state accurately.
- Only explicit server completion clears all listed iOS local account data; offline, generic 401, and ordinary failures do not.
- Turnstile works through the fixed same-origin HTTPS bridge without putting credentials in URLs.
- Full backend/frontend/iOS tests and Debug/Release builds exit 0 in isolated environments.
- Production deletion, deployment, archive, upload, and App Store submission remain separate release gates.
