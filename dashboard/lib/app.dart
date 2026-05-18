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
import 'screens/post_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
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
          const SizedBox(height: 16),
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
                    'Clears cached chat and investment sessions plus in-memory image cache on this device. Backend data is untouched.',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () {
                      ChatScreen.clearCachedState();
                      InvestmentScreen.clearCachedState();
                      PaintingBinding.instance.imageCache.clear();
                      PaintingBinding.instance.imageCache.clearLiveImages();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Local UI cache cleared.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: const Text('Clear cache'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Posts History',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clears the backend-held Social Media Posts history and resets that agent to prompt v1.',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isClearingRecentPosts
                        ? null
                        : () async {
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => _isClearingRecentPosts = true);
                            try {
                              final apiClient = ApiClient();
                              late final Map<String, dynamic> result;
                              try {
                                result = await apiClient.resetPosts();
                              } finally {
                                apiClient.close();
                              }
                              if (!mounted) return;
                              final failed = result['error'] == true;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    failed
                                        ? 'Could not clear recent posts history.'
                                        : 'Recent posts history cleared.',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _isClearingRecentPosts = false);
                              }
                            }
                          },
                    icon: _isClearingRecentPosts
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.history_toggle_off_rounded),
                    label: Text(
                      _isClearingRecentPosts
                          ? 'Clearing…'
                          : 'Clear recent posts/history',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
