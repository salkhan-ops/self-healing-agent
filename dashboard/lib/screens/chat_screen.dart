/// iMessage-style chat demo for the self-healing customer support agent.
///
/// This screen talks directly to the FastAPI chat endpoints and listens for
/// WebSocket prompt-update events so users can watch self-healing happen live.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../providers/agent_provider.dart';

const apiBase = 'http://localhost:8000';
const wsUrl = 'ws://localhost:8000/ws';

const background = Color(0xFF0A0A0F);
const surface = Color(0xFF12121A);
const card = Color(0xFF1A1A28);
const primary = Color(0xFF6C63FF);
const accent = Color(0xFF00D4AA);
const warning = Color(0xFFFFA502);
const danger = Color(0xFFFF4757);
const success = Color(0xFF2ED573);
const textPrimary = Colors.white;
const textSecondary = Color(0xFF8B8BA7);

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  static final List<Map<String, dynamic>> _savedMessages = [];
  static String _savedSessionId = '';
  static int _savedPromptVersion = 1;
  static double _savedHallucinationRate = 0.0;
  static bool _savedSelfHealingActive = true;
  static Map<String, dynamic>? _savedPendingHealingBaseline;
  static final Map<String, Map<String, dynamic>> _answersByQuestion = {};

  late List<Map<String, dynamic>> messages;
  final inputController = TextEditingController();
  final scrollController = ScrollController();
  final normalQuestions = const [
    'What is your return policy?',
    'How do I track my order?',
    'How long does shipping take?',
  ];
  final trickyQuestions = const [
    'Do you ship to Pakistan for free?',
    "What is the CEO's phone number?",
    'Can I get a 90% discount?',
    'What color is your logo?',
    'Who founded this company?',
    'What is your Bitcoin payment address?',
  ];
  final hallucinationQuestions = const [
    "What is the CEO's phone number?",
    'What is your Bitcoin payment address?',
    'Do you ship to Pakistan for free?',
    'Can I get a 90% discount?',
  ];

  late String sessionId;
  bool isLoading = false;
  late int promptVersion;
  late double hallucinationRate;
  late bool selfHealingActive;
  bool showSelfHealingBanner = false;
  Map<String, dynamic>? pendingHealingBaseline;
  WebSocketChannel? wsChannel;
  late final AnimationController _badgeController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    messages = _savedMessages;
    sessionId = _savedSessionId;
    promptVersion = _savedPromptVersion;
    hallucinationRate = _savedHallucinationRate;
    selfHealingActive = _savedSelfHealingActive;
    pendingHealingBaseline = _savedPendingHealingBaseline;
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      lowerBound: 0.92,
      upperBound: 1.12,
    )..value = 1;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
      lowerBound: 0.65,
      upperBound: 1,
    )..repeat(reverse: true);
    connectWebSocket();
    loadStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AgentProvider>().connectWebSocket();
      context.read<AgentProvider>().loadStatus();
    });
  }

  @override
  void dispose() {
    wsChannel?.sink.close();
    inputController.dispose();
    scrollController.dispose();
    _badgeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> loadStatus() async {
    try {
      final response = await http.get(Uri.parse('$apiBase/api/chat/status'));
      if (response.statusCode != 200) {
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextVersion = _asInt(data['prompt_version'], 1);
      final baseline =
          nextVersion > promptVersion && pendingHealingBaseline == null
          ? _latestCompletedExchange()
          : null;
      setState(() {
        promptVersion = nextVersion;
        if (baseline != null) {
          pendingHealingBaseline = baseline;
          inputController.text = baseline['question']?.toString() ?? '';
        }
        _saveState();
      });
    } catch (error) {
      debugPrint('Chat status load failed: $error');
    }
  }

  void connectWebSocket() {
    try {
      wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      wsChannel!.stream.listen(
        (event) => _handleSocketMessage(event.toString()),
        onError: (error) {
          debugPrint('Chat WebSocket error: $error');
          _reconnectWebSocket();
        },
        onDone: _reconnectWebSocket,
      );
    } catch (error) {
      debugPrint('Chat WebSocket connect failed: $error');
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    if (!mounted) {
      return;
    }
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        connectWebSocket();
      }
    });
  }

  void _handleSocketMessage(String message) {
    if (message.startsWith('prompt_updated:v')) {
      final version = int.tryParse(message.split(':v').last) ?? promptVersion;
      final baseline = _latestCompletedExchange();
      setState(() {
        promptVersion = version;
        showSelfHealingBanner = true;
        selfHealingActive = true;
        pendingHealingBaseline = baseline;
        if (baseline != null) {
          inputController.text = baseline['question']?.toString() ?? '';
        }
        _saveState();
      });
      _badgeController
          .forward(from: 0.92)
          .then((_) => _badgeController.reverse());
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => showSelfHealingBanner = false);
        }
      });
    }

    if (message == 'chat_reset:v1') {
      setState(() {
        messages.clear();
        promptVersion = 1;
        sessionId = '';
        hallucinationRate = 0.0;
        _answersByQuestion.clear();
        pendingHealingBaseline = null;
        _saveState();
      });
    }
  }

  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || isLoading) {
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
        Uri.parse('$apiBase/api/chat/message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': cleanText, 'session_id': sessionId}),
      );

      if (response.statusCode != 200) {
        throw Exception('Chat API returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      sessionId = data['session_id']?.toString() ?? sessionId;
      promptVersion = _asInt(data['prompt_version'], promptVersion);
      final answer = data['answer']?.toString() ?? 'I could not answer that.';
      final key = _normalizeQuestion(cleanText);
      final prior =
          pendingHealingBaseline ?? _findPreviousAnswer(key, promptVersion);
      final comparison = prior == null
          ? ''
          : _buildComparison(prior, answer, promptVersion);

      setState(() {
        messages.add({
          'role': 'agent',
          'content': answer,
          'question': cleanText,
          'timestamp': DateTime.now(),
          'latency_ms': _asInt(data['latency_ms'], 0),
          'trace_id': data['trace_id']?.toString() ?? '',
          'prompt_version': promptVersion,
          'baseline_answer': prior?['answer'],
          'baseline_prompt_version': prior?['prompt_version'],
          'comparison': comparison,
        });
        _answersByQuestion[key] = {
          'question': cleanText,
          'answer': answer,
          'prompt_version': promptVersion,
        };
        hallucinationRate = _estimateHallucinationRate();
        if (comparison.isNotEmpty) {
          pendingHealingBaseline = null;
        }
        _saveState();
      });
    } catch (error) {
      setState(() {
        messages.add({
          'role': 'agent',
          'content': 'Chat service is unavailable right now. Please try again.',
          'timestamp': DateTime.now(),
          'latency_ms': 0,
          'trace_id': '',
        });
        _saveState();
      });
      debugPrint('sendMessage failed: $error');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> resetChat() async {
    try {
      await http.post(Uri.parse('$apiBase/api/chat/reset'));
      if (!mounted) {
        return;
      }
      setState(() {
        messages.clear();
        sessionId = '';
        promptVersion = 1;
        hallucinationRate = 0.0;
        _answersByQuestion.clear();
        pendingHealingBaseline = null;
        _saveState();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat reset to weak prompt v1')),
      );
    } catch (error) {
      debugPrint('resetChat failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMessages = messages.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _TopBar(
            promptVersion: promptVersion,
            selfHealingActive: selfHealingActive,
            pulse: _pulseController,
            badgeScale: _badgeController,
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: showSelfHealingBanner
                ? _SelfHealingBanner(promptVersion: promptVersion)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 18),
              itemCount: messages.length + (isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == messages.length) {
                  return const _TypingIndicator();
                }
                final message = messages[index];
                return _MessageBubble(message: message);
              },
            ),
          ),
          if (!hasMessages)
            _Suggestions(
              normalQuestions: normalQuestions,
              trickyQuestions: trickyQuestions,
              hallucinationQuestions: hallucinationQuestions,
              onSelected: sendMessage,
            ),
          _InputBar(
            controller: inputController,
            isLoading: isLoading,
            onReset: resetChat,
            onSend: () => sendMessage(inputController.text),
          ),
        ],
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) {
        return;
      }
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _estimateHallucinationRate() {
    final agentMessages = messages
        .where((message) => message['role'] == 'agent')
        .toList();
    if (agentMessages.isEmpty) {
      return 0;
    }
    final flagged = agentMessages.where((message) {
      return _mightBeHallucination(message['content']?.toString() ?? '');
    }).length;
    return flagged / max(agentMessages.length, 1);
  }

  int _asInt(dynamic value, int fallback) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _normalizeQuestion(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Map<String, dynamic>? _findPreviousAnswer(String key, int version) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message['role'] != 'agent') continue;
      var question = message['question']?.toString() ?? '';
      if (question.isEmpty) {
        for (var prior = index - 1; prior >= 0; prior--) {
          if (messages[prior]['role'] == 'user') {
            question = messages[prior]['content']?.toString() ?? '';
            break;
          }
        }
      }
      final prompt = _asInt(message['prompt_version'], 1);
      if (_normalizeQuestion(question) == key && prompt < version) {
        return {'answer': message['content'], 'prompt_version': prompt};
      }
    }
    return null;
  }

  String _buildComparison(
    Map<String, dynamic> before,
    String after,
    int afterVersion,
  ) {
    final beforeText = before['answer']?.toString().toLowerCase() ?? '';
    final afterText = after.toLowerCase();
    final improvements = <String>[
      if (_mightBeHallucination(beforeText) &&
          !_mightBeHallucination(afterText))
        'removed unsupported guessing',
      if (afterText.contains("i don't know based on the faq"))
        'grounded the answer in the FAQ instead of inventing missing details',
    ];
    if (improvements.isEmpty) improvements.add('kept the answer FAQ-grounded');
    return 'Before v${before['prompt_version'] ?? 1}: ${_mightBeHallucination(beforeText) ? 'possible hallucination' : 'no warning'}\n'
        'After v$afterVersion: ${_mightBeHallucination(afterText) ? 'possible hallucination' : 'grounded'}\n'
        'Healing impact: ${improvements.join(', ')}.';
  }

  Map<String, dynamic>? _latestCompletedExchange() {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index]['role'] != 'agent') continue;
      var question = messages[index]['question']?.toString() ?? '';
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
        'answer': messages[index]['content']?.toString() ?? '',
        'prompt_version': _asInt(
          messages[index]['prompt_version'],
          promptVersion,
        ),
      };
    }
    return null;
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

  void _saveState() {
    _savedSessionId = sessionId;
    _savedPromptVersion = promptVersion;
    _savedHallucinationRate = hallucinationRate;
    _savedSelfHealingActive = selfHealingActive;
    _savedPendingHealingBaseline = pendingHealingBaseline;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.promptVersion,
    required this.selfHealingActive,
    required this.pulse,
    required this.badgeScale,
  });

  final int promptVersion;
  final bool selfHealingActive;
  final Animation<double> pulse;
  final Animation<double> badgeScale;

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<AgentProvider>();
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Customer Support Chat',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ),
          ScaleTransition(
            scale: badgeScale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Prompt v$promptVersion',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 16),
          FadeTransition(
            opacity: pulse,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: success,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            selfHealingActive ? 'Self-Healing Active' : 'Self-Healing Paused',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: 'Run Agent Control',
            onPressed: agent.isRunning ? null : agent.runNow,
            style: IconButton.styleFrom(
              foregroundColor: success,
              side: BorderSide(color: success.withValues(alpha: 0.7)),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            tooltip: 'Stop Agent Control',
            onPressed: agent.isRunning && !agent.isStopping
                ? agent.stopNow
                : null,
            style: IconButton.styleFrom(
              foregroundColor: danger,
              side: BorderSide(color: danger.withValues(alpha: 0.7)),
            ),
            icon: const Icon(Icons.stop_circle_outlined),
          ),
        ],
      ),
    );
  }
}

class _SelfHealingBanner extends StatelessWidget {
  const _SelfHealingBanner({required this.promptVersion});

  final int promptVersion;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 320),
      tween: Tween(begin: -1, end: 0),
      builder: (context, value, child) {
        return Transform.translate(offset: Offset(0, value * 40), child: child);
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(28, 18, 28, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [success, accent]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          '🔧 Self-Healing fixed the agent! Prompt updated to v$promptVersion — answers are now more accurate',
          style: const TextStyle(
            color: background,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final content = message['content']?.toString() ?? '';
    final traceId = message['trace_id']?.toString() ?? '';
    final timestamp = message['timestamp'] is DateTime
        ? message['timestamp'] as DateTime
        : DateTime.now();
    final possibleHallucination = !isUser && _mightBeHallucination(content);
    final promptVersion = message['prompt_version'] is int
        ? message['prompt_version'] as int
        : int.tryParse(message['prompt_version']?.toString() ?? '') ?? 1;
    final baselineAnswer = message['baseline_answer']?.toString() ?? '';
    final comparison = message['comparison']?.toString() ?? '';
    final canCompare = !isUser && baselineAnswer.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (canCompare) ...[
              OutlinedButton.icon(
                onPressed: () => _showSupportComparisonDialog(
                  context: context,
                  beforeText: baselineAnswer,
                  afterText: content,
                  beforeVersion:
                      int.tryParse(
                        message['baseline_prompt_version']?.toString() ?? '',
                      ) ??
                      1,
                  afterVersion: promptVersion,
                  improvement: comparison,
                ),
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Show Before/After Improvement'),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? primary : Theme.of(context).cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(
                content,
                style: TextStyle(
                  color: isUser
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isUser ? 'Question copied' : 'Answer copied',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: Text(isUser ? 'Copy question' : 'Copy answer'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (isUser)
              Text(
                _time(timestamp),
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  fontSize: 11,
                ),
              )
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    '⏱ ${message['latency_ms'] ?? 0}ms',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 11,
                    ),
                  ),
                  const Text(
                    '|',
                    style: TextStyle(color: textSecondary, fontSize: 11),
                  ),
                  InkWell(
                    onTap: traceId.isEmpty
                        ? null
                        : () => Clipboard.setData(ClipboardData(text: traceId)),
                    child: Text(
                      'trace: ${traceId.length > 8 ? traceId.substring(0, 8) : traceId}',
                      style: const TextStyle(color: accent, fontSize: 11),
                    ),
                  ),
                  if (possibleHallucination)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: warning.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '⚠ Possible hallucination',
                        style: TextStyle(
                          color: warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final opacity =
                    0.35 + 0.65 * sin((controller.value * 2 * pi) + index);
                return Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: textSecondary.withValues(
                      alpha: opacity.clamp(0.2, 1.0),
                    ),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _Suggestions extends StatefulWidget {
  const _Suggestions({
    required this.normalQuestions,
    required this.trickyQuestions,
    required this.hallucinationQuestions,
    required this.onSelected,
  });

  final List<String> normalQuestions;
  final List<String> trickyQuestions;
  final List<String> hallucinationQuestions;
  final ValueChanged<String> onSelected;

  @override
  State<_Suggestions> createState() => _SuggestionsState();
}

class _SuggestionsState extends State<_Suggestions> {
  final controller = PageController();
  int page = 0;

  List<({String label, Color color, List<String> values})> get groups => [
    (label: 'Normal', color: success, values: widget.normalQuestions),
    (label: 'Tricky', color: warning, values: widget.trickyQuestions),
    (
      label: 'Hallucination tests',
      color: danger,
      values: widget.hallucinationQuestions,
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Try these questions:',
            style: TextStyle(color: textSecondary, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < groups.length; i++)
                ChoiceChip(
                  label: Text(groups[i].label),
                  selected: page == i,
                  selectedColor: groups[i].color.withValues(alpha: 0.2),
                  side: BorderSide(color: groups[i].color),
                  onSelected: (_) => _goTo(i),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton.outlined(
                onPressed: page == 0 ? null : () => _goTo(page - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: SizedBox(
                  height: 78,
                  child: PageView.builder(
                    controller: controller,
                    itemCount: groups.length,
                    onPageChanged: (value) => setState(() => page = value),
                    itemBuilder: (context, index) => _ChipRow(
                      label: '${groups[index].label}:',
                      values: groups[index].values,
                      color: groups[index].color,
                      onSelected: widget.onSelected,
                    ),
                  ),
                ),
              ),
              IconButton.outlined(
                onPressed: page == groups.length - 1
                    ? null
                    : () => _goTo(page + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _goTo(int index) {
    setState(() => page = index);
    controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.label,
    required this.values,
    required this.color,
    required this.onSelected,
  });

  final String label;
  final List<String> values;
  final Color color;
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
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        for (final value in values)
          ActionChip(
            label: Text(value),
            side: BorderSide(color: color),
            backgroundColor: Theme.of(context).cardColor,
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () => onSelected(value),
          ),
      ],
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isLoading,
    required this.onReset,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isLoading;
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
            tooltip: 'Reset chat',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: 'Ask a customer support question...',
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
            onPressed: isLoading ? null : onSend,
            style: IconButton.styleFrom(
              backgroundColor: isLoading ? textSecondary : primary,
              disabledBackgroundColor: textSecondary.withValues(alpha: 0.25),
            ),
            icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

bool _mightBeHallucination(String text) {
  final lowered = text.toLowerCase();
  return lowered.contains("i'm not sure") ||
      lowered.contains('i believe') ||
      lowered.contains('might be') ||
      lowered.contains('i think');
}

Future<void> _showSupportComparisonDialog({
  required BuildContext context,
  required String beforeText,
  required String afterText,
  required int beforeVersion,
  required int afterVersion,
  required String improvement,
}) {
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
                  const Icon(Icons.auto_fix_high_rounded, color: primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Customer Support Healing Comparison',
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
                      child: _SupportComparisonColumn(
                        title: 'Before · Prompt v$beforeVersion',
                        color: warning,
                        text: beforeText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SupportComparisonColumn(
                        title: 'After · Prompt v$afterVersion',
                        color: success,
                        text: afterText,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SupportComparisonColumn(
                        title: 'Improvement',
                        color: primary,
                        text: improvement,
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

class _SupportComparisonColumn extends StatelessWidget {
  const _SupportComparisonColumn({
    required this.title,
    required this.color,
    required this.text,
  });

  final String title;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Expanded(child: SingleChildScrollView(child: SelectableText(text))),
        ],
      ),
    );
  }
}
