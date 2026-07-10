part of 'onboarding_screen.dart';

// ───────────────────────── glass primitives ─────────────────────────

/// Frosted glass square used for the brand mark on the welcome slide.
class _GlassTile extends StatelessWidget {
  const _GlassTile({
    required this.size,
    required this.radius,
    required this.child,
  });

  final double size;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _white(0.075),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: _white(0.14)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x73000000),
                blurRadius: 56,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Frosted glass card with the signature top amber edge highlight.
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: _white(0.075),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _white(0.12)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 64,
                offset: Offset(0, 22),
              ),
            ],
          ),
          child: Stack(
            children: [
              child,
              // amber edge line across the top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.8,
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x00D9A032),
                            Color(0x61D9A032),
                            Color(0x00D9A032),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── feature card · Projects (kanban) ─────────────────────────

class _ProjectsCard extends StatelessWidget {
  const _ProjectsCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Expanded(
            child: _KanbanColumn(
              head: 'Backlog',
              cards: [
                _KanbanItem('Redesign onboarding', 'Todo', _chipTodo, _dotTodo),
                _KanbanItem('Auth token refresh', 'Todo', _chipTodo, _dotTodo),
              ],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _KanbanColumn(
              head: 'In Progress',
              cards: [
                _KanbanItem(
                  'Sprint velocity chart',
                  'Doing',
                  _chipDoing,
                  _dotDoing,
                ),
                _KanbanItem(
                  'Liquid Glass nav',
                  'Review',
                  _chipReview,
                  _dotReview,
                ),
              ],
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _KanbanColumn(
              head: 'Done',
              cards: [
                _KanbanItem('Push notifications', 'Done', _chipDone, _dotDone),
                _KanbanItem('Dark mode tokens', 'Done', _chipDone, _dotDone),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _dotTodo = Color(0xFF85B5FA);
const _dotDoing = _amber;
const _dotReview = Color(0xFFC49EF5);
const _dotDone = Color(0xFF4CC894);
const _chipTodo = Color(0x2E5B86D6);
const _chipDoing = Color(0x2ED9A032);
const _chipReview = Color(0x2E9A6BD0);
const _chipDone = Color(0x2E2FA06E);

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({required this.head, required this.cards});

  final String head;
  final List<_KanbanItem> cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            head.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 8,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: _white(0.30),
            ),
          ),
        ),
        Container(height: 1, color: _white(0.06)),
        const SizedBox(height: 7),
        for (final c in cards) ...[c, const SizedBox(height: 5)],
      ],
    );
  }
}

class _KanbanItem extends StatelessWidget {
  const _KanbanItem(this.title, this.chip, this.chipBg, this.dot);

  final String title;
  final String chip;
  final Color chipBg;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _white(0.055),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _white(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 8.5,
              height: 1.4,
              color: _white(0.72),
            ),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 4.5,
                  height: 4.5,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 3),
                Text(
                  chip,
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 7,
                    fontWeight: FontWeight.w600,
                    color: dot,
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

// ───────────────────────── feature card · Sprints ─────────────────────────

class _SprintCard extends StatelessWidget {
  const _SprintCard();

  static const _tasks = [
    ('Finalize design system', true),
    ('API integration layer', true),
    ('Push notification flow', false),
    ('QA pass & release', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x1FD9A032),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0x38D9A032)),
                ),
                child: const Text(
                  'Sprint 12',
                  style: TextStyle(
                    fontFamily: AppTheme.fontUi,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: _amber,
                  ),
                ),
              ),
              Text(
                '8 days left · Q2 2026',
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 8.5,
                  color: _white(0.32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const _DonutRing(percent: 0.65, size: 68),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (label, done) in _tasks) ...[
                      _SprintTask(label: label, done: done),
                      const SizedBox(height: 5),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: _white(0.06)),
          const SizedBox(height: 10),
          Row(
            children: const [
              _SprintStat(value: '13', label: 'Completed'),
              SizedBox(width: 14),
              _SprintStat(value: '7', label: 'Open'),
              SizedBox(width: 14),
              _SprintStat(value: '2', label: 'Blocked'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SprintTask extends StatelessWidget {
  const _SprintTask({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? const Color(0xBF2FA06E) : Colors.transparent,
            borderRadius: BorderRadius.circular(3.5),
            border: done ? null : Border.all(color: _white(0.2), width: 1.5),
          ),
          child: done
              ? const Icon(LucideIcons.check, size: 8.5, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 9,
              color: _white(0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _SprintStat extends StatelessWidget {
  const _SprintStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 7.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: _white(0.32),
          ),
        ),
      ],
    );
  }
}

class _DonutRing extends StatelessWidget {
  const _DonutRing({required this.percent, required this.size});

  final double percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: Size(size, size), painter: _DonutPainter(percent)),
          Text(
            '${(percent * 100).round()}%',
            style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.percent);

  final double percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    const stroke = 6.5;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = _white(0.08);
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = _amber
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * percent,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.percent != percent;
}

// ───────────────────────── feature card · Teams ─────────────────────────

class _TeamsCard extends StatelessWidget {
  const _TeamsCard();

  static const _avatars = [
    ('LP', Color(0xFF5B5DBF)),
    ('AK', Color(0xFF2FA06E)),
    ('MH', Color(0xFFC58A22)),
    ('SR', Color(0xFF9A6BD0)),
    ('JW', Color(0xFFD9544B)),
  ];

  static const _feed = [
    (
      'LP',
      Color(0xFF5B5DBF),
      'Merged ',
      'feature/glass-nav',
      ' into main',
      '2m',
    ),
    ('AK', Color(0xFF2FA06E), 'Moved ', 'Auth refresh', ' → In Review', '18m'),
    ('MH', Color(0xFFC58A22), 'Commented on ', 'Sprint 12', ' retro', '1h'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 38,
            child: Stack(
              children: [
                for (var i = 0; i < _avatars.length; i++)
                  Positioned(
                    left: i * 30.0,
                    child: _Avatar(
                      initials: _avatars[i].$1,
                      color: _avatars[i].$2,
                    ),
                  ),
                Positioned(
                  left: _avatars.length * 30.0 + 14,
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _white(0.1),
                      border: Border.all(color: _white(0.12), width: 1.5),
                    ),
                    child: Text(
                      '+4',
                      style: TextStyle(
                        fontFamily: AppTheme.fontUi,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        color: _white(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          for (final row in _feed) ...[
            _FeedRow(
              initials: row.$1,
              color: row.$2,
              pre: row.$3,
              strong: row.$4,
              post: row.$5,
              time: row.$6,
            ),
            const SizedBox(height: 5),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.color});

  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: const Color(0xCC0B0A1A), width: 2),
      ),
      child: Text(
        initials,
        style: const TextStyle(
          fontFamily: AppTheme.fontUi,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.initials,
    required this.color,
    required this.pre,
    required this.strong,
    required this.post,
    required this.time,
  });

  final String initials;
  final Color color;
  final String pre;
  final String strong;
  final String post;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _white(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _white(0.055)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Text(
              initials,
              style: const TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 9,
                  height: 1.4,
                  color: _white(0.58),
                ),
                children: [
                  TextSpan(text: pre),
                  TextSpan(
                    text: strong,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _white(0.82),
                    ),
                  ),
                  TextSpan(text: post),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            time,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 8,
              color: _white(0.28),
            ),
          ),
        ],
      ),
    );
  }
}
