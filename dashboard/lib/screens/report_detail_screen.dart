import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/reports_provider.dart';

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.id});

  final int id;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ReportsProvider>().loadReport(widget.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = context.watch<ReportsProvider>().selectedReport;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: report == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/reports'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        report.problem,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _Badge('${report.improvementPercent.toStringAsFixed(0)}%'),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: report.contentText),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Export'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _CompareCard(
                        title: 'Before',
                        hallucination: report.beforeHallucination,
                        relevance: report.beforeRelevance,
                        latency: report.beforeLatency,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _CompareCard(
                        title: 'After',
                        hallucination: report.afterHallucination,
                        relevance: report.afterRelevance,
                        latency: report.afterLatency,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Card(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      child: SingleChildScrollView(
                        child: Text(
                          report.contentText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.title,
    required this.hallucination,
    required this.relevance,
    required this.latency,
  });

  final String title;
  final double hallucination;
  final double relevance;
  final double latency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('Hallucination ${hallucination.toStringAsFixed(2)}'),
            Text('Relevance ${relevance.toStringAsFixed(2)}'),
            Text('Latency ${latency.toStringAsFixed(0)}ms'),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
