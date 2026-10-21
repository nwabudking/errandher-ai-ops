// ErrandHer AI Operating System — founder's desktop command centre.
// Phase 0 skeleton: one button, one real round trip, nothing else yet.
//
// NOT YET RUN OR ANALYZED — this sandbox has no Flutter SDK. Written
// against documented Flutter desktop + dart:io Process APIs; run
// `flutter analyze` and `flutter run -d windows` (or macos/linux) on your
// machine as the first real test, before trusting this beyond that.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const ErrandHerAiOpsApp());
}

class ErrandHerAiOpsApp extends StatelessWidget {
  const ErrandHerAiOpsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ErrandHer — AI Command Centre',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFF97316), // ErrandHer brand orange
        useMaterial3: true,
      ),
      home: const PingScreen(),
    );
  }
}

/// Result of one `claude -p ... --output-format json` invocation, parsed
/// from the fields we confirmed by hand on 2026-10-21 (see
/// docs/ai-operating-system/04-open-decisions.md in the main repo).
class ClaudeRunResult {
  final bool isError;
  final String result;
  final String? sessionId;
  final double? totalCostUsd;
  final String rawStdout;
  final String rawStderr;

  ClaudeRunResult({
    required this.isError,
    required this.result,
    required this.sessionId,
    required this.totalCostUsd,
    required this.rawStdout,
    required this.rawStderr,
  });
}

/// Shells out to the Claude Code CLI, pointed at the agent workspace
/// (this repo's root — one level up from desktop-app/ in development).
/// A real build should make the workspace path configurable rather than
/// assuming this relative layout; left as a TODO for Phase 1.
class ClaudeCodeRunner {
  static Future<ClaudeRunResult> runAgent({
    required String agentName,
    required String prompt,
    required List<String> allowedTools,
  }) async {
    final workspaceDir = Directory.current.parent.path; // TODO: make configurable, see class doc

    final process = await Process.run(
      'claude',
      [
        '-p', prompt,
        '--agent', agentName,
        '--allowedTools', allowedTools.join(','),
        '--permission-prompts', 'none',
        '--model', 'sonnet', // explicit — a bare call defaults to Opus, confirmed 2026-10-21
        '--output-format', 'json',
      ],
      workingDirectory: workspaceDir,
      runInShell: true,
    );

    final stdout = process.stdout.toString();
    final stderr = process.stderr.toString();

    if (process.exitCode != 0 && stdout.trim().isEmpty) {
      // Claude Code not installed / not on PATH / crashed before producing
      // any JSON at all — distinct from an in-conversation error, which
      // still returns valid JSON with is_error:true.
      return ClaudeRunResult(
        isError: true,
        result: 'Claude Code did not run (exit code ${process.exitCode}). '
            'Is it installed and on your PATH? Is this machine logged in '
            '(run `claude` once interactively if unsure)?',
        sessionId: null,
        totalCostUsd: null,
        rawStdout: stdout,
        rawStderr: stderr,
      );
    }

    try {
      final json = jsonDecode(stdout) as Map<String, dynamic>;
      return ClaudeRunResult(
        isError: json['is_error'] as bool? ?? true,
        result: json['result']?.toString() ?? '(no result field)',
        sessionId: json['session_id'] as String?,
        totalCostUsd: (json['total_cost_usd'] as num?)?.toDouble(),
        rawStdout: stdout,
        rawStderr: stderr,
      );
    } catch (e) {
      return ClaudeRunResult(
        isError: true,
        result: 'Could not parse Claude Code output as JSON: $e',
        sessionId: null,
        totalCostUsd: null,
        rawStdout: stdout,
        rawStderr: stderr,
      );
    }
  }
}

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

    return Scaffold(
      appBar: AppBar(title: const Text('ErrandHer — AI Command Centre (Phase 0)')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Phase 0 proof of concept: this button shells out to Claude Code, '
              'which calls one MCP tool against the AI-Ops API and reports back.',
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
      ),
    );
  }
}
