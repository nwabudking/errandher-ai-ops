#!/usr/bin/env node
// ErrandHer AI-Ops MCP server.
//
// Wraps the Laravel AI-Ops API (routes/ai-ops.php, app/Http/Controllers/
// Api/AiOps/) as MCP tools Claude Code can call directly. Holds the
// AI-Ops credential (AI_OPS_TOKEN) — the desktop app and the agent's
// own prompt never see it.
//
// Phase 0 (ping) is proven end-to-end against a real database and live
// HTTP server. Phase 1's five tools below are the same — tested for real,
// not just written, including a real bug (SupportTicket's priority enum)
// caught and fixed during that testing. This file itself has still not
// been run — no Node runtime in the sandbox that wrote it was ever wired
// to a live Laravel server. First real test happens on your machine.
//
// Deliberately NOT here: approve/reject for proposed actions. Those are
// desktop-app-only, called directly against the Laravel API — an agent
// must never be able to approve its own proposal.
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

const transport = new StdioServerTransport();
await server.connect(transport);
