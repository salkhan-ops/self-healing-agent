import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/api_client.dart';
import 'core/theme.dart';
import 'providers/agent_provider.dart';
import 'providers/metrics_provider.dart';
import 'providers/reports_provider.dart';
import 'providers/scheduler_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/agent_control_screen.dart';
import 'screens/charts_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/investment_screen.dart';
import 'screens/phoenix_traces_screen.dart';
import 'screens/post_screen.dart';
import 'screens/report_detail_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/resources_screen.dart';
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
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Self-Healing Agent Dashboard',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.mode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final path = state.uri.path.toLowerCase();
    if (path == '/login' ||
        path == '/signin' ||
        path == '/sign-in' ||
        path == '/auth' ||
        path == '/auth/callback') {
      return '/';
    }
    return null;
  },
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return _ResponsiveShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
        GoRoute(
          path: '/posts',
          builder: (context, state) => const PostScreen(),
        ),
        GoRoute(
          path: '/investment',
          builder: (context, state) => const InvestmentScreen(),
        ),
        GoRoute(
          path: '/charts',
          builder: (context, state) => const ChartsScreen(),
        ),
        GoRoute(
          path: '/phoenix',
          builder: (context, state) => const PhoenixTracesScreen(),
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
          path: '/resources',
          builder: (context, state) => const ResourcesScreen(),
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

class _ResponsiveShell extends StatefulWidget {
  const _ResponsiveShell({required this.child});

  final Widget child;

  @override
  State<_ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<_ResponsiveShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Treat narrow desktop windows and tablets like compact layouts too.
        // 768px was technically "mobile", but it left cramped screens with a
        // permanent sidebar and made the app feel non-responsive in practice.
        final isMobile = constraints.maxWidth < 1024;

        return Scaffold(
          key: _scaffoldKey,
          drawer: isMobile ? const Drawer(child: Sidebar()) : null,
          body: isMobile
              ? Column(
                  children: [
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                            icon: const Icon(Icons.menu_rounded),
                            tooltip: 'Open menu',
                          ),
                        ),
                      ),
                    ),
                    Expanded(child: widget.child),
                  ],
                )
              : Row(
                  children: [
                    const Sidebar(),
                    Expanded(child: widget.child),
                  ],
                ),
        );
      },
    );
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen();

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  bool _isClearingRecentPosts = false;
  bool _isClearingChat = false;
  bool _isClearingInvestment = false;
  bool _isClearingLocalCache = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'API ${AppConfig.apiBaseUrl}  •  WebSocket ${AppConfig.wsUrl}',
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local UI Cache',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Clears cached sessions and image cache on this device. Use the history reset controls below to clear backend-held agent history.',
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _isClearingLocalCache
                          ? null
                          : () {
                              setState(() => _isClearingLocalCache = true);
                              ChatScreen.clearCachedState();
                              InvestmentScreen.clearCachedState();
                              PaintingBinding.instance.imageCache.clear();
                              PaintingBinding.instance.imageCache
                                  .clearLiveImages();
                              setState(() => _isClearingLocalCache = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Local UI cache cleared.'),
                                ),
                              );
                            },
                      icon: _isClearingLocalCache
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_sweep_rounded),
                      label: Text(
                        _isClearingLocalCache ? 'Clearing…' : 'Clear cache',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reset Demo State',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use these controls when you want a clean prompt v1 demo for a specific agent. They clear backend-held history for that surface.',
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ResetButton(
                          isBusy: _isClearingChat,
                          icon: Icons.chat_bubble_outline_rounded,
                          loadingLabel: 'Clearing chat…',
                          label: 'Customer support',
                          onPressed: () => _resetBackendState(
                            label: 'Customer support history',
                            action: (client) => client.resetChat(),
                            setBusy: (busy) =>
                                setState(() => _isClearingChat = busy),
                            afterSuccess: ChatScreen.clearCachedState,
                          ),
                        ),
                        _ResetButton(
                          isBusy: _isClearingInvestment,
                          icon: Icons.query_stats_rounded,
                          loadingLabel: 'Clearing investment…',
                          label: 'Investment analyst',
                          onPressed: () => _resetBackendState(
                            label: 'Investment history',
                            action: (client) => client.resetInvestment(),
                            setBusy: (busy) =>
                                setState(() => _isClearingInvestment = busy),
                            afterSuccess: InvestmentScreen.clearCachedState,
                          ),
                        ),
                        _ResetButton(
                          isBusy: _isClearingRecentPosts,
                          icon: Icons.history_toggle_off_rounded,
                          loadingLabel: 'Clearing posts…',
                          label: 'Social media posts',
                          onPressed: () => _resetBackendState(
                            label: 'Recent posts history',
                            action: (client) => client.resetPosts(),
                            setBusy: (busy) =>
                                setState(() => _isClearingRecentPosts = busy),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetBackendState({
    required String label,
    required Future<Map<String, dynamic>> Function(ApiClient client) action,
    required ValueChanged<bool> setBusy,
    VoidCallback? afterSuccess,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setBusy(true);
    try {
      final apiClient = ApiClient();
      late final Map<String, dynamic> result;
      try {
        result = await action(apiClient);
      } finally {
        apiClient.close();
      }
      if (!mounted) return;
      final failed = result['error'] == true;
      if (!failed) afterSuccess?.call();
      messenger.showSnackBar(
        SnackBar(
          content: Text(failed ? 'Could not clear $label.' : '$label cleared.'),
        ),
      );
    } finally {
      if (mounted) setBusy(false);
    }
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({
    required this.isBusy,
    required this.icon,
    required this.loadingLabel,
    required this.label,
    required this.onPressed,
  });

  final bool isBusy;
  final IconData icon;
  final String loadingLabel;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isBusy ? null : onPressed,
      icon: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(isBusy ? loadingLabel : label),
    );
  }
}
