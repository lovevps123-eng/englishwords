# Final Review Fix Report

Base commit: `a91c651`

## Delivered changes

- `AppConfiguration.validateServerOverride(_:)` now accepts only an empty path or a path made solely of root slashes, normalizing accepted root forms to no path. Any other path throws `ConfigurationError.pathNotAllowed` with the exact localized description `服务器地址不能包含路径`.
- Failed non-root overrides do not reach the persistence write, so the preceding valid override remains effective.
- Added an integration-style API client test showing a normalized root override resolves `/api/vocab/queue` to exactly `https://api.example.com/api/vocab/queue`.
- Corrected only the `X-App-Client` code comment: it is extractable from the app bundle, exists only as a login Turnstile compatibility marker, and is neither a secret nor an authorization credential. Runtime header behavior was not changed.

## TDD evidence

### RED

1. Added the non-root rejection, persistence-preservation, and root-origin request tests before modifying production code.
2. The first focused compile correctly failed because `ConfigurationError.pathNotAllowed` did not yet exist.
3. After changing the preliminary assertions to the observable localized-error contract, the focused AppConfiguration run compiled and failed as intended:
   - `testDebugRejectsNonRootPathsWithPathNotAllowedError`: all three `/proxy`, `/proxy/`, and `/api` cases did not throw.
   - `testRejectedNonRootPathPreservesLastValidOverride`: `/proxy` did not throw and replaced `https://staging.example.com` with `https://staging.example.com/proxy`.
   - Result: 9 executed, 6 failures, `** TEST FAILED **`.

### GREEN

Implemented the new error case and minimal path validation, then restored the enum assertions. The focused command passed:

```sh
xcodebuild -project app/EnglishWords.xcodeproj -scheme EnglishWords -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EnglishWordsTests/AppConfigurationTests \
  -only-testing:EnglishWordsTests/APIClientSecurityTests test
```

Result: `AppConfigurationTests` 9/9, `APIClientSecurityTests` 11/11; 20 tests total, 0 failures, `** TEST SUCCEEDED **`.

The root-normalization test explicitly covers no path, `/`, and `///`; rejection tests cover `/proxy`, `/proxy/`, and `/api` plus preservation of a previously persisted root override.

## Final verification

| Check | Command/result |
| --- | --- |
| Full Debug unit suite | `xcodebuild ... -configuration Debug ... test` — 61 executed, 0 failures, `** TEST SUCCEEDED **` (59 base tests + 2 new tests). |
| Release simulator build | `xcodebuild -project app/EnglishWords.xcodeproj -scheme EnglishWords -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` — `** BUILD SUCCEEDED **`. |
| Diff whitespace | `git diff --check` — exit 0, no output. |
| Scope/diff self-review | Only the two required production files and their corresponding tests are changed, besides this required report; no existing verification documentation changed. The API client runtime diff is comment-only, and existing login-only header tests remain green. |

The compiler emitted pre-existing Swift 6-concurrency warnings in `APIClient` around `NSLock` use from async contexts; this patch neither changes those lines nor adds new warnings. Simulator test logs also include existing font and mocked transport diagnostics; all assertions passed.

## Explicitly not performed

No production authenticated smoke test was run. No account, password, JWT, or other authentication material was accessed or used.
