# ErrandHer AI Operating System — Agent Workspace

The founder's local control plane. Runs entirely on this machine — closing
the desktop app stops everything, nothing runs unsupervised in the cloud.
Separate from the `errandher` business repository on purpose.

Companion docs live in the main `errandher` repo at
`docs/ai-operating-system/` — read `03-target-architecture-and-plan.md`
for the full design and phased rollout, `04-open-decisions.md` for what's
been verified vs. still open.

## What's here (Phase 0)

```
errandher-ai-ops/
├── CLAUDE.md                          ← shared context every agent reads
├── .claude/agents/
│   └── operations-dispatch.md         ← the one Phase 0 agent, one tool
├── .mcp.json                          ← tells Claude Code where the MCP server is
├── mcp-server/                        ← wraps the Laravel AI-Ops API as MCP tools
│   ├── package.json
│   ├── .env.example                   ← copy to .env, fill in your token
│   └── src/index.js
└── desktop-app/                       ← Flutter Desktop command centre
    ├── pubspec.yaml
    └── lib/main.dart
```

**Nothing in this repo has been run yet.** It was written against
documented APIs (the MCP SDK's stdio-server pattern, Claude Code's
confirmed CLI flags, Flutter desktop + `dart:io.Process`) in a sandbox with
no Flutter SDK, no Node runtime wired to a live server, and no way to
actually execute any of it end-to-end. Treat first setup as real testing,
not a formality.

## Setup

### 1. Mint an AI-Ops API token

In the `errandher` repo, on whatever machine has access to the Laravel app
(local dev, or wherever you run artisan against the real database):

```bash
php artisan ai-ops:token:create "operations-dispatch-desktop-app" --ability=ping
```

Copy the printed token immediately — it's shown exactly once.

### 2. Set up the MCP server

```bash
cd mcp-server
npm install
cp .env.example .env
# edit .env: set AI_OPS_BASE_URL and paste the token from step 1
```

### 3. Set up the desktop app

Needs the Flutter SDK with desktop support enabled
(`flutter config --enable-windows-desktop` or the macos/linux equivalent).

```bash
cd desktop-app
flutter pub get
flutter run -d windows   # or macos / linux
```

### 4. Run the Phase 0 test

Click "Run Ping Check" in the app. Expected: a success card showing
`{"status":"ok","time":"...","agent":"operations-dispatch-desktop-app"}`
pulled straight from the live Laravel API, by way of Claude Code and the
MCP server. If it errors, the raw output panel shows exactly what Claude
Code returned — paste that back for debugging.

## What's deliberately not here yet

Nine more department agents, real business tools beyond the health check,
the approval-queue UI, in-app scheduling. All specced in the main repo's
planning docs, built only once this round trip is proven out for real.
