# Apiary — Feature: Agent Persona

## Addendum to PRODUCT.md v4.0

---

## 1. Problem

Today an agent's behavior is baked into its code. System prompts, instructions, memory — all hardcoded in the agent's repository or config files. This creates problems:

- **Changing behavior = redeploying code.** Tweak a prompt → commit → build → deploy → wait. For a one-word change.
- **No visibility.** Dashboard shows what an agent *does* (tasks, proxy calls), but not *who it is* (how it thinks, what it knows, what rules it follows). Two agents with identical capabilities but different prompts look the same.
- **No versioning.** Prompt changed → old version gone. Can't compare "before vs after". Can't rollback when a prompt change makes reviews worse.
- **No consistency.** Each developer writes prompts differently. No shared structure. New team member reads agent code and has to reverse-engineer the persona.
- **No separation of concerns.** The person who writes agent runtime code (Python, polling logic) is often not the same person who should be tuning the persona (domain expert, product owner).

## 2. Solution: Agent Persona

A **Persona** is a structured, versioned, platform-managed definition of an agent's identity, behavior, and memory. Stored in Apiary, served to agents at runtime, editable from the dashboard.

```
┌─────────────────────────────────────────────────────────────┐
│  🤖 Agent: code-reviewer                                    │
│                                                              │
│  ┌─ Persona v7 (active) ──────────────────────────────────┐ │
│  │                                                         │ │
│  │  📜 SOUL.md     — Who you are, your values              │ │
│  │  📋 AGENT.md    — What you do, your workflow            │ │
│  │  🧠 MEMORY.md   — What you know, project context        │ │
│  │  ⚙️ CONFIG      — Parameters, thresholds, preferences   │ │
│  │                                                         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  History: v7 ← v6 ← v5 ← v4 ← v3 ← v2 ← v1               │
│  v6→v7: "Added security focus to review criteria"           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Agent runtime fetches persona on init, re-fetches on change notification. Generic SDK runtime + persona from Apiary = fully configurable agent behavior without code changes.

---

## 3. Persona Structure

Inspired by Claude's system prompt patterns and OpenClaw's file convention, but adapted for multi-agent orchestration.

### 3.1 Documents

A persona consists of **named documents** — markdown files with specific roles.

| Document     | Purpose                                        | Example content                            |
|-------------|------------------------------------------------|--------------------------------------------|
| `SOUL`      | Identity, personality, values, tone            | "You are a senior code reviewer who prioritizes security and readability..." |
| `AGENT`     | Workflow, capabilities, how to handle tasks    | "When you receive a code_review task: 1) fetch PR diff, 2) analyze each file..." |
| `MEMORY`    | Persistent context, project-specific knowledge | "This project uses Laravel 12, PostgreSQL, follows PSR-12. Auth module was refactored in Jan 2025..." |
| `RULES`     | Hard constraints, do/don't rules              | "NEVER approve PRs that modify .env files. ALWAYS flag SQL queries without parameterization..." |
| `STYLE`     | Output format, communication style            | "Write review comments in this format: [SEVERITY] file:line — description..." |
| `EXAMPLES`  | Few-shot examples of good behavior            | "Example good review comment: [MAJOR] auth.py:42 — SQL injection risk..." |

All documents are optional. An agent can have just `SOUL` and `AGENT`, or the full set.

### 3.2 Config (Structured)

Non-prose parameters that control agent behavior:

```json
{
  "config": {
    "llm": {
      "model": "claude-sonnet-4-5-20250514",
      "temperature": 0.3,
      "max_tokens": 4096
    },
    "review": {
      "max_files": 50,
      "skip_patterns": ["*.lock", "*.min.js", "vendor/*"],
      "severity_levels": ["info", "minor", "major", "critical"],
      "auto_approve_threshold": 0
    },
    "behavior": {
      "ask_clarification": true,
      "suggest_fixes": true,
      "max_comments_per_file": 5
    }
  }
}
```

Config values are accessible in agent code via SDK:

```python
config = client.persona.config
model = config["llm"]["model"]
max_files = config["review"]["max_files"]
```

### 3.3 System Prompt Assembly

When an agent initializes an LLM call, the SDK assembles a system prompt from persona documents:

```
[SOUL.md content]

[AGENT.md content]

[RULES.md content]

[STYLE.md content]

[EXAMPLES.md content]

[MEMORY.md content]

[Task-specific context from channel/knowledge store]
```

Order is configurable. Agent code can also selectively include documents:

```python
# Use all documents
system_prompt = client.persona.assemble()

# Only specific documents
system_prompt = client.persona.assemble(include=["SOUL", "AGENT", "RULES"])

# With additional dynamic context
system_prompt = client.persona.assemble(
    append="Current task context:\n" + task.payload["context"]
)
```

---

## 4. Versioning

### 4.1 Every Change = New Version

```
v1: Initial persona
v2: Added MEMORY.md with project context
v3: Changed SOUL.md — more concise tone
v4: Updated RULES.md — added SQL injection rule
v5: Tweaked CONFIG — temperature 0.5 → 0.3
v6: Updated MEMORY.md — new auth module context
v7: Added security focus to AGENT.md workflow (active)
```

Each version is a **complete snapshot** — all documents + config at that point. No incremental diffs. Simple, no merge conflicts.

### 4.2 Version Metadata

```json
{
  "version": 7,
  "created_at": "2025-02-20T10:00:00Z",
  "created_by": { "type": "human", "id": "user:taras" },
  "message": "Added security focus to review criteria",
  "changes": [
    { "document": "AGENT", "action": "modified" }
  ],
  "active": true,
  "performance": {
    "tasks_completed": 45,
    "avg_rating": 4.2,
    "avg_task_duration": 38
  }
}
```

`performance` is populated over time — how well tasks perform under this persona version.

### 4.3 Diff Between Versions

```json
GET /api/v1/agents/{id}/persona/diff?from=6&to=7

{
  "from_version": 6,
  "to_version": 7,
  "changes": [
    {
      "document": "AGENT",
      "type": "modified",
      "diff": "--- v6\n+++ v7\n@@ -5,6 +5,8 @@\n When reviewing code:\n 1. Fetch PR diff\n 2. Analyze each file\n+3. Pay special attention to security implications\n+4. Flag any changes to authentication or authorization logic\n 5. Post review comments"
    }
  ]
}
```

Dashboard renders this as a visual diff (like GitHub PR diff view).

### 4.4 Rollback

```json
POST /api/v1/agents/{id}/persona/rollback
{
  "to_version": 5,
  "reason": "v6-v7 changes caused too many false positives in security reviews"
}
```

Creates v8 with content identical to v5. Version history preserved — nothing deleted.

Active agents pick up the new version on next persona refresh.

---

## 5. Live Updates (Hot Reload)

### 5.1 How Agents Get Persona Updates

Two mechanisms:

**Init fetch:** Agent starts → fetches full persona → caches locally.

```python
client = ApiaryClient.from_env()
# SDK auto-fetches persona on init
# client.persona is populated with all documents + config
```

**Change notification:** Persona updated in dashboard → Apiary notifies agent.

Agent poll response includes persona version check:

```json
GET /api/v1/tasks/poll

{
  "tasks": [...],
  "persona_version": 7,
  "next_poll_ms": 3000
}
```

Agent SDK compares with cached version. If different:

```python
# Automatic in SDK poll loop — respects agent's update policy
# server_persona_version = the version the server says THIS agent should use
# (active version for auto, pinned version for manual, canary-assigned for staged)
if server_persona_version != cached_version:
    client.persona.refresh()
    # Next LLM call uses new persona
```

No restart. No redeploy. The server returns the policy-correct version for each agent in the poll response: the active version for `auto` agents, the pinned version for `manual` agents, or the canary-assigned version for `staged` agents (see §5.2). When a `manual` agent is explicitly promoted to a new version, the poll response reflects the change and the SDK refreshes on the next cycle.

### 5.2 Lock Mechanism

Some agents should NOT auto-update — production agents that need tested personas:

```json
{
  "persona_settings": {
    "auto_update": false,
    "pinned_version": 5,
    "update_policy": "manual"
  }
}
```

| Policy    | Behavior                                         |
|-----------|--------------------------------------------------|
| `auto`    | Hot-reload on any change (default for dev)       |
| `manual`  | Pinned to specific version, explicit promotion   |
| `staged`  | New version → canary agent first → then all      |

### 5.3 Staged Rollout

For agents with multiple replicas:

```json
POST /api/v1/agents/{id}/persona/promote
{
  "version": 8,
  "strategy": "canary",
  "canary_percentage": 20,
  "auto_promote_after": 3600,
  "rollback_on": {
    "error_rate_above": 0.1,
    "avg_rating_below": 3.5
  }
}
```

1. 20% of agent replicas get persona v8
2. 80% stay on v7
3. After 1 hour, if metrics look good → auto-promote to 100%
4. If error rate spikes → auto-rollback to v7

---

## 6. A/B Testing

### 6.1 Compare Persona Versions

Two versions running simultaneously on different replicas, same tasks:

```json
POST /api/v1/agents/{id}/persona/ab-test
{
  "variant_a": { "version": 7 },
  "variant_b": { "version": 8 },
  "split": 50,
  "duration_hours": 24,
  "metrics": ["task_completion_rate", "avg_duration", "human_rating"]
}
```

Agent Runtime assigns variant A or B to each replica. Tasks are distributed evenly.

### 6.2 Results

```json
GET /api/v1/agents/{id}/persona/ab-test/results

{
  "status": "running",
  "duration": "18h / 24h",
  "variant_a": {
    "version": 7,
    "tasks_completed": 45,
    "avg_task_duration": 38,
    "error_rate": 0.02,
    "human_ratings": { "avg": 4.2, "count": 12 }
  },
  "variant_b": {
    "version": 8,
    "tasks_completed": 42,
    "avg_task_duration": 41,
    "error_rate": 0.01,
    "human_ratings": { "avg": 4.6, "count": 11 }
  },
  "recommendation": "Variant B (v8) shows lower error rate and higher human ratings. Consider promoting."
}
```

Dashboard shows side-by-side comparison with charts.

### 6.3 Integration with Task Replay

Replay the same task with different persona versions:

```json
POST /api/v1/tasks/{id}/replay
{
  "mode": "sandbox",
  "persona_version": 5
}
```

"How would this task have gone with the old prompt?"

---

## 7. Persona Templates

### 7.1 Built-in Templates

Apiary ships starter templates for common agent roles:

| Template              | Documents included                       |
|-----------------------|------------------------------------------|
| Code Reviewer         | SOUL + AGENT + RULES + STYLE + EXAMPLES  |
| Deployer              | SOUL + AGENT + RULES                     |
| Data Analyst          | SOUL + AGENT + STYLE                     |
| Security Scanner      | SOUL + AGENT + RULES + EXAMPLES          |
| Technical Writer      | SOUL + AGENT + STYLE + EXAMPLES          |
| Incident Responder    | SOUL + AGENT + RULES                     |
| General Assistant      | SOUL + AGENT                             |

### 7.2 Template Example: Code Reviewer

**SOUL.md:**
```markdown
You are a senior code reviewer with 10+ years of experience.

Your core values:
- **Security first**: Always look for vulnerabilities
- **Readability**: Code should be clear to the next developer
- **Pragmatism**: Perfect is the enemy of good — suggest improvements, don't block on style
- **Teaching**: Explain *why* something is a problem, not just *what*

Your tone is professional, constructive, and encouraging.
You praise good code as well as flagging issues.
```

**AGENT.md:**
```markdown
## Workflow

When you receive a `code_review` task:

1. Fetch the PR diff via service proxy
2. Read the PR description for context
3. Check project MEMORY for relevant conventions and past decisions
4. Analyze each changed file:
   - Security implications
   - Logic correctness
   - Error handling
   - Test coverage
5. Assign severity to each finding: info / minor / major / critical
6. Write review comments following STYLE format
7. Make approve/request-changes decision
8. Post review to GitHub via service proxy
9. Write review summary to knowledge store

## Decision criteria

- **Approve**: No major/critical issues
- **Request changes**: Any critical issue OR 3+ major issues
- **Comment only**: Only minor/info issues but want to share feedback

## When stuck

If you encounter code you don't understand:
1. Check knowledge store for architecture docs
2. Check MEMORY for project context
3. If still unclear, post a question in the task channel
```

**RULES.md:**
```markdown
## Hard rules (NEVER violate)

- NEVER approve PRs that modify `.env`, `.env.example`, or any file containing secrets
- NEVER approve PRs that disable security features (CSRF, auth middleware, rate limiting)
- NEVER approve PRs without tests for new business logic
- ALWAYS flag raw SQL queries — require parameterized queries
- ALWAYS flag `eval()`, `exec()`, `unserialize()` with user input

## Soft rules (flag but don't block)

- Methods longer than 50 lines → suggest extraction
- Files longer than 500 lines → suggest splitting
- TODO/FIXME comments without ticket reference → flag
- Console.log / dd() / var_dump() → flag for cleanup
```

### 7.3 Fork & Customize

```json
POST /api/v1/agents/{id}/persona/from-template
{
  "template": "code-reviewer",
  "customizations": {
    "MEMORY": "## Project: Apiary\n- Framework: Laravel 12\n- Database: PostgreSQL 16\n- Style: PSR-12\n- All models use ULIDs\n- Auth uses Sanctum tokens",
    "RULES": {
      "append": "\n## Project-specific rules\n- All Eloquent models MUST use BelongsToHive trait\n- API responses MUST follow { data, meta, errors } envelope"
    },
    "config": {
      "llm": { "model": "claude-sonnet-4-5-20250514" },
      "review": { "max_files": 30 }
    }
  }
}
```

Start from template, add project-specific context. Template updates don't overwrite customizations (fork model, not sync).

---

## 8. BYOA Support

Persona is not just for managed agents. BYOA agents can fetch and use personas too.

### 8.1 SDK Usage (BYOA)

```python
from apiary_sdk import ApiaryClient

client = ApiaryClient(url="https://acme.apiary.ai", token="tok_xxx")

# Fetch persona
persona = client.persona

# Use in LLM call
response = openai.chat.completions.create(
    model=persona.config["llm"]["model"],
    messages=[
        {"role": "system", "content": persona.assemble()},
        {"role": "user", "content": task_prompt}
    ],
    temperature=persona.config["llm"]["temperature"]
)
```

Agent code is generic. All behavior comes from persona. Same code, different persona = different agent.

### 8.2 Thin Agent Pattern

This enables a **thin agent** — minimal code that's just a loop + LLM call:

```python
from apiary_sdk import ApiaryClient
import anthropic

client = ApiaryClient.from_env()
llm = anthropic.Anthropic()

while True:
    tasks = client.poll()
    for task in tasks:
        # Assemble system prompt from persona
        system = client.persona.assemble(
            append=f"Current task:\n{json.dumps(task.payload, indent=2)}"
        )
        
        # Call LLM
        response = llm.messages.create(
            model=client.persona.config["llm"]["model"],
            system=system,
            messages=[{"role": "user", "content": "Execute this task."}],
            max_tokens=client.persona.config["llm"]["max_tokens"]
        )
        
        # Complete task with LLM response
        client.complete(task.id, result={"response": response.content[0].text})
    
    client.sleep()
```

20 lines of code. All intelligence in the persona. Change persona in dashboard → agent behavior changes instantly.

### 8.3 Apiary Generic Agent

Take this further: Apiary ships a **generic managed agent runtime** that needs zero custom code. Just configure persona + capabilities in dashboard.

```json
POST /api/v1/managed-agents
{
  "name": "code-reviewer",
  "source": {
    "type": "builtin",
    "runtime": "apiary-generic-agent",
    "version": "latest"
  },
  "capabilities": ["code_review"],
  "persona": { ... }
}
```

Generic agent runtime: poll → read task → assemble persona + task context → call LLM → parse response → execute actions (proxy calls, knowledge writes) → complete task.

**Zero code deployment** — create agent entirely from dashboard.

---

## 9. API

### 9.1 Persona CRUD

```
GET    /api/v1/agents/{id}/persona              — Get current active persona (all docs + config)
PUT    /api/v1/agents/{id}/persona              — Update persona (creates new version)
PATCH  /api/v1/agents/{id}/persona/documents/{name} — Update single document
PATCH  /api/v1/agents/{id}/persona/config       — Update config only
```

### 9.2 Versioning

```
GET    /api/v1/agents/{id}/persona/versions     — List all versions with metadata
GET    /api/v1/agents/{id}/persona/versions/{v}  — Get specific version
GET    /api/v1/agents/{id}/persona/diff?from={v1}&to={v2} — Diff between versions
POST   /api/v1/agents/{id}/persona/rollback     — Rollback to version
POST   /api/v1/agents/{id}/persona/promote      — Promote version (staged/canary)
```

### 9.3 A/B Testing

```
POST   /api/v1/agents/{id}/persona/ab-test      — Start A/B test
GET    /api/v1/agents/{id}/persona/ab-test/results — Get results
POST   /api/v1/agents/{id}/persona/ab-test/stop — Stop test, pick winner
```

### 9.4 Templates

```
GET    /api/v1/persona-templates                — List available templates
GET    /api/v1/persona-templates/{slug}         — Get template details
POST   /api/v1/agents/{id}/persona/from-template — Create persona from template
```

### 9.5 Agent SDK Endpoint

```
GET    /api/v1/persona                          — Get MY persona (agent auth, returns policy-selected version: active for auto, pinned for manual, canary-assigned for staged)
GET    /api/v1/persona/config                   — Get config only
GET    /api/v1/persona/documents/{name}         — Get single document
GET    /api/v1/persona/assembled                — Get pre-assembled system prompt string
PATCH  /api/v1/persona/documents/{name}         — Update single document (agent self-update, respects lock policy)
```

### 9.6 Update Persona (Full Example)

```json
PUT /api/v1/agents/agt_reviewer/persona
{
  "message": "Added security focus and updated project memory",
  "documents": {
    "SOUL": {
      "content": "You are a senior code reviewer with 10+ years of experience.\n\nYour core values:\n- **Security first**: Always look for vulnerabilities\n- **Readability**: Code should be clear to the next developer\n..."
    },
    "AGENT": {
      "content": "## Workflow\n\nWhen you receive a `code_review` task:\n1. Fetch the PR diff\n..."
    },
    "MEMORY": {
      "content": "## Project: Apiary\n- Framework: Laravel 12\n- Database: PostgreSQL 16\n...",
      "locked": false
    },
    "RULES": {
      "content": "## Hard rules\n- NEVER approve PRs that modify .env files\n...",
      "locked": true
    }
  },
  "config": {
    "llm": {
      "model": "claude-sonnet-4-5-20250514",
      "temperature": 0.3,
      "max_tokens": 4096
    }
  }
}
```

Response:

```json
{
  "version": 8,
  "previous_version": 7,
  "created_at": "2025-02-20T12:00:00Z",
  "changes": [
    { "document": "SOUL", "action": "unchanged" },
    { "document": "AGENT", "action": "unchanged" },
    { "document": "MEMORY", "action": "modified" },
    { "document": "RULES", "action": "unchanged" }
  ],
  "active": true,
  "message": "Added security focus and updated project memory"
}
```

---

## 10. Document Locking

Some documents should be editable by agents (MEMORY evolves as project evolves). Others should be locked (RULES set by humans, agents can't weaken their own constraints).

```json
{
  "documents": {
    "SOUL":     { "locked": true,  "editable_by": ["human"] },
    "AGENT":    { "locked": true,  "editable_by": ["human"] },
    "MEMORY":   { "locked": false, "editable_by": ["human", "agent", "self"] },
    "RULES":    { "locked": true,  "editable_by": ["human"] },
    "STYLE":    { "locked": true,  "editable_by": ["human"] },
    "EXAMPLES": { "locked": false, "editable_by": ["human", "agent"] }
  }
}
```

`self` — the agent itself can update its own MEMORY (learning from experience).

Agent updates to MEMORY:

```json
PATCH /api/v1/persona/documents/MEMORY
{
  "append": "\n## Learned 2025-02-20\n- The `users` table has a soft-delete column that affects JOIN queries\n- Team prefers early returns over nested if-else"
}
```

Creates new persona version. Dashboard shows "Agent updated MEMORY" in version history with clear attribution.

Locked documents: API returns 403 if agent tries to modify a locked document. Human must unlock first.

---

## 11. Database Schema

```sql
CREATE TABLE agent_personas (
    id              VARCHAR(26) PRIMARY KEY,
    agent_id        VARCHAR(26) NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
    apiary_id       VARCHAR(26) NOT NULL REFERENCES apiaries(id) ON DELETE CASCADE,
    hive_id         VARCHAR(26) NOT NULL REFERENCES hives(id) ON DELETE CASCADE,
    
    version         INTEGER NOT NULL,
    is_active       BOOLEAN DEFAULT FALSE,
    
    documents       JSONB NOT NULL,
    -- {
    --   "SOUL":     { "content": "...", "locked": true },
    --   "AGENT":    { "content": "...", "locked": true },
    --   "MEMORY":   { "content": "...", "locked": false },
    --   "RULES":    { "content": "...", "locked": true },
    --   ...
    -- }
    
    config          JSONB NOT NULL DEFAULT '{}',
    lock_policy     JSONB DEFAULT '{}',
    
    -- Version metadata
    message         TEXT,
    changes         JSONB DEFAULT '[]',
    created_by_type VARCHAR(10) NOT NULL,    -- human, agent, system
    created_by_id   VARCHAR(26) NOT NULL,
    
    -- Performance tracking
    tasks_completed INTEGER DEFAULT 0,
    avg_task_duration FLOAT,
    avg_rating      FLOAT,
    error_rate      FLOAT,
    
    created_at      TIMESTAMP DEFAULT NOW()
);

CREATE UNIQUE INDEX idx_persona_active ON agent_personas (agent_id)
    WHERE is_active = TRUE;
CREATE INDEX idx_persona_versions ON agent_personas (agent_id, version DESC);
CREATE UNIQUE INDEX idx_persona_version_unique ON agent_personas (agent_id, version);

-- A/B tests
CREATE TABLE persona_ab_tests (
    id              VARCHAR(26) PRIMARY KEY,
    agent_id        VARCHAR(26) NOT NULL REFERENCES agents(id),
    
    variant_a       INTEGER NOT NULL,        -- persona version (validated by app against agent_personas)
    variant_b       INTEGER NOT NULL,        -- persona version (validated by app against agent_personas)
    CONSTRAINT fk_variant_a FOREIGN KEY (agent_id, variant_a) REFERENCES agent_personas(agent_id, version),
    CONSTRAINT fk_variant_b FOREIGN KEY (agent_id, variant_b) REFERENCES agent_personas(agent_id, version),
    CONSTRAINT chk_distinct_variants CHECK (variant_a <> variant_b),
    split           SMALLINT DEFAULT 50 CHECK (split BETWEEN 0 AND 100),
    
    status          VARCHAR(20) DEFAULT 'running',  -- running, completed, stopped
    started_at      TIMESTAMP DEFAULT NOW(),
    ends_at         TIMESTAMP,
    
    results_a       JSONB DEFAULT '{}',
    results_b       JSONB DEFAULT '{}',
    winner          VARCHAR(1),              -- 'a', 'b', or null
    
    created_by      VARCHAR(26) NOT NULL,
    created_at      TIMESTAMP DEFAULT NOW()
);
```

Agents table addition:

```sql
ALTER TABLE agents ADD COLUMN persona_version INTEGER;
ALTER TABLE agents ADD COLUMN persona_update_policy VARCHAR(20) DEFAULT 'auto';
ALTER TABLE agents ADD COLUMN persona_pinned_version INTEGER;
-- Integrity note: persona_version and persona_pinned_version logically reference
-- agent_personas(agent_id, version) but a composite FK here would create a circular
-- dependency (agents ↔ agent_personas). Validity is enforced by PersonaService which
-- verifies the version exists for the agent before writing these columns.
```

---

## 12. Dashboard

### 12.1 Persona Editor

```
┌────────────────────────────────────────────────────────────────────┐
│  🤖 code-reviewer — Persona v7                    [Save v8] 💾    │
│                                                                    │
│  ┌─ Documents ──┐  ┌─ Editor ──────────────────────────────────┐   │
│  │              │  │                                           │   │
│  │  📜 SOUL  🔒  │  │  # Who You Are                           │   │
│  │  📋 AGENT 🔒  │  │                                           │   │
│  │  🧠 MEMORY   │  │  You are a senior code reviewer with     │   │
│  │  ⚡ RULES 🔒  │  │  10+ years of experience.                │   │
│  │  🎨 STYLE 🔒  │  │                                           │   │
│  │  📝 EXAMPLES │  │  Your core values:                        │   │
│  │              │  │  - **Security first**: Always look for    │   │
│  │  ⚙️ CONFIG   │  │    vulnerabilities                        │   │
│  │              │  │  - **Readability**: Code should be clear  │   │
│  └──────────────┘  │    to the next developer                  │   │
│                    │  - **Pragmatism**: Perfect is the enemy   │   │
│                    │    of good                                │   │
│                    │  █                                         │   │
│                    │                                           │   │
│                    │  Preview assembled prompt: 2,340 tokens   │   │
│                    └───────────────────────────────────────────┘   │
│                                                                    │
│  ┌─ Version History ──────────────────────────────────────────┐    │
│  │  v7  ✅ active  @taras  "Added security focus"  2h ago     │    │
│  │  v6  —         @taras  "Updated project memory" 1d ago    │    │
│  │  v5  —         🤖 self  "Learned: soft-delete"   2d ago    │    │
│  │  v4  —         @taras  "Added SQL injection rule" 5d ago  │    │
│  │  [View diff v6→v7] [Rollback to v6]                       │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌─ Performance ───────────────────────────────────────────────┐   │
│  │  v7 (18h): 45 tasks  avg 38s  4.2★  2% errors             │   │
│  │  v6 (3d):  120 tasks avg 42s  3.9★  4% errors             │   │
│  │  📈 v7 is performing better across all metrics              │   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

### 12.2 Token Counter

Live preview shows assembled prompt token count:

```
SOUL:      320 tokens
AGENT:     580 tokens
MEMORY:    840 tokens
RULES:     290 tokens
STYLE:     180 tokens
EXAMPLES:  450 tokens
─────────────────────
Total:     2,660 tokens

Estimated cost per task: ~$0.008 (input) + ~$0.012 (output) = $0.02
Monthly estimate (500 tasks): ~$10
```

Helps optimize persona size vs. cost.

### 12.3 Diff View

Side-by-side diff between any two versions, like GitHub PR view:

```
┌─ v6 ──────────────────────┐  ┌─ v7 ──────────────────────────┐
│ ## Workflow                │  │ ## Workflow                    │
│                            │  │                                │
│ When reviewing code:       │  │ When reviewing code:           │
│ 1. Fetch PR diff           │  │ 1. Fetch PR diff               │
│ 2. Analyze each file       │  │ 2. Analyze each file           │
│                            │  │+3. Pay special attention to    │
│                            │  │+   security implications       │
│                            │  │+4. Flag auth/authz changes     │
│ 3. Post review comments    │  │ 5. Post review comments        │
└────────────────────────────┘  └────────────────────────────────┘
```

### 12.4 Agent Card (Enhanced)

Agent overview card now shows persona summary:

```
┌────────────────────────────────────────────────┐
│  🤖 code-reviewer         🟢 online             │
│                                                 │
│  Persona: v7 (auto-update)  📜 6 docs  ⚙️ config│
│  Identity: "Senior code reviewer, security-first" │
│  Model: claude-sonnet-4-5 @ temp 0.3           │
│                                                 │
│  [Edit Persona]  [View History]  [A/B Test]    │
└────────────────────────────────────────────────┘
```

---

## 13. Integration with Existing Features

### 13.1 Persona + Managed Agents

Managed agent wizard includes persona step:

```
Step 1: Source (Docker / Git / Inline / Builtin)
Step 2: Capabilities + permissions
Step 3: Persona (template or custom)    ← new
Step 4: Launch mode + resources
Step 5: Environment
→ Deploy
```

For builtin generic runtime: persona IS the agent. No code needed.

### 13.2 Persona + Agent Templates (Marketplace)

Agent templates include default persona:

```yaml
# marketplace template
name: GitHub Code Reviewer
persona:
  documents:
    SOUL: |
      You are a senior code reviewer...
    AGENT: |
      ## Workflow...
    RULES: |
      ## Hard rules...
  config:
    llm:
      model: claude-sonnet-4-5-20250514
      temperature: 0.3
```

Install template → persona auto-configured. User customizes from there.

### 13.3 Persona + Task Replay

Replay task with different persona version:

```json
POST /api/v1/tasks/{id}/replay
{
  "mode": "sandbox",
  "persona_version": 5
}
```

"Same task, old prompt — what would have happened?"

### 13.4 Persona + LLM Cost Tracking

Persona token count feeds into cost estimation. Dashboard shows: "This persona uses 2,660 input tokens per call. At current task volume (500/mo), system prompt costs ~$10/mo."

### 13.5 Persona + Channels

When agent participates in a channel, persona informs its behavior:
- SOUL defines tone and values
- RULES define what it can/cannot agree to
- MEMORY provides context for informed discussion

### 13.6 Persona + Observability

Prometheus metrics include persona version label:

```
apiary_task_duration_seconds{agent="code-reviewer",persona_version="7"} ...
apiary_task_error_rate{agent="code-reviewer",persona_version="7"} ...
```

Enables performance correlation: "error rate dropped when we switched to persona v7."

---

## 14. Permissions

| Permission              | Who can do what                                   |
|------------------------|---------------------------------------------------|
| Human: Admin/Owner     | Full persona CRUD, lock/unlock documents           |
| Human: Member          | Edit unlocked documents, view all                  |
| Human: Viewer          | Read-only persona access                           |
| Agent: self            | Update unlocked self-editable docs (MEMORY)        |
| Agent: other           | Cannot modify other agents' personas               |
| API: manage:personas   | Agent permission to manage own persona via API     |

---

## 15. Implementation Priority

| Priority | Feature                              | Effort  | Phase  |
|----------|--------------------------------------|---------|--------|
| P0       | Persona model + CRUD API             | 3 days  | 2      |
| P0       | SDK: fetch persona, assemble prompt  | 2 days  | 2      |
| P0       | Dashboard: persona editor            | 1 week  | 2      |
| P0       | Versioning (auto on every save)      | 2 days  | 2      |
| P1       | Diff view between versions           | 2 days  | 2      |
| P1       | Rollback                             | 1 day   | 2      |
| P1       | Document locking                     | 1 day   | 2      |
| P1       | Hot reload (poll-based update)       | 2 days  | 2      |
| P1       | Token counter + cost estimate        | 1 day   | 2      |
| P1       | Persona templates (built-in)         | 3 days  | 2-3    |
| P2       | Version performance tracking         | 3 days  | 3      |
| P2       | Agent self-update for MEMORY         | 2 days  | 3      |
| P2       | Staged rollout (canary)              | 3 days  | 3-4    |
| P3       | A/B testing                          | 1 week  | 4      |
| P3       | Generic agent runtime (zero code)    | 1 week  | 4      |
| P3       | Persona marketplace integration      | 2 days  | 4+     |

P0+P1 (usable MVP): ~2.5 weeks. Recommended phase: **Phase 2** — early, because it fundamentally changes how agents are configured and makes everything else more powerful.

---

*Feature version: 1.0*
*Depends on: PRODUCT.md v4.0 (agents, hives), FEATURE_MANAGED_AGENTS.md (managed deployment), FEATURE_PLATFORM_ENHANCEMENTS.md (LLM tracking, replay)*
