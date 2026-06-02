import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/theme_provider.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key});

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  final _apiClient = ApiClient();
  Timer? _timer;
  bool _backendOnline = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _apiClient.close();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final status = await _apiClient.getAgentStatus();
    if (!mounted) {
      return;
    }
    setState(() => _backendOnline = status['error'] != true);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final themeProvider = context.watch<ThemeProvider>();

    return Container(
      width: 240,
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: ListView(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => context.go('/'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_fix_high, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Self-Healing Agent',
                      maxLines: 2,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          _SidebarItem(
            icon: Icons.home_rounded,
            label: 'Dashboard',
            path: '/',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.edit_note_rounded,
            label: 'Social Media Posts',
            path: '/posts',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.query_stats,
            label: 'Investment Analyst',
            path: '/investment',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.chat_bubble_outline,
            label: 'Customer Support',
            path: '/chat',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.show_chart_rounded,
            label: 'Charts',
            path: '/charts',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.hub_rounded,
            label: 'Phoenix Traces',
            path: '/phoenix',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.description_rounded,
            label: 'Reports',
            path: '/reports',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.schedule_rounded,
            label: 'Scheduler',
            path: '/scheduler',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.tune_rounded,
            label: 'Agent Control',
            path: '/agent',
            activePath: location,
          ),
          _SidebarItem(
            icon: Icons.settings_rounded,
            label: 'Settings',
            path: '/settings',
            activePath: location,
          ),
          const SizedBox(height: 12),
          _ThemeToggle(
            isDark: themeProvider.isDark,
            onPressed: themeProvider.toggleTheme,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _backendOnline
                        ? AppColors.success
                        : AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _backendOnline ? 'Backend online' : 'Backend offline',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.isDark, required this.onPressed});

  final bool isDark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
      label: Text(isDark ? 'Light mode' : 'Dark mode'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.55)),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.activePath,
  });

  final IconData icon;
  final String label;
  final String path;
  final String activePath;

  @override
  Widget build(BuildContext context) {
    final active = path == '/'
        ? activePath == '/'
        : activePath.startsWith(path);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(path),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.primary : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: active
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).textTheme.bodySmall?.color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
