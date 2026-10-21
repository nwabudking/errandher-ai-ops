import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ProposedAction {
  final int id;
  final String agent;
  final String actionType;
  final Map<String, dynamic> affectedRecords;
  final String businessReason;
  final String? expectedConsequences;
  final double? financialAmount;
  final String riskLevel;
  final String status;
  final Map<String, dynamic>? executionResult;
  final String createdAt;

  ProposedAction({
    required this.id,
    required this.agent,
    required this.actionType,
    required this.affectedRecords,
    required this.businessReason,
    required this.expectedConsequences,
    required this.financialAmount,
    required this.riskLevel,
    required this.status,
    required this.executionResult,
    required this.createdAt,
  });

  factory ProposedAction.fromJson(Map<String, dynamic> j) => ProposedAction(
        id: j['id'] as int,
        agent: j['agent'] as String? ?? '—',
        actionType: j['action_type'] as String? ?? '—',
        affectedRecords: (j['affected_records'] as Map?)?.cast<String, dynamic>() ?? {},
        businessReason: j['business_reason'] as String? ?? '',
        expectedConsequences: j['expected_consequences'] as String?,
        financialAmount: (j['financial_amount'] as num?)?.toDouble(),
        riskLevel: j['risk_level'] as String? ?? 'low',
        status: j['status'] as String? ?? 'pending',
        executionResult: (j['execution_result'] as Map?)?.cast<String, dynamic>(),
        createdAt: j['created_at'] as String? ?? '',
      );
}

class AiOpsApiException implements Exception {
  final String message;
  AiOpsApiException(this.message);
  @override
  String toString() => message;
}

class AiOpsClient {
  final AppConfig config;
  AiOpsClient(this.config);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.approvalToken}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${config.baseUrl}$path').replace(queryParameters: query);

  Future<List<ProposedAction>> listProposedActions({String status = 'pending'}) async {
    final res = await http.get(_uri('/api/ai-ops/proposed-actions', {'status': status}), headers: _headers);
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['proposed_actions'] as List)
        .map((e) => ProposedAction.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ProposedAction> approve(int id) async {
    final res = await http.post(_uri('/api/ai-ops/proposed-actions/$id/approve'), headers: _headers);
    // 500 here still carries a valid proposed_action payload (execution
    // failed but the row is safely in 'approved', retryable) — surface it
    // as data, not just an exception, so the UI can show what happened.
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200 && res.statusCode != 500) {
      throw AiOpsApiException('HTTP ${res.statusCode}: ${res.body}');
    }
    return ProposedAction.fromJson(body['proposed_action'] as Map<String, dynamic>);
  }

  Future<ProposedAction> reject(int id) async {
    final res = await http.post(_uri('/api/ai-ops/proposed-actions/$id/reject'), headers: _headers);
    _checkOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ProposedAction.fromJson(body['proposed_action'] as Map<String, dynamic>);
  }

  void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiOpsApiException('HTTP ${res.statusCode}: ${res.body}');
    }
  }
}
