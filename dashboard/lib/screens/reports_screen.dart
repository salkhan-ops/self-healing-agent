import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/report.dart';
import '../providers/reports_provider.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String query = '';
  int sortColumn = 0;
  bool ascending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ReportsProvider>().loadReports(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsProvider>();
    final reports = _filtered(provider.reports);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 20),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search reports',
            ),
            onChanged: (value) => setState(() => query = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DataTable2(
                  columnSpacing: 18,
                  sortColumnIndex: sortColumn,
                  sortAscending: ascending,
                  columns: [
                    _column('Timestamp', 0),
                    _column('Problem', 1),
                    _column('Root Cause', 2),
                    _column('Improvement', 3),
                    _column('Human Needed', 4),
                  ],
                  rows: reports.map((report) {
                    final improved =
                        report.improvementPercent >= 0 && !report.humanNeeded;
                    return DataRow(
                      color: WidgetStatePropertyAll(
                        (improved ? AppColors.success : AppColors.danger)
                            .withValues(alpha: 0.08),
                      ),
                      cells: [
                        DataCell(
                          Text(
                            DateFormat('MMM d, HH:mm').format(report.timestamp),
                          ),
                          onTap: () => context.go('/reports/${report.id}'),
                        ),
                        DataCell(
                          Text(
                            report.problem,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => context.go('/reports/${report.id}'),
                        ),
                        DataCell(
                          Text(
                            report.rootCause,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => context.go('/reports/${report.id}'),
                        ),
                        DataCell(
                          Text(
                            '${report.improvementPercent.toStringAsFixed(0)}%',
                          ),
                          onTap: () => context.go('/reports/${report.id}'),
                        ),
                        DataCell(
                          Text(report.humanNeeded ? 'YES' : 'NO'),
                          onTap: () => context.go('/reports/${report.id}'),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataColumn2 _column(String label, int index) {
    return DataColumn2(
      label: Text(label),
      onSort: (columnIndex, ascendingValue) => setState(() {
        sortColumn = index;
        ascending = !ascending;
      }),
    );
  }

  List<Report> _filtered(List<Report> reports) {
    final filtered = reports.where((report) {
      final text = '${report.problem} ${report.rootCause} ${report.fixApplied}'
          .toLowerCase();
      return text.contains(query.toLowerCase());
    }).toList();

    filtered.sort((a, b) {
      final result = switch (sortColumn) {
        1 => a.problem.compareTo(b.problem),
        2 => a.rootCause.compareTo(b.rootCause),
        3 => a.improvementPercent.compareTo(b.improvementPercent),
        4 => a.humanNeeded.toString().compareTo(b.humanNeeded.toString()),
        _ => a.timestamp.compareTo(b.timestamp),
      };
      return ascending ? result : -result;
    });

    return filtered;
  }
}
