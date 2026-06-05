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
      title: 'Why Self-Healing Agents Matter for Production AI',
      category: 'Architecture',
      readTime: '6 min',
      summary:
          'A practical view of why agent quality cannot depend on one perfect prompt.',
      sections: [
        _ArticleSection(
          heading: 'The production problem',
          body:
              'AI systems fail in ways that normal software dashboards do not catch quickly enough. A response can be fluent, confident, and still wrong. In customer support, that means a policy mistake. In social media, it means inflated claims. In finance, it means unsupported analysis. A self-healing agent treats these failures as operational incidents instead of isolated bad outputs.',
        ),
        _ArticleSection(
          heading: 'The healing loop',
          body:
              'The core loop is intentionally simple: capture the answer, evaluate it, diagnose the failure mode, rewrite the prompt, verify the new behavior, and publish evidence. This turns a subjective quality complaint into a traceable workflow. The system can show the weak output, the root cause, the prompt patch, and the healed response in one place.',
        ),
        _ArticleSection(
          heading: 'Why it is critical',
          body:
              'Static prompts age quickly. Product policies change, market filings update, and communication standards shift. A self-healing loop gives operators a way to see drift, repair behavior, and prove that the repair improved the next run. For judges and buyers, the value is not just that the agent answers. It is that the agent can explain how it fixed itself.',
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
              'A healing system needs more than logs. It needs input, output, span name, timestamp, use case, scores, and run metadata. Phoenix traces provide the evidence trail for the agent. The dashboard uses that trail to connect an AI output to a Phoenix trace and then to the repair that followed.',
        ),
        _ArticleSection(
          heading: 'What judges should see',
          body:
              'A judge should be able to open Phoenix Traces and immediately see the project, MCP retrieval status, trace IDs, span names, scores, and before or after status. The page makes the important claim visible: the agent is reading its own traces and using those traces to improve behavior.',
        ),
        _ArticleSection(
          heading: 'Why MCP matters',
          body:
              'Phoenix MCP turns observability into an agent-readable interface. Instead of only showing traces to humans, the system can retrieve trace evidence during the repair loop. That is the difference between monitoring and self-healing.',
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
              'Support agents are high-risk because users treat their answers as policy. A weak prompt can invent refund terms, shipping guarantees, or escalation paths. The damage is not theoretical: one hallucinated concession can create cost, confusion, and loss of trust.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The support workflow evaluates the answer against FAQ-grounded expectations. When hallucination is high or relevance is weak, the system diagnoses the pattern and rewrites the prompt toward grounded behavior. The healed prompt instructs the agent to use the FAQ and to admit uncertainty when the answer is not present.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'The judge can ask a policy question, see the initial response, trigger healing, and inspect the before and after report. The important outcome is measurable: lower hallucination, higher relevance, and a final answer that fits the knowledge base.',
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
              'Social media generation often rewards punchy language. That is exactly where hallucination becomes expensive. A brief saying that an office opened in Dubai should not become a claim about market dominance, explosive growth, or invented revenue. Creative tone is useful only when the facts stay intact.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The social media healer compares the brief to the generated post, scores hallucination and relevance, and patches the prompt with stricter grounding rules. The UI keeps the before post, healed post, root cause, and prompt patch visible so the improvement is not hidden behind a regenerate button.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'The post workflow shows a clean business story for hackathon judging: the agent catches exaggerated language, rewrites its own instructions, and produces a safer post using the same user brief.',
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
              'Investment answers are high-stakes because confident language can be mistaken for advice. A useful analyst agent must separate evidence from interpretation. It should cite filing context, show uncertainty, and avoid unsupported buy or sell conclusions.',
        ),
        _ArticleSection(
          heading: 'The repair',
          body:
              'The investment workflow combines SEC context with evaluation of grounding, risk flags, and answer quality. If the answer drifts away from filings or makes unsafe claims, the healing path tightens the prompt around sourced facts, cautious language, and visible limitations.',
        ),
        _ArticleSection(
          heading: 'Product value',
          body:
              'This use case shows why self-healing is not only for chatbots. The same trace, score, diagnose, patch, and verify loop can protect workflows where factual grounding matters more than style.',
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
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Card(
        margin: EdgeInsets.zero,
        color: selected
            ? AppColors.primary.withValues(alpha: 0.16)
            : Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? AppColors.primary : Colors.transparent,
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
            const SizedBox(height: 22),
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
  });

  final String title;
  final String category;
  final String readTime;
  final String summary;
  final List<_ArticleSection> sections;
}

class _ArticleSection {
  const _ArticleSection({required this.heading, required this.body});

  final String heading;
  final String body;
}
