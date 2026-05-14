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
import 'package:web_socket_channel/web_socket_channel.dart';

const apiBase = 'http://localhost:8000';
const wsUrl = 'ws://localhost:8000/ws';

const background = Color(0xFF0A0A0F);
const surface = Color(0xFF12121A);
const card = Color(0xFF1A1A28);
const primary = Color(0xFF6C63FF);
const accent = Color(0xFF00D4AA);
const warning = Color(0xFFFFA502);
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

  late String sessionId;
  bool isLoading = false;
  late int promptVersion;
  late double hallucinationRate;
  late bool selfHealingActive;
  bool showSelfHealingBanner = false;
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
      setState(() => promptVersion = _asInt(data['prompt_version'], 1));
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
      setState(() {
        promptVersion = version;
        showSelfHealingBanner = true;
        selfHealingActive = true;
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
        _saveState();
      });
    }
  }

  Future<void> sendMessage(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || isLoading) {
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

      setState(() {
        messages.add({
          'role': 'agent',
          'content': answer,
          'timestamp': DateTime.now(),
          'latency_ms': _asInt(data['latency_ms'], 0),
          'trace_id': data['trace_id']?.toString() ?? '',
        });
        hallucinationRate = _estimateHallucinationRate();
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
      backgroundColor: background,
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

  void _saveState() {
    _savedSessionId = sessionId;
    _savedPromptVersion = promptVersion;
    _savedHallucinationRate = hallucinationRate;
    _savedSelfHealingActive = selfHealingActive;
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
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: card)),
      ),
      child: Row(
        children: [
          const Expanded(
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
            style: const TextStyle(
              color: textSecondary,
              fontWeight: FontWeight.w600,
            ),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? primary : card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(
                content,
                style: const TextStyle(color: textPrimary, height: 1.35),
              ),
            ),
            const SizedBox(height: 6),
            if (isUser)
              Text(
                _time(timestamp),
                style: const TextStyle(color: textSecondary, fontSize: 11),
              )
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    '⏱ ${message['latency_ms'] ?? 0}ms',
                    style: const TextStyle(color: textSecondary, fontSize: 11),
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
          color: card,
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

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.normalQuestions,
    required this.trickyQuestions,
    required this.onSelected,
  });

  final List<String> normalQuestions;
  final List<String> trickyQuestions;
  final ValueChanged<String> onSelected;

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
          _ChipRow(
            label: 'Normal:',
            values: normalQuestions,
            color: success,
            onSelected: onSelected,
          ),
          const SizedBox(height: 8),
          _ChipRow(
            label: 'Tricky:',
            values: trickyQuestions,
            color: warning,
            onSelected: onSelected,
          ),
        ],
      ),
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
            backgroundColor: Colors.transparent,
            labelStyle: const TextStyle(color: textPrimary),
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
      decoration: const BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: card)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.refresh, color: textSecondary),
            tooltip: 'Reset chat',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isLoading,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Ask a customer support question...',
                filled: true,
                fillColor: card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
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
