import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/metric.dart';
import '../providers/agent_provider.dart';
import '../providers/metrics_provider.dart';
import '../providers/reports_provider.dart';
import '../widgets/metric_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MetricsProvider>().loadSummary();
      context.read<MetricsProvider>().loadChartData('day');
      context.read<ReportsProvider>().loadReports();
      context.read<AgentProvider>().connectWebSocket();
      context.read<AgentProvider>().loadStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.watch<MetricsProvider>();
    final reports = context.watch<ReportsProvider>().reports.take(5).toList();
    final agent = context.watch<AgentProvider>();
    final summary = metrics.summary;
    final points = metrics.chartData;

    return _Page(
      title: 'Dashboard',
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'Health Score',
                    value: (summary?.healthScore ?? 0).toStringAsFixed(0),
                    trend: summary?.healthScore ?? 0,
                    values: points
                        .map((point) => point.improvementPercent)
                        .toList(),
                    good: (summary?.healthScore ?? 0) >= 70,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: MetricCard(
                    title: 'Hallucination',
                    value: (summary?.avgHallucination ?? 0).toStringAsFixed(2),
                    trend: -12,
                    values: points.map((point) => point.hallucination).toList(),
                    good: (summary?.avgHallucination ?? 0) <= 0.4,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: MetricCard(
                    title: 'Relevance',
                    value: (summary?.avgRelevance ?? 0).toStringAsFixed(2),
                    trend: 8,
                    values: points.map((point) => point.relevance).toList(),
                    good: (summary?.avgRelevance ?? 0) >= 0.6,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: MetricCard(
                    title: 'Latency',
                    value: (summary?.avgLatency ?? 0).toStringAsFixed(0),
                    suffix: 'ms',
                    trend: -5,
                    values: points.map((point) => point.latencyMs).toList(),
                    good: (summary?.avgLatency ?? 0) <= 3000,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _LinePanel(points: points)),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _Panel(
                    title: 'Last Reports',
                    child: ListView.separated(
                      itemCount: reports.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final report = reports[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            report.problem,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            report.rootCause,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            '${report.improvementPercent.toStringAsFixed(0)}%',
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Panel(
                    title: 'Live Output',
                    child: ListView(
                      children: agent.liveOutput.reversed
                          .take(40)
                          .map(
                            (line) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                line,
                                style: const TextStyle(color: AppColors.accent),
                              ),
                            ),
                          )
                          .toList(),
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

class _LinePanel extends StatelessWidget {
  const _LinePanel({required this.points});

  final List<MetricPoint> points;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Last 24 Hours',
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
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 34),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            _line(
              points.map((point) => point.relevance).toList(),
              AppColors.accent,
            ),
            _line(
              points.map((point) => point.hallucination).toList(),
              AppColors.danger,
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _line(List<double> values, Color color) {
    final data = values.isEmpty ? [0.0, 0.0] : values;
    return LineChartBarData(
      spots: [
        for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i]),
      ],
      color: color,
      barWidth: 3,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.12),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          Expanded(child: child),
        ],
      ),
    );
  }
}
