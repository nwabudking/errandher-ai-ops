// ErrandHer AI Operating System — founder's desktop command centre.
//
// NOT YET RUN on a real Flutter install — this sandbox has no Flutter SDK.
// Written against documented Flutter desktop APIs; run `flutter analyze`
// and `flutter run -d windows` (or macos/linux) on your machine as the
// first real test.
import 'package:flutter/material.dart';
import 'screens/ping_screen.dart';
import 'screens/approvals_screen.dart';

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
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (icon: Icons.approval, label: 'Approvals', body: const ApprovalsScreen()),
      (icon: Icons.network_ping, label: 'Diagnostics', body: const PingScreen()),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('ErrandHer — AI Command Centre (${tabs[_tab].label})')),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final t in tabs)
                NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: tabs[_tab].body),
        ],
      ),
    );
  }
}
