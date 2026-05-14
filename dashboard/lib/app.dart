import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'providers/agent_provider.dart';
import 'providers/metrics_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/scheduler_provider.dart';
import 'screens/agent_control_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/investment_screen.dart';
import 'screens/report_detail_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/scheduler_screen.dart';
import 'widgets/sidebar.dart';

class SelfHealingDashboardApp extends StatelessWidget {
  const SelfHealingDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MetricsProvider()),
        ChangeNotifierProvider(create: (_) => ReportsProvider()),
        ChangeNotifierProvider(create: (_) => SchedulerProvider()),
        ChangeNotifierProvider(create: (_) => AgentProvider()),
      ],
      child: MaterialApp.router(
        title: 'Self-Healing Agent Dashboard',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: _router,
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return Scaffold(
          body: Row(
            children: [
              const Sidebar(),
              Expanded(child: child),
            ],
          ),
        );
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
        GoRoute(
          path: '/investment',
          builder: (context, state) => const InvestmentScreen(),
        ),
        GoRoute(
          path: '/charts',
          builder: (context, state) => const ChartsScreen(),
        ),
        GoRoute(
          path: '/reports',
          builder: (context, state) => const ReportsScreen(),
        ),
        GoRoute(
          path: '/reports/:id',
          builder: (context, state) {
            final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
            return ReportDetailScreen(id: id);
          },
        ),
        GoRoute(
          path: '/scheduler',
          builder: (context, state) => const SchedulerScreen(),
        ),
        GoRoute(
          path: '/agent',
          builder: (context, state) => const AgentControlScreen(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const _SettingsScreen(),
        ),
      ],
    ),
  ],
);

class _SettingsScreen extends StatelessWidget {
  const _SettingsScreen();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 20),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'API http://localhost:8000  •  WebSocket ws://localhost:8000/ws',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
