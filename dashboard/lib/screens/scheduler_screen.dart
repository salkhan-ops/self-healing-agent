import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/responsive.dart';
import '../core/theme.dart';
import '../models/schedule.dart';
import '../providers/scheduler_provider.dart';

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
  bool showCreatePanel = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<SchedulerProvider>().loadSchedules(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SchedulerProvider>();
    final schedules = provider.schedules;
    final activeCount = schedules.where((schedule) => schedule.enabled).length;
    final totalRuns = schedules.fold<int>(
      0,
      (total, schedule) => total + schedule.runCount,
    );
    final nextRun = _nextRun(schedules);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;

        return Padding(
          padding: Responsive.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                onAddPressed: () =>
                    setState(() => showCreatePanel = !showCreatePanel),
                showCreatePanel: showCreatePanel,
              ),
              const SizedBox(height: 18),
              _SummaryRow(
                activeCount: activeCount,
                totalCount: schedules.length,
                nextRun: nextRun,
                totalRuns: totalRuns,
                previewOnly: AppConfig.publicDemoMode,
              ),
              if (AppConfig.publicDemoMode) ...[
                const SizedBox(height: 12),
                const _SchedulerPublicNotice(),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: compact
                    ? ListView(
                        children: [
                          if (showCreatePanel) ...[
                            _ScheduleFormCard(
                              onCreated: () =>
                                  setState(() => showCreatePanel = false),
                            ),
                            const SizedBox(height: 16),
                          ],
                          _ScheduleListCard(schedules: schedules),
                          const SizedBox(height: 16),
                          _CalendarCard(schedules: schedules),
                          const SizedBox(height: 16),
                          _UpcomingRunsCard(schedules: schedules),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              children: [
                                if (showCreatePanel) ...[
                                  SizedBox(
                                    height: 292,
                                    child: _ScheduleFormCard(
                                      onCreated: () => setState(
                                        () => showCreatePanel = false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Expanded(
                                  child: _ScheduleListCard(
                                    schedules: schedules,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: Column(
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _CalendarCard(schedules: schedules),
                                ),
                                const SizedBox(height: 16),
                                Expanded(
                                  flex: 4,
                                  child: _UpcomingRunsCard(
                                    schedules: schedules,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  DateTime? _nextRun(List<Schedule> schedules) {
    final upcoming =
        schedules
            .where((schedule) => schedule.enabled && schedule.nextRun != null)
            .map((schedule) => schedule.nextRun!)
            .toList()
          ..sort();
    return upcoming.isEmpty ? null : upcoming.first;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onAddPressed, required this.showCreatePanel});

  final VoidCallback onAddPressed;
  final bool showCreatePanel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scheduler',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 6),
              Text(
                'Plan recurring self-healing checks without manually babysitting the agents.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        ElevatedButton.icon(
          onPressed: onAddPressed,
          icon: Icon(showCreatePanel ? Icons.close_rounded : Icons.add),
          label: Text(showCreatePanel ? 'Close' : 'Add Schedule'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.activeCount,
    required this.totalCount,
    required this.nextRun,
    required this.totalRuns,
    required this.previewOnly,
  });

  final int activeCount;
  final int totalCount;
  final DateTime? nextRun;
  final int totalRuns;
  final bool previewOnly;

  @override
  Widget build(BuildContext context) {
    final nextText = nextRun == null
        ? 'Manual only'
        : DateFormat('MMM d, HH:mm').format(nextRun!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 760 ? 2 : 4;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: width,
              icon: Icons.power_settings_new_rounded,
              label: 'Active schedules',
              value: '$activeCount / $totalCount',
              color: AppColors.success,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.event_available_rounded,
              label: 'Next run',
              value: nextText,
              color: AppColors.primary,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.repeat_rounded,
              label: 'Mode',
              value: previewOnly
                  ? 'Preview'
                  : activeCount == 0
                  ? 'Manual'
                  : 'Automatic',
              color: AppColors.accent,
            ),
            _SummaryCard(
              width: width,
              icon: Icons.analytics_outlined,
              label: 'Completed runs',
              value: '$totalRuns',
              color: AppColors.warning,
            ),
          ],
        );
      },
    );
  }
}

class _SchedulerPublicNotice extends StatelessWidget {
  const _SchedulerPublicNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Public mode: scheduler planning is visible, but background scheduled runs are preview-only to prevent unexpected API cost. Turn PUBLIC_DEMO_MODE=false for production automation.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 104,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleListCard extends StatelessWidget {
  const _ScheduleListCard({required this.schedules});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Automation queue',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              AppConfig.publicDemoMode
                  ? 'Preview schedules without starting background agent runs in public mode.'
                  : 'Recurring runs use the same self-healing loop as Agent Control, scheduled at safe intervals.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: schedules.isEmpty
                  ? const _EmptyScheduleState()
                  : ListView.separated(
                      itemCount: schedules.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) =>
                          _ScheduleTile(schedule: schedules[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyScheduleState extends StatelessWidget {
  const _EmptyScheduleState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_rounded, size: 46, color: AppColors.primary),
          SizedBox(height: 14),
          Text(
            'No recurring checks yet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          SizedBox(height: 8),
          Text(
            'Add a schedule when you want the agent to evaluate drift and repair prompts on a cadence.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({required this.schedule});

  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<SchedulerProvider>();
    final format = DateFormat('MMM d, HH:mm');

    return Card(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: schedule.enabled
                ? AppColors.success.withValues(alpha: 0.26)
                : AppColors.textSecondary.withValues(alpha: 0.16),
          ),
        ),
        child: Row(
          children: [
            Switch(
              value: schedule.enabled,
              onChanged: (_) => provider.toggleSchedule(schedule.id),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        schedule.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      _StatusPill(enabled: schedule.enabled),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _MetaText(
                        icon: Icons.timer_outlined,
                        text: 'Every ${schedule.intervalMinutes} min',
                      ),
                      _MetaText(
                        icon: Icons.history_rounded,
                        text:
                            'Last ${schedule.lastRun == null ? 'never' : format.format(schedule.lastRun!)}',
                      ),
                      _MetaText(
                        icon: Icons.event_rounded,
                        text:
                            'Next ${schedule.nextRun == null ? 'paused' : format.format(schedule.nextRun!)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${schedule.runCount}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const Text(
                  'runs',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Delete schedule',
              onPressed: () => provider.deleteSchedule(schedule.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        enabled ? 'Active' : 'Paused',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.schedules});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(14, (index) => now.add(Duration(days: index)));
    final scheduledDays = schedules
        .where((schedule) => schedule.enabled && schedule.nextRun != null)
        .map((schedule) => DateUtils.dateOnly(schedule.nextRun!))
        .toSet();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Run calendar',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'A lightweight view of upcoming automation windows.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final hasRun = scheduledDays.contains(
                    DateUtils.dateOnly(day),
                  );
                  final isToday = DateUtils.isSameDay(day, now);
                  return _CalendarDay(
                    day: day,
                    hasRun: hasRun,
                    isToday: isToday,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.hasRun,
    required this.isToday,
  });

  final DateTime day;
  final bool hasRun;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final color = hasRun
        ? AppColors.primary
        : isToday
        ? AppColors.accent
        : AppColors.card;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: hasRun || isToday ? 0.18 : 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: hasRun || isToday ? 0.7 : 0.25),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('E').format(day),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${day.day}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: hasRun ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpcomingRunsCard extends StatelessWidget {
  const _UpcomingRunsCard({required this.schedules});

  final List<Schedule> schedules;

  @override
  Widget build(BuildContext context) {
    final upcoming = _upcomingRuns();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Next 3 scheduled runs',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              AppConfig.publicDemoMode
                  ? 'Preview windows only; public mode will not execute background runs.'
                  : 'Upcoming automation windows based on active intervals.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: upcoming.isEmpty
                  ? const _NoUpcomingRuns()
                  : ListView.separated(
                      itemCount: upcoming.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final run = upcoming[index];
                        return _UpcomingRunTile(
                          index: index + 1,
                          name: run.name,
                          when: run.when,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<({String name, DateTime when})> _upcomingRuns() {
    final runs = <({String name, DateTime when})>[];
    for (final schedule in schedules) {
      if (!schedule.enabled || schedule.nextRun == null) continue;
      var next = schedule.nextRun!;
      for (var count = 0; count < 3; count++) {
        runs.add((name: schedule.name, when: next));
        next = next.add(Duration(minutes: schedule.intervalMinutes));
      }
    }
    runs.sort((a, b) => a.when.compareTo(b.when));
    return runs.take(3).toList();
  }
}

class _UpcomingRunTile extends StatelessWidget {
  const _UpcomingRunTile({
    required this.index,
    required this.name,
    required this.when,
  });

  final int index;
  final String name;
  final DateTime when;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEE, MMM d · HH:mm').format(when),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: AppColors.textSecondary,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _NoUpcomingRuns extends StatelessWidget {
  const _NoUpcomingRuns();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy_rounded,
            color: AppColors.textSecondary,
            size: 34,
          ),
          SizedBox(height: 10),
          Text(
            'No upcoming runs',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'Create or enable a schedule to populate the next run queue.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ScheduleFormCard extends StatefulWidget {
  const _ScheduleFormCard({this.onCreated});

  final VoidCallback? onCreated;

  @override
  State<_ScheduleFormCard> createState() => _ScheduleFormCardState();
}

class _ScheduleFormCardState extends State<_ScheduleFormCard> {
  final nameController = TextEditingController(text: 'Self-healing run');
  final intervalController = TextEditingController(text: '60');
  bool enabled = true;
  bool isSaving = false;

  @override
  void dispose() {
    nameController.dispose();
    intervalController.dispose();
    super.dispose();
  }

  Future<void> _createSchedule() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = nameController.text.trim();
    final interval = int.tryParse(intervalController.text.trim());

    if (name.isEmpty || interval == null || interval < 1) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter a name and interval of at least 1 minute.'),
        ),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      await context.read<SchedulerProvider>().createSchedule(
        name,
        interval,
        enabled: enabled,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Schedule created and enabled.'
                : 'Schedule created in paused mode.',
          ),
        ),
      );
      widget.onCreated?.call();
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create schedule: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final fields = [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: intervalController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Interval minutes',
                ),
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create recurring check',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 14),
                if (compact)
                  Column(
                    children: [
                      fields[0],
                      const SizedBox(height: 12),
                      fields[1],
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: fields[0]),
                      const SizedBox(width: 12),
                      SizedBox(width: 180, child: fields[1]),
                    ],
                  ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: compact ? constraints.maxWidth : 300,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Expanded(
                            child: Text(
                              'Enable immediately',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: isSaving
                                ? null
                                : (value) => setState(() => enabled = value),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: compact ? constraints.maxWidth : 160,
                      child: ElevatedButton.icon(
                        onPressed: isSaving ? null : _createSchedule,
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(isSaving ? 'Creating…' : 'Create'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
