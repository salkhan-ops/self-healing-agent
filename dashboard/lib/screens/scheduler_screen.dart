import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/schedule.dart';
import '../providers/scheduler_provider.dart';

class SchedulerScreen extends StatefulWidget {
  const SchedulerScreen({super.key});

  @override
  State<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends State<SchedulerScreen> {
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Scheduler',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showAddSchedule(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Schedule'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: provider.schedules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _ScheduleTile(schedule: provider.schedules[index]),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSchedule(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      isScrollControlled: true,
      builder: (_) => const _ScheduleForm(),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        title: Text(
          schedule.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Last ${schedule.lastRun == null ? 'never' : format.format(schedule.lastRun!)}  •  Next ${schedule.nextRun == null ? 'paused' : format.format(schedule.nextRun!)}',
          style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
        ),
        leading: Switch(
          value: schedule.enabled,
          onChanged: (_) => provider.toggleSchedule(schedule.id),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('${schedule.runCount} runs'),
            ),
            IconButton(
              onPressed: () => provider.deleteSchedule(schedule.id),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm();

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  final nameController = TextEditingController(text: 'Self-healing run');
  final intervalController = TextEditingController(text: '60');
  bool enabled = true;

  @override
  void dispose() {
    nameController.dispose();
    intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: intervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Interval minutes'),
          ),
          SwitchListTile(
            value: enabled,
            onChanged: (value) => setState(() => enabled = value),
            title: const Text('Enable immediately'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final interval = int.tryParse(intervalController.text) ?? 60;
                await context.read<SchedulerProvider>().createSchedule(
                  nameController.text,
                  interval,
                  enabled: enabled,
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ),
        ],
      ),
    );
  }
}
