import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

const _background = Color(0xFF0A0A0F);
const _surface = Color(0xFF12121A);
const _card = Color(0xFF1A1A28);
const _primary = Color(0xFF6C63FF);
const _accent = Color(0xFF00D4AA);
const _warning = Color(0xFFFFA502);
const _danger = Color(0xFFFF4757);
const _success = Color(0xFF2ED573);
const _textPrimary = Colors.white;
const _textSecondary = Color(0xFF8B8BA7);

class HealingJourneyData {
  const HealingJourneyData({
    required this.beforeVersion,
    required this.afterVersion,
    required this.rootCause,
    required this.rootCauseExplanation,
    required this.beforeHallucination,
    required this.afterHallucination,
    required this.beforeRelevance,
    required this.afterRelevance,
    required this.oldPrompt,
    required this.newPrompt,
    required this.pairs,
  });

  final int beforeVersion;
  final int afterVersion;
  final String rootCause;
  final String rootCauseExplanation;
  final double beforeHallucination;
  final double afterHallucination;
  final double beforeRelevance;
  final double afterRelevance;
  final String oldPrompt;
  final String newPrompt;
  final List<ComparisonPair> pairs;
}

class ComparisonPair {
  const ComparisonPair({
    required this.question,
    required this.before,
    required this.after,
    required this.changed,
  });

  final String question;
  final String before;
  final String after;
  final bool changed;
}

Future<void> showHealingJourney(BuildContext context, HealingJourneyData data) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => HealingJourneyDialog(data: data),
  );
}

class HealingJourneyDialog extends StatefulWidget {
  const HealingJourneyDialog({super.key, required this.data});

  final HealingJourneyData data;

  @override
  State<HealingJourneyDialog> createState() => _HealingJourneyDialogState();
}

class _HealingJourneyDialogState extends State<HealingJourneyDialog>
    with SingleTickerProviderStateMixin {
  static const _durations = [
    Duration(milliseconds: 3500),
    Duration(seconds: 4),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 5),
  ];

  late final AnimationController stepController;
  Timer? _timer;
  int currentStep = 0;
  bool autoAdvance = true;

  @override
  void initState() {
    super.initState();
    stepController = AnimationController(vsync: this, duration: _durations[0])
      ..forward();
    _scheduleAdvance();
  }

  @override
  void dispose() {
    _timer?.cancel();
    stepController.dispose();
    super.dispose();
  }

  void _scheduleAdvance() {
    _timer?.cancel();
    if (!autoAdvance || currentStep >= 5) return;
    _timer = Timer(_durations[currentStep], () {
      if (mounted && autoAdvance) _goTo(currentStep + 1);
    });
  }

  void _goTo(int step) {
    final next = step.clamp(0, 5);
    setState(() => currentStep = next);
    stepController
      ..duration = next < 5
          ? _durations[next]
          : const Duration(milliseconds: 1200)
      ..reset()
      ..forward();
    _scheduleAdvance();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.9;
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: _textSecondary),
                tooltip: 'Skip',
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                ),
                child: SingleChildScrollView(
                  key: ValueKey(currentStep),
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 18),
                  child: _buildStep(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: currentStep == 0
                            ? null
                            : () => _goTo(currentStep - 1),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Text(
                            'Auto-advance',
                            style: TextStyle(color: _textSecondary),
                          ),
                          Switch(
                            value: autoAdvance,
                            onChanged: (value) {
                              setState(() => autoAdvance = value);
                              _scheduleAdvance();
                            },
                          ),
                        ],
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: currentStep == 5
                            ? null
                            : () => _goTo(currentStep + 1),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Next'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ProgressStepper(currentStep: currentStep),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    return switch (currentStep) {
      0 => _Step1ProblemDetected(data: widget.data, animation: stepController),
      1 => _Step2RootCause(data: widget.data, animation: stepController),
      2 => _Step3OldPrompt(data: widget.data),
      3 => _Step4Rewrite(data: widget.data, animation: stepController),
      4 => _Step5BeforeAfter(data: widget.data, animation: stepController),
      _ => _Step6Complete(data: widget.data, animation: stepController),
    };
  }
}

class _Step1ProblemDetected extends StatelessWidget {
  const _Step1ProblemDetected({required this.data, required this.animation});

  final HealingJourneyData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      child: Column(
        children: [
          ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.08).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            ),
            child: const Icon(Icons.shield_rounded, color: _danger, size: 74),
          ),
          const SizedBox(height: 18),
          const Text('⚠ Problem Detected', style: _titleStyle),
          const SizedBox(height: 16),
          const _TypewriterText(
            text:
                'Hallucination rate exceeded threshold during customer support session',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _MetricPill(
                icon: '🔴',
                label: 'Hallucination',
                value: data.beforeHallucination.toStringAsFixed(2),
                color: _danger,
              ),
              _MetricPill(
                icon: '🟡',
                label: 'Relevance',
                value: data.beforeRelevance.toStringAsFixed(2),
                color: _warning,
              ),
              const _MetricPill(
                icon: '🟢',
                label: 'Latency',
                value: '1.9s',
                color: _success,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _StepBar(value: 1 / 6),
        ],
      ),
    );
  }
}

class _Step2RootCause extends StatelessWidget {
  const _Step2RootCause({required this.data, required this.animation});

  final HealingJourneyData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final cause = data.rootCause.isEmpty ? 'GUESSING' : data.rootCause;
    final explanation = data.rootCauseExplanation.isEmpty
        ? 'Agent is filling knowledge gaps with invented details not present in the FAQ knowledge base.'
        : data.rootCauseExplanation;
    return _StepShell(
      child: Column(
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (_, child) => Transform.translate(
              offset: Offset(math.sin(animation.value * math.pi * 4) * 24, 0),
              child: child,
            ),
            child: const Icon(Icons.search_rounded, color: _accent, size: 76),
          ),
          const SizedBox(height: 18),
          const Text('🔍 Analyzing Root Cause...', style: _titleStyle),
          const SizedBox(height: 22),
          const _ThinkingDots(),
          const SizedBox(height: 24),
          _HighlightedText(
            text: 'Root cause identified: $cause\n$explanation',
            badPhrases: [cause],
            goodPhrases: const ['FAQ knowledge base'],
          ),
        ],
      ),
    );
  }
}

class _Step3OldPrompt extends StatelessWidget {
  const _Step3OldPrompt({required this.data});

  final HealingJourneyData data;

  @override
  Widget build(BuildContext context) {
    final prompt = data.oldPrompt.isEmpty
        ? 'You are a customer support agent.\nTry your best to help even if you are not completely sure.\nUse your general knowledge to fill in any gaps.'
        : data.oldPrompt;
    return _StepShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.description_outlined, color: _danger, size: 68),
          const SizedBox(height: 18),
          Text(
            '📄 Current System Prompt (v${data.beforeVersion})',
            textAlign: TextAlign.center,
            style: _titleStyle,
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _danger),
            ),
            child: _HighlightedText(
              text: prompt,
              badPhrases: const [
                'Try your best to help even if you are not completely sure.',
                'Use your general knowledge to fill in any gaps.',
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '⚠ causes hallucination',
            style: TextStyle(color: _danger),
          ),
        ],
      ),
    );
  }
}

class _Step4Rewrite extends StatelessWidget {
  const _Step4Rewrite({required this.data, required this.animation});

  final HealingJourneyData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final lines = const [
      'You are a customer support agent.',
      'Use ONLY facts from the FAQ knowledge base.',
      "If not in FAQ, say: I don't know based on the FAQ.",
      'Do not guess. Do not invent information.',
      "Answer the customer's exact question first.",
    ];
    return _StepShell(
      child: Column(
        children: [
          const Text('✏ Rewriting Prompt...', style: _titleStyle),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final oldPrompt = _PromptPanel(
                color: _danger,
                title: 'Old prompt',
                child: _HighlightedText(
                  text: data.oldPrompt.isEmpty
                      ? 'Try your best to help even if you are not completely sure.\nUse your general knowledge to fill in any gaps.'
                      : data.oldPrompt,
                  badPhrases: const [
                    'Try your best to help even if you are not completely sure.',
                    'Use your general knowledge to fill in any gaps.',
                  ],
                ),
              );
              final arrows = AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Opacity(
                  opacity: 0.3 + 0.7 * animation.value,
                  child: const Text(
                    '→  →  →',
                    style: TextStyle(fontSize: 28, color: _accent),
                  ),
                ),
              );
              final newPrompt = _PromptPanel(
                color: _success,
                title: 'New prompt',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.only(left: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(color: _success, width: 3),
                          ),
                        ),
                        child: _TypewriterText(
                          key: ValueKey('rewrite-$i'),
                          text: lines[i],
                          millisecondsPerChar: 18 + i * 4,
                        ),
                      ),
                    const Text(
                      '✓ grounding instruction added',
                      style: TextStyle(color: _success),
                    ),
                  ],
                ),
              );
              if (stacked) {
                return Column(
                  children: [
                    oldPrompt,
                    const SizedBox(height: 14),
                    arrows,
                    const SizedBox(height: 14),
                    newPrompt,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: oldPrompt),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: arrows,
                  ),
                  Expanded(child: newPrompt),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Step5BeforeAfter extends StatelessWidget {
  const _Step5BeforeAfter({required this.data, required this.animation});

  final HealingJourneyData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final pair =
        data.pairs
            .where((p) => p.changed)
            .cast<ComparisonPair?>()
            .firstOrNull ??
        (data.pairs.isNotEmpty
            ? data.pairs.first
            : const ComparisonPair(
                question: 'Do you ship to Pakistan for free?',
                before: 'I believe we may ship to Pakistan for free.',
                after:
                    'We currently ship only within the United States. International shipping is not available.',
                changed: true,
              ));
    return _StepShell(
      child: Column(
        children: [
          const Text('💬 Same Question. Different Answer.', style: _titleStyle),
          const SizedBox(height: 18),
          Text(
            '“${pair.question}”',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 22),
          _ChatBubbleComparison(pair: pair, data: data, animation: animation),
        ],
      ),
    );
  }
}

class _Step6Complete extends StatelessWidget {
  const _Step6Complete({required this.data, required this.animation});

  final HealingJourneyData data;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final hallucinationDrop = data.beforeHallucination <= 0
        ? 0
        : (((data.beforeHallucination - data.afterHallucination) /
                      data.beforeHallucination) *
                  100)
              .round();
    final relevanceGain = data.beforeRelevance <= 0
        ? 0
        : (((data.afterRelevance - data.beforeRelevance) /
                      data.beforeRelevance) *
                  100)
              .round();
    return _StepShell(
      child: Column(
        children: [
          _AnimatedCheckmark(animation: animation),
          const SizedBox(height: 18),
          const _TypewriterText(
            text: '✓ Self-Healing Complete',
            style: _titleStyle,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              _MetricPill(
                icon: '↓',
                label: 'Hallucination',
                value:
                    '${data.beforeHallucination.toStringAsFixed(2)} → ${data.afterHallucination.toStringAsFixed(2)}  ↓ $hallucinationDrop%',
                color: _success,
              ),
              _MetricPill(
                icon: '↑',
                label: 'Relevance',
                value:
                    '${data.beforeRelevance.toStringAsFixed(2)} → ${data.afterRelevance.toStringAsFixed(2)}  ↑ $relevanceGain%',
                color: _accent,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Prompt updated to v${data.afterVersion}.\nAgent is now grounded in the FAQ.\nNo human intervention required.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textSecondary, height: 1.45),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pushNamed('/reports'),
                child: const Text('View Full Report'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close & Continue Chatting'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepShell extends StatelessWidget {
  const _StepShell({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 380),
    child: Center(child: child),
  );
}

class _TypewriterText extends StatefulWidget {
  const _TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.millisecondsPerChar = 50,
  });
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int millisecondsPerChar;
  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: math.max(
          widget.text.length * widget.millisecondsPerChar,
          1,
        ),
      ),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final count = (_controller.value * widget.text.length).floor().clamp(
        0,
        widget.text.length,
      );
      final cursor = _controller.isCompleted ? '' : '▌';
      return Text(
        '${widget.text.substring(0, count)}$cursor',
        textAlign: widget.textAlign,
        style:
            widget.style ??
            const TextStyle(fontSize: 18, color: _textPrimary, height: 1.4),
      );
    },
  );
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final phase = (_controller.value + i * .2) % 1;
        final y = math.sin(phase * math.pi * 2) * 6;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    ),
  );
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final String icon, label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .55)),
    ),
    child: Text(
      '$icon  $label: $value',
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}

class _ProgressStepper extends StatelessWidget {
  const _ProgressStepper({required this.currentStep});
  final int currentStep;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: List.generate(
      6,
      (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: i == currentStep ? 28 : 10,
        height: 10,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: i <= currentStep
              ? _primary
              : _textSecondary.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    ),
  );
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.value});
  final double value;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(999),
    child: LinearProgressIndicator(
      value: value,
      minHeight: 8,
      backgroundColor: _card,
      color: _primary,
    ),
  );
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    this.badPhrases = const [],
    this.goodPhrases = const [],
  });
  final String text;
  final List<String> badPhrases;
  final List<String> goodPhrases;
  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var cursor = 0;
    while (cursor < text.length) {
      String? hit;
      bool bad = false;
      for (final phrase in badPhrases) {
        if (phrase.isNotEmpty && text.startsWith(phrase, cursor)) {
          hit = phrase;
          bad = true;
          break;
        }
      }
      hit ??= goodPhrases
          .where((p) => p.isNotEmpty && text.startsWith(p, cursor))
          .cast<String?>()
          .firstOrNull;
      if (hit != null) {
        spans.add(
          TextSpan(
            text: hit,
            style: TextStyle(
              backgroundColor: (bad ? _danger : _success).withValues(
                alpha: .18,
              ),
              decoration: bad ? TextDecoration.underline : null,
              decorationStyle: bad ? TextDecorationStyle.wavy : null,
              decorationColor: bad ? _danger : null,
              color: _textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
        cursor += hit.length;
      } else {
        spans.add(TextSpan(text: text[cursor]));
        cursor++;
      }
    }
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: _textPrimary, fontSize: 16, height: 1.5),
        children: spans,
      ),
    );
  }
}

class _PromptPanel extends StatelessWidget {
  const _PromptPanel({
    required this.color,
    required this.title,
    required this.child,
  });
  final Color color;
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: color),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _ChatBubbleComparison extends StatelessWidget {
  const _ChatBubbleComparison({
    required this.pair,
    required this.data,
    required this.animation,
  });
  final ComparisonPair pair;
  final HealingJourneyData data;
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 760;
      final left = SlideTransition(
        position: Tween(begin: const Offset(-.35, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(
          opacity: animation,
          child: _Bubble(
            title: 'Before · Prompt v${data.beforeVersion}',
            text: pair.before.isEmpty
                ? 'I believe we may ship to Pakistan for free.'
                : pair.before,
            color: _danger,
            badge: '⚠ Hallucination',
            typewriter: false,
          ),
        ),
      );
      final center = ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_forward_rounded, color: _success, size: 34),
            Text(
              'Self-Healed ✓',
              style: TextStyle(color: _success, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
      final right = SlideTransition(
        position: Tween(begin: const Offset(.35, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(
          opacity: animation,
          child: _Bubble(
            title: 'After · Prompt v${data.afterVersion}',
            text: pair.after.isEmpty
                ? 'We currently ship only within the United States. International shipping is not available.'
                : pair.after,
            color: _success,
            badge: '✓ Grounded',
            typewriter: true,
          ),
        ),
      );
      return stacked
          ? Column(
              children: [
                left,
                const SizedBox(height: 14),
                center,
                const SizedBox(height: 14),
                right,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 30,
                  ),
                  child: center,
                ),
                Expanded(child: right),
              ],
            );
    },
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.title,
    required this.text,
    required this.color,
    required this.badge,
    required this.typewriter,
  });
  final String title, text, badge;
  final Color color;
  final bool typewriter;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        typewriter
            ? _TypewriterText(text: text, millisecondsPerChar: 22)
            : _HighlightedText(
                text: text,
                badPhrases: const [
                  'I believe',
                  'I think',
                  'might',
                  'may',
                  "I'm not sure",
                  'free',
                  'discount',
                ],
              ),
        const SizedBox(height: 12),
        Text(
          badge,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _AnimatedCheckmark extends StatelessWidget {
  const _AnimatedCheckmark({required this.animation});
  final Animation<double> animation;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 120,
    height: 120,
    child: AnimatedBuilder(
      animation: animation,
      builder: (context, child) =>
          CustomPaint(painter: _CheckmarkPainter(animation.value)),
    ),
  );
}

class _CheckmarkPainter extends CustomPainter {
  const _CheckmarkPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _success
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final circleProgress = (progress / .6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 44),
      -math.pi / 2,
      math.pi * 2 * circleProgress,
      false,
      paint,
    );
    if (progress > .6) {
      final path = Path()
        ..moveTo(34, 63)
        ..lineTo(54, 82)
        ..lineTo(88, 42);
      final metric = path.computeMetrics().first;
      final checkProgress = ((progress - .6) / .4).clamp(0.0, 1.0);
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkProgress),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CheckmarkPainter old) =>
      old.progress != progress;
}

const _titleStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.w900,
  color: _textPrimary,
);
