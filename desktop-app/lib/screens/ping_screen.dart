import 'package:flutter/material.dart';
import '../claude_runner.dart';

/// Phase 0's proof-of-concept screen, kept as a standing diagnostic: if
/// this stops working, nothing downstream (Approvals tab included, since
/// agents need the same Claude Code pipeline to propose anything in the
/// first place) can be trusted either.
class PingScreen extends StatefulWidget {
  const PingScreen({super.key});

  @override
  State<PingScreen> createState() => _PingScreenState();
}

class _PingScreenState extends State<PingScreen> {
  bool _running = false;
  ClaudeRunResult? _lastResult;

  Future<void> _runPingCheck() async {
    setState(() => _running = true);

    final result = await ClaudeCodeRunner.runAgent(
      agentName: 'operations-dispatch',
      prompt: "Run the ai_ops_ping tool and report exactly what it returns — "
          "status, timestamp, and agent name.",
      allowedTools: ['mcp__errandher-ai-ops__ai_ops_ping'],
    );

    if (!mounted) return;
    setState(() {
      _running = false;
      _lastResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _lastResult;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diagnostic: shells out to Claude Code, which calls one MCP tool '
            'against the AI-Ops API and reports back. If this fails, nothing '
            'relying on Claude Code can be trusted either.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _running ? null : _runPingCheck,
            icon: _running
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_ping),
            label: Text(_running ? 'Running…' : 'Run Ping Check'),
          ),
          const SizedBox(height: 24),
          if (result != null) ...[
            Card(
              color: result.isError
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.isError ? 'Error' : 'Success',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(result.result),
                    if (result.sessionId != null) ...[
                      const SizedBox(height: 8),
                      Text('Session: ${result.sessionId}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (result.totalCostUsd != null)
                      Text(
                        'Reported cost: \$${result.totalCostUsd!.toStringAsFixed(4)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Raw output (for debugging):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.rawStdout.isEmpty ? '(empty stdout)\n${result.rawStderr}' : result.rawStdout,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
