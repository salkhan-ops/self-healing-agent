import 'package:flutter/material.dart';

import '../core/responsive.dart';
import '../core/theme.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  int _selectedIndex = 0;

  static const _articles = <_ResourceArticle>[
    _ResourceArticle(
      title: 'Self-Healing Agent Architecture',
      category: 'Architecture',
      readTime: '7 min',
      summary:
          'A visual explanation of how the dashboard, FastAPI backend, Phoenix MCP, Gemini, and the healing loop work together.',
      showArchitectureDiagram: true,
      sections: [
        _ArticleSection(
          heading: 'The production problem',
          body:
              'AI systems fail in ways that normal software dashboards do not catch quickly enough. A response can be fluent, confident, and still wrong. In customer support, that means a policy mistake. In social media, it means inflated claims. In finance, it means unsupported analysis. A self-healing agent treats these failures as operational incidents instead of isolated bad outputs.',
        ),
        _ArticleSection(
          heading: 'The healing loop',
          body:
              'The core loop is intentionally simple: capture the answer, evaluate it, diagnose the failure mode, rewrite the prompt, verify the new behavior, and publish evidence. This turns a subjective quality complaint into a traceable workflow.',
        ),
        _ArticleSection(
          heading: 'Why the architecture matters',
          body:
              'The agent does not only generate answers. It observes its own behavior through Phoenix traces, retrieves those traces through MCP, uses Gemini to judge and repair failures, and then pushes updated prompts back into the live agents.',
        ),
      ],
    ),
    _ResourceArticle(
      title: 'Phoenix Traces as the Agent Memory for Repair',
      category: 'Observability',
      readTime: '5 min',
      summary:
          'How trace evidence connects one AI output to the healing action that follows.',
      sections: [
        _ArticleSection(
          heading: 'Trace first, diagnose second',
          body:
              'A healing system needs more than logs. It needs input, output, span name, timestamp, use case, scores, and run metadata. Phoenix traces provide the evidence trail for the agent.',
        ),
        _ArticleSection(
          heading: 'What judges should see',
          body:
              'A judge should be able to open Phoenix Traces and immediately see the project, MCP retrieval status, trace IDs, span names, scores, and before or after status.',
        ),
        _ArticleSection(
          heading: 'Why MCP matters',
          body:
              'Phoenix MCP turns observability into an agent-readable interface. Instead of only showing traces to humans, the system can retrieve trace evidence during the repair loop.',
        ),
      ],
    ),
    _ResourceArticle(
      title: 'Use Case: Customer Support That Stops Guessing',
      category: 'Customer Support',
      readTime: '6 min',
      summary:
          'How the support agent moves from confident guessing to FAQ-grounded answers.',
      sections: [
        _ArticleSection(
          heading: 'The risk',
          body:
              'Support agents are high-risk because users treat their answers as policy. A weak prompt can invent refund terms, shipping guarantees, or escalation paths.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The support workflow evaluates the answer against FAQ-grounded expectations. When hallucination is high or relevance is weak, the system diagnoses the pattern and rewrites the prompt toward grounded behavior.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'The judge can ask a policy question, see the initial response, trigger healing, and inspect the before and after report.',
        ),
      ],
    ),
    _ResourceArticle(
      title: 'Use Case: Social Media Posts Without Inflated Claims',
      category: 'Social Media',
      readTime: '5 min',
      summary:
          'Why post generation needs claim discipline, not just creativity.',
      sections: [
        _ArticleSection(
          heading: 'The risk',
          body:
              'Social media generation often rewards punchy language. That is exactly where hallucination becomes expensive.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The social media healer compares the brief to the generated post, scores hallucination and relevance, and patches the prompt with stricter grounding rules.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'The post workflow shows a clean business story for hackathon judging: the agent catches exaggerated language, rewrites its own instructions, and produces a safer post.',
        ),
      ],
    ),
    _ResourceArticle(
      title: 'Use Case: Investment Analysis Grounded in SEC Evidence',
      category: 'Investment',
      readTime: '7 min',
      summary:
          'How SEC-grounded analysis reduces unsupported financial conclusions.',
      sections: [
        _ArticleSection(
          heading: 'The risk',
          body:
              'Investment answers are high-stakes because confident language can be mistaken for advice.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The investment workflow combines SEC context with evaluation of grounding, risk flags, and answer quality.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'This use case shows why self-healing is not only for chatbots. The same trace, score, diagnose, patch, and verify loop can protect factual workflows.',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _articles[_selectedIndex];

    return Padding(
      padding: Responsive.pagePadding(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resources',
                  style: TextStyle(
                    fontSize: Responsive.isHandset(context) ? 28 : 34,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 20),
                if (compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ArticleList(
                        articles: _articles,
                        selectedIndex: _selectedIndex,
                        onSelected: _selectArticle,
                      ),
                      const SizedBox(height: 16),
                      _ArticleReader(article: selected),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 360,
                        child: _ArticleList(
                          articles: _articles,
                          selectedIndex: _selectedIndex,
                          onSelected: _selectArticle,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: _ArticleReader(article: selected)),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _selectArticle(int index) {
    setState(() => _selectedIndex = index);
  }
}

class _ArticleList extends StatelessWidget {
  const _ArticleList({
    required this.articles,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ResourceArticle> articles;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < articles.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ArticleCard(
              article: articles[index],
              selected: index == selectedIndex,
              onPressed: () => onSelected(index),
            ),
          ),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.article,
    required this.selected,
    required this.onPressed,
  });

  final _ResourceArticle article;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Card(
        margin: EdgeInsets.zero,
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? AppColors.primary
                : Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(label: article.category),
                  _MetaPill(label: article.readTime),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                article.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                article.summary,
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArticleReader extends StatelessWidget {
  const _ArticleReader({required this.article});

  final _ResourceArticle article;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: Responsive.pagePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaPill(label: article.category),
                _MetaPill(label: article.readTime),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              article.title,
              style: TextStyle(
                fontSize: Responsive.isHandset(context) ? 22 : 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              article.summary,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            if (article.showArchitectureDiagram) ...[
              const _ArchitectureDiagram(),
              const SizedBox(height: 28),
            ],
            for (final section in article.sections) ...[
              Text(
                section.heading,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(section.body, style: const TextStyle(height: 1.55)),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArchitectureDiagram extends StatelessWidget {
  const _ArchitectureDiagram();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 760;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.18),
            AppColors.primary.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _DiagramHeader(),
          const SizedBox(height: 22),
          if (compact)
            const _CompactArchitectureFlow()
          else
            const _WideArchitectureFlow(),
          const SizedBox(height: 22),
          const _HealingLoopStrip(),
        ],
      ),
    );
  }
}

class _DiagramHeader extends StatelessWidget {
  const _DiagramHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.account_tree_rounded),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Self-Healing System Map',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                'How traces become diagnosis, prompt repair, verification, and reports.',
                style: TextStyle(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WideArchitectureFlow extends StatelessWidget {
  const _WideArchitectureFlow();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(
              child: _ArchitectureBand(
                title: 'Flutter Dashboard',
                subtitle: 'Screens + providers',
                color: Color(0xFF4285F4),
                icon: Icons.dashboard_customize_rounded,
                items: [
                  'Dashboard',
                  'Customer Support',
                  'Social Posts',
                  'Investment',
                  'Phoenix Traces',
                  'Reports',
                ],
              ),
            ),
            _DiagramArrow(),
            Expanded(
              child: _ArchitectureBand(
                title: 'FastAPI Backend',
                subtitle: 'Routes + WebSocket',
                color: Color(0xFF7C4DFF),
                icon: Icons.api_rounded,
                items: [
                  '/api/chat',
                  '/api/posts',
                  '/api/investment',
                  '/api/agent',
                  '/api/phoenix',
                  '/ws',
                ],
              ),
            ),
            _DiagramArrow(),
            Expanded(
              child: _ArchitectureBand(
                title: 'Self-Healing Loop',
                subtitle: 'Observe → repair',
                color: Color(0xFFFFB300),
                icon: Icons.auto_fix_high_rounded,
                items: [
                  'TraceReader',
                  'Evaluator',
                  'RootCause',
                  'PromptImprover',
                  'Verifier',
                  'Reporter',
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: const [
            Expanded(
              child: _ArchitectureBand(
                title: 'External Intelligence',
                subtitle: 'AI + observability',
                color: Color(0xFF00ACC1),
                icon: Icons.hub_rounded,
                items: [
                  'Gemini 2.5 Flash',
                  'Arize Phoenix',
                  'Phoenix MCP',
                  'SEC EDGAR',
                  'Slack',
                ],
              ),
            ),
            _DiagramArrow(),
            Expanded(
              child: _ArchitectureBand(
                title: 'Memory + Evidence',
                subtitle: 'Persistent proof',
                color: Color(0xFF43A047),
                icon: Icons.storage_rounded,
                items: [
                  'SQLite metrics',
                  'Incident reports',
                  'FAQ text',
                  'SEC cache',
                  'Policy memory',
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CompactArchitectureFlow extends StatelessWidget {
  const _CompactArchitectureFlow();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        _ArchitectureBand(
          title: 'Flutter Dashboard',
          subtitle: 'Screens + providers',
          color: Color(0xFF4285F4),
          icon: Icons.dashboard_customize_rounded,
          items: ['Dashboard', 'Phoenix Traces', 'Agent Control'],
        ),
        _VerticalArrow(),
        _ArchitectureBand(
          title: 'FastAPI Backend',
          subtitle: 'Routes + WebSocket',
          color: Color(0xFF7C4DFF),
          icon: Icons.api_rounded,
          items: ['/api/chat', '/api/posts', '/api/agent', '/ws'],
        ),
        _VerticalArrow(),
        _ArchitectureBand(
          title: 'Self-Healing Loop',
          subtitle: 'Diagnose + repair',
          color: Color(0xFFFFB300),
          icon: Icons.auto_fix_high_rounded,
          items: ['TraceReader', 'Evaluator', 'PromptImprover', 'Verifier'],
        ),
        _VerticalArrow(),
        _ArchitectureBand(
          title: 'Gemini + Phoenix MCP',
          subtitle: 'Judge + trace retrieval',
          color: Color(0xFF00ACC1),
          icon: Icons.hub_rounded,
          items: ['Gemini 2.5 Flash', 'Arize Phoenix', 'Phoenix MCP'],
        ),
      ],
    );
  }
}

class _ArchitectureBand extends StatelessWidget {
  const _ArchitectureBand({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.items,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 210),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagramArrow extends StatelessWidget {
  const _DiagramArrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 210,
      child: Center(
        child: Icon(
          Icons.arrow_forward_rounded,
          color: AppColors.primary,
          size: 28,
        ),
      ),
    );
  }
}

class _VerticalArrow extends StatelessWidget {
  const _VerticalArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Icon(
        Icons.arrow_downward_rounded,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }
}

class _HealingLoopStrip extends StatelessWidget {
  const _HealingLoopStrip();

  static const steps = [
    ('1', 'Answer'),
    ('2', 'Trace'),
    ('3', 'MCP Read'),
    ('4', 'Diagnose'),
    ('5', 'Patch'),
    ('6', 'Verify'),
    ('7', 'Report'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The 7-step healing loop',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final step in steps)
                _StepChip(number: step.$1, label: step.$2),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 7, right: 11, top: 7, bottom: 7),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ResourceArticle {
  const _ResourceArticle({
    required this.title,
    required this.category,
    required this.readTime,
    required this.summary,
    required this.sections,
    this.showArchitectureDiagram = false,
  });

  final String title;
  final String category;
  final String readTime;
  final String summary;
  final List<_ArticleSection> sections;
  final bool showArchitectureDiagram;
}

class _ArticleSection {
  const _ArticleSection({required this.heading, required this.body});

  final String heading;
  final String body;
}
