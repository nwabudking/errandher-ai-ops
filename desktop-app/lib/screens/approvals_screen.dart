import 'package:flutter/material.dart';
import '../ai_ops_client.dart';
import '../config.dart';

/// Lists pending AI-proposed actions and lets the founder approve or
/// reject them — calling the Laravel API directly over HTTP. No Claude
/// Code involved in this path at all: the LLM's job ended at "propose,"
/// this screen is where a human decides.
class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  AppConfig? _config;
  AiOpsClient? _client;
  List<ProposedAction>? _actions;
  String? _error;
  bool _loading = true;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final config = await AppConfig.load();
    if (!mounted) return;

    if (config == null) {
      setState(() {
        _loading = false;
        _error = 'No config.json found (or it is missing baseUrl/approvalToken). '
            'Copy config.example.json to config.json in the desktop-app folder '
            'and fill in your AI-Ops base URL and approval token — see the '
            'workspace README.';
      });
      return;
    }

    setState(() {
      _config = config;
      _client = AiOpsClient(config);
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final client = _client;
    if (client == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final actions = await client.listProposedActions(status: 'pending');
      if (!mounted) return;
      setState(() {
        _actions = actions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load proposed actions: $e';
        _loading = false;
      });
    }
  }

  Future<void> _decide(ProposedAction action, bool approve) async {
    final client = _client;
    if (client == null) return;

    setState(() => _busyIds.add(action.id));

    try {
      final result = approve ? await client.approve(action.id) : await client.reject(action.id);
      if (!mounted) return;

      final message = result.status == 'executed'
          ? 'Executed: ${result.executionResult}'
          : result.status == 'approved'
              ? 'Approved but execution failed — see execution_result. Retry from here once fixed.'
              : 'Marked ${result.status}.';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busyIds.remove(action.id));
    }
  }

  Color _riskColor(BuildContext context, String risk) {
    final scheme = Theme.of(context).colorScheme;
    return switch (risk) {
      'high' => scheme.errorContainer,
      'medium' => scheme.tertiaryContainer,
      _ => scheme.secondaryContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _actions == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _init, child: const Text('Retry')),
          ],
        ),
      );
    }

    final actions = _actions ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Text('${actions.length} pending', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refresh,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: actions.isEmpty
              ? const Center(child: Text('Nothing pending approval.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: actions.length,
                  itemBuilder: (context, i) {
                    final a = actions[i];
                    final busy = _busyIds.contains(a.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    a.actionType.replaceAll('_', ' '),
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _riskColor(context, a.riskLevel),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(a.riskLevel, style: const TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('From: ${a.agent} · #${a.id} · ${a.createdAt}',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 12),
                            Text(a.businessReason),
                            if (a.expectedConsequences != null) ...[
                              const SizedBox(height: 8),
                              Text('Expected: ${a.expectedConsequences}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              a.affectedRecords.entries.map((e) => '${e.key}: ${e.value}').join('  ·  '),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: busy ? null : () => _decide(a, false),
                                  child: const Text('Reject'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: busy ? null : () => _decide(a, true),
                                  child: busy
                                      ? const SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Approve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
