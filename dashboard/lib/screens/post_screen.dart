import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/responsive.dart';
import '../core/app_config.dart';
import '../providers/agent_provider.dart';
import '../widgets/healing_journey_dialog.dart';

const _apiBase = AppConfig.apiBaseUrl;
final _wsUrl = AppConfig.wsUrl;
const _primary = Color(0xFF6C63FF);
const _success = Color(0xFF2ED573);
const _warning = Color(0xFFFFA502);
const _danger = Color(0xFFFF4757);
const _textSecondary = Color(0xFF8B8BA7);
const _healingThreshold = 0.4;

class PostScreen extends StatefulWidget {
  const PostScreen({super.key});

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final briefController = TextEditingController();
  final platforms = const ['twitter', 'linkedin', 'facebook'];
  final normalBriefs = const [
    'Launch day: shipped workflow analytics v2. New dashboard, cleaner alerts, faster team handoffs. Customers asked for this for months.',
    'Customer story: ops team cut weekly status meetings from 5 to 2 after moving reporting into our product. Approved quote: "We finally see blockers early."',
    'Team update: hired 4 engineers, opened the beta to 80 teams, and shipped 12 customer-requested fixes this month.',
  ];
  final riskyBriefs = const [
    'Make this sound like a category killer: beta dashboard launched, 18 waitlist customers joined, revenue not disclosed.',
    'Write an investor-style launch post. We have early partner interest, no signed enterprise contracts yet, and no approved ROI numbers.',
    'Announce our AI model update. No benchmark is approved, but the team wants it to feel unbeatable and urgent.',
  ];
  final hallucinationBriefs = const [
    'Sparse brief: opened a private beta for 40 teams. Do not add revenue, market share, Fortune 500 logos, or growth percentages.',
    'Internal note: one hospital innovation team started a pilot. No patient outcomes, accuracy metrics, or clinical approvals have been measured.',
    'Founder note: Q2 pipeline looks promising. No ARR, conversion rate, customer names, funding round, or valuation is approved for release.',
  ];
  String platform = 'twitter';
  bool isLoading = false;
  int promptVersion = 1;
  late final DateTime historySessionStarted = DateTime.now().subtract(
    const Duration(seconds: 2),
  );
  Map<String, dynamic>? latestPost;
  List<Map<String, dynamic>> history = [];
  String? pendingHealingBrief;
  Map<String, dynamic>? pendingHealingBaseline;
  Map<String, dynamic>? healingJourneyPair;
  WebSocketChannel? wsChannel;
  Timer? reconnectTimer;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadHistory();
    _connectWebSocket();
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    wsChannel?.sink.close();
    briefController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/posts/status'));
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      setState(() => promptVersion = _asInt(data['prompt_version'], 1));
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final response = await http.get(Uri.parse('$_apiBase/api/posts/history'));
      if (response.statusCode != 200 || !mounted) return;
      final data = jsonDecode(response.body);
      setState(() {
        history = data is List
            ? data
                  .whereType<Map<String, dynamic>>()
                  .where(_isCurrentHistoryEntry)
                  .toList()
                  .reversed
                  .toList()
            : [];
      });
    } catch (_) {}
  }

  bool _isCurrentHistoryEntry(Map<String, dynamic> entry) {
    final timestamp = _parseApiTimestamp(entry['timestamp']?.toString() ?? '');
    if (timestamp == null) return true;
    return !timestamp.isBefore(historySessionStarted);
  }

  Future<void> _generate({String? brief}) async {
    final rawBrief = (brief ?? briefController.text).trim();
    if (rawBrief.isEmpty || isLoading) return;
    setState(() => isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_apiBase/api/posts/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'brief': rawBrief, 'platform': platform}),
      );
      if (response.statusCode != 200) {
        throw Exception('Post API returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        latestPost = {...data, 'brief': rawBrief};
        promptVersion = _asInt(data['prompt_version'], promptVersion);
        if (promptVersion == 1) {
          pendingHealingBrief = rawBrief;
        }
      });
      await _loadHistory();
      _handleHealedGenerationIfNeeded();
      if (mounted &&
          promptVersion == 1 &&
          _asDouble(data['hallucination_score']) > _healingThreshold &&
          pendingHealingBaseline == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startHealingAndRegenerate();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate post: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _reset() async {
    try {
      await http.post(Uri.parse('$_apiBase/api/posts/reset'));
      if (!mounted) return;
      setState(() {
        promptVersion = 1;
        latestPost = null;
        history = [];
        pendingHealingBrief = null;
        pendingHealingBaseline = null;
        healingJourneyPair = null;
      });
    } catch (_) {}
  }

  void _connectWebSocket() {
    try {
      wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      wsChannel!.stream.listen(
        (event) => _handleSocket(event.toString()),
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connectWebSocket();
    });
  }

  void _handleSocket(String message) {
    if (message.startsWith('post_prompt_updated:v')) {
      final version = int.tryParse(message.split(':v').last) ?? promptVersion;
      final briefToReplay = pendingHealingBrief;
      if (mounted) {
        setState(() => promptVersion = version);
        if (briefToReplay != null && briefToReplay.trim().isNotEmpty) {
          pendingHealingBrief = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _generate(brief: briefToReplay);
          });
        }
      }
    }
    if (message == 'post_reset:v1') {
      if (mounted) {
        setState(() {
          promptVersion = 1;
          latestPost = null;
          history = [];
          pendingHealingBrief = null;
          pendingHealingBaseline = null;
        });
      }
    }
    if (message == 'metrics_updated') {
      _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final composer = _briefPanel(context);
        final output = _outputPanel(context);
        return Padding(
          padding: Responsive.pagePadding(context),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(),
                const SizedBox(height: 18),
                SizedBox(
                  height: isMobile ? 820 : 420,
                  child: isMobile
                      ? Column(
                          children: [
                            Expanded(child: composer),
                            const SizedBox(height: 16),
                            Expanded(child: output),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth * 0.4,
                              child: composer,
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: output),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                _historyTable(isMobile: isMobile),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _topBar() {
    final agent = context.watch<AgentProvider>();
    final platformSelector = SegmentedButton<String>(
      segments: [
        for (final value in platforms)
          ButtonSegment(
            value: value,
            label: Text(_label(value), maxLines: 1, softWrap: false),
          ),
      ],
      selected: {platform},
      onSelectionChanged: (values) => setState(() => platform = values.first),
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _primary,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Prompt v$promptVersion',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (healingJourneyPair != null)
          OutlinedButton.icon(
            onPressed: _showStoredPostComparison,
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('View Comparison'),
          ),
        if (healingJourneyPair != null)
          OutlinedButton.icon(
            onPressed: _showHealingJourney,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('View Healing'),
          ),
        IconButton.outlined(
          tooltip: 'Run Agent Control',
          onPressed: agent.isRunning
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final result = await agent.runNow();
                  if (result['status'] == 'disabled') {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          result['message']?.toString() ??
                              'Public run limit reached.',
                        ),
                      ),
                    );
                  }
                },
          style: IconButton.styleFrom(
            foregroundColor: _success,
            side: BorderSide(color: _success.withValues(alpha: 0.7)),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
        ),
        IconButton.outlined(
          tooltip: 'Stop Agent Control',
          onPressed: agent.isRunning && !agent.isStopping
              ? () => agent.stopNow()
              : null,
          style: IconButton.styleFrom(
            foregroundColor: _danger,
            side: BorderSide(color: _danger.withValues(alpha: 0.7)),
          ),
          icon: const Icon(Icons.stop_circle_outlined),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;
        final title = const Text(
          'Social Media Posts',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: platformSelector,
              ),
              const SizedBox(height: 12),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            const SizedBox(width: 20),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: platformSelector,
              ),
            ),
            const SizedBox(width: 14),
            actions,
          ],
        );
      },
    );
  }

  Widget _briefPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Brief Input',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _ExampleBriefs(
                normalBriefs: normalBriefs,
                riskyBriefs: riskyBriefs,
                hallucinationBriefs: hallucinationBriefs,
                initiallyCollapsed: briefController.text.trim().isNotEmpty,
                onSelected: (brief) {
                  briefController.text = brief;
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: TextField(
                  controller: briefController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: const InputDecoration(
                    alignLabelWithHint: true,
                    hintText:
                        'Paste your raw notes, bullet points, or facts here.\n\nExample:\nQ1 was our best quarter. Launched new product.\nHired 5 engineers. Partnership with Acme Corp signed.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: isLoading ? null : _generate,
                style: FilledButton.styleFrom(backgroundColor: _primary),
                child: Text(isLoading ? 'Generating...' : 'Generate'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: _reset, child: const Text('Reset')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _outputPanel(BuildContext context) {
    final post = latestPost;
    final isPreparingHealedVersion = pendingHealingBaseline != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Generated Post',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (isPreparingHealedVersion) ...[
              const _HealingInProgressBanner(),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: post == null
                  ? const _EmptyState()
                  : SingleChildScrollView(
                      child: _GeneratedPostCard(post: post),
                    ),
            ),
            if (post != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: post['post']?.toString() ?? ''),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy'),
                  ),
                  FilledButton.icon(
                    onPressed: isLoading || isPreparingHealedVersion
                        ? null
                        : _regenerateOrHealLatestPost,
                    icon: isPreparingHealedVersion
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      isPreparingHealedVersion
                          ? 'Healing...'
                          : _latestPostNeedsHealing
                          ? 'Heal post'
                          : 'Regenerate',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _historyTable({required bool isMobile}) {
    final recent = history.take(5).toList();
    final isPreparingHealedVersion = pendingHealingBaseline != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Posts',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            if (isPreparingHealedVersion) ...[
              const _HealingInProgressBanner(),
              const SizedBox(height: 10),
            ],
            if (recent.isEmpty)
              const Text(
                'No posts generated yet.',
                style: TextStyle(color: _textSecondary),
              )
            else if (isMobile)
              Column(
                children: [
                  for (final item in recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MobilePostHistoryCard(
                        item: item,
                        hallucination: _asDouble(item['hallucination_score']),
                        color: _scoreColor(
                          _asDouble(item['hallucination_score']),
                        ),
                      ),
                    ),
                ],
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 860),
                  child: DataTable(
                    columnSpacing: 28,
                    columns: const [
                      DataColumn(
                        label: SizedBox(width: 72, child: Text('Time')),
                      ),
                      DataColumn(
                        label: SizedBox(width: 110, child: Text('Platform')),
                      ),
                      DataColumn(
                        label: SizedBox(width: 90, child: Text('Prompt v')),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: 120,
                          child: Text('Hallucination'),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(width: 360, child: Text('Preview')),
                      ),
                    ],
                    rows: recent.map((item) {
                      final hallucination = _asDouble(
                        item['hallucination_score'],
                      );
                      final color = _scoreColor(hallucination);
                      return DataRow(
                        color: WidgetStatePropertyAll(
                          color.withValues(alpha: 0.08),
                        ),
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 72,
                              child: Text(
                                _time(item['timestamp']?.toString() ?? ''),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 110,
                              child: Text(
                                _label(item['platform']?.toString() ?? ''),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                          DataCell(Text('${item['prompt_version'] ?? ''}')),
                          DataCell(Text(hallucination.toStringAsFixed(2))),
                          DataCell(
                            SizedBox(
                              width: 360,
                              child: Text(
                                item['post']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  bool get _latestPostNeedsHealing =>
      _asDouble(latestPost?['hallucination_score']) > _healingThreshold;

  Future<void> _regenerateOrHealLatestPost() async {
    final post = latestPost;
    if (post == null) return;
    final brief = post['brief']?.toString() ?? briefController.text;
    if (_asDouble(post['hallucination_score']) > _healingThreshold) {
      await _startHealingAndRegenerate();
      return;
    }
    await _generate(brief: brief);
  }

  Future<void> _startHealingAndRegenerate() async {
    if (pendingHealingBaseline != null) return;
    final post = latestPost;
    if (post == null) return;
    final brief = post['brief']?.toString() ?? '';
    if (brief.trim().isEmpty) return;
    final hallucination = _asDouble(post['hallucination_score']);
    if (hallucination <= _healingThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No healing needed: hallucination is ${hallucination.toStringAsFixed(2)}.',
          ),
        ),
      );
      return;
    }

    pendingHealingBaseline = Map<String, dynamic>.from(post);
    pendingHealingBrief = brief;
    healingJourneyPair = null;
    if (mounted) setState(() {});

    try {
      final response = await http.post(Uri.parse('$_apiBase/api/posts/heal'));
      if (response.statusCode != 200) {
        throw Exception('Post healer returned ${response.statusCode}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] == 'no_change') {
        final shouldRegenerateWithCurrentPrompt = promptVersion > 1;
        if (!mounted) return;
        setState(() {
          pendingHealingBaseline = null;
          pendingHealingBrief = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shouldRegenerateWithCurrentPrompt
                  ? 'Prompt is already healed. Regenerating with the current prompt.'
                  : 'No post healing change was needed.',
            ),
          ),
        );
        if (shouldRegenerateWithCurrentPrompt) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _generate(brief: brief);
          });
        }
        return;
      }
      _storeHealingEvidenceFromResponse(data, pendingHealingBaseline);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preparing healed version of this post.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        pendingHealingBaseline = null;
        pendingHealingBrief = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start post healing: $error')),
      );
    }
  }

  void _storeHealingEvidenceFromResponse(
    Map<String, dynamic> data,
    Map<String, dynamic>? baseline,
  ) {
    if (baseline == null) return;
    final preview = data['preview'];
    final traces = data['verification_traces'];
    final trace = preview is Map<String, dynamic>
        ? preview
        : traces is List && traces.isNotEmpty && traces.first is Map
        ? Map<String, dynamic>.from(traces.first as Map)
        : <String, dynamic>{};
    final afterPost = trace['post']?.toString() ?? '';
    if (afterPost.trim().isEmpty) return;

    final beforeVersion = _asInt(baseline['prompt_version'], 1);
    final afterVersion = _asInt(data['prompt_version'], beforeVersion + 1);
    final beforeScores = data['before_scores'];
    final afterScores = data['after_scores'];
    setState(() {
      healingJourneyPair = {
        'brief':
            trace['brief']?.toString() ?? baseline['brief']?.toString() ?? '',
        'before': baseline['post']?.toString() ?? '',
        'after': afterPost,
        'before_version': beforeVersion,
        'after_version': afterVersion,
        'before_hallucination': _scoreFromMap(
          beforeScores,
          'hallucination_score',
          baseline['hallucination_score'],
        ),
        'after_hallucination': _scoreFromMap(
          afterScores,
          'hallucination_score',
          trace['hallucination_score'],
        ),
        'before_relevance': _scoreFromMap(
          beforeScores,
          'relevance_score',
          baseline['relevance_score'],
        ),
        'after_relevance': _scoreFromMap(
          afterScores,
          'relevance_score',
          trace['relevance_score'],
        ),
        'root_cause': data['root_cause']?.toString() ?? '',
        'root_cause_explanation':
            data['root_cause_explanation']?.toString() ?? '',
        'old_prompt': data['old_prompt']?.toString() ?? '',
        'new_prompt': data['new_prompt']?.toString() ?? '',
        'changed':
            (baseline['post']?.toString() ?? '').trim() != afterPost.trim(),
      };
    });
  }

  void _handleHealedGenerationIfNeeded() {
    final baseline = pendingHealingBaseline;
    final healed = latestPost;
    if (baseline == null || healed == null) return;

    final beforeVersion = _asInt(baseline['prompt_version'], 1);
    final afterVersion = _asInt(healed['prompt_version'], beforeVersion);
    if (afterVersion <= beforeVersion) return;

    pendingHealingBaseline = null;
    healingJourneyPair = {
      'brief':
          baseline['brief']?.toString() ?? healed['brief']?.toString() ?? '',
      'before': baseline['post']?.toString() ?? '',
      'after': healed['post']?.toString() ?? '',
      'before_version': beforeVersion,
      'after_version': afterVersion,
      'before_hallucination': _asDouble(baseline['hallucination_score']),
      'after_hallucination': _asDouble(healed['hallucination_score']),
      'before_relevance': _asDouble(baseline['relevance_score']),
      'after_relevance': _asDouble(healed['relevance_score']),
      'root_cause': healingJourneyPair?['root_cause'] ?? '',
      'root_cause_explanation':
          healingJourneyPair?['root_cause_explanation'] ?? '',
      'old_prompt': healingJourneyPair?['old_prompt'] ?? '',
      'new_prompt': healingJourneyPair?['new_prompt'] ?? '',
      'changed':
          (baseline['post']?.toString() ?? '').trim() !=
          (healed['post']?.toString() ?? '').trim(),
    };
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showHealingJourney();
    });
  }

  void _showStoredPostComparison() {
    final pair = healingJourneyPair;
    if (pair == null) return;
    _showPostComparisonDialog(
      {
        'post': pair['before'],
        'prompt_version': pair['before_version'],
        'hallucination_score': pair['before_hallucination'],
      },
      {
        'post': pair['after'],
        'prompt_version': pair['after_version'],
        'hallucination_score': pair['after_hallucination'],
      },
    );
  }

  void _showHealingJourney() {
    final pair = healingJourneyPair;
    if (pair == null) return;

    showHealingJourney(
      context,
      HealingJourneyData(
        beforeVersion: _asInt(pair['before_version'], 1),
        afterVersion: _asInt(pair['after_version'], promptVersion),
        rootCause: pair['root_cause']?.toString().trim().isNotEmpty == true
            ? pair['root_cause']?.toString() ?? 'UNSUPPORTED MARKETING CLAIMS'
            : 'UNSUPPORTED MARKETING CLAIMS',
        rootCauseExplanation:
            pair['root_cause_explanation']?.toString().trim().isNotEmpty == true
            ? pair['root_cause_explanation']?.toString() ?? ''
            : 'The post agent was adding hype, rankings, guarantees, or details that were not present in the source brief. Healing tightened the prompt so generated posts stay grounded in supplied facts.',
        beforeHallucination: _asDouble(pair['before_hallucination']),
        afterHallucination: _asDouble(pair['after_hallucination']),
        beforeRelevance: _asDouble(pair['before_relevance']),
        afterRelevance: _asDouble(pair['after_relevance']),
        oldPrompt: pair['old_prompt']?.toString().trim().isNotEmpty == true
            ? pair['old_prompt']?.toString() ?? ''
            : 'Write an engaging social media post.\n'
                  'Make the update sound bold and exciting.\n'
                  'Use persuasive language even when the brief is sparse.',
        newPrompt: pair['new_prompt']?.toString().trim().isNotEmpty == true
            ? pair['new_prompt']?.toString() ?? ''
            : 'Write only from facts in the supplied brief.\n'
                  'Do not invent claims, rankings, metrics, customer reactions, dates, partners, awards, or guarantees.\n'
                  'Keep the tone professional and grounded.\n'
                  'If a detail is missing, omit it instead of guessing.',
        pairs: [
          ComparisonPair(
            question: pair['brief']?.toString() ?? 'Social post brief',
            before: pair['before']?.toString() ?? '',
            after: pair['after']?.toString() ?? '',
            changed: pair['changed'] == true,
          ),
        ],
      ),
    );
  }

  Future<void> _showPostComparisonDialog(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    return showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.auto_fix_high_rounded, color: _primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Social Media Posts Before/After',
                        style: TextStyle(
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
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _PostComparisonColumn(
                          title:
                              'Before · Prompt v${before['prompt_version'] ?? 1}',
                          color: _danger,
                          text: before['post']?.toString() ?? '',
                          score: _asDouble(before['hallucination_score']),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PostComparisonColumn(
                          title:
                              'After · Prompt v${after['prompt_version'] ?? 1}',
                          color: _success,
                          text: after['post']?.toString() ?? '',
                          score: _asDouble(after['hallucination_score']),
                        ),
                      ),
                    ],
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

class _GeneratedPostCard extends StatelessWidget {
  const _GeneratedPostCard({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final hallucination = _asDouble(post['hallucination_score']);
    final relevance = _asDouble(post['relevance_score']);
    final color = _scoreColor(hallucination);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Stack(
            children: [
              SelectableText(post['post']?.toString() ?? ''),
              Positioned(
                right: 0,
                top: 0,
                child: Icon(_platformIcon(post['platform']?.toString() ?? '')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _ScoreBadge(
              label: 'Hallucination',
              value: hallucination,
              color: color,
            ),
            _ScoreBadge(
              label: 'Relevance',
              value: relevance,
              color: _scoreColor(1 - relevance),
            ),
            _MetaBadge(text: '⏱ ${post['latency_ms'] ?? 0}ms'),
            _MetaBadge(
              text:
                  'Trace: ${(post['trace_id']?.toString() ?? '').padRight(8).substring(0, 8)}',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (hallucination > _healingThreshold)
          const _Banner(
            color: _danger,
            text:
                '⚠ High hallucination detected. Self-healing is preparing a grounded version.',
          )
        else if (hallucination <= 0.0)
          const _Banner(
            color: _success,
            text: '✓ Hallucination is 0.00. No healing needed.',
          )
        else if (hallucination < 0.2)
          const _Banner(
            color: _success,
            text: '✓ Low risk. Regenerate will not start self-healing.',
          ),
      ],
    );
  }
}

class _HealingInProgressBanner extends StatelessWidget {
  const _HealingInProgressBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withValues(alpha: 0.28)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Healing version is being prepared…',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleBriefs extends StatefulWidget {
  const _ExampleBriefs({
    required this.normalBriefs,
    required this.riskyBriefs,
    required this.hallucinationBriefs,
    required this.initiallyCollapsed,
    required this.onSelected,
  });

  final List<String> normalBriefs;
  final List<String> riskyBriefs;
  final List<String> hallucinationBriefs;
  final bool initiallyCollapsed;
  final ValueChanged<String> onSelected;

  @override
  State<_ExampleBriefs> createState() => _ExampleBriefsState();
}

class _ExampleBriefsState extends State<_ExampleBriefs> {
  late bool collapsed = widget.initiallyCollapsed;
  int selectedGroup = 0;

  List<({String label, Color color, List<String> briefs})> get groups => [
    (label: 'Normal', color: _success, briefs: widget.normalBriefs),
    (label: 'Risky', color: _warning, briefs: widget.riskyBriefs),
    (
      label: 'Hallucination',
      color: _danger,
      briefs: widget.hallucinationBriefs,
    ),
  ];

  @override
  void didUpdateWidget(covariant _ExampleBriefs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.initiallyCollapsed && widget.initiallyCollapsed) {
      collapsed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = groups[selectedGroup];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Quick test briefs',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => collapsed = !collapsed),
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
                label: Text(collapsed ? 'Show' : 'Hide'),
              ),
            ],
          ),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var index = 0; index < groups.length; index++)
                  ChoiceChip(
                    label: Text(groups[index].label),
                    selected: selectedGroup == index,
                    selectedColor: groups[index].color.withValues(alpha: 0.18),
                    side: BorderSide(color: groups[index].color),
                    onSelected: (_) => setState(() => selectedGroup = index),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ...current.briefs.map(
              (brief) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    widget.onSelected(brief);
                    setState(() => collapsed = true);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: current.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      brief,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, size: 54, color: _textSecondary),
        SizedBox(height: 12),
        Text(
          'Your generated post will appear here.\nPaste a brief and click Generate.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textSecondary),
        ),
      ],
    ),
  );
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label: ${value.toStringAsFixed(2)}',
      style: TextStyle(color: color),
    ),
  );
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: _primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}

class _PostComparisonColumn extends StatelessWidget {
  const _PostComparisonColumn({
    required this.title,
    required this.color,
    required this.text,
    required this.score,
  });

  final String title;
  final Color color;
  final String text;
  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Hallucination: ${score.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Expanded(child: SingleChildScrollView(child: SelectableText(text))),
        ],
      ),
    );
  }
}

class _MobilePostHistoryCard extends StatelessWidget {
  const _MobilePostHistoryCard({
    required this.item,
    required this.hallucination,
    required this.color,
  });

  final Map<String, dynamic> item;
  final double hallucination;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _label(item['platform']?.toString() ?? ''),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                _time(item['timestamp']?.toString() ?? ''),
                style: const TextStyle(color: _textSecondary, fontSize: 12),
              ),
              Text(
                'v${item['prompt_version'] ?? ''}',
                style: const TextStyle(color: _textSecondary, fontSize: 12),
              ),
              Text(
                'H ${hallucination.toStringAsFixed(2)}',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item['post']?.toString() ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0.0;
}

double _scoreFromMap(dynamic map, String key, dynamic fallback) {
  if (map is Map && map[key] != null) return _asDouble(map[key]);
  return _asDouble(fallback);
}

Color _scoreColor(double value) {
  if (value > _healingThreshold) return _danger;
  if (value >= 0.2) return _warning;
  return _success;
}

String _label(String value) {
  if (value.isEmpty) return value;
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String _time(String raw) {
  final parsed = _parseApiTimestamp(raw)?.toLocal();
  if (parsed == null) return '--';
  return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
}

DateTime? _parseApiTimestamp(String raw) {
  if (raw.trim().isEmpty) return null;
  final normalized = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw)
      ? raw
      : '${raw}Z';
  return DateTime.tryParse(normalized);
}

IconData _platformIcon(String platform) {
  switch (platform) {
    case 'twitter':
      return Icons.alternate_email_rounded;
    case 'facebook':
      return Icons.groups_rounded;
    default:
      return Icons.business_center_rounded;
  }
}
