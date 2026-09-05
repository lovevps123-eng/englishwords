# Account Deletion Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend account-management session, deletion request/receipt flow, durable and re-entrant deletion worker, and administrator scheduling APIs required by the approved account-lifecycle design.

**Architecture:** A typed short-lived account-management JWT permits only self-service status and deletion operations, including for non-active users. An `AccountDeletionRequest` is the durable workflow and receipt record; administrators queue work, a cron-safe worker claims it with PostgreSQL row locks, persisted file tasks finish first, and a final explicit database transaction removes user-owned data and identity. Deletion stays disabled until service-level, retention, upload-cache, and operations settings are explicitly configured.

**Tech Stack:** FastAPI, Pydantic 2, SQLAlchemy 2 async, PostgreSQL 16, Alembic, Redis, pytest/pytest-asyncio, Docker.

**Spec:** `docs/superpowers/specs/2026-09-05-account-lifecycle-design.md`

## Global Constraints

- Work only in the isolated `senior-platform` branch/worktree; do not modify production data, deploy services, or submit App Store review.
- Account deletion affects the shared senior-platform identity and all associated web/iOS learning data, not only the English App.
- `X-App-Client` remains a login-only compatibility header and is never accepted as registration, account-session, receipt, or deletion authorization.
- Access, refresh, account-management, and receipt credentials are distinct; a credential of one type must fail every dependency for another type.
- Store only an HMAC digest of a 256-bit-or-stronger receipt. Return receipt plaintext only on initial creation and never put it in URL parameters, audit entries, application logs, or exception text.
- `ACCOUNT_DELETION_ENABLED` defaults to `false`. Enabling requires explicit non-empty policy version, SLA days, receipt-retention days, and receipt HMAC pepper; no code path may silently assume seven days.
- Persist `due_at` when a request is created. Later configuration changes must not extend an existing deadline.
- There is no administrator rejection action for deletion. Administrators may queue requested work and retry failed work only.
- Never recursively delete a broad directory or delete an unverified URL. Every file operation targets one normalized relative key recorded in a persistent task.
- Shared dictionaries, articles, question banks, knowledge points, subject content, regions, and administrator content remain intact.
- A request becomes `completed` only after all required file tasks are terminal-success and the database purge transaction commits. Missing files are idempotent success; unsafe/ambiguous paths and I/O errors are failure.
- Current code policy deletes user-linked payment, LLM-usage, and detailed audit rows. Production enablement remains blocked until the operator confirms payment, security-log, receipt, backup, and provider-retention obligations against this policy.
- New user-owned uploads must use user-scoped keys and `Cache-Control: no-store`. Production enablement remains blocked until the `/uploads/users/` edge-cache bypass and removal of pre-existing cached user objects are verified.

---

### Task 1: Add typed credentials and transaction-friendly audit entries

**Files:**
- Modify: `backend/app/core/security.py`
- Modify: `backend/app/core/audit.py`
- Modify: `backend/app/api/deps.py`
- Test: `backend/tests/test_account_token_types.py`

**Interfaces:**
- Produces: `create_account_management_token(user_id: UUID, authenticated_at: datetime) -> str`.
- Produces: `require_token_type(payload: dict, expected: str, *, allow_legacy_access: bool = False) -> None`.
- Produces: `hash_deletion_receipt(receipt: str, pepper: str) -> str` using HMAC-SHA256.
- Produces: `add_audit_entry(db, user_id, action, target_type, target_id, detail, request) -> AuditLog` without committing.
- Preserves: `log_audit(...)` as the existing add-and-commit compatibility wrapper.
- Produces: `get_account_management_user` dependency that intentionally loads pending, rejected, disabled, or deleting users without granting learning access.

- [ ] **Step 1: Write failing token-isolation and audit unit-of-work tests**

Add tests proving new access tokens contain `type="access"`, refresh tokens cannot call `get_current_user`, legacy tokens with neither `type` nor `scope` remain temporarily accepted as access tokens, and account-management tokens are rejected by learning/admin dependencies. Assert account-management tokens require `type="account_management"`, `scope="account:self"`, and `auth_time`; assert `add_audit_entry` does not commit. Assert the receipt digest is deterministic, 64 hexadecimal characters, and never contains the raw receipt.

```python
def test_receipt_hash_is_keyed_and_one_way():
    raw = "receipt-secret-value"
    digest = hash_deletion_receipt(raw, "test-pepper")
    assert len(digest) == 64
    assert raw not in digest
    assert digest != hash_deletion_receipt(raw, "different-pepper")
```

- [ ] **Step 2: Run the focused tests and confirm the missing interfaces fail**

Run: `cd backend && pytest tests/test_account_token_types.py -q`

Expected: collection fails for the missing account-management token, receipt hash, dependency, or audit-builder interfaces.

- [ ] **Step 3: Implement typed claims with legacy-access compatibility**

New tokens use the existing `type` claim name:

```python
def create_account_management_token(user_id: uuid.UUID, authenticated_at: datetime) -> str:
    expires = datetime.now(timezone.utc) + timedelta(minutes=10)
    return jwt.encode(
        {
            "sub": str(user_id),
            "type": "account_management",
            "scope": "account:self",
            "auth_time": int(authenticated_at.timestamp()),
            "exp": expires,
        },
        settings.SECRET_KEY,
        algorithm="HS256",
    )
```

`get_current_user` accepts `type="access"` and the legacy shape that has neither `type` nor `scope`; it explicitly rejects `type="refresh"` and `type="account_management"`. `get_account_management_user` accepts only the exact management type/scope and never calls `ensure_account_can_authenticate`.

- [ ] **Step 4: Split audit construction from commit**

`add_audit_entry` builds and adds an `AuditLog` without committing. `log_audit` calls it and then commits, so existing routes retain behavior. New lifecycle services add audit entries inside their own transactions.

- [ ] **Step 5: Run focused, auth, and full backend tests**

Run: `cd backend && pytest tests/test_account_token_types.py tests/test_auth.py tests/test_app_client_login.py tests/test_registration_approval.py -q`

Run: `cd backend && pytest -q`

Expected: all pass; old App access tokens keep working, while refresh and management tokens cannot masquerade as access tokens.

- [ ] **Step 6: Commit the credential boundary**

```bash
git add backend/app/core/security.py backend/app/core/audit.py backend/app/api/deps.py backend/tests/test_account_token_types.py
git commit -m "feat(account): isolate account management credentials"
```

---

### Task 2: Add deletion workflow schema, explicit enablement config, and reversible migration

**Files:**
- Create: `backend/app/models/account_deletion.py`
- Modify: `backend/app/models/__init__.py`
- Modify: `backend/app/core/config.py`
- Modify: `backend/.env.example`
- Modify: `deploy/.env.example`
- Create: `backend/alembic/versions/20260905_0002_account_deletion.py`
- Test: `backend/tests/test_account_deletion_models.py`

**Interfaces:**
- Produces: `DeletionRequestStatus(requested, processing, failed, completed, cancelled)`.
- Produces: `DeletionFileTaskStatus(pending, running, deleted, not_found, retained_shared, failed)`.
- Produces: `AccountDeletionRequest` and `DeletionFileTask` ORM models.
- Produces: `StoredUpload` ownership ledger for new user-scoped files.
- Produces: `account_deletion_configuration() -> AccountDeletionConfiguration`, raising `AccountDeletionConfigurationError` unless every required value is explicit when enablement is true.

- [ ] **Step 1: Write failing model, config, and migration-source tests**

Assert request fields include nullable `subject_user_id` as a plain indexed UUID rather than a user FK, unique indexed `receipt_hash`, persisted `due_at`, snapshotted `receipt_retention_days`, nullable `receipt_expires_at`, processing lease fields, failure code, attempt count, a PII-free `purge_summary`, and timestamps. Assert file tasks have a unique `(deletion_request_id, storage_key)` constraint. Assert migration `down_revision == "20260905_0001"` and contains the PostgreSQL partial unique index:

```sql
CREATE UNIQUE INDEX uq_account_deletion_open_user
ON account_deletion_requests (subject_user_id)
WHERE status IN ('requested', 'processing', 'failed');
```

Configuration tests cover disabled-with-empty-values, enabled-with-complete-values, and enabled with missing/zero/negative SLA or retention. Required settings are:

```python
ACCOUNT_DELETION_ENABLED: bool = False
ACCOUNT_DELETION_POLICY_VERSION: str | None = None
ACCOUNT_DELETION_SLA_DAYS: int | None = None
ACCOUNT_DELETION_RECEIPT_RETENTION_DAYS: int | None = None
ACCOUNT_DELETION_RECEIPT_PEPPER: str | None = None
ACCOUNT_DELETION_WORKER_LEASE_SECONDS: int = 300
```

- [ ] **Step 2: Run focused tests and confirm schema is absent**

Run: `cd backend && pytest tests/test_account_deletion_models.py -q`

Expected: collection or assertions fail because the models, configuration helper, and migration do not exist.

- [ ] **Step 3: Implement models and constraints**

Use varchar-backed enums. `AccountDeletionRequest` owns `DeletionFileTask` through `deletion_request_id ON DELETE CASCADE`; neither table depends on a live `users` row. `StoredUpload.user_id` is nullable with `ON DELETE SET NULL`, while its immutable `storage_key` is unique. Do not store phone, name, password hash, receipt plaintext, or token plaintext in workflow rows.

- [ ] **Step 4: Add explicit configuration examples**

Both environment examples keep deletion disabled and list operator-owned values as comments so blank integers cannot break startup:

```dotenv
ACCOUNT_DELETION_ENABLED=false
ACCOUNT_DELETION_WORKER_LEASE_SECONDS=300
# Required and uncommented only when ACCOUNT_DELETION_ENABLED=true:
# ACCOUNT_DELETION_POLICY_VERSION
# ACCOUNT_DELETION_SLA_DAYS
# ACCOUNT_DELETION_RECEIPT_RETENTION_DAYS
# ACCOUNT_DELETION_RECEIPT_PEPPER
```

The helper returns a typed configuration only when enabled and complete. No endpoint derives a fallback SLA.

- [ ] **Step 5: Implement the reversible Alembic migration**

Create the three tables, indexes, unique constraints, and partial open-request index. Downgrade drops only Phase 2 objects in reverse dependency order. Do not amend `20260905_0001` after this dependent revision exists.

- [ ] **Step 6: Run model and full suites**

Run: `cd backend && pytest tests/test_account_deletion_models.py tests/test_account_status.py -q`

Run: `cd backend && pytest -q`

Expected: all pass with deletion disabled by default.

- [ ] **Step 7: Commit schema and configuration**

```bash
git add backend/app/models/account_deletion.py backend/app/models/__init__.py backend/app/core/config.py backend/.env.example deploy/.env.example backend/alembic/versions/20260905_0002_account_deletion.py backend/tests/test_account_deletion_models.py
git commit -m "feat(account): add durable deletion workflow schema"
```

---

### Task 3: Add restricted account session and self-status APIs

**Files:**
- Create: `backend/app/schemas/account.py`
- Create: `backend/app/api/account.py`
- Modify: `backend/app/main.py`
- Test: `backend/tests/test_account_management_session.py`

**Interfaces:**
- Produces: `POST /api/account/session`.
- Produces: `GET /api/account/status`.
- Produces: `AccountSessionRequest(phone, password, turnstile_token)` and `AccountSessionResponse(account_management_token, token_type, expires_in)`.
- Produces: minimal `AccountStatusResponse(account_status, rejection_reason, deletion_request)`.

- [ ] **Step 1: Write failing API tests for credential privacy and token isolation**

Patch Turnstile success for valid cases. Assert unknown phone and wrong password return the same status/body; IP and phone throttles are called; `X-App-Client` never bypasses Turnstile. Parameterize active, pending, rejected, disabled, and deleting users: correct credentials receive only an account-management token, never access/refresh tokens. Assert access, refresh, legacy access, and management tokens are accepted only by their intended dependencies.

- [ ] **Step 2: Run focused tests and confirm endpoints return 404**

Run: `cd backend && pytest tests/test_account_management_session.py -q`

Expected: 404 for `/api/account/session` and `/api/account/status`.

- [ ] **Step 3: Implement the account router**

The session endpoint always performs independent rate limiting and Turnstile verification, queries by phone, verifies bcrypt, and returns the same `401 ACCOUNT_CREDENTIALS_INVALID` response for unknown/wrong credentials. It never reveals status until after authentication and excludes administrator accounts with `403 ACCOUNT_SELF_SERVICE_UNAVAILABLE`.

The status endpoint returns only:

```json
{
  "account_status": "rejected",
  "rejection_reason": "暂不符合内部使用范围",
  "deletion_request": null
}
```

It omits phone, name, school, region, role, learning content, administrator notes, receipt hash, lease data, and internal failure text.

- [ ] **Step 4: Register the router and run security regressions**

Run: `cd backend && pytest tests/test_account_management_session.py tests/test_app_client_login.py tests/test_registration_approval.py -q`

Run: `cd backend && pytest -q`

Expected: all pass; the existing login-only App header behavior is unchanged.

- [ ] **Step 5: Commit account session and status**

```bash
git add backend/app/schemas/account.py backend/app/api/account.py backend/app/main.py backend/tests/test_account_management_session.py
git commit -m "feat(account): add restricted self service session"
```

---

### Task 4: Add idempotent request, cancellation, and receipt-status APIs

**Files:**
- Create: `backend/app/services/account_deletion.py`
- Modify: `backend/app/schemas/account.py`
- Modify: `backend/app/api/account.py`
- Modify: `backend/app/services/account_lifecycle.py`
- Test: `backend/tests/test_account_deletion_requests.py`

**Interfaces:**
- Produces: `create_or_get_deletion_request(db, user, command, now) -> CreateDeletionResult`.
- Produces: `cancel_deletion_request(db, user, now) -> CancellationResult`.
- Produces: `get_receipt_status(db, raw_receipt, now) -> ReceiptStatusResponse`.
- Produces: `POST /api/account/deletion-requests`, `POST /api/account/deletion-requests/cancel`, and `POST /api/account/deletion-receipt/status`.

- [ ] **Step 1: Write failing lifecycle tests**

Cover the exact request contract:

```json
{
  "confirmation": "DELETE_ACCOUNT",
  "policy_version": "2026-09-05",
  "reason": "不再使用"
}
```

Assert disabled configuration returns `503 ACCOUNT_DELETION_NOT_ENABLED`; wrong confirmation/policy fails; the first creation returns `201` with one plaintext receipt; a retry returns the existing request with `idempotent=true` and no receipt; and two concurrent creations leave one unfinished row. Assert `due_at` and `receipt_retention_days` are snapshotted at creation, while `receipt_expires_at` remains null until completion or cancellation.

Cancellation accepts only `requested -> cancelled`, is idempotent after cancellation, and returns 409 for processing/failed/completed. A cancellation-versus-processing race must leave one coherent state. Pending/rejected/disabled users can create and cancel through the restricted session.

Receipt queries use a request body, return only status/timestamps/failure category, work after the user row is absent, and make malformed, unknown, and expired receipts indistinguishable. Completion sets `receipt_expires_at = completed_at + receipt_retention_days`; cancellation applies the same rule from `cancelled_at`. Assert logs/audits contain no raw receipt.

- [ ] **Step 2: Run focused tests and confirm service/routes are absent**

Run: `cd backend && pytest tests/test_account_deletion_requests.py -q`

Expected: import or 404 failures.

- [ ] **Step 3: Implement locked, idempotent request creation**

Lock the user row, validate explicit configuration/policy, find an unfinished request, and create only when none exists. Generate `secrets.token_urlsafe(32)`, store the HMAC digest, and return plaintext through the service result object only. Catch partial-index `IntegrityError`, roll back, reload, and return the winning request without a receipt.

- [ ] **Step 4: Implement cancellation and receipt lookup**

Lock the request for cancellation. Never transition a processing or failed request back to an account-active state. Receipt lookup computes the HMAC and performs one indexed digest query; expired/unknown/malformed values share `404 DELETION_RECEIPT_NOT_FOUND`.

Extend lifecycle edges so `pending_approval`, `rejected`, `active`, and `disabled` may enter `deleting` only when the deletion service begins processing; `deleting` remains terminal and no registration/legacy endpoint gains that transition.

- [ ] **Step 5: Run focused, lifecycle, and full tests**

Run: `cd backend && pytest tests/test_account_deletion_requests.py tests/test_account_lifecycle.py tests/test_account_management_session.py -q`

Run: `cd backend && pytest -q`

Expected: all pass.

- [ ] **Step 6: Commit request and receipt flow**

```bash
git add backend/app/services/account_deletion.py backend/app/schemas/account.py backend/app/api/account.py backend/app/services/account_lifecycle.py backend/tests/test_account_deletion_requests.py
git commit -m "feat(account): add deletion requests and receipts"
```

---

### Task 5: Establish upload ownership and persistent safe file tasks

**Files:**
- Modify: `backend/app/services/storage.py`
- Modify: `backend/app/api/upload.py`
- Modify: `backend/app/api/image_studio.py`
- Modify: `backend/app/api/content.py`
- Modify: `backend/scripts/cleanup_uploads.py`
- Modify: `frontend/web/nginx.conf`
- Modify: `deploy/cloudflare-setup.md`
- Modify: `backend/app/services/account_deletion.py`
- Test: `backend/tests/test_account_deletion_files.py`

**Interfaces:**
- Produces: `store_upload(db, data, filename, content_type, *, owner_user_id, purpose) -> StoredUpload`.
- Produces: `normalize_owned_storage_key(url_or_key: str, upload_root: Path) -> str`.
- Produces: `build_deletion_file_tasks(db, request, user_id) -> list[DeletionFileTask]`.
- Produces: `execute_file_task(task_id) -> DeletionFileTaskStatus`.

- [ ] **Step 1: Write failing storage and path-safety tests**

Assert user files use `users/<user UUID>/<random UUID>.<safe extension>`, administrator/global content has no user owner, and ledger creation accompanies successful storage. Reject traversal, absolute paths, encoded traversal, symlinks escaping `UPLOAD_DIR`, external URLs, unknown extensions, and legacy names not matching the generated-name format.

Build tasks from the target's `StoredUpload`, own `SessionMessage.images`, and `StudioImage.url`; never delete `StudioImage.source_url`. If another surviving row references the same legacy file, mark `retained_shared`. Missing files become `not_found`; I/O failure becomes `failed`; retries never create a second task or delete twice.

- [ ] **Step 2: Run focused tests and confirm ownership interfaces are absent**

Run: `cd backend && pytest tests/test_account_deletion_files.py -q`

Expected: imports fail or stored uploads lack ownership rows.

- [ ] **Step 3: Implement user-scoped storage and ledger writes**

Normalize the extension from an allowlist, create only the one user directory needed, write a random object, add the ledger record, and unlink that just-created object if its database transaction fails. Migrate generic authenticated upload and generated image results to this interface; administrator content remains explicitly global.

- [ ] **Step 4: Implement conservative legacy discovery and task execution**

Accept legacy local URLs only when they match `/uploads/<32 lowercase hex>.<allowed extension>`, are referenced by the target's rows, resolve inside the upload root, and have no surviving reference. Store normalized relative keys before deleting any referencing database row. Use one-file `unlink`; never use a recursive operation or unresolved glob.

- [ ] **Step 5: Prevent caching for new user-scoped files**

Configure `/uploads/users/` with `Cache-Control: private, no-store` ahead of the general uploads location and document the matching Cloudflare cache-bypass rule. Keep account deletion disabled until production confirms the edge rule and clears previously cached user objects.

- [ ] **Step 6: Update orphan cleanup and run focused/full tests**

The cleanup script recursively considers ledger-backed user paths but never deletes a live ledger object or follows symlinks. Run:

`cd backend && pytest tests/test_account_deletion_files.py -q`

`cd backend && pytest -q`

Expected: all pass; unrelated/global/shared files remain.

- [ ] **Step 7: Commit upload ownership and file tasks**

```bash
git add backend/app/services/storage.py backend/app/api/upload.py backend/app/api/image_studio.py backend/app/api/content.py backend/scripts/cleanup_uploads.py frontend/web/nginx.conf deploy/cloudflare-setup.md backend/app/services/account_deletion.py backend/tests/test_account_deletion_files.py
git commit -m "feat(account): track and safely purge user uploads"
```

---

### Task 6: Implement the explicit, re-entrant deletion executor

**Files:**
- Create: `backend/app/services/account_deletion_manifest.py`
- Modify: `backend/app/services/account_deletion.py`
- Modify: `backend/app/core/rate_limit.py`
- Modify: `backend/app/core/sms.py`
- Modify: `backend/app/api/tutoring.py`
- Modify: `backend/app/api/image_studio.py`
- Modify: `backend/app/services/engagement.py`
- Test: `backend/tests/test_account_deletion_executor.py`

**Interfaces:**
- Produces: `claim_next_deletion_request(db, worker_id, now) -> AccountDeletionRequest | None` using `FOR UPDATE SKIP LOCKED` and a 300-second configurable lease.
- Produces: `execute_deletion_request(request_id, worker_id, now) -> ExecutionResult`.
- Produces: `purge_user_database_data(db, request, user) -> PurgeSummary`.
- Produces: `clear_user_redis_state(user_id, phone) -> None` with exact prefixes only.
- Produces: `ensure_user_not_deleting_before_commit(db, user_id) -> None` for long-running/secondary-session writers.

- [ ] **Step 1: Write a failing full-graph executor test**

Create two synthetic users plus shared dictionary/question/article/knowledge rows. Give the target rows in every direct table and every indirect child table, audit entries with target/user PII, LLM/payment rows, tutoring/composition/study children, push data, Redis keys, owned files, one missing file, and one unrelated/shared file.

Assert successful execution deletes only the target's user-owned rows, detailed audit/LLM/payment records and identity; leaves the other user and all shared corpus rows/files intact; clears exact Redis user/phone keys; preserves the request and file-task receipt records; and marks completed only after terminal-success file states.

- [ ] **Step 2: Write failing crash, retry, lease, and concurrent-write tests**

Assert two workers cannot claim the same request, an unexpired lease cannot be stolen, an expired processing lease is reclaimable, repeated execution is safe, file failure sets `failed` and leaves the user `deleting`, and retry resumes only failed/pending work. Force a database purge exception and assert the entire database deletion transaction rolls back and completion is not recorded.

Simulate a tutoring end-of-stream, image-studio secondary session, and weekly-report write after processing starts; each must re-read account status immediately before committing and refuse a deleting/missing user. A write that wins before deletion may cause the purge transaction to retry, but no write may commit after user deletion or recreate identity-linked data.

- [ ] **Step 3: Run focused tests and confirm the executor is absent**

Run: `cd backend && pytest tests/test_account_deletion_executor.py -q`

Expected: import failures or unhandled foreign-key/file cases.

- [ ] **Step 4: Implement the explicit deletion manifest**

The manifest contains concrete SQLAlchemy delete/update statements in dependency order:

1. `guide_messages`, `session_messages`, `study_task_progress`, `wrong_questions`.
2. `composition_guides`, `composition_records`, `tutoring_sessions`, `study_plans`, `exam_records`.
3. `vocab_result_logs`, `user_word_progress`, `vocab_quiz_records`, `vocab_entries`.
4. `practice_records`, `weakness_records`, `daily_checkins`, `weekly_reports`, `push_subscriptions`, `studio_images`.
5. User-linked `payment_records`, `llm_usage_logs`, and detailed `audit_logs` where the target is actor, target, or exact PII appears in structured detail.
6. `stored_uploads` after their file tasks are terminal-success.
7. `users` last; clear request reason and `subject_user_id`, then update the non-FK deletion request to `completed` with timestamp, computed receipt expiry, and aggregate counts in the same transaction.

Do not reflect over every database table and do not rely on ORM cascade. Each statement records its affected count for postcondition verification.

- [ ] **Step 5: Implement claim, processing, and retry semantics**

Queue claim locks one eligible row (`requested`/`failed` explicitly scheduled, or expired `processing`) with `SKIP LOCKED`, sets lease/worker/attempt, and atomically transitions the live user to `deleting`. Processing creates/reuses file tasks, completes all file work, clears Redis, then runs the final purge. Any exception stores a stable public failure category plus separately sanitized internal logging; it never reactivates the user or says completed.

- [ ] **Step 6: Fence late writers**

Call `ensure_user_not_deleting_before_commit` from tutoring stream completion/regeneration, image-studio record persistence, weekly report generation, and any other secondary-session path found by `rg "async_session|StreamingResponse|yield" backend/app backend/scripts`. Cron selection and per-user processing both require `AccountStatus.active`, not only `is_active`.

- [ ] **Step 7: Run executor and full regression suites**

Run: `cd backend && pytest tests/test_account_deletion_executor.py tests/test_account_lifecycle.py tests/test_engagement.py -q`

Run: `cd backend && pytest -q`

Expected: all pass; failure cases never return completed.

- [ ] **Step 8: Commit the executor**

```bash
git add backend/app/services/account_deletion_manifest.py backend/app/services/account_deletion.py backend/app/core/rate_limit.py backend/app/core/sms.py backend/app/api/tutoring.py backend/app/api/image_studio.py backend/app/services/engagement.py backend/tests/test_account_deletion_executor.py
git commit -m "feat(account): add reentrant deletion executor"
```

---

### Task 7: Add administrator scheduling APIs and a durable worker entry point

**Files:**
- Modify: `backend/app/schemas/admin.py`
- Modify: `backend/app/api/admin.py`
- Create: `backend/scripts/process_account_deletions.py`
- Create: `backend/scripts/purge_expired_deletion_receipts.py`
- Modify: `backend/scripts/send_daily_reminders.py`
- Modify: `backend/scripts/generate_weekly_reports.py`
- Modify: `backend/scripts/archive_old_sessions.py`
- Test: `backend/tests/test_admin_account_deletions.py`
- Test: `backend/tests/test_account_deletion_worker.py`

**Interfaces:**
- Produces: `GET /api/admin/deletion-requests?status=&overdue=&page=&per_page=`.
- Produces: `POST /api/admin/deletion-requests/{request_id}/process`.
- Produces: `POST /api/admin/deletion-requests/{request_id}/retry`.
- Produces: `python scripts/process_account_deletions.py --limit N --worker-id ID`.
- Produces: `python scripts/purge_expired_deletion_receipts.py --limit N --dry-run`.

- [ ] **Step 1: Write failing admin authorization, scheduling, and privacy tests**

Assert only active administrators can list/queue/retry. The list exposes status, stored deadline/overdue flag, request timestamp, safe failure category, attempts, and target impact summary while the user exists; it never returns password hash, receipt hash/plaintext, token, IP, user agent, worker lease token, internal exception, or App key.

Process accepts requested and returns `202 {status:"queued"}`; retry accepts failed only; repeat calls are idempotent and create one schedule audit. There is no reject/deny deletion endpoint. Legacy direct/batch hard-delete remains 409.

- [ ] **Step 2: Write failing worker claim tests**

Create multiple queued and unscheduled requests. Assert `--limit 2` claims at most two queued/expired rows, independent workers do not duplicate claims, one request failure does not stop the rest, exit code is non-zero when any claimed request fails, and output contains request UUIDs/failure categories but no phone/name/receipt/token. Assert the purge command removes only completed/cancelled requests whose stored `receipt_expires_at` has passed, cascades their file-task history, and leaves active/failed/unexpired requests intact; dry-run deletes nothing.

- [ ] **Step 3: Run focused tests and confirm APIs/script are absent**

Run: `cd backend && pytest tests/test_admin_account_deletions.py tests/test_account_deletion_worker.py -q`

Expected: 404/import failures.

- [ ] **Step 4: Implement admin list and queue/retry routes**

Queueing sets `execution_requested_at` and an audit entry in one transaction; it does not call the executor in the web process and never responds “deleted.” Overdue uses persisted `due_at < now` and excludes completed/cancelled. `process` never accepts failed; `retry` never accepts requested/processing/completed/cancelled.

- [ ] **Step 5: Implement the bounded worker script and cron gates**

The worker loops up to `--limit`, uses a stable explicit `--worker-id`, and calls the claim/executor service. The receipt purge is separately bounded and never removes unfinished workflows. Reminder/report/archive scripts recheck `AccountStatus.active` per target so they cannot write or push after processing begins.

- [ ] **Step 6: Run focused and full suites**

Run: `cd backend && pytest tests/test_admin_account_deletions.py tests/test_account_deletion_worker.py tests/test_admin_registration_decisions.py -q`

Run: `cd backend && pytest -q`

Expected: all pass.

- [ ] **Step 7: Commit administrator scheduling and worker**

```bash
git add backend/app/schemas/admin.py backend/app/api/admin.py backend/scripts/process_account_deletions.py backend/scripts/purge_expired_deletion_receipts.py backend/scripts/send_daily_reminders.py backend/scripts/generate_weekly_reports.py backend/scripts/archive_old_sessions.py backend/tests/test_admin_account_deletions.py backend/tests/test_account_deletion_worker.py
git commit -m "feat(admin): schedule account deletion work"
```

---

### Task 8: Prove PostgreSQL behavior and document the production enablement gate

**Files:**
- Create: `backend/tests/postgres/test_account_deletion_postgres.py`
- Create: `deploy/account-deletion-runbook.md`
- Modify: `docs/usage-guide.md`

**Interfaces:**
- Produces: a PostgreSQL-only test lane for partial indexes, row locks, `SKIP LOCKED`, cancellation/processing races, and full-graph deletion.
- Produces: an operator runbook that keeps the feature disabled until every named gate has evidence.

- [ ] **Step 1: Write PostgreSQL integration tests**

Against a disposable PostgreSQL 16 database, verify:

- `alembic upgrade head` from a minimal pre-Phase-1 users table; active/disabled backfill remains correct.
- Migration `0002` creates the partial unique index and all workflow constraints.
- Two simultaneous creates produce one unfinished request.
- Cancellation versus processing produces one coherent winner.
- Two workers claim a request once with `SKIP LOCKED`.
- Full-graph deletion removes the target only, receipt lookup survives user deletion, and downgrade removes only Phase 2 objects.

- [ ] **Step 2: Run the disposable PostgreSQL lane and full suite**

Run the PostgreSQL test in a new named Docker network/container with synthetic data only. Set every account-deletion setting explicitly in that container; never reuse the production hostname or database URL.

Run: `cd backend && pytest -q`

Expected: PostgreSQL lane and all backend tests exit 0.

- [ ] **Step 3: Write the enablement runbook**

The runbook requires recorded confirmation for: SLA days; receipt retention; payment/security-log/backup/provider handling; worker cron and alert owner; failed/overdue dashboard owner; `/uploads/users/` origin and Cloudflare no-cache behavior; legacy cached-object purge; synthetic full-graph dry run; rollback; reviewer account exclusion; and user completion-confirmation copy.

The production sequence is fixed:

1. Backup and verify restore in non-production.
2. Deploy code with `ACCOUNT_DELETION_ENABLED=false`.
3. Run `alembic upgrade head` and schema/preflight checks.
4. Configure worker and monitoring without claiming real requests.
5. Confirm retention/cache/provider settings and populate all explicit values.
6. Enable in a non-production environment and complete synthetic end-to-end deletion.
7. Enable production, then update iOS/admin UI release materials.

- [ ] **Step 4: Self-review the plan gate against the approved design**

Verify every design requirement for restricted sessions, deletion receipt, requested/processing/failed/cancelled/completed states, no denial action, explicit data list, persistent file tasks, retries, PII minimization, and no production action has a corresponding test or runbook gate. Record any operationally unconfirmed item as a release blocker, not a runtime default.

- [ ] **Step 5: Commit verification and runbook**

```bash
git add backend/tests/postgres/test_account_deletion_postgres.py deploy/account-deletion-runbook.md docs/usage-guide.md
git commit -m "test(account): verify deletion workflow on postgres"
```

---

## Phase 2 completion gate

Phase 2 is complete only with fresh evidence that:

- Every backend test and PostgreSQL-specific lifecycle test exits 0.
- Access, refresh, management, and receipt credentials cannot substitute for one another.
- Unknown accounts and wrong passwords have indistinguishable account-session responses.
- All eligible account states can request deletion without receiving learning/admin access.
- Request creation, cancellation, scheduling, worker claim, retry, and receipt lookup are idempotent under concurrency.
- File failure or database failure never reports completed and never reactivates a deleting account.
- A synthetic user populated across every known relationship is deleted while another user and all shared content remain intact.
- User identity, learning rows, detailed audit/LLM/payment rows, push endpoints, Redis state, and verified owned files are removed; the minimal receipt remains usable until its stored expiry.
- Long-running/secondary-session writers and cron scripts cannot recreate target data after processing starts.
- No password, SMS code, App key, JWT, receipt, raw internal exception, or deleted-user PII appears in response/audit/log assertions.
- Migration upgrade/downgrade and partial-index/row-lock behavior are proven on disposable PostgreSQL 16.
- Production deletion remains disabled until every runbook retention, backup, worker, CDN/cache, provider, and support-owner gate is confirmed.

After this gate, execute separate plans for the administrator web UI, iOS registration/account-management UI, and final privacy/App Store release updates.
