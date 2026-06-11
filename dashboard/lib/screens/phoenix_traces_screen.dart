import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';
import '../core/responsive.dart';
import '../core/theme.dart';

class PhoenixTracesScreen extends StatefulWidget {
  const PhoenixTracesScreen({super.key});

  @override
  State<PhoenixTracesScreen> createState() => _PhoenixTracesScreenState();
}

class _PhoenixTracesScreenState extends State<PhoenixTracesScreen> {
  bool isLoading = true;
  String? error;
  Map<String, dynamic> payload = {};
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load(refresh: true);
    timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(refresh: false),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load({required bool refresh}) async {
    if (mounted) {
      setState(() {
        isLoading = true;
        error = null;
      });
    }
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConfig.apiBaseUrl}/api/phoenix/traces?refresh=$refresh',
        ),
      );
      if (response.statusCode != 200) {
        throw Exception('Phoenix API returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        payload = data;
        isLoading = false;
      });
    } catch (exc) {
      if (!mounted) return;
      setState(() {
        error = exc.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mcp = _map(payload['mcp']);
    final traces = _list(payload['traces']);
    final timeline = _list(payload['timeline']);
    return Padding(
      padding: Responsive.pagePadding(context),
      child: RefreshIndicator(
        onRefresh: () => _load(refresh: true),
        child: ListView(
          children: [
            _Header(
              isLoading: isLoading,
              onRefresh: () => _load(refresh: true),
            ),
            const SizedBox(height: 16),
            if (error != null) _ErrorBanner(error: error!),
            _McpStatusCard(
              mcp: mcp,
              projectName: payload['project_name']?.toString() ?? '',
              phoenixHost: payload['phoenix_host']?.toString() ?? '',
            ),
            const SizedBox(height: 16),
            _TimelineCard(items: timeline),
            const SizedBox(height: 16),
            _TraceTable(
              traces: traces,
              onOpen: (trace) => _showTraceDetail(context, trace),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTraceDetail(
    BuildContext context,
    Map<String, dynamic> trace,
  ) {
    final comparison = _map(trace['comparison']);
    final before = _map(comparison['before']);
    final after = _map(comparison['after']);
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hub_rounded, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${trace['agent_name'] ?? 'Agent'} · ${trace['trace_id'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _DetailSection(
                          title: 'Original Prompt',
                          text: trace['prompt']?.toString() ?? '',
                        ),
                        _DetailSection(
                          title: 'Original Response',
                          text:
                              before['response']?.toString().isNotEmpty == true
                              ? before['response']?.toString() ?? ''
                              : trace['response']?.toString() ?? '',
                        ),
                        _ScoreRow(trace: trace),
                        _DetailSection(
                          title: 'Root Cause Diagnosis',
                          text:
                              trace['root_cause_diagnosis']
                                      ?.toString()
                                      .isNotEmpty ==
                                  true
                              ? '${trace['root_cause']}: ${trace['root_cause_diagnosis']}'
                              : 'No healing diagnosis recorded yet.',
                        ),
                        _DetailSection(
                          title: 'Prompt Patch Applied',
                          text:
                              trace['prompt_patch_applied']
                                      ?.toString()
                                      .isNotEmpty ==
                                  true
                              ? trace['prompt_patch_applied']?.toString() ?? ''
                              : 'No prompt patch recorded yet.',
                        ),
                        _DetailSection(
                          title: 'Verification Results',
                          text: const JsonEncoder.withIndent(
                            '  ',
                          ).convert(trace['verification_results'] ?? {}),
                        ),
                        _DetailSection(
                          title: 'Final Healed Response',
                          text: after['response']?.toString().isNotEmpty == true
                              ? after['response']?.toString() ?? ''
                              : trace['final_healed_response']?.toString() ??
                                    'No healed response recorded yet.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'Phoenix Traces',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
        IconButton.outlined(
          onPressed: isLoading ? null : onRefresh,
          tooltip: 'Refresh Phoenix traces',
          icon: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }
}

class _McpStatusCard extends StatelessWidget {
  const _McpStatusCard({
    required this.mcp,
    required this.projectName,
    required this.phoenixHost,
  });

  final Map<String, dynamic> mcp;
  final String projectName;
  final String phoenixHost;

  @override
  Widget build(BuildContext context) {
    final status = mcp['status']?.toString() ?? 'not_run';
    final color = _statusColor(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_tree_rounded, color: color),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Phoenix MCP Trace Retrieval',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _Pill(text: status, color: color),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricChip(
                  label: 'Traces fetched',
                  value: '${mcp['traces_fetched'] ?? 0}',
                ),
                _MetricChip(
                  label: 'Retrieval time',
                  value: '${mcp['retrieval_time_ms'] ?? 0}ms',
                ),
                _MetricChip(
                  label: 'Project',
                  value: projectName.isEmpty ? 'unknown' : projectName,
                ),
                _MetricChip(
                  label: 'Phoenix',
                  value: phoenixHost.isEmpty ? 'not configured' : phoenixHost,
                ),
              ],
            ),
            if ((mcp['last_error']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                mcp['last_error'].toString(),
                style: const TextStyle(color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hackathon Run Mode',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final status = item['status']?.toString() ?? 'waiting';
              final color = _statusColor(status);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded, color: color, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['step']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              _time(item['timestamp']?.toString() ?? ''),
                              item['span_name']?.toString() ?? '',
                              item['trace_id']?.toString() ?? '',
                            ].where((part) => part.isNotEmpty).join(' · '),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if ((item['details']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(item['details'].toString()),
                            ),
                        ],
                      ),
                    ),
                    _Pill(text: status, color: color),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TraceTable extends StatelessWidget {
  const _TraceTable({required this.traces, required this.onOpen});

  final List<Map<String, dynamic>> traces;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Traces',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (traces.isEmpty)
              const Text(
                'No traces recorded yet. Generate a post, send a chat message, or run Agent Control.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 22,
                  columns: const [
                    DataColumn(label: Text('Time')),
                    DataColumn(label: Text('Agent')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Hallucination')),
                    DataColumn(label: Text('Relevance')),
                    DataColumn(label: Text('Trace ID')),
                    DataColumn(label: Text('Spans')),
                    DataColumn(label: Text('Before/After')),
                  ],
                  rows: traces.map((trace) {
                    final status = trace['status']?.toString() ?? 'captured';
                    final color = _statusColor(status);
                    return DataRow(
                      cells: [
                        DataCell(
                          Text(_time(trace['timestamp']?.toString() ?? '')),
                        ),
                        DataCell(
                          Text(
                            '${trace['agent_name'] ?? ''}\n${trace['use_case'] ?? ''}',
                          ),
                        ),
                        DataCell(_Pill(text: status, color: color)),
                        DataCell(Text(_score(trace['hallucination_score']))),
                        DataCell(Text(_score(trace['relevance_score']))),
                        DataCell(
                          SelectableText(
                            _short(trace['trace_id']?.toString() ?? ''),
                          ),
                        ),
                        DataCell(Text('${trace['span_count'] ?? 1}')),
                        DataCell(
                          TextButton.icon(
                            onPressed: () => onOpen(trace),
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: Text(
                              (trace['before_after_status']?.toString() ?? '')
                                      .isEmpty
                                  ? 'Open'
                                  : trace['before_after_status'].toString(),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.trace});

  final Map<String, dynamic> trace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricChip(
            label: 'Hallucination',
            value: _score(trace['hallucination_score']),
          ),
          _MetricChip(
            label: 'Relevance',
            value: _score(trace['relevance_score']),
          ),
          _MetricChip(
            label: 'Status',
            value: trace['status']?.toString() ?? '',
          ),
          _MetricChip(
            label: 'Healing run',
            value: trace['healing_run_id']?.toString().isNotEmpty == true
                ? trace['healing_run_id'].toString()
                : 'none',
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          SelectableText(
            text.trim().isEmpty ? 'Not recorded yet.' : text.trim(),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(error, style: const TextStyle(color: AppColors.danger)),
      ),
    );
  }
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is List) {
    return value.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }
  return [];
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

String _score(dynamic value) {
  final score = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0.0;
  return score.toStringAsFixed(2);
}

String _short(String value) {
  if (value.length <= 12) return value;
  return value.substring(0, 12);
}

String _time(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return '';
  return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}:${parsed.second.toString().padLeft(2, '0')}';
}

Color _statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'fallback':
    case 'success':
    case 'healthy':
    case 'healed':
    case 'completed':
    case 'captured':
      return AppColors.success;
    case 'failed':
    case 'error':
      return AppColors.danger;
    default:
      return AppColors.warning;
  }
}
