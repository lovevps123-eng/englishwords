# Account Lifecycle Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, backward-compatible account status model and make every self-registration await an administrator decision.

**Architecture:** The existing `senior-platform` remains the identity system. A single account-state service owns transitions and keeps legacy `is_active` synchronized; auth and admin APIs call that service rather than inferring state from login timestamps. This phase does not implement account deletion or expose iOS registration yet.

**Tech Stack:** FastAPI, SQLAlchemy async ORM, PostgreSQL-compatible Alembic migration, Pydantic, pytest/httpx.

**Spec:** `docs/superpowers/specs/2026-09-05-account-lifecycle-design.md`

## Global Constraints

- Existing active users and the App Review account remain active; existing inactive users migrate to `disabled` and are never auto-enabled.
- All web and future iOS self-registration ends in `pending_approval`, regardless of SMS configuration.
- SMS verification and admin approval are independent; a verified phone does not grant learning access.
- Admin-created accounts may start `active`.
- `pending_approval`, `rejected`, `disabled`, and `deleting` never receive access or refresh tokens.
- Do not change production state, deploy, or test deletion against a real user in this phase.
- Do not log plaintext passwords, SMS codes, tokens, or the configured App client key.

---

### Task 1: Persist an explicit account status

**Files:**
- Modify: `../senior-platform/backend/app/models/user.py`
- Create: `../senior-platform/backend/alembic/versions/20260905_0001_account_status.py`
- Modify: `../senior-platform/backend/app/schemas/auth.py`
- Test: `../senior-platform/backend/tests/test_account_status.py`

**Interfaces:**
- Produces: `AccountStatus(str, enum.Enum)` with `pending_approval`, `active`, `rejected`, `disabled`, `deleting`.
- Produces: `User.account_status: AccountStatus`; keeps `User.is_active` during compatibility migration.
- Produces: `UserResponse.account_status: str` while retaining `is_active: bool` for old clients.

- [x] **Step 1: Write the failing model and schema tests**

Create tests that instantiate an active user fixture and assert `account_status == AccountStatus.active`, serialize `UserResponse`, and inspect the new column. Include a migration-source test asserting the upgrade SQL/backfill maps `is_active = true` to `active` and every false value to `disabled`.

```python
def test_existing_inactive_users_are_not_classified_as_pending(migration_source):
    assert "WHEN is_active THEN 'active'" in migration_source
    assert "ELSE 'disabled'" in migration_source
```

- [x] **Step 2: Run the focused test and confirm the expected failure**

Run: `cd ../senior-platform/backend && pytest tests/test_account_status.py -q`

Expected: collection/import failure because `AccountStatus` and the migration do not exist.

- [x] **Step 3: Add the enum, ORM column, schema field, and reversible migration**

Define the enum next to `UserRole`. Add a non-null indexed status column with an ORM default of `AccountStatus.active` so administrator-created and legacy test users retain current semantics. The migration must:

```sql
ALTER TABLE users ADD COLUMN account_status VARCHAR(32);
UPDATE users SET account_status = CASE WHEN is_active THEN 'active' ELSE 'disabled' END;
ALTER TABLE users ALTER COLUMN account_status SET NOT NULL;
CREATE INDEX ix_users_account_status ON users (account_status);
```

Use Alembic operations that work with the configured PostgreSQL database and provide a downgrade that drops only this index and column. Do not infer `pending_approval` from `last_login_at`.

- [x] **Step 4: Run model and full backend tests**

Run: `cd ../senior-platform/backend && pytest tests/test_account_status.py -q`

Expected: all focused tests pass.

Run: `cd ../senior-platform/backend && pytest -q`

Expected: all existing tests pass; if fixtures expose missing explicit defaults, fix fixture construction without weakening production constraints.

- [x] **Step 5: Commit the isolated model change in senior-platform**

```bash
git -C ../senior-platform add backend/app/models/user.py backend/app/schemas/auth.py backend/alembic/versions/20260905_0001_account_status.py backend/tests/test_account_status.py
git -C ../senior-platform commit -m "feat(auth): add explicit account status"
```

---

### Task 2: Centralize allowed account transitions

**Files:**
- Create: `../senior-platform/backend/app/services/account_lifecycle.py`
- Test: `../senior-platform/backend/tests/test_account_lifecycle.py`

**Interfaces:**
- Consumes: `User`, `AccountStatus` from Task 1.
- Produces: `transition_account(user: User, target: AccountStatus) -> None`.
- Produces: `account_can_authenticate(user: User) -> bool`.
- Produces: `AccountTransitionError(ValueError)` for forbidden edges.

- [x] **Step 1: Write the failing transition matrix tests**

Use a parameterized test for these allowed edges: pending→active, pending→rejected, rejected→pending, active→disabled, disabled→active, and active→deleting. Assert pending→disabled, rejected→active, deleting→active, and deleting→disabled raise `AccountTransitionError`. Assert every transition synchronizes `is_active` to true only for `active`.

```python
@pytest.mark.parametrize("status, expected", [
    (AccountStatus.active, True),
    (AccountStatus.pending_approval, False),
    (AccountStatus.rejected, False),
    (AccountStatus.disabled, False),
    (AccountStatus.deleting, False),
])
def test_authentication_gate(status, expected, user):
    user.account_status = status
    assert account_can_authenticate(user) is expected
```

- [x] **Step 2: Run the focused test and confirm it fails**

Run: `cd ../senior-platform/backend && pytest tests/test_account_lifecycle.py -q`

Expected: import failure for the missing service.

- [x] **Step 3: Implement the explicit transition table**

The service contains one immutable transition mapping and no database commit:

```python
ALLOWED_TRANSITIONS = {
    AccountStatus.pending_approval: {AccountStatus.active, AccountStatus.rejected},
    AccountStatus.rejected: {AccountStatus.pending_approval},
    AccountStatus.active: {AccountStatus.disabled, AccountStatus.deleting},
    AccountStatus.disabled: {AccountStatus.active, AccountStatus.deleting},
    AccountStatus.deleting: set(),
}
```

Callers own their transaction and audit entry. Assign `user.is_active = target is AccountStatus.active` inside the service. Reject no-op transitions so retries do not create false audit events; API callers may return an idempotent response before calling it.

- [x] **Step 4: Run focused and backend tests**

Run: `cd ../senior-platform/backend && pytest tests/test_account_lifecycle.py tests/test_account_status.py -q`

Expected: all focused tests pass.

Run: `cd ../senior-platform/backend && pytest -q`

Expected: all backend tests pass.

- [x] **Step 5: Commit the lifecycle service**

```bash
git -C ../senior-platform add backend/app/services/account_lifecycle.py backend/tests/test_account_lifecycle.py
git -C ../senior-platform commit -m "feat(auth): centralize account state transitions"
```

---

### Task 3: Make self-registration always await approval

**Files:**
- Modify: `../senior-platform/backend/app/api/auth.py`
- Modify: `../senior-platform/backend/app/api/deps.py`
- Modify: `../senior-platform/backend/app/schemas/auth.py`
- Test: `../senior-platform/backend/tests/test_registration_approval.py`
- Modify: `../senior-platform/backend/tests/test_app_client_login.py`

**Interfaces:**
- Consumes: `AccountStatus` and `account_can_authenticate` from Tasks 1–2.
- Produces: `RegisterResponse(message: str, status: Literal['pending_approval'])`.
- Preserves: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/refresh` paths.

- [x] **Step 1: Write failing API tests for both SMS modes and every auth gate**

Patch Turnstile success in test only. Parameterize `SMS_ENABLED` true/false; when true, patch valid SMS verification. Assert both successful registrations return 201 with exactly `status: pending_approval`, store a password hash and inactive compatibility flag, and issue no tokens. Assert login, bearer auth, and refresh reject pending/rejected/disabled/deleting with stable machine codes.

```python
assert response.status_code == 201
assert response.json()["status"] == "pending_approval"
assert "access_token" not in response.json()
```

Retain the security regression asserting `X-App-Client` bypass applies to login only, never registration.

- [x] **Step 2: Run focused tests and confirm behavior is currently wrong**

Run: `cd ../senior-platform/backend && pytest tests/test_registration_approval.py tests/test_app_client_login.py -q`

Expected: registration tests fail because SMS-enabled registration auto-activates and responses lack the explicit status.

- [x] **Step 3: Implement uniform pending registration and status-aware authentication**

Set every self-registered `User` to `account_status=AccountStatus.pending_approval` and `is_active=False`; preserve Turnstile, phone, cooldown, SMS, password, region, and duplicate checks. Type the response with `RegisterResponse`.

Replace timestamp-based status inference in login and `get_current_user` with explicit status mapping. Refresh must call the same authentication predicate before minting tokens. Return public error bodies with `detail` and `code`, e.g. `ACCOUNT_PENDING_APPROVAL`, `ACCOUNT_REJECTED`, `ACCOUNT_DISABLED`, `ACCOUNT_DELETING`; do not expose administrator notes.

- [x] **Step 4: Run security, auth, and full backend suites**

Run: `cd ../senior-platform/backend && pytest tests/test_registration_approval.py tests/test_app_client_login.py tests/test_auth.py -q`

Expected: all focused tests pass.

Run: `cd ../senior-platform/backend && pytest -q`

Expected: all backend tests pass.

- [x] **Step 5: Commit the registration behavior**

```bash
git -C ../senior-platform add backend/app/api/auth.py backend/app/api/deps.py backend/app/schemas/auth.py backend/tests/test_registration_approval.py backend/tests/test_app_client_login.py
git -C ../senior-platform commit -m "feat(auth): require approval for self registration"
```

---

### Task 4: Add administrator registration decisions without reviving deletion paths

**Files:**
- Modify: `../senior-platform/backend/app/schemas/admin.py`
- Modify: `../senior-platform/backend/app/api/admin.py`
- Test: `../senior-platform/backend/tests/test_admin_registration_decisions.py`

**Interfaces:**
- Consumes: `transition_account` from Task 2.
- Produces: `RegistrationDecisionRequest(decision: Literal['approve', 'reject', 'return_to_pending'], user_reason: str | None)`.
- Produces: `POST /api/admin/users/{user_id}/registration-decision`.
- Extends: admin list response and filter with `account_status`.

- [x] **Step 1: Write failing authorization, transition, and privacy tests**

Assert only admins can decide. Approval accepts pending only; rejection requires a trimmed user-visible reason of 1–200 characters; returning to pending accepts rejected only. Repeat of the same decision is idempotent and creates no second audit entry. Assert deleting accounts cannot be enabled through patch or batch action. Assert audit detail never contains password, SMS code, token, or configured App key.

- [x] **Step 2: Run focused tests and confirm endpoints are absent**

Run: `cd ../senior-platform/backend && pytest tests/test_admin_registration_decisions.py -q`

Expected: 404 or schema import failure.

- [x] **Step 3: Implement decisions and route legacy enable/disable through the service**

Add the typed request and endpoint. Use `transition_account`; persist the state transition and audit entry in one transaction, recording administrator ID, target user ID, from/to states, and safe reason. Extend listing and filters with the explicit state.

Change legacy single and batch enable/disable calls to valid transitions; never allow a request to alter `deleting`. Remove batch hard-delete and direct hard-delete behavior for non-test environments in this phase: return `409 ACCOUNT_DELETION_WORKFLOW_REQUIRED`. The later deletion executor will replace it. Administrator accounts remain non-deletable.

- [x] **Step 4: Run focused and full suites**

Run: `cd ../senior-platform/backend && pytest tests/test_admin_registration_decisions.py tests/test_registration_approval.py -q`

Expected: all focused tests pass.

Run: `cd ../senior-platform/backend && pytest -q`

Expected: all backend tests pass.

- [x] **Step 5: Run migration smoke against an isolated PostgreSQL database**

Run an ephemeral test database using the project's existing deployment tooling. Apply `alembic upgrade head`, query the active/inactive backfill counts, then run `alembic downgrade base` only against that disposable database. Expected: no null statuses, active counts match pre-migration `is_active=true`, disabled counts match false, and downgrade removes only the new column/index. Never point this command at production.

- [x] **Step 6: Commit the admin API change**

```bash
git -C ../senior-platform add backend/app/api/admin.py backend/app/schemas/admin.py backend/tests/test_admin_registration_decisions.py
git -C ../senior-platform commit -m "feat(admin): manage registration decisions"
```

---

## Phase 1 completion gate

Phase 1 is complete only after fresh evidence shows:

- Full backend suite exits 0.
- A disposable PostgreSQL migration round trip exits 0 with verified backfill counts.
- Existing active login and App-client login regressions pass.
- SMS on and off both produce pending self-registration.
- Pending, rejected, disabled, and deleting accounts cannot obtain or refresh access.
- Admin decisions are authorized, state-valid, idempotent, and audited without secrets.
- No production database, deployment, iOS source, or App Store record changed.

After this gate, write and execute separate plans for: deletion request/executor; iOS registration and account-management UI; admin web operations and final privacy/release updates.

## Completion evidence

- Backend branch: `codex/account-lifecycle-phase-1` at `e96f4e2`.
- Final isolated Docker test run: `132 passed`.
- Disposable PostgreSQL 16 migration round trip: upgrade/backfill/index/column checks passed; downgrade preserved existing rows and removed only the new schema objects.
- Disposable PostgreSQL 16 concurrency smoke: two simultaneous approvals produced one transition, one idempotent response, and one audit entry.
- Production database, deployed backend, iOS source, and App Store Connect records were not changed during this phase.
