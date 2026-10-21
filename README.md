# ErrandHer AI Operating System — Agent Workspace

The founder's local control plane. Runs entirely on this machine — closing
the desktop app stops everything, nothing runs unsupervised in the cloud.
Separate from the `errandher` business repository on purpose.

Companion docs live in the main `errandher` repo at
`docs/ai-operating-system/` — read `03-target-architecture-and-plan.md`
for the full design and phased rollout, `04-open-decisions.md` for what's
been verified vs. still open.

## What's here (Phase 1)

```
errandher-ai-ops/
├── CLAUDE.md                          ← shared context every agent reads
├── .claude/agents/
│   ├── operations-dispatch.md         ← delayed orders, runner availability
│   └── customer-experience.md         ← open support cases, customer messaging
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
real database** — delayed-order detection, proposing a case and a message,
approving one and rejecting the other, confirmed exactly one ticket and one
notification were created, confirmed idempotency on retry, confirmed the
full audit trail. That's real, not assumed.

**This repo's own pieces — the MCP server and the desktop app — have not
been run.** Written against documented APIs in a sandbox with no Flutter
SDK and no Node runtime wired to a live server. Treat first setup here as
real testing, not a formality.

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
# The agents' token — covers everything both department agents use
php artisan ai-ops:token:create "operations-dispatch-desktop-app" \
  --ability=ping \
  --ability=orders.read_delayed \
  --ability=runners.read_available \
  --ability=support.read_open_cases \
  --ability=support.propose_case \
  --ability=customer.propose_message

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
  Then switch to the Approvals tab and click Refresh — any proposal it
  filed should appear, with Approve/Reject buttons. Approving executes
  immediately through real business logic (creates an actual support
  ticket, sends an actual in-app notification) — test against a real but
  low-stakes order first.

If anything errors, the raw output (Diagnostics tab) or the snackbar
message (Approvals tab) shows what actually happened — paste that back for
debugging.

## What's deliberately not here yet

Eight more department agents, in-app scheduling (recurring checks without
manually running `claude` each time), deep-links into the existing admin
dashboards. All specced in the main repo's planning docs, built phase by
phase once each one is proven out for real.
