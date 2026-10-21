#!/usr/bin/env node
// ErrandHer AI-Ops MCP server.
//
// Wraps the Laravel AI-Ops API (routes/ai-ops.php, app/Http/Controllers/
// Api/AiOps/) as MCP tools Claude Code can call directly. Holds the
// AI-Ops credential (AI_OPS_TOKEN) — the desktop app and the agent's
// own prompt never see it.
//
// Phase 0 (ping), Phase 1 (dispatch/support/customer), and Phase 2
// (finance/runner tools below) are all proven end-to-end against a real
// database and live HTTP server, including the executors each propose
// tool triggers on approval — tested for real, not just written. This
// file's own Node process has been started and connected its stdio
// transport without error, but has not yet been driven by a real Claude
// Code session on your machine — that's still the first real test.
//
// Deliberately NOT here: approve/reject for proposed actions (desktop-app
// -only — an agent must never approve its own proposal), and no
// withdrawal approve/reject tool at all — money movement stays behind the
// existing admin dashboard, never something a propose-and-click flow
// executes. See FinanceController's class comment in the main repo.
//
// Config (environment variables, set in .env — see .env.example):
//   AI_OPS_BASE_URL   e.g. https://errandher.ng  (or your local dev URL)
//   AI_OPS_TOKEN       plaintext token from `php artisan ai-ops:token:create`

import { config as loadEnv } from 'dotenv';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';

// Load mcp-server/.env explicitly by path — don't rely on whatever
// directory Claude Code happens to spawn this process from.
const __dirname = dirname(fileURLToPath(import.meta.url));
loadEnv({ path: join(__dirname, '..', '.env') });

const BASE_URL = process.env.AI_OPS_BASE_URL;
const TOKEN = process.env.AI_OPS_TOKEN;

const server = new McpServer({
  name: 'errandher-ai-ops',
  version: '0.2.0',
});

async function callAiOps(path, init = {}) {
  if (!BASE_URL || !TOKEN) {
    throw new Error('AI_OPS_BASE_URL or AI_OPS_TOKEN is not set — check your .env file.');
  }
  const res = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      Accept: 'application/json',
      ...(init.method === 'POST' ? { 'Content-Type': 'application/json' } : {}),
      ...(init.headers || {}),
    },
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`AI-Ops API ${res.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

function textResult(value) {
  return { content: [{ type: 'text', text: JSON.stringify(value) }] };
}

function errorResult(err) {
  return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
}

server.registerTool(
  'ai_ops_ping',
  {
    title: 'AI-Ops health check',
    description:
      "Confirms the AI-Ops API is reachable and this agent's credential is valid. " +
      'The first thing to call when verifying the pipeline works.',
    inputSchema: {},
  },
  async () => {
    try {
      return textResult(await callAiOps('/api/ai-ops/ping'));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_delayed_orders',
  {
    title: 'Read delayed orders',
    description:
      'Lists active orders flagged at or above the given severity by the same SLA logic the admin ' +
      'dispatch dashboard uses — "delayed" here means exactly what it means to a human admin, not a ' +
      'separate AI-invented definition.',
    inputSchema: {
      min_flag: z.enum(['at_risk', 'delayed', 'critical']).optional()
        .describe('Minimum severity to include. Defaults to "delayed" if omitted.'),
    },
  },
  async ({ min_flag }) => {
    try {
      const qs = min_flag ? `?min_flag=${encodeURIComponent(min_flag)}` : '';
      return textResult(await callAiOps(`/api/ai-ops/orders/delayed${qs}`));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_available_runners',
  {
    title: 'Read available runners',
    description: 'Lists runners currently marked available and approved — for assessing whether a delayed order could be reassigned.',
    inputSchema: {},
  },
  async () => {
    try {
      return textResult(await callAiOps('/api/ai-ops/runners/available'));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_open_support_cases',
  {
    title: 'Read open support cases',
    description: 'Lists currently open or in-progress support tickets, most recent first.',
    inputSchema: {},
  },
  async () => {
    try {
      return textResult(await callAiOps('/api/ai-ops/support/open-cases'));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_propose_support_case',
  {
    title: 'Propose a support case',
    description:
      'Proposes creating a support ticket for an order issue. Does NOT create anything — only files a ' +
      'proposal that a human must approve via the desktop app before a ticket actually exists.',
    inputSchema: {
      order_id: z.number().int().describe('The order this case is about.'),
      subject: z.string().max(255).describe('Short ticket subject.'),
      description: z.string().describe('Full description of the issue.'),
      category: z.string().max(100).optional().describe('e.g. "delivery_issue" — defaults to "other" if omitted.'),
      business_reason: z.string().describe('Why this case is being proposed — required, shown to the human approving it.'),
    },
  },
  async (args) => {
    try {
      return textResult(await callAiOps('/api/ai-ops/support/propose-case', {
        method: 'POST',
        body: JSON.stringify(args),
      }));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_propose_customer_message',
  {
    title: 'Propose a customer message',
    description:
      'Proposes an in-app notification to the customer about their order. Does NOT send anything — only ' +
      'files a proposal that a human must approve via the desktop app before it actually goes out.',
    inputSchema: {
      order_id: z.number().int().describe('The order this message is about.'),
      title: z.string().max(255).describe('Notification title.'),
      body: z.string().max(1000).describe('Notification body — the actual message text the customer sees.'),
      business_reason: z.string().describe('Why this message is being proposed — required, shown to the human approving it.'),
    },
  },
  async (args) => {
    try {
      return textResult(await callAiOps('/api/ai-ops/customer/propose-message', {
        method: 'POST',
        body: JSON.stringify(args),
      }));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_reconciliation_summary',
  {
    title: 'Read finance reconciliation summary',
    description:
      'Reads revenue/commission/service-charge/refund totals for a date range — the same numbers the ' +
      'admin ledger dashboard shows, computed the same way.',
    inputSchema: {
      range: z.enum(['today', 'yesterday', 'week', 'month']).optional()
        .describe('Defaults to "today" if omitted. Ignored if date_from/date_to are given.'),
      date_from: z.string().optional().describe('YYYY-MM-DD — overrides range if given.'),
      date_to: z.string().optional().describe('YYYY-MM-DD — overrides range if given.'),
    },
  },
  async ({ range, date_from, date_to }) => {
    try {
      const params = new URLSearchParams();
      if (range) params.set('range', range);
      if (date_from) params.set('date_from', date_from);
      if (date_to) params.set('date_to', date_to);
      const qs = params.toString() ? `?${params.toString()}` : '';
      return textResult(await callAiOps(`/api/ai-ops/finance/reconciliation-summary${qs}`));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_pending_withdrawals',
  {
    title: 'Read pending withdrawals',
    description: 'Lists withdrawal requests awaiting approval, oldest first, plus pending/approved/paid-out totals.',
    inputSchema: {},
  },
  async () => {
    try {
      return textResult(await callAiOps('/api/ai-ops/finance/pending-withdrawals'));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_propose_fraud_flag',
  {
    title: 'Propose a fraud/anomaly flag',
    description:
      'Proposes flagging a user for fraud/anomaly review. Does NOT touch any wallet, withdrawal, or order — ' +
      'only files a flag a human must approve via the desktop app. Never a substitute for approving or ' +
      'rejecting a withdrawal yourself; that stays in the existing admin dashboard.',
    inputSchema: {
      user_id: z.number().int().describe('The user this flag is about.'),
      flag_type: z.enum(['referral_abuse', 'suspicious_withdrawal', 'fake_gps', 'multiple_accounts', 'excessive_cancellations', 'ledger_anomaly', 'other'])
        .describe('What kind of issue this is.'),
      description: z.string().describe('What was observed, in enough detail for a human reviewer to act on.'),
      severity: z.enum(['low', 'medium', 'high', 'critical']).optional().describe('Defaults to "medium" if omitted.'),
      business_reason: z.string().describe('Why this is being flagged — required, shown to the human approving it.'),
    },
  },
  async (args) => {
    try {
      return textResult(await callAiOps('/api/ai-ops/finance/propose-flag', {
        method: 'POST',
        body: JSON.stringify(args),
      }));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_read_flagged_runners',
  {
    title: 'Read flagged runners',
    description: 'Lists runners with at least one strike, an active suspension, or a permanent ban — most strikes first.',
    inputSchema: {},
  },
  async () => {
    try {
      return textResult(await callAiOps('/api/ai-ops/runners/flagged'));
    } catch (err) {
      return errorResult(err);
    }
  },
);

server.registerTool(
  'ai_ops_propose_runner_strike',
  {
    title: 'Propose a runner strike',
    description:
      'Proposes issuing a strike against a runner. Does NOT issue anything — only files a proposal a human ' +
      'must approve via the desktop app. On approval it runs the exact same strike system the admin dashboard ' +
      'uses: 1st strike warns, 2nd suspends 7 days, 3rd permanently bans. Never propose a strike you are not ' +
      'prepared to see escalate to suspension or a ban if this is not their first.',
    inputSchema: {
      runner_id: z.number().int().describe('The runner this strike is about.'),
      reason: z.string().max(500).describe('Short reason for the strike.'),
      notes: z.string().max(1000).optional().describe('Additional context for the record.'),
      business_reason: z.string().describe('Why this strike is being proposed — required, shown to the human approving it.'),
    },
  },
  async (args) => {
    try {
      return textResult(await callAiOps('/api/ai-ops/runners/propose-strike', {
        method: 'POST',
        body: JSON.stringify(args),
      }));
    } catch (err) {
      return errorResult(err);
    }
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
