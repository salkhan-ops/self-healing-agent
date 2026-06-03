import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../core/theme.dart';
import '../core/websocket.dart';
import '../providers/metrics_provider.dart';

class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key});

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  final periods = const ['hour', 'day', 'week', 'month', 'year'];
  late final WebSocketClient webSocketClient;

  @override
  void initState() {
    super.initState();
    webSocketClient = WebSocketClient()..connect();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MetricsProvider>();
      provider.listenForUpdates(webSocketClient.messageStream);
      provider.loadChartData('day');
    });
  }

  @override
  void dispose() {
    webSocketClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MetricsProvider>();
    final points = provider.chartData;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        return Padding(
          padding: Responsive.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Charts',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
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
              ),
              const SizedBox(height: 20),
              _MetricHint(points: points),
              const SizedBox(height: 14),
              Expanded(
                child: compact
                    ? ListView(
                        children: [
                          SizedBox(
                            height: 240,
                            child: _Chart(
                              title: 'Hallucination Rate',
                              color: AppColors.danger,
                              values: points
                                  .map((p) => p.hallucination)
                                  .toList(),
                              idealText: 'lower is better',
                              threshold: 0.40,
                              thresholdLabel: 'risk line',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 240,
                            child: _Chart(
                              title: 'Relevance Score',
                              color: AppColors.accent,
                              values: points.map((p) => p.relevance).toList(),
                              idealText: 'higher is better',
                              threshold: 0.80,
                              thresholdLabel: 'target',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 240,
                            child: _Chart(
                              title: 'Latency',
                              color: AppColors.warning,
                              values: points.map((p) => p.latencyMs).toList(),
                              idealText: 'milliseconds',
                              isLatency: true,
                              threshold: 3000,
                              thresholdLabel: 'limit',
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: _Chart(
                              title: 'Hallucination Rate',
                              color: AppColors.danger,
                              values: points
                                  .map((p) => p.hallucination)
                                  .toList(),
                              idealText: 'lower is better',
                              threshold: 0.40,
                              thresholdLabel: 'risk line',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _Chart(
                              title: 'Relevance Score',
                              color: AppColors.accent,
                              values: points.map((p) => p.relevance).toList(),
                              idealText: 'higher is better',
                              threshold: 0.80,
                              thresholdLabel: 'target',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _Chart(
                              title: 'Latency',
                              color: AppColors.warning,
                              values: points.map((p) => p.latencyMs).toList(),
                              idealText: 'milliseconds',
                              isLatency: true,
                              threshold: 3000,
                              thresholdLabel: 'limit',
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
            : 'Showing ${points.length} saved metric snapshots from backend runs.',
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
    this.isLatency = false,
    this.threshold,
    this.thresholdLabel,
  });

  final String title;
  final Color color;
  final List<double> values;
  final String idealText;
  final bool isLatency;
  final double? threshold;
  final String? thresholdLabel;

  @override
  Widget build(BuildContext context) {
    final data = values.isEmpty ? [0.0, 0.0] : values;
    final latest = values.isEmpty ? 0.0 : values.last;
    final isFlat =
        values.length > 1 && values.every((value) => value == values.first);
    final maxValue = data.fold<double>(0, math.max);
    final double maxY = isLatency
        ? math
              .max(
                threshold ?? 0.0,
                maxValue <= 0 ? 1000 : (maxValue * 1.18).ceilToDouble(),
              )
              .toDouble()
        : 1.0;
    final valueText = isLatency
        ? '${latest.toStringAsFixed(0)}ms'
        : latest.toStringAsFixed(2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$valueText · $idealText',
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
            const SizedBox(height: 8),
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: isLatency ? maxY / 3 : 0.25,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: AppColors.textSecondary.withValues(alpha: 0.14),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                        interval: isLatency ? maxY / 3 : 0.25,
                        getTitlesWidget: (value, meta) => Text(
                          isLatency
                              ? value.toStringAsFixed(0)
                              : value.toStringAsFixed(2),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  extraLinesData: threshold == null
                      ? const ExtraLinesData()
                      : ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: threshold!.clamp(0, maxY).toDouble(),
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.35,
                              ),
                              strokeWidth: 1,
                              dashArray: [6, 6],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.topRight,
                                labelResolver: (_) => thresholdLabel ?? '',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
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
                      barWidth: 3.5,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      dotData: FlDotData(
                        show: data.length <= 12,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: color,
                              strokeWidth: 2,
                              strokeColor: Theme.of(context).cardColor,
                            ),
                      ),
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
