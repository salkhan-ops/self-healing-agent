import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/theme.dart';
import '../providers/agent_provider.dart';

class AgentControlScreen extends StatefulWidget {
  const AgentControlScreen({super.key});

  @override
  State<AgentControlScreen> createState() => _AgentControlScreenState();
}

class _AgentControlScreenState extends State<AgentControlScreen> {
  final _apiClient = ApiClient();
  final _faqController = TextEditingController();
  double hallucinationLimit = 0.4;
  double relevanceMinimum = 0.6;
  double latencyMaximum = 3000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AgentProvider>().connectWebSocket();
      context.read<AgentProvider>().loadStatus();
      _loadFaq();
    });
  }

  @override
  void dispose() {
    _apiClient.close();
    _faqController.dispose();
    super.dispose();
  }

  Future<void> _loadFaq() async {
    _faqController.text = await _apiClient.getFaq();
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentProvider>();
    final statusLabel = agent.isRunning
        ? (agent.isStopping ? 'STOPPING' : 'RUNNING')
        : (agent.status['status']?.toString().toUpperCase() ?? 'IDLE');

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
                      onPressed: agent.isRunning ? null : () => agent.runNow(),
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
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _Terminal(lines: agent.liveOutput)),
                      const SizedBox(height: 16),
                      _Thresholds(
                        hallucinationLimit: hallucinationLimit,
                        relevanceMinimum: relevanceMinimum,
                        latencyMaximum: latencyMaximum,
                        onHallucinationChanged: (value) =>
                            setState(() => hallucinationLimit = value),
                        onRelevanceChanged: (value) =>
                            setState(() => relevanceMinimum = value),
                        onLatencyChanged: (value) =>
                            setState(() => latencyMaximum = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FAQ Editor',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: TextField(
                              controller: _faqController,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              style: const TextStyle(fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _apiClient.updateFaq(_faqController.text),
                              icon: const Icon(Icons.save),
                              label: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
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
    return Row(
      children: [
        SizedBox(width: 160, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(
          width: 70,
          child: Text(value.toStringAsFixed(max > 1 ? 0 : 2)),
        ),
      ],
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
