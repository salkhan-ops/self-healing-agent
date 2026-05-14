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
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: _Chart(
                    title: 'Hallucination Rate',
                    color: AppColors.danger,
                    values: points.map((p) => p.hallucination).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _Chart(
                    title: 'Relevance Score',
                    color: AppColors.accent,
                    values: points.map((p) => p.relevance).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _Chart(
                    title: 'Latency',
                    color: AppColors.warning,
                    values: points.map((p) => p.latencyMs).toList(),
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

class _Chart extends StatelessWidget {
  const _Chart({
    required this.title,
    required this.color,
    required this.values,
  });

  final String title;
  final Color color;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final data = values.isEmpty ? [0.0, 0.0] : values;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
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
