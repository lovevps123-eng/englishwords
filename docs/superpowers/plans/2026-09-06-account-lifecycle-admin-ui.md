# Account Lifecycle Administrator UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing senior-platform administrator UI correctly approve or reject registrations and safely schedule or retry account deletion workflows.

**Architecture:** Extend the existing FastAPI administrator list contract only where the UI needs stable target and queue information, then consume it through the current Axios layer and React/Tailwind pages. Keep registration decisions in the existing Users page and give deletion workflows a separate administrator route so the two operations cannot be confused.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy async, pytest, React 18, TypeScript 5.6, Axios, Vite, Vitest, Testing Library.

**Spec:** `docs/superpowers/specs/2026-09-05-account-lifecycle-design.md`

## Global Constraints

- Work in `/Users/masf/develop/project/senior-platform`; never connect tests to production services or production databases.
- Registration actions are exactly `approve`, `reject`, and `return_to_pending`; rejection requires a trimmed user-visible reason of at most 200 characters.
- Account deletion has no approve/reject action. Administrators may queue `requested` work and retry `failed` work only.
- Remove direct single-user and batch hard-delete controls from the UI; deletion must use the durable workflow.
- A `202` scheduling response means queued, never completed.
- Do not expose receipts, leases, passwords, tokens, internal exception text, or deleted-user identity.
- Keep `ACCOUNT_DELETION_ENABLED=false` in checked-in examples and do not deploy during this plan.
- Preserve the existing untracked `.claude/` and `backend/.superpowers/sdd/final-cleanup-report.md` files.

---

### Task 1: Complete the administrator deletion-list contract

**Files:**
- Modify: `backend/app/schemas/admin.py`
- Modify: `backend/app/api/admin.py`
- Test: `backend/tests/test_admin_account_deletions.py`

**Interfaces:**
- Consumes: `AccountDeletionRequest.execution_requested_at`, nullable `subject_user_id`, joined `User`, and existing administrator authentication.
- Produces: `DeletionRequestAdminResponse.subject`, `queued_at`, stable `(requested_at, id)` pagination, and timezone-aware response timestamps.

- [ ] **Step 1: Write failing response-contract tests**

Add focused tests proving that a live subject is returned only to an authenticated administrator, a completed request has `subject: null`, queued work exposes `queued_at`, equal timestamps sort by descending request ID, and every serialized timestamp has a UTC offset. Assert the response never contains `receipt`, lease fields, password data, or internal failure text.

```python
assert item["subject"] == {
    "user_id": str(user.id),
    "phone": user.phone,
    "name": user.name,
}
assert item["queued_at"].endswith(("Z", "+00:00"))
assert "receipt" not in item
```

- [ ] **Step 2: Run the focused tests and confirm the contract is missing**

Run: `docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest tests/test_admin_account_deletions.py -q`

Expected: FAIL because `subject`, `queued_at`, stable ID ordering, and explicit UTC serialization are absent.

- [ ] **Step 3: Implement the minimal typed response**

Add a nullable administrator-only identity summary and queue timestamp:

```python
class DeletionSubjectSummary(BaseModel):
    user_id: uuid.UUID
    phone: str
    name: str

class DeletionRequestAdminResponse(BaseModel):
    # existing fields stay unchanged
    queued_at: datetime | None = None
    subject: DeletionSubjectSummary | None = None
```

Build `subject` from the joined live `User`, set `queued_at` from `execution_requested_at`, normalize datetimes with the existing `_as_utc`, and order by `requested_at.desc(), id.desc()`. Do not retain identity in terminal receipts or add identity columns to the deletion table.

- [ ] **Step 4: Run focused and full backend verification**

Run:

```bash
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest tests/test_admin_account_deletions.py -q
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest -q
git diff --check
```

Expected: focused and full suites exit 0; only the documented strict SQLite concurrency xfail and PostgreSQL-only skips remain.

- [ ] **Step 5: Commit the administrator contract**

```bash
git add backend/app/schemas/admin.py backend/app/api/admin.py backend/tests/test_admin_account_deletions.py
git commit -m "feat(admin): expose safe deletion queue context"
```

---

### Task 2: Add typed web API calls and a focused test harness

**Files:**
- Modify: `frontend/web/src/api/admin.ts`
- Create: `frontend/web/src/api/errors.ts`
- Modify: `frontend/web/package.json`
- Modify: `frontend/web/package-lock.json`
- Modify: `frontend/web/vite.config.ts`
- Create: `frontend/web/src/test/setup.ts`
- Create: `frontend/web/src/api/admin.test.ts`

**Interfaces:**
- Consumes: Task 1 response contract and existing `client` Axios instance.
- Produces: typed account-status, registration-decision, deletion-list/process/retry calls and `apiErrorMessage(error, fallback)`.

- [ ] **Step 1: Add the smallest frontend test dependencies**

Install development-only `vitest`, `jsdom`, `@testing-library/react`, and `@testing-library/jest-dom`, add `"test": "vitest run"`, and configure `test.environment = "jsdom"` plus `setupFiles = ["./src/test/setup.ts"]`. Do not add a new state library or component framework.

- [ ] **Step 2: Write failing API contract tests**

Mock the existing Axios client and assert exact calls:

```ts
expect(client.post).toHaveBeenCalledWith(
  `/admin/users/${userId}/registration-decision`,
  { decision: "reject", user_reason: "资料不完整" },
)
expect(client.get).toHaveBeenCalledWith("/admin/deletion-requests", { params })
expect(client.post).toHaveBeenCalledWith(`/admin/deletion-requests/${requestId}/process`)
```

Also prove `apiErrorMessage` extracts string details, `{code,message}` details, and falls back without rendering `[object Object]`.

- [ ] **Step 3: Run tests and confirm the functions are absent**

Run: `cd frontend/web && npm test -- --run src/api/admin.test.ts`

Expected: FAIL because the new types/functions/error normalizer do not exist.

- [ ] **Step 4: Implement types and API functions**

Define exact unions:

```ts
export type AccountStatus = "pending_approval" | "active" | "rejected" | "disabled" | "deleting";
export type DeletionStatus = "requested" | "processing" | "failed" | "completed" | "cancelled";
export type RegistrationDecision = "approve" | "reject" | "return_to_pending";
```

Extend `UserListParams` with `account_status`, add the Task 1 response types, and export `decideRegistration`, `getDeletionRequests`, `processDeletionRequest`, and `retryDeletionRequest`. Stop exporting `deleteUser` to UI consumers; keep backend compatibility outside this plan unchanged.

- [ ] **Step 5: Run API tests and the production build**

Run:

```bash
cd frontend/web
npm test -- --run src/api/admin.test.ts
npm run build
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the web contract layer**

```bash
git add frontend/web/src/api frontend/web/src/test frontend/web/package.json frontend/web/package-lock.json frontend/web/vite.config.ts
git commit -m "feat(admin): add account lifecycle web contracts"
```

---

### Task 3: Correct registration decisions in the Users page

**Files:**
- Modify: `frontend/web/src/pages/admin/Users.tsx`
- Create: `frontend/web/src/pages/admin/Users.test.tsx`

**Interfaces:**
- Consumes: `AccountStatus`, `decideRegistration`, `updateUser`, `apiErrorMessage` from Task 2.
- Produces: explicit status filters/badges and only valid state-dependent actions.

- [ ] **Step 1: Write failing state/action tests**

Render representative rows and assert:

```ts
expect(screen.getByRole("button", { name: "批准" })).toBeInTheDocument()
expect(screen.getByRole("button", { name: "拒绝" })).toBeInTheDocument()
expect(screen.queryByRole("button", { name: /删除/ })).not.toBeInTheDocument()
```

Cover: pending approve/reject; rejected user-visible reason and return-to-pending; active/disabled enablement; deleting has no role/status/reset actions; rejection refuses blank or over-200-character reasons; a 409 response shows its safe message.

- [ ] **Step 2: Run the focused page test and confirm the old inference/actions fail**

Run: `cd frontend/web && npm test -- --run src/pages/admin/Users.test.tsx`

Expected: FAIL because the page infers state from `is_active`/`last_login_at` and exposes direct deletion.

- [ ] **Step 3: Implement explicit registration-state UI**

Use `account_status` for filtering and badges. Call `decideRegistration` for pending/rejected transitions. Keep ordinary enable/disable only for `active` and `disabled`. Remove single and batch delete controls and remove the corresponding selection action; do not relabel direct deletion as account deletion.

- [ ] **Step 4: Add local loading and error handling**

Disable the row action while its request is in flight, refresh after success, and render `apiErrorMessage` after failure. Keep phone/name visible here because this is the authenticated administrator user list.

- [ ] **Step 5: Run focused tests and build**

Run:

```bash
cd frontend/web
npm test -- --run src/pages/admin/Users.test.tsx
npm run build
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the registration UI**

```bash
git add frontend/web/src/pages/admin/Users.tsx frontend/web/src/pages/admin/Users.test.tsx
git commit -m "feat(admin): manage registration decisions"
```

---

### Task 4: Add the account-deletion operations page

**Files:**
- Create: `frontend/web/src/pages/admin/AccountDeletions.tsx`
- Create: `frontend/web/src/pages/admin/AccountDeletions.test.tsx`
- Modify: `frontend/web/src/App.tsx`
- Modify: `frontend/web/src/components/Navbar.tsx`
- Modify: `frontend/web/src/pages/Dashboard.tsx`

**Interfaces:**
- Consumes: Task 2 deletion APIs and Task 1 safe subject/queue response.
- Produces: administrator route `/admin/account-deletions` guarded by the existing `AdminGuard`.

- [ ] **Step 1: Write failing workflow-action tests**

Cover requested-unqueued shows `排队执行`; requested with `queued_at` shows `已排队` and no repeat action; failed shows `重试`; processing/completed/cancelled have no action; overdue rows are visibly marked; subject identity is shown only when present; no approve/reject control exists; 503 displays `注销功能尚未启用`; a successful `202` displays `已排队，等待后台处理` rather than completed.

- [ ] **Step 2: Run the focused test and confirm the page is absent**

Run: `cd frontend/web && npm test -- --run src/pages/admin/AccountDeletions.test.tsx`

Expected: FAIL because the page and route do not exist.

- [ ] **Step 3: Implement the minimal operations table**

Follow the existing admin table, filter, badge, and pagination patterns. Columns are request ID, optional subject phone/name, status, requested time, due time, attempt count, safe failure category, and action. Add status and overdue filters. Do not show raw exceptions or a deletion success until the list returns `completed`.

- [ ] **Step 4: Register administrator navigation**

Add the guarded route and one `账号注销` entry to the desktop/mobile administrator menus and administrator dashboard links. Do not change ordinary student navigation.

- [ ] **Step 5: Run frontend and backend release checks**

Run:

```bash
cd frontend/web
npm test
npm run build
cd ../..
docker run --rm --network none -v "$PWD:/workspace" -w /workspace/backend senior-platform-account-lifecycle-test:latest pytest -q
git diff --check
```

Expected: every command exits 0; the backend retains its documented environment skips/xfail only.

- [ ] **Step 6: Commit the deletion operations UI**

```bash
git add frontend/web/src/pages/admin/AccountDeletions.tsx frontend/web/src/pages/admin/AccountDeletions.test.tsx frontend/web/src/App.tsx frontend/web/src/components/Navbar.tsx frontend/web/src/pages/Dashboard.tsx
git commit -m "feat(admin): operate account deletion queue"
```

## Completion Gate

- An administrator can approve/reject/return a registration only from valid states and sees safe failures.
- Direct user hard-delete controls are absent from the web UI.
- An administrator can identify a live deletion subject, queue requested work, retry failed work, and see overdue/completed state without a deny action.
- Refreshing a queued request does not re-enable the queue button.
- Frontend tests, frontend production build, full backend tests, and `git diff --check` all exit 0.
- No deployment, migration, worker enablement, production deletion, or App Store operation occurs in this plan.
