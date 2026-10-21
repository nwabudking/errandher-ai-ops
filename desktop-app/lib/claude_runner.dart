import 'dart:convert';
import 'dart:io';

/// Result of one `claude -p ... --output-format json` invocation, parsed
/// from the fields confirmed by hand on 2026-10-21 (see
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
/// assuming this relative layout; left as a TODO for a later phase.
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
