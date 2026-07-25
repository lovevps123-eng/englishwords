# 后端词汇模块实施计划（senior-platform）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 senior-platform 后端新增"系统背词"能力：基于已入库的 ECDICT 词典（13,644 词，高考标签 3,677 词）提供每日队列、简化 SM-2 复习、离线幂等提交、统计和例句富化。

**Architecture:** 新表 `user_word_progress` 关联现有 `dictionary_entries`（不复制词条数据）；`vocab_result_logs` 表以 client 生成的 UUID 做幂等去重支撑 App 离线补交。新端点追加进现有 `api/vocab.py` 路由（`/api/vocab` 前缀已注册）。现有 `vocab_entries` 生词本与其端点保持不动。

**Tech Stack:** FastAPI + SQLAlchemy 2.0 async + PostgreSQL（测试用 in-memory SQLite，沿用 `tests/conftest.py` 的 `client` fixture）

## Global Constraints

- 工作目录：`/Users/masf/develop/project/senior-platform/backend`；测试命令一律 `python -m pytest tests/... -v`
- `Base.metadata.create_all()` 不会给已有表加列 → `dictionary_entries` 的新列必须写进 Task 6 的生产 ALTER SQL
- 反馈三档字符串常量：`know` / `fuzzy` / `unknown`（App 与后端的契约，不得改名）
- SRS 间隔沿用现有约定 `{1:1, 2:3, 3:7, 4:14, 5:30}` 天，stage 5 后固定 30 天，stage≥5 视为掌握
- 队列/统计端点不得使用 JSONB `@>` 操作符（SQLite 测试跑不了）→ 难度层用新列 `tier` 整型过滤
- 例句 JSON 结构：`[{"en": str, "cn": str, "source": "gaokao"|"tatoeba"|"freedict"|"llm"}]`，每词最多 3 条

---

### Task 1: 数据模型（进度表、幂等日志、词典新列）

**Files:**
- Modify: `app/models/vocab.py`（文件末尾追加两个模型）
- Modify: `app/models/dictionary.py`（DictionaryEntry 加两列）
- Test: `tests/test_vocab_models.py`

**Interfaces:**
- Produces: `UserWordProgress(user_id, word_id, stage, next_review_at, collected, correct_count, wrong_count)`，唯一约束 `(user_id, word_id)`；`VocabResultLog(client_id: str PK, user_id)`；`DictionaryEntry.tier: int|None`、`DictionaryEntry.examples: list|None`

- [ ] **Step 1: 写失败测试**

```python
# tests/test_vocab_models.py
"""Model-level tests for the systematic vocab study tables."""
import uuid
import pytest
from sqlalchemy.exc import IntegrityError

from tests.conftest import TestSessionLocal, TEST_REGION_ID


async def _make_user(session):
    from app.models.user import User
    user = User(
        phone=f"138{uuid.uuid4().hex[:8]}", password_hash="x",
        name="词汇测试", region_id=TEST_REGION_ID,
    )
    session.add(user)
    await session.commit()
    return user


async def _make_word(session, word="abandon", tier=1):
    from app.models.dictionary import DictionaryEntry
    entry = DictionaryEntry(
        word=word, phonetic="/əˈbændən/",
        definitions=[{"pos": "v", "meaning": "放弃"}],
        exam_tags=["高考"], tier=tier,
        examples=[{"en": "He abandoned the plan.", "cn": "他放弃了计划。", "source": "llm"}],
    )
    session.add(entry)
    await session.commit()
    return entry


@pytest.mark.asyncio
async def test_user_word_progress_unique_per_user_word():
    from app.models.vocab import UserWordProgress
    async with TestSessionLocal() as s:
        user, word = await _make_user(s), await _make_word(s)
        s.add(UserWordProgress(user_id=user.id, word_id=word.id, stage=1))
        await s.commit()
        s.add(UserWordProgress(user_id=user.id, word_id=word.id, stage=2))
        with pytest.raises(IntegrityError):
            await s.commit()


@pytest.mark.asyncio
async def test_result_log_pk_is_client_id():
    from app.models.vocab import VocabResultLog
    async with TestSessionLocal() as s:
        user = await _make_user(s)
        s.add(VocabResultLog(client_id="abc-123", user_id=user.id))
        await s.commit()
        s.add(VocabResultLog(client_id="abc-123", user_id=user.id))
        with pytest.raises(IntegrityError):
            await s.commit()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_vocab_models.py -v`
Expected: FAIL（`ImportError`/`AttributeError`: UserWordProgress 不存在；DictionaryEntry 无 tier）

- [ ] **Step 3: 实现模型**

`app/models/dictionary.py` 在 `difficulty` 行后加：

```python
    tier: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)  # 1=高考基础层 2=拔高层
    examples: Mapped[list | None] = mapped_column(JSONB, nullable=True)  # [{en, cn, source}]
```

`app/models/vocab.py` 末尾追加（补充导入 `UniqueConstraint`、`func` 已有）：

```python
class UserWordProgress(Base):
    __tablename__ = "user_word_progress"
    __table_args__ = (UniqueConstraint("user_id", "word_id", name="uq_user_word_progress"),)

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    word_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("dictionary_entries.id"), index=True)
    stage: Mapped[int] = mapped_column(Integer, default=0)  # 0=已收藏未学 1-5=SRS阶段
    collected: Mapped[bool] = mapped_column(Boolean, default=False)  # 阅读中收藏的词优先进队列
    next_review_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    correct_count: Mapped[int] = mapped_column(Integer, default=0)
    wrong_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class VocabResultLog(Base):
    __tablename__ = "vocab_result_logs"

    client_id: Mapped[str] = mapped_column(String(64), primary_key=True)  # App 端生成的 UUID
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
```

`vocab.py` 头部导入行改为 `from sqlalchemy import String, Integer, Boolean, DateTime, Text, ForeignKey, UniqueConstraint`。

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_vocab_models.py tests/test_models.py -v`
Expected: 全部 PASS（含旧模型测试不回归）

- [ ] **Step 5: Commit**

```bash
git add app/models/vocab.py app/models/dictionary.py tests/test_vocab_models.py
git commit -m "feat(vocab): 系统背词进度表 + 幂等日志表 + 词典 tier/examples 列"
```

### Task 2: SRS 反馈纯函数

**Files:**
- Create: `app/services/srs.py`
- Test: `tests/test_srs.py`

**Interfaces:**
- Produces: `apply_feedback(stage: int, feedback: str) -> tuple[int, int]` 返回 `(new_stage, interval_days)`；非法 feedback 抛 `ValueError`。Task 3/4 的端点依赖它。

- [ ] **Step 1: 写失败测试**

```python
# tests/test_srs.py
import pytest
from app.services.srs import apply_feedback


@pytest.mark.parametrize("stage,feedback,expected", [
    (0, "know", (1, 1)),      # 新词认识 → stage1，1天后复习
    (1, "know", (2, 3)),
    (4, "know", (5, 30)),
    (5, "know", (5, 30)),     # 封顶
    (3, "fuzzy", (3, 7)),     # 模糊：原地重复当前间隔
    (0, "fuzzy", (1, 1)),
    (4, "unknown", (1, 1)),   # 不认识：打回 stage1
])
def test_apply_feedback(stage, feedback, expected):
    assert apply_feedback(stage, feedback) == expected


def test_invalid_feedback_raises():
    with pytest.raises(ValueError):
        apply_feedback(1, "maybe")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_srs.py -v`
Expected: FAIL with `ModuleNotFoundError: app.services.srs`

- [ ] **Step 3: 实现**

```python
# app/services/srs.py
"""简化版 SM-2：三档反馈驱动的间隔重复。App 契约常量，勿改档位名。"""

REVIEW_INTERVALS = {1: 1, 2: 3, 3: 7, 4: 14, 5: 30}
MAX_STAGE = 5


def apply_feedback(stage: int, feedback: str) -> tuple[int, int]:
    """Return (new_stage, interval_days) for a review feedback."""
    if feedback == "know":
        new_stage = min(stage + 1, MAX_STAGE)
    elif feedback == "fuzzy":
        new_stage = max(stage, 1)
    elif feedback == "unknown":
        new_stage = 1
    else:
        raise ValueError(f"invalid feedback: {feedback}")
    return new_stage, REVIEW_INTERVALS[new_stage]
```

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_srs.py -v`
Expected: 8 PASS

- [ ] **Step 5: Commit**

```bash
git add app/services/srs.py tests/test_srs.py
git commit -m "feat(vocab): 简化 SM-2 反馈函数"
```

### Task 3: 每日队列端点

**Files:**
- Modify: `app/api/vocab.py`（末尾追加端点；头部补导入）
- Test: `tests/test_vocab_api.py`（新建，含本计划后续任务共用的注册/造词 helper）

**Interfaces:**
- Consumes: Task 1 模型
- Produces: `GET /api/vocab/queue?new_limit=50&tier=1` → `{"new": [word...], "review": [word...]}`；word 序列化为 `{"id", "word", "phonetic", "definitions", "examples", "stage"}`（new 中 stage 恒为 0）

- [ ] **Step 1: 写失败测试**

```python
# tests/test_vocab_api.py
"""API tests for the systematic vocab study endpoints (queue/results/collect/stats)."""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from httpx import AsyncClient

from tests.conftest import TestSessionLocal, TEST_REGION_ID


async def _auth_headers(client: AsyncClient, phone="13800139001") -> dict:
    resp = await client.post("/api/auth/register", json={
        "phone": phone, "password": "Test123456", "name": "背词学生",
        "grade": "高三", "region_id": str(TEST_REGION_ID),
    })
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def _seed_words(n=5, tier=1, prefix="word"):
    from app.models.dictionary import DictionaryEntry
    ids = []
    async with TestSessionLocal() as s:
        for i in range(n):
            e = DictionaryEntry(
                word=f"{prefix}{i}", phonetic=f"/{prefix}{i}/", tier=tier,
                definitions=[{"pos": "n", "meaning": f"释义{i}"}],
                exam_tags=["高考"], difficulty=1,
                examples=[{"en": f"Use {prefix}{i}.", "cn": f"用{prefix}{i}。", "source": "llm"}],
            )
            s.add(e); await s.flush(); ids.append(e.id)
        await s.commit()
    return ids


@pytest.mark.asyncio
async def test_queue_returns_new_words_by_tier(client: AsyncClient):
    await _seed_words(5, tier=1)
    await _seed_words(3, tier=2, prefix="hard")
    headers = await _auth_headers(client)
    resp = await client.get("/api/vocab/queue?new_limit=3&tier=1", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["new"]) == 3
    assert all(w["word"].startswith("word") for w in body["new"])
    assert body["review"] == []
    assert {"id", "word", "phonetic", "definitions", "examples", "stage"} <= set(body["new"][0])


@pytest.mark.asyncio
async def test_queue_includes_due_reviews_and_excludes_learned_from_new(client: AsyncClient):
    from app.models.vocab import UserWordProgress
    from app.models.user import User
    from sqlalchemy import select
    ids = await _seed_words(4, tier=1)
    headers = await _auth_headers(client, phone="13800139002")
    async with TestSessionLocal() as s:
        user = (await s.execute(select(User).where(User.phone == "13800139002"))).scalar_one()
        s.add(UserWordProgress(  # 已到期 → 应出现在 review
            user_id=user.id, word_id=ids[0], stage=2,
            next_review_at=datetime.now(timezone.utc) - timedelta(hours=1)))
        s.add(UserWordProgress(  # 未到期 → 两边都不出现
            user_id=user.id, word_id=ids[1], stage=3,
            next_review_at=datetime.now(timezone.utc) + timedelta(days=3)))
        await s.commit()
    resp = await client.get("/api/vocab/queue?new_limit=10&tier=1", headers=headers)
    body = resp.json()
    assert [w["id"] for w in body["review"]] == [str(ids[0])]
    new_ids = {w["id"] for w in body["new"]}
    assert str(ids[0]) not in new_ids and str(ids[1]) not in new_ids
    assert len(body["new"]) == 2
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_vocab_api.py -v`
Expected: FAIL with 404（/queue 未定义。注意：现有 `GET /{vocab_id}` 类路由若吞掉 /queue 导致 422，也按失败处理，实现时把 /queue 定义放在动态路由之前）

- [ ] **Step 3: 实现端点**

`app/api/vocab.py` 头部补导入：

```python
from sqlalchemy import or_
from app.models.dictionary import DictionaryEntry
from app.models.vocab import UserWordProgress, VocabResultLog
from app.services.srs import apply_feedback
```

追加端点（若文件存在 `/{vocab_id}` 形式的动态路由，本端点必须写在其上方）：

```python
def _word_payload(entry: DictionaryEntry, stage: int = 0) -> dict:
    return {
        "id": str(entry.id), "word": entry.word, "phonetic": entry.phonetic,
        "definitions": entry.definitions or [], "examples": entry.examples or [],
        "stage": stage,
    }


@router.get("/queue")
async def get_daily_queue(
    new_limit: int = 50, tier: int = 1,
    user=Depends(get_current_user), db: AsyncSession = Depends(get_db),
):
    """当日队列 = 到期复习词 + 收藏待学词 + 新词（按难度升序补足 new_limit）。"""
    now = datetime.now(timezone.utc)

    review_rows = (await db.execute(
        select(UserWordProgress, DictionaryEntry)
        .join(DictionaryEntry, UserWordProgress.word_id == DictionaryEntry.id)
        .where(UserWordProgress.user_id == user.id, UserWordProgress.stage > 0,
               UserWordProgress.next_review_at <= now)
        .order_by(UserWordProgress.next_review_at).limit(200)
    )).all()
    review = [_word_payload(e, p.stage) for p, e in review_rows]

    collected_rows = (await db.execute(
        select(UserWordProgress, DictionaryEntry)
        .join(DictionaryEntry, UserWordProgress.word_id == DictionaryEntry.id)
        .where(UserWordProgress.user_id == user.id, UserWordProgress.stage == 0)
        .order_by(UserWordProgress.created_at).limit(new_limit)
    )).all()
    new_words = [_word_payload(e) for _, e in collected_rows]

    remaining = new_limit - len(new_words)
    if remaining > 0:
        seen = select(UserWordProgress.word_id).where(UserWordProgress.user_id == user.id)
        fresh = (await db.execute(
            select(DictionaryEntry)
            .where(DictionaryEntry.tier == tier, DictionaryEntry.id.not_in(seen))
            .order_by(DictionaryEntry.difficulty, DictionaryEntry.word).limit(remaining)
        )).scalars().all()
        new_words += [_word_payload(e) for e in fresh]

    return {"new": new_words, "review": review}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_vocab_api.py -v`
Expected: 2 PASS

- [ ] **Step 5: Commit**

```bash
git add app/api/vocab.py tests/test_vocab_api.py
git commit -m "feat(vocab): 每日队列端点（复习+收藏+新词）"
```

### Task 4: 幂等批量提交端点

**Files:**
- Modify: `app/api/vocab.py`
- Test: `tests/test_vocab_api.py`（追加）

**Interfaces:**
- Consumes: `apply_feedback`、Task 1 模型、Task 3 的 `_auth_headers`/`_seed_words`
- Produces: `POST /api/vocab/results`，body `{"results": [{"client_id": str, "word_id": str, "feedback": "know"|"fuzzy"|"unknown"}]}` → `{"processed": int, "skipped": int}`；重复 client_id 跳过（离线补交安全）

- [ ] **Step 1: 写失败测试（追加到 tests/test_vocab_api.py）**

```python
@pytest.mark.asyncio
async def test_results_idempotent_and_updates_progress(client: AsyncClient):
    from app.models.vocab import UserWordProgress
    from sqlalchemy import select
    ids = await _seed_words(2, tier=1)
    headers = await _auth_headers(client, phone="13800139003")
    payload = {"results": [
        {"client_id": "c1", "word_id": str(ids[0]), "feedback": "know"},
        {"client_id": "c2", "word_id": str(ids[1]), "feedback": "unknown"},
    ]}
    resp = await client.post("/api/vocab/results", json=payload, headers=headers)
    assert resp.status_code == 200
    assert resp.json() == {"processed": 2, "skipped": 0}

    # 重复提交同批（模拟离线补交重放）→ 全部 skipped，进度不变
    resp2 = await client.post("/api/vocab/results", json=payload, headers=headers)
    assert resp2.json() == {"processed": 0, "skipped": 2}

    async with TestSessionLocal() as s:
        rows = (await s.execute(select(UserWordProgress).order_by(UserWordProgress.created_at))).scalars().all()
        assert len(rows) == 2
        know = next(r for r in rows if r.word_id == ids[0])
        unknown = next(r for r in rows if r.word_id == ids[1])
        assert know.stage == 1 and know.correct_count == 1 and know.next_review_at is not None
        assert unknown.stage == 1 and unknown.wrong_count == 1


@pytest.mark.asyncio
async def test_results_invalid_feedback_400(client: AsyncClient):
    ids = await _seed_words(1, tier=1, prefix="bad")
    headers = await _auth_headers(client, phone="13800139004")
    resp = await client.post("/api/vocab/results", json={
        "results": [{"client_id": "x1", "word_id": str(ids[0]), "feedback": "maybe"}]
    }, headers=headers)
    assert resp.status_code == 400
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_vocab_api.py -v`
Expected: 新增 2 条 FAIL（404）

- [ ] **Step 3: 实现端点（追加到 app/api/vocab.py，同样置于动态路由之前）**

```python
@router.post("/results")
async def submit_results(
    request: Request,
    user=Depends(get_current_user), db: AsyncSession = Depends(get_db),
):
    """批量提交答题结果；client_id 幂等去重，支持 App 离线补交重放。"""
    body = await request.json()
    now = datetime.now(timezone.utc)
    processed = skipped = 0
    for r in body.get("results", []):
        try:
            new_stage_preview = apply_feedback(0, r["feedback"])  # 先校验 feedback 合法
        except (ValueError, KeyError):
            raise HTTPException(400, f"非法反馈: {r.get('feedback')}")
        if await db.get(VocabResultLog, r["client_id"]):
            skipped += 1
            continue
        word_id = uuid.UUID(r["word_id"])
        prog = (await db.execute(
            select(UserWordProgress).where(
                UserWordProgress.user_id == user.id, UserWordProgress.word_id == word_id)
        )).scalar_one_or_none()
        if prog is None:
            prog = UserWordProgress(user_id=user.id, word_id=word_id)
            db.add(prog)
        new_stage, days = apply_feedback(prog.stage, r["feedback"])
        prog.stage = new_stage
        prog.next_review_at = now + timedelta(days=days)
        if r["feedback"] == "know":
            prog.correct_count += 1
        else:
            prog.wrong_count += 1
        db.add(VocabResultLog(client_id=r["client_id"], user_id=user.id))
        processed += 1
    await db.commit()
    return {"processed": processed, "skipped": skipped}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_vocab_api.py -v`
Expected: 4 PASS

- [ ] **Step 5: Commit**

```bash
git add app/api/vocab.py tests/test_vocab_api.py
git commit -m "feat(vocab): 幂等批量提交答题结果"
```

### Task 5: 收藏与统计端点

**Files:**
- Modify: `app/api/vocab.py`
- Test: `tests/test_vocab_api.py`（追加）

**Interfaces:**
- Consumes: Task 1/3/4 的模型与 helper
- Produces: `POST /api/vocab/collect` body `{"word": str}` → 200 `{"status": "collected", "word_id": str}` / 404（词典无此词）/ 200 `{"status": "exists"}`；`GET /api/vocab/stats` → `{"learning", "mastered", "due_today", "days_active", "streak"}`

- [ ] **Step 1: 写失败测试（追加）**

```python
@pytest.mark.asyncio
async def test_collect_creates_stage0_and_dedups(client: AsyncClient):
    from app.models.vocab import UserWordProgress
    from sqlalchemy import select
    await _seed_words(1, tier=1, prefix="ocean")
    headers = await _auth_headers(client, phone="13800139005")
    r1 = await client.post("/api/vocab/collect", json={"word": "Ocean0"}, headers=headers)
    assert r1.status_code == 200 and r1.json()["status"] == "collected"
    r2 = await client.post("/api/vocab/collect", json={"word": "ocean0"}, headers=headers)
    assert r2.json()["status"] == "exists"
    r3 = await client.post("/api/vocab/collect", json={"word": "nosuchword"}, headers=headers)
    assert r3.status_code == 404
    async with TestSessionLocal() as s:
        rows = (await s.execute(select(UserWordProgress))).scalars().all()
        assert len(rows) == 1 and rows[0].stage == 0 and rows[0].collected is True


@pytest.mark.asyncio
async def test_stats_counts(client: AsyncClient):
    ids = await _seed_words(3, tier=1, prefix="stat")
    headers = await _auth_headers(client, phone="13800139006")
    await client.post("/api/vocab/results", json={"results": [
        {"client_id": "s1", "word_id": str(ids[0]), "feedback": "know"},
        {"client_id": "s2", "word_id": str(ids[1]), "feedback": "unknown"},
    ]}, headers=headers)
    resp = await client.get("/api/vocab/stats", headers=headers)
    body = resp.json()
    assert body["learning"] == 2 and body["mastered"] == 0
    assert body["days_active"] == 1 and body["streak"] == 1
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_vocab_api.py -v`
Expected: 新增 2 条 FAIL（404）

- [ ] **Step 3: 实现两个端点（追加，置于动态路由之前）**

```python
@router.post("/collect")
async def collect_word(
    request: Request,
    user=Depends(get_current_user), db: AsyncSession = Depends(get_db),
):
    """阅读中收藏生词：建 stage=0 进度行，优先进入下次新词队列。"""
    body = await request.json()
    word = (body.get("word") or "").strip().lower()
    entry = (await db.execute(
        select(DictionaryEntry).where(sa_func.lower(DictionaryEntry.word) == word)
    )).scalar_one_or_none()
    if entry is None:
        raise HTTPException(404, "词典中没有这个词")
    existing = (await db.execute(
        select(UserWordProgress).where(
            UserWordProgress.user_id == user.id, UserWordProgress.word_id == entry.id)
    )).scalar_one_or_none()
    if existing:
        return {"status": "exists", "word_id": str(entry.id)}
    db.add(UserWordProgress(user_id=user.id, word_id=entry.id, stage=0, collected=True))
    await db.commit()
    return {"status": "collected", "word_id": str(entry.id)}


@router.get("/stats")
async def vocab_stats(
    user=Depends(get_current_user), db: AsyncSession = Depends(get_db),
):
    now = datetime.now(timezone.utc)
    rows = (await db.execute(
        select(UserWordProgress.stage, UserWordProgress.next_review_at)
        .where(UserWordProgress.user_id == user.id, UserWordProgress.stage > 0)
    )).all()
    learning = sum(1 for stage, _ in rows if stage < 5)
    mastered = sum(1 for stage, _ in rows if stage >= 5)
    due_today = sum(1 for _, due in rows if due is not None and due <= now)

    dates = sorted({d[0] for d in (await db.execute(
        select(sa_func.date(VocabResultLog.created_at))
        .where(VocabResultLog.user_id == user.id).distinct()
    )).all()}, reverse=True)
    streak = 0
    from datetime import date as date_cls, timedelta as td
    expect = now.date()
    for d in dates:
        d = d if isinstance(d, date_cls) else date_cls.fromisoformat(str(d))
        if d == expect:
            streak += 1; expect = expect - td(days=1)
        elif d == expect - td(days=0):  # 同日重复防御（distinct 后不会发生）
            continue
        else:
            break
    return {"learning": learning, "mastered": mastered, "due_today": due_today,
            "days_active": len(dates), "streak": streak}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_vocab_api.py tests/test_vocab_models.py tests/test_srs.py -v`
Expected: 全部 PASS

- [ ] **Step 5: 全量回归 + Commit**

Run: `python -m pytest tests/ -v` → 全部 PASS（旧测试不回归）

```bash
git add app/api/vocab.py tests/test_vocab_api.py
git commit -m "feat(vocab): 收藏生词 + 学习统计端点"
```

### Task 6: 例句富化脚本

**Files:**
- Create: `scripts/enrich_examples.py`
- Test: `tests/test_enrich_examples.py`

**Interfaces:**
- Consumes: `DictionaryEntry.examples`（Task 1）；现有 `gaokao_questions` 表（content/passage 字段）；现有 `app.services.llm_router.simple_chat`
- Produces: 可重复执行的 CLI：`python scripts/enrich_examples.py [--tier 1] [--limit 100] [--tatoeba data/cmn-eng.tsv]`。纯函数 `split_sentences(text) -> list[str]`、`pick_examples(word, sentences, max_n=3) -> list[str]` 可单测。

- [ ] **Step 1: 写失败测试**

```python
# tests/test_enrich_examples.py
from scripts.enrich_examples import split_sentences, pick_examples


def test_split_sentences_basic():
    text = "He left. She stayed! Did they win? U.S. policy changed."
    out = split_sentences(text)
    assert "He left." in out and "She stayed!" in out and "Did they win?" in out


def test_pick_examples_word_boundary_and_length():
    sentences = [
        "I can run fast.",                       # 命中 run
        "Running is fun.",                       # 变形不命中（v1 只做词边界精确匹配）
        "The brunch was good.",                  # 子串不命中
        "Run.",                                  # 过短过滤（<4 词）
        "I run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run and run.",  # 过长过滤（>25 词）
    ]
    out = pick_examples("run", sentences)
    assert out == ["I can run fast."]


def test_pick_examples_caps_at_max():
    sentences = [f"I like to run in the {p}." for p in ["park", "gym", "rain", "snow"]]
    assert len(pick_examples("run", sentences, max_n=3)) == 3
```

- [ ] **Step 2: 跑测试确认失败**

Run: `python -m pytest tests/test_enrich_examples.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: 实现脚本**

```python
# scripts/enrich_examples.py
"""
为 dictionary_entries 补例句（spec 优先级：高考真题 > Tatoeba > Free Dictionary 已存释义例句 > LLM）。

Usage:
    python scripts/enrich_examples.py [--tier 1] [--limit 100] [--tatoeba data/cmn-eng.tsv]

- 只处理 examples 为空的词；可重复执行（幂等）。
- Tatoeba TSV 来自 manythings.org/anki 的 cmn-eng 句对（tab 分隔: eng \t cmn）。
- 例句结构 [{"en", "cn", "source"}]，每词最多 3 条；中文翻译缺失时由 LLM 补。
"""
import argparse
import asyncio
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, or_
from app.core.database import async_session
from app.models.dictionary import DictionaryEntry

_SENT_RE = re.compile(r"(?<!\b[A-Z])(?<=[.!?])\s+")


def split_sentences(text: str) -> list[str]:
    """Split English prose into sentences (naive, good enough for corpus mining)."""
    return [s.strip() for s in _SENT_RE.split(text or "") if s.strip()]


def pick_examples(word: str, sentences: list[str], max_n: int = 3) -> list[str]:
    """词边界精确匹配 + 4~25 词长度过滤，保序去重取前 max_n 句。"""
    pat = re.compile(rf"\b{re.escape(word)}\b", re.IGNORECASE)
    out, seen = [], set()
    for s in sentences:
        if len(out) >= max_n:
            break
        if not pat.search(s):
            continue
        n_words = len(s.split())
        if not (4 <= n_words <= 25):
            continue
        key = s.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(s)
    return out


def load_tatoeba(path: str) -> list[tuple[str, str]]:
    """manythings cmn-eng.tsv: eng<TAB>cmn[<TAB>attribution]"""
    pairs = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2:
                pairs.append((parts[0], parts[1]))
    return pairs


async def gaokao_sentences(db) -> list[str]:
    """现有英语真题语料 → 句子池。"""
    from app.models.gaokao import GaokaoQuestion
    rows = (await db.execute(
        select(GaokaoQuestion.content, GaokaoQuestion.passage)
        .where(GaokaoQuestion.subject == "english")
    )).all()
    pool = []
    for content, passage in rows:
        pool += split_sentences(content or "")
        pool += split_sentences(passage or "")
    return pool


async def translate_batch(sentences: list[str]) -> list[str]:
    """LLM 翻译英文例句为中文（一次调用一批）。"""
    from app.services.llm_router import simple_chat
    prompt = (
        "把下面的英文句子逐句翻译成简洁的中文，只输出 JSON 数组（与输入等长）：\n"
        + json.dumps(sentences, ensure_ascii=False)
    )
    resp = await simple_chat(prompt)
    try:
        out = json.loads(resp.strip().strip("`").removeprefix("json"))
        if isinstance(out, list) and len(out) == len(sentences):
            return [str(x) for x in out]
    except (json.JSONDecodeError, AttributeError):
        pass
    return ["" for _ in sentences]  # 翻译失败不阻塞，cn 留空待补


async def llm_example(word: str, meaning: str) -> dict | None:
    """所有语料都没命中时，LLM 生成一条适合高中生的例句。"""
    from app.services.llm_router import simple_chat
    prompt = (
        f"为英语单词 {word}（{meaning}）写一个适合中国高中生的例句。"
        '只输出 JSON: {"en": "...", "cn": "..."}'
    )
    resp = await simple_chat(prompt)
    try:
        d = json.loads(resp.strip().strip("`").removeprefix("json"))
        return {"en": d["en"], "cn": d["cn"], "source": "llm"}
    except (json.JSONDecodeError, KeyError, AttributeError):
        return None


def freedict_examples(entry: DictionaryEntry) -> list[str]:
    """enrich_dictionary.py 已存入 definitions [{pos, meaning, example}] 的英文例句。"""
    out = []
    for d in entry.definitions or []:
        ex = (d.get("example") or "").strip()
        if ex:
            out.append(ex)
    return out


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", type=int, default=1)
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--tatoeba", default=None)
    args = ap.parse_args()

    tatoeba = load_tatoeba(args.tatoeba) if args.tatoeba else []
    tatoeba_en = [p[0] for p in tatoeba]
    tatoeba_cn = {p[0].lower(): p[1] for p in tatoeba}

    async with async_session() as db:
        pool = await gaokao_sentences(db)
        entries = (await db.execute(
            select(DictionaryEntry)
            .where(DictionaryEntry.tier == args.tier,
                   or_(DictionaryEntry.examples.is_(None), DictionaryEntry.examples == []))
            .order_by(DictionaryEntry.difficulty, DictionaryEntry.word)
            .limit(args.limit)
        )).scalars().all()
        print(f"待补例句: {len(entries)} 词")

        for i, entry in enumerate(entries):
            examples = []
            for en in pick_examples(entry.word, pool):
                examples.append({"en": en, "cn": "", "source": "gaokao"})
            if len(examples) < 3:
                for en in pick_examples(entry.word, tatoeba_en, max_n=3 - len(examples)):
                    examples.append({"en": en, "cn": tatoeba_cn.get(en.lower(), ""), "source": "tatoeba"})
            if len(examples) < 3:
                for en in pick_examples(entry.word, freedict_examples(entry), max_n=3 - len(examples)):
                    examples.append({"en": en, "cn": "", "source": "freedict"})
            if not examples:
                meaning = (entry.definitions or [{}])[0].get("meaning", "")
                gen = await llm_example(entry.word, meaning)
                if gen:
                    examples.append(gen)

            need_cn = [e["en"] for e in examples if not e["cn"]]
            if need_cn:
                translations = await translate_batch(need_cn)
                it = iter(translations)
                for e in examples:
                    if not e["cn"]:
                        e["cn"] = next(it)

            entry.examples = examples
            if (i + 1) % 20 == 0:
                await db.commit()
                print(f"  {i + 1}/{len(entries)} 已提交")
        await db.commit()
        print("完成")


if __name__ == "__main__":
    asyncio.run(main())
```

- [ ] **Step 4: 跑测试确认通过**

Run: `python -m pytest tests/test_enrich_examples.py -v`
Expected: 3 PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/enrich_examples.py tests/test_enrich_examples.py
git commit -m "feat(vocab): 例句富化脚本（真题>Tatoeba>FreeDict>LLM，来源标记）"
```

### Task 7: 生产迁移与部署

**Files:**
- Modify: `README.md`（数据脚本节补一行 enrich_examples 用法）
- 生产数据库 ALTER + 部署

**Interfaces:**
- Consumes: 全部前置任务
- Produces: 生产环境可用的 /api/vocab/queue|results|collect|stats；高考层词条带 tier 和首批例句

- [ ] **Step 1: 本地全量测试 + push**

```bash
python -m pytest tests/ -v   # 全部 PASS 后
git push
```

- [ ] **Step 2: 生产加列（create_all 不会加列，必须手动）**

```bash
ssh root@202.182.116.2 'docker exec deploy-postgres-1 psql -U masf masf -c "
ALTER TABLE dictionary_entries ADD COLUMN IF NOT EXISTS tier INTEGER;
ALTER TABLE dictionary_entries ADD COLUMN IF NOT EXISTS examples JSONB;
CREATE INDEX IF NOT EXISTS ix_dictionary_entries_tier ON dictionary_entries(tier);
UPDATE dictionary_entries SET tier = 1 WHERE exam_tags @> '"'"'[\"高考\"]'"'"';
UPDATE dictionary_entries SET tier = 2 WHERE tier IS NULL AND (exam_tags @> '"'"'[\"四级\"]'"'"' OR exam_tags @> '"'"'[\"六级\"]'"'"');
"'
```

Expected: `UPDATE 3677`（tier=1）；tier=2 为四六级词条数

- [ ] **Step 3: 部署（新表由 create_all 自动建）**

```bash
ssh root@202.182.116.2 "bash /opt/masf/deploy.sh"
ssh root@202.182.116.2 "docker logs deploy-backend-1 2>&1 | grep -v health | tail -10"
```

Expected: 启动无异常

- [ ] **Step 4: 首批例句富化试跑**

```bash
ssh root@202.182.116.2 "docker exec deploy-backend-1 python scripts/enrich_examples.py --tier 1 --limit 50"
ssh root@202.182.116.2 'docker exec deploy-postgres-1 psql -U masf masf -tc "SELECT count(*) FROM dictionary_entries WHERE examples IS NOT NULL"'
```

Expected: 输出"完成"；count ≥ 50。抽查 3 个词的 examples 内容质量（source 分布、中文翻译在），确认后再分批跑完 3,677 词（Tatoeba 语料下载后传入 --tatoeba）

- [ ] **Step 5: 线上冒烟 + 文档 + Commit**

用测试账号 curl 验证（登录取 token 后）：

```bash
curl -s -H "Authorization: Bearer $TOKEN" "https://<域名>/api/vocab/queue?new_limit=5&tier=1"
```

Expected: 返回 5 个新词，字段齐全。README.md 数据脚本节加一行后：

```bash
git add README.md && git commit -m "docs: enrich_examples 脚本用法" && git push
```

## Self-Review 已执行

- spec 覆盖：队列/三档反馈 SRS/幂等提交/收藏打通阅读/统计/例句来源优先级/tier 分层 → Task 1-7 逐项对应；听力模块属计划 3，App 端属计划 4
- 类型一致：`apply_feedback` 签名、feedback 常量、word payload 字段、examples 结构在各任务间已核对
- 无占位符；所有测试均含完整代码与预期结果
