import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/metrics_provider.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final periods = const ['hour', 'day', 'week', 'month', 'year'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MetricsProvider>().loadChartData('day');
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MetricsProvider>();
    final points = provider.chartData;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Charts',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: [
              for (final period in periods)
                ButtonSegment(
                  value: period,
                  label: Text(
                    '${period[0].toUpperCase()}${period.substring(1)}',
                  ),
                ),
            ],
            selected: {provider.selectedPeriod},
            onSelectionChanged: (selection) =>
                provider.loadChartData(selection.first),
          ),
          const SizedBox(height: 20),
          _MetricHint(points: points),
          const SizedBox(height: 14),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _Chart(
                    title: 'Hallucination Rate',
                    color: AppColors.danger,
                    values: points.map((p) => p.hallucination).toList(),
                    idealText: 'lower is better',
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _Chart(
                    title: 'Relevance Score',
                    color: AppColors.accent,
                    values: points.map((p) => p.relevance).toList(),
                    idealText: 'higher is better',
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _Chart(
                    title: 'Latency',
                    color: AppColors.warning,
                    values: points.map((p) => p.latencyMs).toList(),
                    idealText: 'milliseconds',
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

class _MetricHint extends StatelessWidget {
  const _MetricHint({required this.points});

  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.28)),
      ),
      child: Text(
        points.isEmpty
            ? 'No saved metric snapshots yet. Run Agent Control to create chart data.'
            : 'Showing ${points.length} saved support-agent snapshots. Flat hallucination/relevance lines mean the evaluator saved identical scores for those runs; latency still changes per run.',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.title,
    required this.color,
    required this.values,
    required this.idealText,
  });

  final String title;
  final Color color;
  final List<double> values;
  final String idealText;

  @override
  Widget build(BuildContext context) {
    final data = values.isEmpty ? [0.0, 0.0] : values;
    final latest = values.isEmpty ? 0.0 : values.last;
    final isFlat =
        values.length > 1 && values.every((value) => value == values.first);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${latest.toStringAsFixed(title == 'Latency' ? 0 : 2)} · $idealText',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (isFlat) ...[
              const SizedBox(height: 6),
              const Text(
                'Flat line: no score movement in the selected period.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: AppColors.card),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppColors.surface,
                      getTooltipItems: (spots) => spots
                          .map(
                            (spot) => LineTooltipItem(
                              spot.y.toStringAsFixed(3),
                              const TextStyle(color: AppColors.textPrimary),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < data.length; i++)
                          FlSpot(i.toDouble(), data[i]),
                      ],
                      color: color,
                      barWidth: 3,
                      isCurved: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.3),
                            color.withValues(alpha: 0.02),
                          ],
                        ),
                      ),
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
}
