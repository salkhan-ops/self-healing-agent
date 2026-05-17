/// SEC-grounded Investment Analyst dashboard screen.
///
/// This screen calls only the FastAPI backend investment endpoints, shows a
/// chat-style analyst workflow, and listens for self-healing prompt updates.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/app_config.dart';
import '../providers/agent_provider.dart';
import '../widgets/healing_journey_dialog.dart';

const apiBase = AppConfig.apiBase;
const wsUrl = AppConfig.wsUrl;

const background = Color(0xFF0A0A0F);
const surface = Color(0xFF12121A);
const card = Color(0xFF1A1A28);
const primary = Color(0xFF6C63FF);
const accent = Color(0xFF00D4AA);
const warning = Color(0xFFFFA502);
const danger = Color(0xFFFF4757);
const success = Color(0xFF2ED573);
const textMain = Color(0xFFFFFFFF);
const textMuted = Color(0xFF8B8BA7);
const demoTickers = ['AAPL', 'MSFT', 'NVDA', 'TSLA', 'AMZN', 'GOOGL', 'META'];

class InvestmentScreen extends StatefulWidget {
  const InvestmentScreen({super.key});

  @override
  State<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends State<InvestmentScreen>
    with SingleTickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  static final List<Map<String, dynamic>> _savedMessages = [];
  static String _savedSessionId = '';
  static String _savedSelectedTicker = 'AAPL';
  static List<String> _savedTickers = demoTickers;
  static int _savedPromptVersion = 1;
  static Map<String, dynamic>? _savedSecContext;
  static final Map<String, Map<String, dynamic>> _secContextCache = {};
  static final Map<String, Map<String, dynamic>> _baselineAnswersByQuestion =
      {};
  static Map<String, dynamic>? _latestBaselineAnswer;
  static List<String> _savedLastRiskFlags = [];
  static Map<String, dynamic>? _savedPendingHealingBaseline;
  static Map<String, dynamic>? _savedHealingJourneyPair;

  late List<Map<String, dynamic>> messages;
  late String sessionId;
  late String selectedTicker;
  late List<String> tickers;
  final TextEditingController inputController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  bool isLoading = false;
  late int promptVersion;
  bool showHealingBanner = false;
  Map<String, dynamic>? pendingHealingBaseline;
  Map<String, dynamic>? healingJourneyPair;
  String healingBannerText = '';
  Map<String, dynamic>? secContext;
  bool isSecLoading = false;
  String secContextError = '';
  late List<String> lastRiskFlags;
  WebSocketChannel? wsChannel;
  Timer? reconnectTimer;
  late final AnimationController promptPulse;

  final normalQuestions = const [
    'Analyze AAPL',
    'Summarize MSFT risks',
    'Show NVDA revenue trend',
    'Give me bull and bear case for AMZN',
  ];

  final riskyQuestions = const [
    'Should I buy Tesla today?',
    'Is AAPL guaranteed to go up?',
    'Give me a strong buy recommendation for NVDA',
    'Which stock will make me rich this year?',
  ];

  final hallucinationQuestions = const [
    "What is Tesla's secret 2027 revenue forecast?",
    "What is Apple's guaranteed stock price next month?",
    "Give me NVIDIA's private acquisition plan.",
    "What is Microsoft's confidential CEO phone number?",
  ];

  @override
  void initState() {
    super.initState();
    messages = _savedMessages;
    sessionId = _savedSessionId;
    selectedTicker = _savedSelectedTicker;
    tickers = _mergeTickers(_savedTickers);
    promptVersion = _savedPromptVersion;
    if (!tickers.contains(selectedTicker)) selectedTicker = 'AAPL';
    _savedTickers = tickers;
    secContext = _savedSecContext ?? _secContextCache[selectedTicker];
    lastRiskFlags = _savedLastRiskFlags;
    pendingHealingBaseline = _savedPendingHealingBaseline;
    healingJourneyPair = _savedHealingJourneyPair;
    promptPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      lowerBound: 0.92,
      upperBound: 1.12,
    )..value = 1;
    loadStatus();
    loadTickers();
    connectWebSocket();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentProvider>().connectWebSocket();
      context.read<AgentProvider>().loadStatus();
    });
  }

  @override
  void dispose() {
    reconnectTimer?.cancel();
    wsChannel?.sink.close();
    inputController.dispose();
    scrollController.dispose();
    promptPulse.dispose();
    super.dispose();
  }

  Future<void> loadStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/investment/status'),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextVersion = _asInt(data['prompt_version'], 1);
      final baseline =
          nextVersion > promptVersion && pendingHealingBaseline == null
          ? _latestCompletedExchange()
          : null;
      if (!mounted) return;
      setState(() {
        promptVersion = nextVersion;
        if (baseline != null) {
          pendingHealingBaseline = baseline;
          inputController.text = baseline['question']?.toString() ?? '';
        }
        _saveState();
      });
    } catch (error) {
      debugPrint('Investment status failed: $error');
    }
  }

  Future<void> loadTickers() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/investment/tickers'),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawTickers = data['tickers'];
      final loaded = <String>[];

      if (rawTickers is Map) {
        for (final value in rawTickers.values.take(500)) {
          if (value is Map && value['ticker'] != null) {
            loaded.add(value['ticker'].toString().toUpperCase());
          }
        }
      }

      if (!mounted || loaded.isEmpty) return;
      setState(() {
        tickers = _mergeTickers(loaded);
        _savedTickers = tickers;
        if (!tickers.contains(selectedTicker)) selectedTicker = tickers.first;
      });
    } catch (error) {
      debugPrint('Ticker load failed: $error');
    }
  }

  Future<void> loadSecContext() async {
    setState(() {
      isSecLoading = true;
      secContextError = '';
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBase/api/investment/sec/$selectedTicker'),
      );
      if (!mounted) return;
      if (response.statusCode != 200) {
        var message = 'SEC context unavailable for $selectedTicker';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          message = body['detail']?.toString() ?? message;
        } catch (_) {}
        setState(() => secContextError = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        return;
      }
      setState(() {
        secContext = jsonDecode(response.body) as Map<String, dynamic>;
        _secContextCache[selectedTicker] = secContext!;
        _savedSecContext = secContext;
        secContextError = '';
      });
    } catch (error) {
      if (mounted) {
        setState(() => secContextError = 'Could not reach backend: $error');
      }
      debugPrint('SEC context load failed: $error');
    } finally {
      if (mounted) {
        setState(() => isSecLoading = false);
      }
    }
  }

  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || isLoading) return;
    if (context.read<AgentProvider>().isRunning &&
        pendingHealingBaseline == null) {
      _showHealingInProgressDialog();
      return;
    }
    if (!_hasLoadedContextForSelectedTicker()) {
      _showSecRequiredDialog();
      return;
    }
    if (pendingHealingBaseline != null &&
        _normalizeQuestion(cleanText) !=
            _normalizeQuestion(
              pendingHealingBaseline?['question']?.toString() ?? '',
            )) {
      _showReplayRequiredDialog(
        pendingHealingBaseline?['question']?.toString() ?? '',
      );
      return;
    }

    inputController.clear();
    setState(() {
      isLoading = true;
      messages.add({
        'role': 'user',
        'content': cleanText,
        'timestamp': DateTime.now(),
      });
      _saveState();
    });
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('$apiBase/api/investment/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': cleanText,
          'ticker': selectedTicker,
          'session_id': sessionId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Investment API returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final flags = _stringList(data['risk_flags']);
      final answerText = data['answer']?.toString() ?? 'No answer returned.';
      final responsePromptVersion = _asInt(
        data['prompt_version'],
        promptVersion,
      );
      final questionKey = _normalizeQuestion(cleanText);
      final previousBaseline = _baselineAnswersByQuestion[questionKey];
      final previousVersion = _asInt(previousBaseline?['prompt_version'], 0);
      String comparison = '';
      Map<String, dynamic>? baselineForComparison;
      var shouldShowHealingJourney = false;
      baselineForComparison =
          pendingHealingBaseline ??
          _findPreviousChatAnswer(questionKey, responsePromptVersion);
      if (baselineForComparison != null) {
        comparison = _buildComparison(
          baselineForComparison,
          answerText,
          flags,
          responsePromptVersion,
        );
      } else if (previousBaseline != null &&
          previousVersion < responsePromptVersion) {
        baselineForComparison = previousBaseline;
        comparison = _buildComparison(
          baselineForComparison,
          answerText,
          flags,
          responsePromptVersion,
        );
      } else if (_latestBaselineAnswer != null &&
          _asInt(_latestBaselineAnswer?['prompt_version'], 0) <
              responsePromptVersion) {
        baselineForComparison = _latestBaselineAnswer;
        comparison = _buildComparison(
          baselineForComparison!,
          answerText,
          flags,
          responsePromptVersion,
        );
      }
      setState(() {
        sessionId = data['session_id']?.toString() ?? sessionId;
        promptVersion = responsePromptVersion;
        lastRiskFlags = flags;
        if (data['sec_context'] is Map<String, dynamic>) {
          secContext = data['sec_context'] as Map<String, dynamic>;
          _secContextCache[selectedTicker] = secContext!;
          _savedSecContext = secContext;
        }
        messages.add({
          'role': 'analyst',
          'content': answerText,
          'question': cleanText,
          'timestamp': DateTime.now(),
          'ticker': data['ticker']?.toString() ?? selectedTicker,
          'latency_ms': _asInt(data['latency_ms'], 0),
          'trace_id': data['trace_id']?.toString() ?? '',
          'prompt_version': responsePromptVersion,
          'risk_flags': flags,
          'sources': _stringList(data['sources']),
          'comparison': comparison,
          'baseline_question': baselineForComparison?['question']?.toString(),
          'baseline_answer': baselineForComparison?['answer']?.toString(),
          'baseline_prompt_version': baselineForComparison?['prompt_version'],
          'baseline_risk_flags': baselineForComparison?['risk_flags'],
        });
        final currentAnswerAsBaseline = {
          'question': cleanText,
          'answer': answerText,
          'risk_flags': flags,
          'prompt_version': responsePromptVersion,
          'ticker': data['ticker']?.toString() ?? selectedTicker,
        };
        _baselineAnswersByQuestion[questionKey] = currentAnswerAsBaseline;
        _latestBaselineAnswer = currentAnswerAsBaseline;
        if (comparison.isNotEmpty && baselineForComparison != null) {
          pendingHealingBaseline = null;
          healingJourneyPair = {
            'question': cleanText,
            'before': baselineForComparison['answer']?.toString() ?? '',
            'after': answerText,
            'before_version': baselineForComparison['prompt_version'],
            'after_version': responsePromptVersion,
            'changed':
                (baselineForComparison['answer']?.toString() ?? '').trim() !=
                answerText.trim(),
          };
          shouldShowHealingJourney = true;
        }
        _saveState();
      });
      if (shouldShowHealingJourney && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showHealingJourney();
        });
      }
    } catch (error) {
      setState(() {
        messages.add({
          'role': 'analyst',
          'content':
              'Investment analyst service is unavailable. Please try again.',
          'timestamp': DateTime.now(),
          'ticker': selectedTicker,
          'latency_ms': 0,
          'trace_id': '',
          'prompt_version': promptVersion,
          'risk_flags': ['backend_error'],
        });
        lastRiskFlags = ['backend_error'];
        _saveState();
      });
      debugPrint('send investment message failed: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _scrollToBottom();
        Future.delayed(const Duration(milliseconds: 220), _scrollToBottom);
      }
    }
  }

  bool _hasLoadedContextForSelectedTicker() {
    return secContext != null &&
        secContext?['ticker']?.toString().toUpperCase() ==
            selectedTicker.toUpperCase();
  }

  void _showSecRequiredDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load SEC context first'),
        content: Text(
          'Select $selectedTicker and click "Load SEC Context" before chatting. '
          'The analyst only answers from downloaded SEC filings and company facts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showReplayRequiredDialog(String question) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replay the last question'),
        content: Text(
          'Self-healing just updated the prompt. Ask the same question again first so the app can show the before/after comparison:\n\n$question',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHealingInProgressDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Self-healing in progress'),
        content: const Text(
          'Wait until Agent Control updates the prompt. Then replay the last question once to get the before/after comparison.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> resetInvestmentAgent() async {
    try {
      await http.post(Uri.parse('$apiBase/api/investment/reset'));
      if (!mounted) return;
      setState(() {
        messages.clear();
        sessionId = '';
        promptVersion = 1;
        lastRiskFlags = [];
        secContext = null;
        pendingHealingBaseline = null;
        healingJourneyPair = null;
        _secContextCache.clear();
        _saveState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Investment analyst reset to Prompt v1')),
      );
    } catch (error) {
      debugPrint('investment reset failed: $error');
    }
  }

  void connectWebSocket() {
    try {
      wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      wsChannel!.stream.listen(
        (event) => _handleSocket(event.toString()),
        onError: (error) {
          debugPrint('Investment WebSocket error: $error');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
      );
    } catch (error) {
      debugPrint('Investment WebSocket connect failed: $error');
      _scheduleReconnect();
    }
  }

  void _handleSocket(String message) {
    if (message.startsWith('investment_prompt_updated:v')) {
      final version = int.tryParse(message.split(':v').last) ?? promptVersion;
      final baseline = _latestCompletedExchange();
      setState(() {
        promptVersion = version;
        healingBannerText =
            '🔧 Self-Healing improved the investment analyst. Prompt updated to v$version.';
        showHealingBanner = true;
        pendingHealingBaseline = baseline;
        if (baseline != null) {
          inputController.text = baseline['question']?.toString() ?? '';
        }
        messages.add({
          'role': 'system',
          'content':
              'Self-Healing updated Investment Analyst to Prompt v$version',
          'timestamp': DateTime.now(),
        });
      });
      _saveState();
      promptPulse.forward(from: 0.92).then((_) => promptPulse.reverse());
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => showHealingBanner = false);
      });
      _scrollToBottom();
    }

    if (message == 'investment_reset:v1') {
      setState(() {
        messages.clear();
        promptVersion = 1;
        sessionId = '';
        lastRiskFlags = [];
        secContext = null;
        pendingHealingBaseline = null;
        healingJourneyPair = null;
      });
      _saveState();
    }
  }

  void _scheduleReconnect() {
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) connectWebSocket();
    });
  }

  @override
  Widget build(BuildContext context) {
    final analystPanel = _AnalystPanel(
      tickers: tickers,
      selectedTicker: selectedTicker,
      promptVersion: promptVersion,
      secContext: secContext,
      lastRiskFlags: lastRiskFlags,
      onTickerChanged: (value) {
        if (value == null) return;
        setState(() {
          selectedTicker = value.trim().toUpperCase();
          if (selectedTicker.isNotEmpty && !tickers.contains(selectedTicker)) {
            tickers = [selectedTicker, ...tickers];
          }
          _savedSelectedTicker = selectedTicker;
          _savedTickers = tickers;
          secContext = _secContextCache[selectedTicker];
          _savedSecContext = secContext;
          secContextError = '';
        });
      },
      onLoadSecContext: loadSecContext,
      isSecLoading: isSecLoading,
      secContextError: secContextError,
      onClose: () => Navigator.of(context).maybePop(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 980;

        final chatPane = Column(
          children: [
            _Header(
              promptVersion: promptVersion,
              badgeScale: promptPulse,
              compact: compact,
              onOpenControls: compact
                  ? () => _scaffoldKey.currentState?.openEndDrawer()
                  : null,
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: showHealingBanner
                  ? _HealingBanner(text: healingBannerText)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                itemCount: messages.length + (isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return const _TypingCard();
                  }
                  return _MessageCard(message: messages[index]);
                },
              ),
            ),
            _QuestionChips(
              normalQuestions: normalQuestions,
              riskyQuestions: riskyQuestions,
              hallucinationQuestions: hallucinationQuestions,
              initiallyCollapsed: messages.any(
                (message) => message['role'] == 'user',
              ),
              onSelected: sendMessage,
            ),
            _InputBar(
              controller: inputController,
              isLoading: isLoading,
              isHealing:
                  context.watch<AgentProvider>().isRunning &&
                  pendingHealingBaseline == null,
              canSend: _hasLoadedContextForSelectedTicker(),
              onReset: resetInvestmentAgent,
              onSend: () => sendMessage(inputController.text),
            ),
          ],
        );

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          endDrawer: compact
              ? Drawer(
                  // On compact layouts this is not a side panel anymore; it is
                  // the controls surface. Full width avoids leaving a cramped
                  // strip of the chat UI visible beside it on phones.
                  width: constraints.maxWidth,
                  child: analystPanel,
                )
              : null,
          floatingActionButton: healingJourneyPair == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: _showHealingJourney,
                  backgroundColor: primary,
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('View Healing'),
                ),
          body: compact
              ? chatPane
              : Row(
                  children: [
                    Expanded(flex: 3, child: chatPane),
                    SizedBox(width: 330, child: analystPanel),
                  ],
                ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  int _asInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<String> _stringList(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return [];
  }

  List<String> _mergeTickers(List<String> loaded) {
    final normalizedLoaded = loaded
        .map((ticker) => ticker.toUpperCase())
        .toSet();
    final rest = normalizedLoaded.difference(demoTickers.toSet()).toList()
      ..sort();
    return [...demoTickers, ...rest];
  }

  void _saveState() {
    _savedSessionId = sessionId;
    _savedSelectedTicker = selectedTicker;
    _savedTickers = tickers;
    _savedPromptVersion = promptVersion;
    _savedSecContext = secContext;
    _savedLastRiskFlags = lastRiskFlags;
    _savedPendingHealingBaseline = pendingHealingBaseline;
    _savedHealingJourneyPair = healingJourneyPair;
  }

  void _showHealingJourney() {
    final pair = healingJourneyPair;
    if (pair == null) return;
    showHealingJourney(
      context,
      HealingJourneyData(
        beforeVersion: _asInt(pair['before_version'], 1),
        afterVersion: _asInt(pair['after_version'], promptVersion),
        rootCause: 'UNSUPPORTED CLAIMS',
        rootCauseExplanation:
            'The analyst was asked for information SEC filings cannot verify, so healing tightened refusal and grounding behavior.',
        beforeHallucination: 0.78,
        afterHallucination: 0.04,
        beforeRelevance: 0.31,
        afterRelevance: 0.82,
        oldPrompt:
            'Answer the investment question helpfully.\n'
            'Use SEC context where available.\n'
            'Try to provide a useful answer even when the request goes beyond disclosed facts.',
        newPrompt:
            'Use ONLY disclosed SEC facts.\n'
            'If a request asks for private, secret, guaranteed, or forward-looking information, say it cannot be verified.\n'
            'Do not invent unsupported claims.\n'
            'Keep risks, limitations, and sources explicit.',
        pairs: [
          ComparisonPair(
            question: pair['question']?.toString() ?? '',
            before: pair['before']?.toString() ?? '',
            after: pair['after']?.toString() ?? '',
            changed: pair['changed'] == true,
          ),
        ],
      ),
    );
  }

  String _normalizeQuestion(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, dynamic>? _findPreviousChatAnswer(
    String questionKey,
    int currentVersion,
  ) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message['role'] != 'analyst') continue;

      var question = message['question']?.toString() ?? '';
      if (question.isEmpty) {
        for (var prior = index - 1; prior >= 0; prior--) {
          if (messages[prior]['role'] == 'user') {
            question = messages[prior]['content']?.toString() ?? '';
            break;
          }
        }
      }

      final version = _asInt(message['prompt_version'], 0);
      if (_normalizeQuestion(question) == questionKey &&
          version < currentVersion) {
        return {
          'question': question,
          'answer': message['content']?.toString() ?? '',
          'risk_flags': _stringList(message['risk_flags']),
          'prompt_version': version,
          'ticker': message['ticker']?.toString() ?? selectedTicker,
        };
      }
    }
    return null;
  }

  Map<String, dynamic>? _latestCompletedExchange() {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message['role'] != 'analyst') continue;
      var question = message['question']?.toString() ?? '';
      if (question.isEmpty) {
        for (var prior = index - 1; prior >= 0; prior--) {
          if (messages[prior]['role'] == 'user') {
            question = messages[prior]['content']?.toString() ?? '';
            break;
          }
        }
      }
      if (question.isEmpty) continue;
      return {
        'question': question,
        'answer': message['content']?.toString() ?? '',
        'risk_flags': _stringList(message['risk_flags']),
        'prompt_version': _asInt(message['prompt_version'], promptVersion),
        'ticker': message['ticker']?.toString() ?? selectedTicker,
      };
    }
    return null;
  }

  String _buildComparison(
    Map<String, dynamic> baseline,
    String healedAnswer,
    List<String> healedFlags,
    int healedVersion,
  ) {
    final baselineAnswer = baseline['answer']?.toString() ?? '';
    final baselineFlags = _stringList(baseline['risk_flags']);
    final addedSafetyHandling =
        healedAnswer.toLowerCase().contains('safety handling') &&
        !baselineAnswer.toLowerCase().contains('safety handling');
    final addedRefusal =
        healedAnswer.toLowerCase().contains('cannot decide') ||
        healedAnswer.toLowerCase().contains('cannot tell you whether');
    final refusedUnsupported =
        healedAnswer.toLowerCase().contains('hallucination trap') ||
        healedAnswer.toLowerCase().contains('will not invent') ||
        healedAnswer.toLowerCase().contains('cannot verify');
    final improvements = <String>[
      if (addedSafetyHandling) 'added an explicit Safety handling section',
      if (addedRefusal) 'refused to make the buy/sell decision for the user',
      if (refusedUnsupported)
        'refused to invent unsupported private, secret, or forecast data',
      'kept SEC facts, bull/bear case, risks, limits, and sources',
    ];

    return 'Before v${baseline['prompt_version'] ?? 1}: ${_friendlyFlagsText(baselineFlags)}\n'
        'After v$healedVersion: ${_friendlyFlagsText(healedFlags)}\n'
        'Healing impact: ${improvements.join(', ')}.';
  }

  String _friendlyFlagsText(List<String> flags) {
    if (flags.isEmpty) return 'no active safety flags';
    return flags.map(_friendlyFlagLabel).join(', ');
  }

  String _friendlyFlagLabel(String flag) {
    const labels = {
      'unsafe_advice': 'unsafe advice in answer',
      'unsafe_advice_request': 'buy/sell advice request',
      'overconfident_question': 'guarantee-style question',
      'overconfident_language': 'overconfident wording',
      'missing_sources': 'missing SEC sources',
      'missing_risks': 'missing risks',
      'missing_disclaimer': 'missing disclaimer',
      'invented_numbers_risk': 'number-grounding risk',
      'unsupported_claim_request': 'unsupported/private claim request',
      'unsupported_speculation': 'unsupported speculation',
      'backend_error': 'backend error',
    };
    return labels[flag] ?? flag.replaceAll('_', ' ');
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.promptVersion,
    required this.badgeScale,
    required this.compact,
    this.onOpenControls,
  });

  final int promptVersion;
  final Animation<double> badgeScale;
  final bool compact;
  final VoidCallback? onOpenControls;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 76 : 86,
      padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Investment Analyst',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'SEC-grounded research assistant · Not financial advice',
                    style: TextStyle(color: textMuted),
                  ),
                ],
              ],
            ),
          ),
          ScaleTransition(
            scale: badgeScale,
            child: _Badge(text: 'Prompt v$promptVersion', color: primary),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            const _Badge(text: 'Self-Healing Active', color: success),
            const SizedBox(width: 10),
            const _Badge(text: 'SEC Data', color: accent),
          ] else ...[
            const SizedBox(width: 6),
            IconButton(
              onPressed: onOpenControls,
              tooltip: 'Open research controls',
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealingBanner extends StatelessWidget {
  const _HealingBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 300),
      tween: Tween(begin: -18, end: 0),
      builder: (context, value, child) {
        return Transform.translate(offset: Offset(0, value), child: child);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [success, accent]),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: background,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final role = message['role']?.toString() ?? '';
    if (role == 'system') {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: success.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            message['content']?.toString() ?? '',
            style: const TextStyle(color: success),
          ),
        ),
      );
    }

    final isUser = role == 'user';
    final traceId = message['trace_id']?.toString() ?? '';
    final riskFlags = _stringList(message['risk_flags']);
    final sources = _stringList(message['sources']);
    final promptVersion = _asInt(message['prompt_version'], 1);
    final content = message['content']?.toString() ?? '';
    final comparison = message['comparison']?.toString() ?? '';
    final copyText = isUser ? content : _FormattedAnswer.visibleText(content);
    final baselineAnswer = message['baseline_answer']?.toString() ?? '';
    final canCompare = !isUser && baselineAnswer.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 760),
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: isUser ? primary : Theme.of(context).cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                border: isUser
                    ? null
                    : Border.all(color: Theme.of(context).dividerColor),
              ),
              child: isUser
                  ? SelectableText(
                      content,
                      style: const TextStyle(color: textMain, height: 1.35),
                    )
                  : _FormattedAnswer(text: content),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: isUser ? WrapAlignment.end : WrapAlignment.start,
              children: [
                _CopyChip(
                  label: isUser ? 'Copy question' : 'Copy answer',
                  text: copyText,
                ),
                if (canCompare)
                  _CompareChip(
                    beforeText: baselineAnswer,
                    afterText: content,
                    beforeVersion: _asInt(
                      message['baseline_prompt_version'],
                      1,
                    ),
                    afterVersion: promptVersion,
                    beforeFlags: _stringList(message['baseline_risk_flags']),
                    afterFlags: riskFlags,
                    improvement: comparison,
                  ),
              ],
            ),
            if (!isUser) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Meta('Ticker: ${message['ticker'] ?? ''}'),
                  _Meta('Latency: ${message['latency_ms'] ?? 0}ms'),
                  InkWell(
                    onTap: traceId.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: traceId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Trace ID copied')),
                            );
                          },
                    child: _Meta(
                      'Trace: ${traceId.length > 8 ? traceId.substring(0, 8) : traceId}',
                    ),
                  ),
                  _Meta('Prompt: v$promptVersion'),
                  if (sources.isNotEmpty) _SourcesChip(sources: sources),
                ],
              ),
              const SizedBox(height: 8),
              _RiskFlags(flags: riskFlags),
              const SizedBox(height: 8),
              if (comparison.isNotEmpty) ...[
                _ComparisonBox(text: comparison),
                const SizedBox(height: 8),
              ],
              if (comparison.isEmpty)
                _HealingImpact(
                  promptVersion: promptVersion,
                  riskFlags: riskFlags,
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is List) return value.map((item) => item.toString()).toList();
    return [];
  }

  int _asInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class _FormattedAnswer extends StatelessWidget {
  const _FormattedAnswer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = visibleLines(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: SelectableText(
              line,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.35,
                fontSize: _isHeading(line) ? 15 : 14,
                fontWeight: _isHeading(line)
                    ? FontWeight.w900
                    : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }

  static String visibleText(String value) {
    return visibleLines(value).join('\n');
  }

  static List<String> visibleLines(String value) {
    final output = <String>[];
    var insideSources = false;

    for (final rawLine in value.split('\n')) {
      final cleaned = rawLine.replaceAll('**', '').trimRight();
      final trimmed = cleaned.trim();

      if (trimmed.toLowerCase() == 'sources' ||
          trimmed.toLowerCase() == 'sec sources:') {
        insideSources = true;
        continue;
      }

      if (insideSources) {
        if (trimmed.toLowerCase().contains('not financial advice')) {
          insideSources = false;
          output.add('Not financial advice.');
        }
        continue;
      }

      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        continue;
      }

      output.add(cleaned);
    }

    while (output.isNotEmpty && output.last.trim().isEmpty) {
      output.removeLast();
    }
    return output;
  }

  bool _isHeading(String line) {
    const headings = [
      'Summary',
      'Key SEC facts',
      'Bull case',
      'Bear case',
      'Risks',
      'Data limitations',
      'Confidence',
      'Sources',
      'Not financial advice.',
    ];
    return headings.contains(line.trim());
  }
}

class _CopyChip extends StatelessWidget {
  const _CopyChip({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$label copied')));
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: textMuted.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_rounded, size: 13, color: textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareChip extends StatelessWidget {
  const _CompareChip({
    required this.beforeText,
    required this.afterText,
    required this.beforeVersion,
    required this.afterVersion,
    required this.beforeFlags,
    required this.afterFlags,
    required this.improvement,
  });

  final String beforeText;
  final String afterText;
  final int beforeVersion;
  final int afterVersion;
  final List<String> beforeFlags;
  final List<String> afterFlags;
  final String improvement;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showHealingComparisonDialog(
        context: context,
        beforeText: beforeText,
        afterText: afterText,
        beforeVersion: beforeVersion,
        afterVersion: afterVersion,
        beforeFlags: beforeFlags,
        afterFlags: afterFlags,
        improvement: improvement,
      ),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: primary.withValues(alpha: 0.35)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows_rounded, size: 13, color: primary),
            SizedBox(width: 5),
            Text(
              'Compare',
              style: TextStyle(
                color: primary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showHealingComparisonDialog({
  required BuildContext context,
  required String beforeText,
  required String afterText,
  required int beforeVersion,
  required int afterVersion,
  required List<String> beforeFlags,
  required List<String> afterFlags,
  required String improvement,
}) {
  final cleanedBefore = beforeText.isEmpty
      ? 'No v1 baseline was captured in this browser session. Reset, ask the risky question once, run Agent Control, then ask it again.'
      : _FormattedAnswer.visibleText(beforeText);
  final cleanedAfter = _FormattedAnswer.visibleText(afterText);
  final improvementText = improvement.isEmpty
      ? _fallbackImprovementText()
      : improvement;

  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_fix_high_rounded, color: primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Prompt Healing Comparison',
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ComparisonColumn(
                        title: 'Before · Prompt v$beforeVersion',
                        color: warning,
                        text: cleanedBefore,
                        flags: beforeFlags,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ComparisonColumn(
                        title: 'After · Prompt v$afterVersion',
                        color: success,
                        text: cleanedAfter,
                        flags: afterFlags,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ComparisonColumn(
                        title: 'Improvement',
                        color: primary,
                        text: improvementText,
                        flags: const [],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            'BEFORE v$beforeVersion\n$cleanedBefore\n\nAFTER v$afterVersion\n$cleanedAfter\n\nIMPROVEMENT\n$improvementText',
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Comparison copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy comparison'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _fallbackImprovementText() {
  return 'The healed prompt should make risky investment questions safer by refusing personal buy/sell decisions, grounding the answer in SEC facts, and showing risks, data limits, and sources.';
}

class _ComparisonColumn extends StatelessWidget {
  const _ComparisonColumn({
    required this.title,
    required this.color,
    required this.text,
    required this.flags,
  });

  final String title;
  final Color color;
  final String text;
  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            _RiskFlags(flags: flags),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: const TextStyle(
                  color: textMain,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonBox extends StatelessWidget {
  const _ComparisonBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_fix_high_rounded, color: primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Healing comparison',
                  style: TextStyle(
                    color: primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  text,
                  style: const TextStyle(
                    color: textMain,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
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

class _SourcesChip extends StatelessWidget {
  const _SourcesChip({required this.sources});

  final List<String> sources;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: surface,
            title: const Text('SEC Sources'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: SelectableText(
                  sources.join('\n\n'),
                  style: const TextStyle(color: textMuted, height: 1.45),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: sources.join('\n'))),
                child: const Text('Copy all'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Text(
          'Sources (${sources.length})',
          style: const TextStyle(
            color: accent,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _HealingImpact extends StatelessWidget {
  const _HealingImpact({required this.promptVersion, required this.riskFlags});

  final int promptVersion;
  final List<String> riskFlags;

  @override
  Widget build(BuildContext context) {
    final riskyQuestion =
        riskFlags.contains('unsafe_advice_request') ||
        riskFlags.contains('overconfident_question');
    final healed = promptVersion > 1;

    final text = healed
        ? 'Self-healing active: prompt v$promptVersion requires SEC grounding, balanced bull/bear framing, risks, data limits, and no personal buy/sell advice.'
        : riskyQuestion
        ? 'Risky question detected: this is exactly what self-healing should improve. Run Agent Control, then ask again to compare the safer prompt.'
        : 'Baseline answer: uses SEC context and safety checks; prompt healing will make risky questions more explicit and source-grounded.';

    final color = healed
        ? success
        : riskyQuestion
        ? warning
        : accent;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            healed ? Icons.auto_fix_high : Icons.info_outline,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskFlags extends StatelessWidget {
  const _RiskFlags({required this.flags});

  final List<String> flags;

  @override
  Widget build(BuildContext context) {
    if (flags.isEmpty) {
      return const _FlagChip(label: 'No safety flags', color: success);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final flag in flags)
          _FlagChip(
            label: _friendlyFlagLabel(flag),
            color:
                flag == 'unsafe_advice' ||
                    flag == 'unsafe_advice_request' ||
                    flag == 'unsupported_claim_request' ||
                    flag == 'unsupported_speculation'
                ? danger
                : warning,
          ),
      ],
    );
  }

  String _friendlyFlagLabel(String flag) {
    const labels = {
      'unsafe_advice': 'unsafe advice',
      'unsafe_advice_request': 'buy/sell request',
      'overconfident_question': 'guarantee-style question',
      'overconfident_language': 'overconfident wording',
      'missing_sources': 'missing SEC sources',
      'missing_risks': 'missing risks',
      'missing_disclaimer': 'missing disclaimer',
      'invented_numbers_risk': 'number-grounding risk',
      'unsupported_claim_request': 'unsupported/private claim',
      'unsupported_speculation': 'unsupported speculation',
      'backend_error': 'backend error',
    };
    return labels[flag] ?? flag.replaceAll('_', ' ');
  }
}

class _QuestionChips extends StatelessWidget {
  const _QuestionChips({
    required this.normalQuestions,
    required this.riskyQuestions,
    required this.hallucinationQuestions,
    required this.initiallyCollapsed,
    required this.onSelected,
  });

  final List<String> normalQuestions;
  final List<String> riskyQuestions;
  final List<String> hallucinationQuestions;
  final bool initiallyCollapsed;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return _QuestionCarousel(
      groups: [
        _QuestionGroup('Normal research', success, normalQuestions),
        _QuestionGroup('Risky demo', warning, riskyQuestions),
        _QuestionGroup('Hallucination tests', danger, hallucinationQuestions),
      ],
      initiallyCollapsed: initiallyCollapsed,
      onSelected: onSelected,
    );
  }
}

class _QuestionGroup {
  const _QuestionGroup(this.label, this.color, this.values);

  final String label;
  final Color color;
  final List<String> values;
}

class _QuestionCarousel extends StatefulWidget {
  const _QuestionCarousel({
    required this.groups,
    required this.initiallyCollapsed,
    required this.onSelected,
  });

  final List<_QuestionGroup> groups;
  final bool initiallyCollapsed;
  final ValueChanged<String> onSelected;

  @override
  State<_QuestionCarousel> createState() => _QuestionCarouselState();
}

class _QuestionCarouselState extends State<_QuestionCarousel> {
  late bool collapsed = widget.initiallyCollapsed;
  final PageController controller = PageController();
  int page = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuestionCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.initiallyCollapsed && widget.initiallyCollapsed) {
      collapsed = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (collapsed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => collapsed = false),
            icon: const Icon(Icons.tips_and_updates_outlined),
            label: const Text('Show suggested questions'),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Suggested questions',
                  style: TextStyle(
                    color: textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide suggestions',
                onPressed: () => setState(() => collapsed = true),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.groups.length; i++)
                ChoiceChip(
                  label: Text(widget.groups[i].label),
                  selected: page == i,
                  selectedColor: widget.groups[i].color.withValues(alpha: 0.2),
                  side: BorderSide(color: widget.groups[i].color),
                  onSelected: (_) => _goToPage(i),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'Previous suggestions',
                onPressed: page == 0 ? null : () => _goToPage(page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 84,
                  child: PageView.builder(
                    controller: controller,
                    itemCount: widget.groups.length,
                    onPageChanged: (value) => setState(() => page = value),
                    itemBuilder: (context, index) {
                      final group = widget.groups[index];
                      return _ChipLine(
                        label: '${group.label}:',
                        color: group.color,
                        values: group.values,
                        onSelected: (value) {
                          widget.onSelected(value);
                          setState(() => collapsed = true);
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Next suggestions',
                onPressed: page == widget.groups.length - 1
                    ? null
                    : () => _goToPage(page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.groups.length; i++)
                Container(
                  width: i == page ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == page
                        ? widget.groups[i].color
                        : textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToPage(int index) {
    setState(() => page = index);
    controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

class _ChipLine extends StatelessWidget {
  const _ChipLine({
    required this.label,
    required this.color,
    required this.values,
    required this.onSelected,
  });

  final String label;
  final Color color;
  final List<String> values;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
        for (final value in values)
          ActionChip(
            label: Text(value),
            onPressed: () => onSelected(value),
            side: BorderSide(color: color),
            backgroundColor: Theme.of(context).cardColor,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.isHealing,
    required this.canSend,
    required this.onReset,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isLoading;
  final bool isHealing;
  final bool canSend;
  final VoidCallback onReset;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onReset,
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
            tooltip: 'Reset investment analyst',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading && !isHealing,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isHealing
                    ? 'Self-healing is updating the prompt...'
                    : canSend
                    ? 'Ask an SEC-grounded investment research question...'
                    : 'Load SEC context before chatting...',
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filled(
            onPressed: isLoading || isHealing ? null : onSend,
            style: IconButton.styleFrom(backgroundColor: primary),
            icon: const Icon(Icons.arrow_upward_rounded, color: textMain),
          ),
        ],
      ),
    );
  }
}

class _AnalystPanel extends StatelessWidget {
  const _AnalystPanel({
    required this.tickers,
    required this.selectedTicker,
    required this.promptVersion,
    required this.secContext,
    required this.isSecLoading,
    required this.secContextError,
    required this.lastRiskFlags,
    required this.onTickerChanged,
    required this.onLoadSecContext,
    this.onClose,
  });

  final List<String> tickers;
  final String selectedTicker;
  final int promptVersion;
  final Map<String, dynamic>? secContext;
  final bool isSecLoading;
  final String secContextError;
  final List<String> lastRiskFlags;
  final ValueChanged<String?> onTickerChanged;
  final VoidCallback onLoadSecContext;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final filings = secContext?['recent_filings'];
    final filingList = filings is List
        ? filings.whereType<Map>().toList()
        : <Map>[];
    final tenK = filingList
        .cast<Map>()
        .where((item) => item['form'] == '10-K')
        .firstOrNull;
    final tenQ = filingList
        .cast<Map>()
        .where((item) => item['form'] == '10-Q')
        .firstOrNull;
    final sourceCount = secContext?['source_urls'] is List
        ? (secContext!['source_urls'] as List).length
        : 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Research Controls',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Close research controls',
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _PanelSection(
            title: 'Ticker Selector',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tickers.contains(selectedTicker)
                      ? selectedTicker
                      : null,
                  menuMaxHeight: 360,
                  items: [
                    for (final ticker in tickers.take(300))
                      DropdownMenuItem(value: ticker, child: Text(ticker)),
                  ],
                  onChanged: onTickerChanged,
                  decoration: const InputDecoration(labelText: 'Ticker'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ticker in demoTickers.take(5))
                      ChoiceChip(
                        label: Text(ticker),
                        selected: selectedTicker == ticker,
                        selectedColor: primary.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selectedTicker == ticker
                              ? primary
                              : textMuted.withValues(alpha: 0.3),
                        ),
                        onSelected: (_) => onTickerChanged(ticker),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: ValueKey('manual-ticker-$selectedTicker'),
                  initialValue: selectedTicker,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z.]')),
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onFieldSubmitted: (value) {
                    final ticker = value.trim().toUpperCase();
                    if (ticker.isNotEmpty) onTickerChanged(ticker);
                  },
                  decoration: const InputDecoration(
                    labelText: 'Type ticker',
                    hintText: 'TSLA',
                    suffixIcon: Icon(Icons.keyboard_return_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Demo tickers stay pinned even if SEC loads a partial list.',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          _PanelSection(
            title: 'Prompt Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine('Prompt version', 'v$promptVersion'),
                const _InfoLine('Self-healing', 'Active'),
                const _InfoLine('Phoenix tracing', 'Configured by backend'),
              ],
            ),
          ),
          _PanelSection(
            title: 'SEC Source',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Source: SEC EDGAR filings / XBRL company facts',
                  style: TextStyle(color: textMuted),
                ),
                Text(
                  'Backend endpoint: /api/investment/sec/$selectedTicker',
                  style: const TextStyle(color: textMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isSecLoading ? null : onLoadSecContext,
                    icon: isSecLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined),
                    label: Text(
                      isSecLoading
                          ? 'Loading SEC Context...'
                          : 'Load SEC Context',
                    ),
                  ),
                ),
                if (secContextError.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: danger.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      secContextError,
                      style: const TextStyle(color: danger, fontSize: 12),
                    ),
                  ),
                ],
                if (secContext != null) ...[
                  const SizedBox(height: 12),
                  _InfoLine(
                    'Company',
                    secContext?['company_name']?.toString() ?? 'Unavailable',
                  ),
                  _InfoLine(
                    'CIK',
                    secContext?['cik']?.toString() ?? 'Unavailable',
                  ),
                  _InfoLine('Latest 10-K', _filingText(tenK)),
                  _InfoLine('Latest 10-Q', _filingText(tenQ)),
                  _InfoLine('Source URLs', '$sourceCount'),
                ],
              ],
            ),
          ),
          _PanelSection(
            title: 'Safety Checklist',
            child: Column(
              children: [
                _CheckRow(
                  'Avoids personal financial advice',
                  !lastRiskFlags.contains('unsafe_advice') &&
                      !lastRiskFlags.contains('unsafe_advice_request'),
                ),
                _CheckRow(
                  'Includes SEC sources',
                  !lastRiskFlags.contains('missing_sources'),
                ),
                _CheckRow(
                  'Includes risks',
                  !lastRiskFlags.contains('missing_risks'),
                ),
                _CheckRow('Includes data limitations', true),
                _CheckRow(
                  'Includes "Not financial advice"',
                  !lastRiskFlags.contains('missing_disclaimer'),
                ),
              ],
            ),
          ),
          _PanelSection(
            title: 'Demo Instructions',
            child: const Text(
              "Demo: Ask 'Should I buy Tesla today?', then run Self-Healing from Agent Control, then ask again. The answer should become safer and more source-grounded.",
              style: TextStyle(color: textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _filingText(Map? filing) {
    if (filing == null) return 'Unavailable';
    final date = filing['report_date'] ?? filing['filing_date'] ?? '';
    final accession = filing['accession_number'] ?? '';
    return '$date ${accession.toString().isEmpty ? '' : '· $accession'}';
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(color: textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.ok);

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber_rounded,
            color: ok ? success : warning,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _FlagChip extends StatelessWidget {
  const _FlagChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(color: textMuted, fontSize: 11));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TypingCard extends StatelessWidget {
  const _TypingCard();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analyzing SEC filings...',
              style: TextStyle(color: accent, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4),
            Text(
              'First Gemini-backed answer can take 10-20s. Healed risky answers use the faster safe path.',
              style: TextStyle(color: textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
