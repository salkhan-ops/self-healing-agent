import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.trend,
    required this.values,
    required this.good,
    this.suffix = '',
  });

  final String title;
  final String value;
  final double trend;
  final List<double> values;
  final bool good;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.success : AppColors.danger;
    final arrow = trend >= 0 ? '↑' : '↓';

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 145;

          return Padding(
            padding: EdgeInsets.all(compact ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        '$value$suffix',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 22 : 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '$arrow ${trend.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 46,
                    child: _Sparkline(values: values, color: color),
                  ),
                ] else ...[
                  const Spacer(),
                  Container(height: 3, color: color.withValues(alpha: 0.8)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final chartValues = values.isEmpty ? [0.0, 0.0] : values.take(7).toList();

    return LineChart(
      LineChartData(
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        minY: chartValues.reduce((a, b) => a < b ? a : b),
        maxY: chartValues.reduce((a, b) => a > b ? a : b) + 0.01,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var index = 0; index < chartValues.length; index++)
                FlSpot(index.toDouble(), chartValues[index]),
            ],
            color: color,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}
