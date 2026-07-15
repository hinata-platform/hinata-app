import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/repositories/legal_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../knowledge/markdown/markdown_renderer.dart';
import 'legal_models.dart';

/// Public, standalone legal page (privacy policy / terms of service).
///
/// Reachable cold at `/privacy-policy` and `/terms-of-service` without
/// authentication. The markdown comes from the server (operator-replaceable,
/// stored in object storage — see `GET /api/v1/legal/{type}`); when no server
/// is reachable yet (native app before connecting, offline) the bundled
/// default under `assets/legal/` is rendered instead, so the pages never
/// depend on a connection.
class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, required this.type});

  final LegalDocType type;

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  final List<TapGestureRecognizer> _recognizers = [];
  String? _markdown;
  bool _loading = true;
  bool _loadStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Not initState: resolving the locale (Localizations.localeOf) needs
    // inherited widgets, which are only available from here on.
    if (!_loadStarted) {
      _loadStarted = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final lang = _lang;
    // Prefer the server copy (operators can replace it without an app
    // release); any failure — no server selected, offline, older server
    // without the endpoint — falls back to the bundled default.
    try {
      final doc = await context
          .read<LegalRepository>()
          .fetch(widget.type.slug, lang);
      if (doc.markdown.trim().isNotEmpty) {
        if (mounted) {
          setState(() {
            _markdown = doc.markdown;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      // Fall through to the bundled asset.
    }
    final bundled = await rootBundle
        .loadString('assets/legal/${widget.type.slug}.$lang.md');
    if (mounted) {
      setState(() {
        _markdown = bundled;
        _loading = false;
      });
    }
  }

  String get _lang {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'de' ? 'de' : 'en';
  }

  String get _title => switch (widget.type) {
        LegalDocType.privacy => context.t('legal.privacyPolicy'),
        LegalDocType.terms => context.t('legal.termsOfService'),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: _loading
                  ? const Center(child: HiveLoader(size: 36))
                  : Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _body(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline2)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(LucideIcons.arrowLeft),
            tooltip: context.t('common.back'),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/login'),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    // Reparse on rebuild — dispose the previous link recognizers first (same
    // idiom as the knowledge reader).
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final parsed =
        KbMarkdownParser(sink: _recognizers).parse(_markdown ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parsed.nodes,
    );
  }
}
