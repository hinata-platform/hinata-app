import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hex_mark.dart';

/// One-time feature tour shown after the first successful server connection.
///
/// Implements the "hinata Onboarding Concept" design: a branded, dark-navy
/// walk-through with ambient orbs, liquid-glass feature cards, animated page
/// dots and a Continue → Get Started call-to-action. Always renders dark —
/// it is a brand splash, independent of the app's [ThemeMode].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.storage,
    required this.onDone,
  });

  final AppStorage storage;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// ─── design palette (constant across themes — this screen is always dark) ───
const _amber = AppColors.accent; // #D9A032
const _amber2 = Color(0xFFB9831F);
const _bgTop = Color(0xFF1D1B38);
const _bgMid = Color(0xFF11102A);
const _bgBot = Color(0xFF19152E);
const _navFade = Color(0xFF0B0A1A);

Color _white(double o) => Colors.white.withValues(alpha: o);

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _total = 4;

  final _controller = PageController();
  late final AnimationController _ambient;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Single long-running clock drives the orb drift + logo glow pulse.
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _ambient.dispose();
    super.dispose();
  }

  bool get _isLast => _index == _total - 1;

  void _goTo(int i) {
    _controller.animateToPage(
      i.clamp(0, _total - 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _goTo(_index + 1);
    }
  }

  Future<void> _finish() async {
    await widget.storage.setOnboardingDone();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgMid,
      body: Stack(
        children: [
          // ── ambient background ──
          const Positioned.fill(child: _BackgroundGradient()),
          Positioned.fill(child: _Orbs(animation: _ambient)),

          // ── foreground ──
          SafeArea(
            child: Column(
              children: [
                _TopBar(visible: !_isLast, onSkip: () => _goTo(_total - 1)),
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      _WelcomeSlide(glow: _ambient),
                      _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.projects.title',
                        bodyKey: 'onboarding.projects.body',
                        card: const _ProjectsCard(),
                      ),
                      _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.sprints.title',
                        bodyKey: 'onboarding.sprints.body',
                        card: const _SprintCard(),
                      ),
                      _FeatureSlide(
                        labelKey: 'onboarding.label',
                        titleKey: 'onboarding.teams.title',
                        bodyKey: 'onboarding.teams.body',
                        card: const _TeamsCard(),
                      ),
                    ],
                  ),
                ),
                _BottomNav(
                  index: _index,
                  total: _total,
                  isLast: _isLast,
                  onCta: _next,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── background ─────────────────────────

class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [_bgTop, _bgMid, _bgBot],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
    );
  }
}

/// Three softly-drifting colour orbs, redrawn from the ambient clock.
class _Orbs extends StatelessWidget {
  const _Orbs({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = animation.value * 2 * math.pi;
          return Stack(
            children: [
              _orb(
                size: 360,
                color: const Color(0x33D9A032), // amber .20
                top: -120 + math.sin(t) * 24,
                right: -130 + math.cos(t * 0.8) * 18,
              ),
              _orb(
                size: 300,
                color: const Color(0x296450D2), // violet .16
                bottom: 20 + math.cos(t * 0.9) * 26,
                left: -90 + math.sin(t * 1.1) * 20,
              ),
              _orb(
                size: 220,
                color: const Color(0x12C85A32), // warm .07
                top: 360 + math.sin(t * 1.3) * 22,
                right: -40 + math.cos(t) * 16,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _orb({
    required double size,
    required Color color,
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── chrome ─────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.visible, required this.onSkip});

  final bool visible;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 240),
        opacity: visible ? 1 : 0,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 20),
            child: TextButton(
              onPressed: visible ? onSkip : null,
              style: TextButton.styleFrom(
                foregroundColor: _white(0.45),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(context.t('onboarding.skip')),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.total,
    required this.isLast,
    required this.onCta,
  });

  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [_navFade, Color(0x00000000)],
          stops: [0.45, 1.0],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  margin: const EdgeInsets.symmetric(horizontal: 3.5),
                  height: 6,
                  width: i == index ? 28 : 6,
                  decoration: BoxDecoration(
                    color: i == index ? _amber : _white(0.22),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: i == index
                        ? [
                            BoxShadow(
                              color: _amber.withValues(alpha: 0.55),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _CtaButton(isLast: isLast, onTap: onCta),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatefulWidget {
  const _CtaButton({required this.isLast, required this.onTap});

  final bool isLast;
  final VoidCallback onTap;

  @override
  State<_CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<_CtaButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final isLast = widget.isLast;
    final label = context.t(
      isLast ? 'onboarding.getStarted' : 'onboarding.continue',
    );

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: isLast
                ? ImageFilter.blur()
                : ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: isLast
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_amber, _amber2],
                      )
                    : null,
                color: isLast ? null : _white(0.10),
                border: Border.all(
                  color: isLast ? Colors.transparent : _white(0.16),
                ),
                boxShadow: isLast
                    ? [
                        BoxShadow(
                          color: _amber.withValues(alpha: 0.40),
                          blurRadius: 30,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontUi,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.15,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── slides ─────────────────────────

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide({required this.glow});

  final Animation<double> glow;

  @override
  Widget build(BuildContext context) {
    // The brand hero scales up on wider canvases so it never reads as a small
    // phone artefact stranded in the middle of a desktop window.
    final tile = switch (context.layoutSize) {
      LayoutSize.compact => 132.0,
      LayoutSize.medium => 168.0,
      LayoutSize.expanded => 200.0,
    };
    final glowSize = tile * 1.6;
    final word = switch (context.layoutSize) {
      LayoutSize.compact => 42.0,
      LayoutSize.medium => 54.0,
      LayoutSize.expanded => 66.0,
    };
    final tagline = switch (context.layoutSize) {
      LayoutSize.compact => 14.5,
      LayoutSize.medium => 17.0,
      LayoutSize.expanded => 19.0,
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: glowSize,
              height: glowSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // pulsing amber glow
                  AnimatedBuilder(
                    animation: glow,
                    builder: (context, child) {
                      final p =
                          0.5 + 0.5 * math.sin(glow.value * 2 * math.pi * 6.7);
                      return Opacity(
                        opacity: 0.7 + 0.3 * p,
                        child: Transform.scale(
                          scale: 1 + 0.13 * p,
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      width: glowSize,
                      height: glowSize,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0x47D9A032), Color(0x00D9A032)],
                          stops: [0.0, 0.65],
                        ),
                      ),
                    ),
                  ),
                  // glass tile + brand mark
                  _GlassTile(
                    size: tile,
                    radius: tile * 0.29,
                    child: HexMark(size: tile * 0.53),
                  ),
                ],
              ),
            ),
            SizedBox(height: tile * 0.21),
            Text(
              'hinata',
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: word,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('onboarding.tagline'),
              style: TextStyle(
                fontFamily: AppTheme.fontUi,
                fontSize: tagline,
                color: _white(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  const _FeatureSlide({
    required this.labelKey,
    required this.titleKey,
    required this.bodyKey,
    required this.card,
  });

  final String labelKey;
  final String titleKey;
  final String bodyKey;
  final Widget card;

  @override
  Widget build(BuildContext context) {
    return switch (context.layoutSize) {
      // Phone: visual on top, centred text below.
      LayoutSize.compact => _stacked(context, scale: 1, cardWidth: null),
      // Tablet portrait: same stack, scaled up and tighter to a max width.
      LayoutSize.medium => _stacked(context, scale: 1.28, cardWidth: 440),
      // Desktop / tablet landscape: two-column hero.
      LayoutSize.expanded => _split(context),
    };
  }

  Widget _stacked(
    BuildContext context, {
    required double scale,
    required double? cardWidth,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardWidth ?? 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              cardWidth == null
                  ? _GlassCard(child: card)
                  : _scaledCard(maxWidth: cardWidth),
              SizedBox(height: 28 * scale),
              _text(context, scale: scale, align: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _split(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: _text(
                  context,
                  scale: 1.4,
                  align: TextAlign.left,
                  crossAxis: CrossAxisAlignment.start,
                  bodyMaxWidth: 380,
                ),
              ),
              const SizedBox(width: 56),
              Expanded(
                flex: 6,
                child: Align(
                  alignment: Alignment.center,
                  child: _scaledCard(maxWidth: 480),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The mini-UI card is authored at a fixed 360px "design width"; on wider
  /// layouts we scale that whole composition uniformly so the inner type stays
  /// in proportion instead of stretching the columns and shrinking the text.
  Widget _scaledCard({required double maxWidth}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: 360, child: _GlassCard(child: card)),
      ),
    );
  }

  Widget _text(
    BuildContext context, {
    required double scale,
    required TextAlign align,
    CrossAxisAlignment crossAxis = CrossAxisAlignment.center,
    double bodyMaxWidth = 290,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          context.t(labelKey).toUpperCase(),
          style: TextStyle(
            fontFamily: AppTheme.fontUi,
            fontSize: 10.5 * scale,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.1,
            color: _amber,
          ),
        ),
        SizedBox(height: 7 * scale),
        Text(
          context.t(titleKey),
          textAlign: align,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 31 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.1,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 11 * scale),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bodyMaxWidth),
          child: Text(
            context.t(bodyKey),
            textAlign: align,
            style: TextStyle(
              fontFamily: AppTheme.fontUi,
              fontSize: 13.5 * scale,
              height: 1.7,
              color: _white(0.48),
            ),
          ),
        ),
      ],
    );
  }
}

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
