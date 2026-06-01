import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/theme.dart';
import '../providers/agent_provider.dart';

class AgentControlScreen extends StatefulWidget {
  const AgentControlScreen({super.key});

  @override
  State<AgentControlScreen> createState() => _AgentControlScreenState();
}

class _AgentControlScreenState extends State<AgentControlScreen> {
  double hallucinationLimit = 0.2;
  double relevanceMinimum = 0.6;
  double latencyMaximum = 3000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AgentProvider>().connectWebSocket();
      context.read<AgentProvider>().loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentProvider>();
    final statusLabel = agent.isRunning
        ? (agent.isStopping ? 'STOPPING' : 'RUNNING')
        : (agent.status['status']?.toString().toUpperCase() ?? 'IDLE');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final lowerContent = isMobile
            ? ListView(
                children: [
                  SizedBox(
                    height: 240,
                    child: _Terminal(lines: agent.liveOutput),
                  ),
                  const SizedBox(height: 16),
                  _thresholds(),
                  const SizedBox(height: 16),
                  _learningLoopCard(agent),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _Terminal(lines: agent.liveOutput)),
                        const SizedBox(height: 16),
                        _thresholds(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _learningLoopCard(agent)),
                ],
              );

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Agent Control',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: agent.isRunning
                              ? null
                              : () async {
                                  final shouldRun = await _confirmFullLoopRun(
                                    context,
                                  );
                                  if (!shouldRun || !context.mounted) {
                                    return;
                                  }

                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final result = await agent.runNow();
                                  if (result['status'] == 'disabled') {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          result['message']?.toString() ??
                                              'Public demo limit reached.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Run Agent Now'),
                          style: ElevatedButton.styleFrom(
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 34,
                              vertical: 20,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: agent.isRunning && !agent.isStopping
                              ? () => agent.stopNow()
                              : null,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(
                            agent.isStopping ? 'Stopping...' : 'Stop Agent',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _StatusBadge(label: statusLabel, running: agent.isRunning),
                    if (AppConfig.publicDemoMode) ...[
                      const SizedBox(height: 12),
                      const _PublicDemoAgentNotice(),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Expanded(child: lowerContent),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirmFullLoopRun(BuildContext context) async {
    if (!AppConfig.publicDemoMode) {
      return true;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Run full self-healing loop?'),
        content: const Text(
          'This starts the full multi-agent loop: chat, posts, investment, evaluation, prompt healing, and verification. It may take 1–2 minutes. Public demo mode allows three full runs per browser, enough to judge each use case once.\n\nUse one demo run now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Run full loop'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Widget _thresholds() => _Thresholds(
    hallucinationLimit: hallucinationLimit,
    relevanceMinimum: relevanceMinimum,
    latencyMaximum: latencyMaximum,
    onHallucinationChanged: (value) =>
        setState(() => hallucinationLimit = value),
    onRelevanceChanged: (value) => setState(() => relevanceMinimum = value),
    onLatencyChanged: (value) => setState(() => latencyMaximum = value),
  );

  Widget _learningLoopCard(AgentProvider agent) {
    final status = agent.status;
    final currentRunId = status['current_run_id']?.toString();
    final lastRun = status['last_run']?.toString();
    final nextRun = status['next_run']?.toString();
    final lastError = status['last_error']?.toString();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Learning Loop',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              'The agent observes recent behavior, diagnoses drift, updates prompts, and verifies whether the change actually improved outcomes.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
            _LoopStat(
              label: 'Current state',
              value: agent.isRunning
                  ? (agent.isStopping ? 'Stopping safely' : 'Learning now')
                  : 'Watching',
            ),
            _LoopStat(
              label: 'Current run',
              value: currentRunId == null || currentRunId.isEmpty
                  ? 'No active run'
                  : currentRunId,
            ),
            _LoopStat(
              label: 'Last completed run',
              value: lastRun == null || lastRun.isEmpty
                  ? 'Not yet recorded'
                  : lastRun,
            ),
            _LoopStat(
              label: 'Next scheduled run',
              value: nextRun == null || nextRun.isEmpty
                  ? 'Manual only'
                  : nextRun,
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: lastError == null || lastError.isEmpty
                    ? AppColors.surface
                    : AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: lastError == null || lastError.isEmpty
                      ? AppColors.card
                      : AppColors.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                lastError == null || lastError.isEmpty
                    ? 'No loop errors reported.'
                    : 'Last error: $lastError',
                style: TextStyle(
                  color: lastError == null || lastError.isEmpty
                      ? AppColors.textSecondary
                      : AppColors.danger,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicDemoAgentNotice extends StatelessWidget {
  const _PublicDemoAgentNotice();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: AppColors.warning,
              size: 18,
            ),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Public demo mode: three full loops per browser, plus lightweight feature-tab testing.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoopStat extends StatelessWidget {
  const _LoopStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Terminal extends StatelessWidget {
  const _Terminal({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView(
        children: lines.isEmpty
            ? [
                const Text(
                  'waiting for agent output...',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontFamily: 'monospace',
                  ),
                ),
              ]
            : lines
                  .map(
                    (line) => Text(
                      line,
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontFamily: 'monospace',
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }
}

class _Thresholds extends StatelessWidget {
  const _Thresholds({
    required this.hallucinationLimit,
    required this.relevanceMinimum,
    required this.latencyMaximum,
    required this.onHallucinationChanged,
    required this.onRelevanceChanged,
    required this.onLatencyChanged,
  });

  final double hallucinationLimit;
  final double relevanceMinimum;
  final double latencyMaximum;
  final ValueChanged<double> onHallucinationChanged;
  final ValueChanged<double> onRelevanceChanged;
  final ValueChanged<double> onLatencyChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SliderRow(
              label: 'Hallucination limit',
              value: hallucinationLimit,
              min: 0,
              max: 1,
              onChanged: onHallucinationChanged,
            ),
            _SliderRow(
              label: 'Relevance minimum',
              value: relevanceMinimum,
              min: 0,
              max: 1,
              onChanged: onRelevanceChanged,
            ),
            _SliderRow(
              label: 'Latency maximum',
              value: latencyMaximum,
              min: 0,
              max: 10000,
              onChanged: onLatencyChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: value,
                      min: min,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ),
                  Text(value.toStringAsFixed(max > 1 ? 0 : 2)),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(width: 160, child: Text(label)),
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 70,
              child: Text(value.toStringAsFixed(max > 1 ? 0 : 2)),
            ),
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.running});

  final String label;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final color = running ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}
