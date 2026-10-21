import 'dart:convert';
import 'dart:io';

/// Loads desktop-app/config.json — the desktop app's OWN credential
/// (proposed-actions.manage ability), separate from the MCP server's
/// agent token in mcp-server/.env. See CLAUDE.md in the workspace root:
/// "Two separate credentials — don't conflate them."
///
/// Never committed — see .gitignore. Copy config.example.json to get
/// started.
class AppConfig {
  final String baseUrl;
  final String approvalToken;

  AppConfig({required this.baseUrl, required this.approvalToken});

  static String get _configPath =>
      '${Directory.current.path}${Platform.pathSeparator}config.json';

  static Future<AppConfig?> load() async {
    final file = File(_configPath);
    if (!await file.exists()) return null;

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final baseUrl = json['baseUrl'] as String?;
      final token = json['approvalToken'] as String?;
      if (baseUrl == null || token == null || baseUrl.isEmpty || token.isEmpty) {
        return null;
      }
      return AppConfig(baseUrl: baseUrl, approvalToken: token);
    } catch (_) {
      return null;
    }
  }
}
