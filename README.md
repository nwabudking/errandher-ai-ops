# ErrandHer AI Operating System — Agent Workspace

The founder's local control plane. Runs entirely on this machine — closing
the desktop app stops everything, nothing runs unsupervised in the cloud.
Separate from the `errandher` business repository on purpose.

Companion docs live in the main `errandher` repo at
`docs/ai-operating-system/` — read `03-target-architecture-and-plan.md`
for the full design and phased rollout, `04-open-decisions.md` for what's
been verified vs. still open.

## What's here (all 4 phases — all 10 departments)

```
errandher-ai-ops/
├── CLAUDE.md                          ← shared context every agent reads
├── .claude/agents/
│   ├── operations-dispatch.md         ← delayed orders, runner availability
│   ├── customer-experience.md         ← open support cases, customer messaging
│   ├── finance-reconciliation.md      ← reconciliation summary, pending withdrawals, fraud flags
│   ├── runner-management.md           ← flagged runners, strike recommendations
│   ├── vendor-market-ops.md           ← vendor applications, out-of-stock products
│   ├── technology-security.md         ← open fraud flags, admin activity, dispositions
│   ├── people-admin-compliance.md     ← expiring documents, role audit log
│   ├── marketing-growth.md            ← referral performance, promo banners
│   ├── business-intelligence-quality.md ← platform snapshot, quality metrics (read-only)
│   └── chief-ai-operating-officer.md  ← cross-department briefing (read-only, every department)
├── .mcp.json                          ← tells Claude Code where the MCP server is
├── mcp-server/                        ← wraps the Laravel AI-Ops API as MCP tools
│   ├── package.json
│   ├── .env.example                   ← copy to .env — the AGENTS' credential
│   └── src/index.js
└── desktop-app/                       ← Flutter Desktop command centre
    ├── pubspec.yaml
    ├── config.example.json            ← copy to config.json — the APP's OWN credential
    └── lib/
        ├── main.dart                  ← two tabs: Approvals, Diagnostics
        ├── config.dart
        ├── ai_ops_client.dart
        ├── claude_runner.dart
        └── screens/
```

**The Laravel side (`errandher` repo) has been tested end-to-end against a
real database for all four phases** — Phase 1: delayed-order detection,
proposing a case and a message, approving one and rejecting the other,
confirmed exactly one ticket and one notification were created, confirmed
idempotency on retry, confirmed the full audit trail. Phase 2: reconciliation
summary and pending-withdrawals read tools checked against real DB queries,
proposing and approving a fraud flag and a runner strike confirmed to create
exactly the right rows via the real `FraudFlag`/`StrikeService` logic, retry
confirmed idempotent. Phase 3: vendor/out-of-stock/fraud-flag/expiring-document
read tools checked against real DB queries, proposing and approving a vendor
message, a fraud-flag disposition, and an expiry reminder confirmed to create
exactly the right notification/flag rows. Phase 4: referral-summary,
active-banners, platform-snapshot, and quality-metrics read tools checked
against real DB queries (and a real enum bug — `Referral.status` is
`pending/qualified/rewarded/rejected`, not `pending/completed` — caught and
fixed by testing, not guessed); proposing and approving a banner confirmed
it's created but inactive, and confirmed it does NOT appear in
active-banners afterward, proving the double-gate actually holds. Validation
and cross-department ability checks confirmed throughout every phase. That's
real, not assumed.

**This repo's own pieces — the MCP server and the desktop app — have been
syntax-checked and the MCP server has been started against a live Laravel
server (all twenty-three tools registered, connects cleanly), but the
desktop app itself has not been run.** No Flutter SDK in this sandbox.
Treat first `flutter run` on your machine as real testing, not a formality.

**Finance, Runner Management, and Vendor & Market Ops hold a stricter
rule than Phase 1:** no tool here approves/rejects a withdrawal or
suspends/bans a runner or vendor directly. **People/Admin/Compliance
holds the strictest rule of all** — no tool anywhere, not even a
propose one, changes an admin role or permission. **Marketing's banner
tool is double-gated** (created inactive, needs a separate human
activation step), **Business Intelligence has no propose tool**, and
**the Chief AI Operating Officer has read tools only, for every
department, and nothing else.** See `CLAUDE.md` and each agent's own
file for why.

## Two separate credentials — don't mix them up

- **The agents' token** (`mcp-server/.env`) — read/propose abilities only.
  Can never approve anything.
- **The desktop app's own token** (`desktop-app/config.json`) —
  `proposed-actions.manage` only. This is the founder's own authority,
  exercised by clicking a button in the app, never by an agent.

See `CLAUDE.md` for why these stay separate.

## Setup

### 1. Mint two AI-Ops API tokens

In the `errandher` repo, wherever you run artisan against the real
database:

```bash
# The agents' token — covers everything all ten department agents use
php artisan ai-ops:token:create "ai-ops-desktop-app" \
  --ability=ping \
  --ability=orders.read_delayed \
  --ability=runners.read_available \
  --ability=support.read_open_cases \
  --ability=support.propose_case \
  --ability=customer.propose_message \
  --ability=finance.read_reconciliation \
  --ability=finance.read_pending_withdrawals \
  --ability=finance.propose_flag \
  --ability=runners.read_flagged \
  --ability=runners.propose_strike \
  --ability=vendors.read_pending \
  --ability=vendors.read_stock_issues \
  --ability=vendors.propose_message \
  --ability=security.read_fraud_flags \
  --ability=security.read_admin_activity \
  --ability=security.propose_flag_disposition \
  --ability=compliance.read_expiring_documents \
  --ability=compliance.read_role_audit_log \
  --ability=compliance.propose_expiry_reminder \
  --ability=marketing.read_referral_summary \
  --ability=marketing.read_active_banners \
  --ability=marketing.propose_banner \
  --ability=bi.read_platform_snapshot \
  --ability=bi.read_quality_metrics

# The desktop app's own token — approval authority, nothing else
php artisan ai-ops:token:create "desktop-app" --ability=proposed-actions.manage
```

Copy each printed token immediately — shown exactly once.

### 2. Set up the MCP server (the agents' side)

```bash
cd mcp-server
npm install
cp .env.example .env
# edit .env: set AI_OPS_BASE_URL and paste the FIRST token above
```

### 3. Set up the desktop app's own config

```bash
cd desktop-app
cp config.example.json config.json
# edit config.json: set baseUrl and paste the SECOND token above
```

### 4. Run the desktop app

Needs the Flutter SDK with desktop support enabled
(`flutter config --enable-windows-desktop` or the macos/linux equivalent).

```bash
flutter pub get
flutter run -d windows   # or macos / linux
```

### 5. Test it for real

- **Diagnostics tab** — click "Run Ping Check". Expected: a success card
  with the real JSON from your live Laravel API, by way of Claude Code and
  the MCP server.
- **Approvals tab** — empty until an agent actually proposes something.
  To generate a real test case, open a terminal in this workspace folder
  and run:
  ```bash
  claude -p "Run a dispatch check: find delayed orders and propose a support case or customer message for anything critical." \
    --agent operations-dispatch \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_delayed_orders,mcp__errandher-ai-ops__ai_ops_propose_support_case,mcp__errandher-ai-ops__ai_ops_propose_customer_message" \
    --permission-prompts none --model sonnet --output-format json
  ```

  Or try the Phase 2 agents the same way, e.g.:
  ```bash
  claude -p "Run a finance check for today and flag anything that looks off." \
    --agent finance-reconciliation \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_reconciliation_summary,mcp__errandher-ai-ops__ai_ops_read_pending_withdrawals,mcp__errandher-ai-ops__ai_ops_propose_fraud_flag" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Check for flagged runners and recommend a strike if warranted." \
    --agent runner-management \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_flagged_runners,mcp__errandher-ai-ops__ai_ops_propose_runner_strike" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Check vendor applications and out-of-stock products." \
    --agent vendor-market-ops \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_vendors_pending_review,mcp__errandher-ai-ops__ai_ops_read_out_of_stock_products,mcp__errandher-ai-ops__ai_ops_propose_vendor_message" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Review open fraud flags and recent admin activity." \
    --agent technology-security \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_open_fraud_flags,mcp__errandher-ai-ops__ai_ops_read_recent_admin_activity,mcp__errandher-ai-ops__ai_ops_propose_fraud_flag_disposition" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Check for runners with documents expiring soon." \
    --agent people-admin-compliance \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_expiring_documents,mcp__errandher-ai-ops__ai_ops_read_role_audit_log,mcp__errandher-ai-ops__ai_ops_propose_expiry_reminder" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Check referral performance and active banners." \
    --agent marketing-growth \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_referral_summary,mcp__errandher-ai-ops__ai_ops_read_active_banners,mcp__errandher-ai-ops__ai_ops_propose_promo_banner" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Give me the platform snapshot and quality metrics." \
    --agent business-intelligence-quality \
    --allowedTools "mcp__errandher-ai-ops__ai_ops_read_platform_snapshot,mcp__errandher-ai-ops__ai_ops_read_quality_metrics" \
    --permission-prompts none --model sonnet --output-format json

  claude -p "Give me today's full executive briefing across every department." \
    --agent chief-ai-operating-officer \
    --permission-prompts none --model sonnet --output-format json
  ```
  Then switch to the Approvals tab and click Refresh — any proposal it
  filed should appear, with Approve/Reject buttons. Approving executes
  immediately through real business logic (creates an actual support
  ticket, sends an actual in-app notification) — test against a real but
  low-stakes order first.

If anything errors, the raw output (Diagnostics tab) or the snackbar
message (Approvals tab) shows what actually happened — paste that back for
debugging.

## What's deliberately not here yet

All ten departments from the original plan now have real, tested tools.
What's still not here: in-app scheduling (recurring checks without
manually running `claude` each time) and deep-links into the existing
admin dashboards — both specced in the main repo's planning docs, not
yet built. No new departments are planned beyond the original ten
without a new decision to expand scope.
