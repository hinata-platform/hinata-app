import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/hinata_repository.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/hex_mark.dart';
import '../../sprint/modals/glass_modal.dart';
import '../git_tokens.dart';
import '../widgets/provider_glyph.dart';

/// Opens the Liquid-Glass connect wizard. Resolves to the updated [Project]
/// (with `git` set) once a repository is linked, or `null` if cancelled.
Future<Project?> showConnectRepoWizard(
  BuildContext context, {
  required Project project,
  bool startToken = false,
}) {
  return showGlassModal<Project>(
    context,
    width: 640,
    builder: (modalContext) =>
        _ConnectRepoWizard(project: project, startToken: startToken),
  );
}

typedef _Scope = ({String title, String desc, String scope, bool required});

const Map<String, List<_Scope>> _permsByProvider = {
  'github': [
    (title: 'Repository metadata', desc: 'Names, branches, topics', scope: 'Read', required: true),
    (title: 'Contents (code)', desc: 'Sync development info & create branches', scope: 'Read & write', required: false),
    (title: 'Pull requests', desc: 'Link and update pull requests', scope: 'Read & write', required: false),
    (title: 'Issues', desc: 'Smart-commit comments & transitions', scope: 'Read & write', required: false),
    (title: 'Deployments & checks', desc: 'Show build & deployment status', scope: 'Read', required: false),
    (title: 'Webhooks', desc: 'Receive push, branch & PR events', scope: 'Read & write', required: false),
  ],
  'gitlab': [
    (title: 'api', desc: 'Read development info & transition issues', scope: 'Full', required: true),
    (title: 'read_repository', desc: 'Branches, commits & merge requests', scope: 'Read', required: false),
    (title: 'write_repository', desc: 'Create branches from issues', scope: 'Write', required: false),
    (title: 'Webhooks', desc: 'Receive push & MR events', scope: 'Read & write', required: false),
  ],
  'bitbucket': [
    (title: 'account', desc: 'Identify your workspaces', scope: 'Read', required: true),
    (title: 'repository', desc: 'Branches, commits & pull requests', scope: 'Read', required: false),
    (title: 'pullrequest', desc: 'Link and update pull requests', scope: 'Read & write', required: false),
    (title: 'webhook', desc: 'Receive repository events', scope: 'Read & write', required: false),
  ],
};

enum _Step { provider, authorize, owner, repo, token }

class _ConnectRepoWizard extends StatefulWidget {
  const _ConnectRepoWizard({required this.project, required this.startToken});

  final Project project;
  final bool startToken;

  @override
  State<_ConnectRepoWizard> createState() => _ConnectRepoWizardState();
}

class _ConnectRepoWizardState extends State<_ConnectRepoWizard> {
  late _Step _step = widget.startToken ? _Step.token : _Step.provider;
  GitProvider? _provider;
  bool _busy = false;

  // Real OAuth: the in-flight session state + the consent URL (for re-opening)
  // while we wait for the browser round-trip to complete.
  bool _awaiting = false;
  String? _state;
  String? _authUrl;

  // Set when the backend reports no OAuth app is registered for the chosen
  // provider yet — we surface a clear "an admin must set this up" panel instead
  // of silently dropping to the manual URL + token method.
  bool _unavailable = false;

  List<GitOwner> _owners = const [];
  GitOwner? _owner;
  List<GitRepo> _repos = const [];
  GitRepo? _repo;
  String _query = '';

  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  HinataRepository get _repoApi => context.read<HinataRepository>();
  String get _pid => widget.project.id;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.navy,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _pickProvider(GitProvider p) {
    setState(() {
      _provider = p;
      _owner = null;
      _repo = null;
      _owners = const [];
      _repos = const [];
      _unavailable = false;
      _step = _Step.authorize;
    });
  }

  Future<void> _authorize() async {
    final provider = _provider;
    if (provider == null) return;
    setState(() {
      _busy = true;
      _awaiting = false;
      _unavailable = false;
    });
    try {
      // Real server-brokered OAuth: get the provider consent URL + session state,
      // open it in the browser, then poll until the callback has exchanged the
      // code for a token. Owners/repos are then fetched with the real token.
      final start = await _repoApi.gitOAuthStart(_pid, provider.id);
      if (!mounted) return;
      if (!start.available || start.authorizeUrl == null || start.state == null) {
        // No OAuth app is registered for this provider yet. This is a
        // platform-wide, admin-only setup — surface a clear explanation
        // (works for non-admins too) instead of silently dropping to the
        // manual URL + token method.
        setState(() => _unavailable = true);
        return;
      }
      _state = start.state;
      _authUrl = start.authorizeUrl;
      final launched = await launchUrl(
        Uri.parse(start.authorizeUrl!),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _toast('Could not open the browser to authorize on ${provider.label}.');
        return;
      }
      if (mounted) setState(() => _awaiting = true);
      final ok = await _pollAuthorization(start.state!);
      if (!mounted) return;
      if (!ok) {
        _toast('Authorization wasn\'t completed. Please try again.');
        setState(() => _awaiting = false);
        return;
      }
      final owners = await _repoApi.gitOwners(_pid, provider.id, state: _state);
      if (!mounted) return;
      _awaiting = false;
      if (owners.length == 1) {
        _owner = owners.single;
        await _loadRepos();
        if (!mounted) return;
        setState(() => _step = _Step.repo);
      } else {
        setState(() {
          _owners = owners;
          _step = _Step.owner;
        });
      }
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _awaiting = false;
        });
      }
    }
  }

  /// Polls the OAuth session (~3 min) while the user completes consent in the
  /// browser. Returns true once authorized, false on error/timeout.
  Future<bool> _pollAuthorization(String state) async {
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return false;
      try {
        final status = await _repoApi.gitOAuthSession(state);
        if (status.authorized) return true;
        if (status.failed) return false;
      } catch (_) {
        // Transient (e.g. session not yet visible) — keep polling.
      }
    }
    return false;
  }

  Future<void> _pickOwner(GitOwner owner) async {
    setState(() {
      _owner = owner;
      _busy = true;
    });
    try {
      await _loadRepos();
      if (mounted) setState(() => _step = _Step.repo);
    } catch (e) {
      _toast(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRepos() async {
    final provider = _provider!;
    final repos = await _repoApi.gitRepos(
      _pid,
      provider.id,
      _owner!.id,
      state: _state,
    );
    _repos = repos;
  }

  Future<void> _connect() async {
    final provider = _provider;
    final owner = _owner;
    final repo = _repo;
    if (provider == null || owner == null || repo == null) return;
    setState(() => _busy = true);
    try {
      final updated = await _repoApi.gitConnect(
        _pid,
        provider: provider.id,
        owner: owner.id,
        repo: repo.name,
        state: _state,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      _toast(_message(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connectToken() async {
    final url = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty || token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = await _repoApi.gitConnectToken(
        _pid,
        repoUrl: url,
        token: token,
      );
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      _toast(_message(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(Object e) =>
      e is ApiFailure ? e.message : 'Something went wrong. Please try again.';

  bool get _canFinish => switch (_step) {
    _Step.token => _urlCtrl.text.trim().isNotEmpty && _tokenCtrl.text.trim().isNotEmpty,
    _Step.repo => _repo != null,
    _ => false,
  };

  void _back() {
    setState(() {
      _step = switch (_step) {
        _Step.authorize => _Step.provider,
        _Step.owner => _Step.authorize,
        _Step.repo => _owners.length > 1 ? _Step.owner : _Step.authorize,
        _ => _step,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: _body(),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _header() {
    final p = widget.project;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.gitBranch, size: 20, color: AppColors.accentStrong),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect a repository',
                  style: TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Link ${p.name} '),
                      TextSpan(
                        text: '(${p.key})',
                        style: const TextStyle(fontFamily: AppTheme.fontMono),
                      ),
                      const TextSpan(text: ' to its own Git repository'),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            icon: Icon(LucideIcons.x, size: 20, color: AppColors.inkSoft),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return switch (_step) {
      _Step.provider => _providerStep(),
      _Step.authorize => _authorizeStep(),
      _Step.owner => _ownerStep(),
      _Step.repo => _repoStep(),
      _Step.token => _tokenStep(),
    };
  }

  // ── step rail ──────────────────────────────────────────────────────────
  Widget _stepRail() {
    final p = _provider;
    final steps = <(_Step, String)>[
      (_Step.provider, 'Provider'),
      (_Step.authorize, 'Authorize'),
      (_Step.owner, p == null ? 'Owner' : _cap(p.ownerWord)),
      (_Step.repo, p == null ? 'Repository' : _cap(p.unit)),
    ];
    final currentIdx = steps.indexWhere((s) => s.$1 == _step);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Container(
                width: 20,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Flexible(child: _stepChip(i, steps[i].$2, currentIdx)),
          ],
        ],
      ),
    );
  }

  Widget _stepChip(int index, String label, int currentIdx) {
    final done = index < currentIdx;
    final on = index == currentIdx;
    final bg = done
        ? AppColors.success
        : on
        ? AppColors.navy
        : AppColors.canvas2;
    final fg = (done || on) ? Colors.white : AppColors.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: done
              ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
              : Text(
                  '${index + 1}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
                ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: on ? AppColors.ink : AppColors.inkFaint,
            ),
          ),
        ),
      ],
    );
  }

  // ── provider step ──────────────────────────────────────────────────────
  Widget _providerStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        LayoutBuilder(
          builder: (context, c) {
            final twoCol = c.maxWidth >= 460;
            final cards = [
              for (final p in GitProvider.values) _providerCard(p),
            ];
            if (!twoCol) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    cards[i],
                  ],
                ],
              );
            }
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: (c.maxWidth - 12) / 2, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _hint(
          icon: LucideIcons.server,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Self-managed GitLab or GitHub Enterprise? '),
                _linkSpan(
                  'Connect with a URL & access token',
                  () => setState(() => _step = _Step.token),
                ),
                const TextSpan(text: ' instead.'),
              ],
            ),
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }

  Widget _providerCard(GitProvider p) {
    return _CardButton(
      onTap: () => _pickProvider(p),
      child: Row(
        children: [
          ProviderGlyph(provider: p, size: 38),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p.label,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontBrand,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  p.host,
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            ),
            child: Text(
              'OAuth',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── awaiting browser consent ───────────────────────────────────────────
  Widget _awaitingStep(GitProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        const SizedBox(height: 6),
        _hint(
          icon: LucideIcons.externalLink,
          child: Text(
            'Approve access in the ${p.label} tab that just opened, then come '
            'back here — this updates automatically.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Waiting for ${p.label} authorization…',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: () {
              final url = _authUrl;
              if (url != null) {
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              }
            },
            icon: Icon(LucideIcons.refreshCw, size: 14, color: AppColors.inkSoft),
            label: Text(
              'Reopen the authorization page',
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
        ),
      ],
    );
  }

  // ── OAuth app not registered yet ───────────────────────────────────────
  Widget _unavailableStep(GitProvider p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(LucideIcons.lock, size: 24, color: AppColors.warning),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'One-click ${p.label} sign-in isn\'t available yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'An administrator still needs to register hinata as an OAuth app for '
            '${p.label} before you can connect with one click. This is a one-time '
            'platform setup done in Admin area → Git integration.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.55, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 16),
        _hint(
          icon: LucideIcons.keyRound,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Have a personal access token? ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                  text:
                      'You can connect this project right now with a repository '
                      'URL and access token — no admin setup required. ',
                ),
                _linkSpan(
                  'Connect with a URL & token',
                  () => setState(() => _step = _Step.token),
                ),
              ],
            ),
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
          ),
        ),
      ],
    );
  }

  // ── authorize step ─────────────────────────────────────────────────────
  Widget _authorizeStep() {
    final p = _provider!;
    if (_awaiting) return _awaitingStep(p);
    if (_unavailable) return _unavailableStep(p);
    final perms = _permsByProvider[p.id] ?? _permsByProvider['github']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const HexMark(size: 30, color: AppColors.accent),
            ),
            const SizedBox(width: 14),
            Icon(LucideIcons.arrowLeftRight, size: 18, color: AppColors.inkFaint),
            const SizedBox(width: 14),
            ProviderGlyph(provider: p, size: 46),
          ],
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Authorize hinata on ${p.label}',
            style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'hinata for ${p.label} will be able to:',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < perms.length; i++)
                Container(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: AppColors.hairline2)),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.circleCheckBig, size: 16, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: perms[i].title),
                                  if (perms[i].required)
                                    TextSpan(
                                      text: ' · required',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.inkFaint,
                                      ),
                                    ),
                                ],
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              perms[i].desc,
                              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        perms[i].scope,
                        style: TextStyle(
                          fontFamily: AppTheme.fontMono,
                          fontSize: 10.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── owner step ─────────────────────────────────────────────────────────
  Widget _ownerStep() {
    final p = _provider!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Choose the ${p.ownerWord} hinata was installed on.',
            style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
          ),
        ),
        for (final o in _owners) ...[
          _OwnerItem(
            owner: o,
            provider: p,
            selected: _owner?.id == o.id,
            onTap: _busy ? null : () => _pickOwner(o),
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  // ── repo step ──────────────────────────────────────────────────────────
  Widget _repoStep() {
    final p = _provider!;
    final needle = _query.toLowerCase();
    final filtered = _repos
        .where((r) => needle.isEmpty || r.name.toLowerCase().contains(needle))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepRail(),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
          child: Row(
            children: [
              Icon(LucideIcons.search, size: 16, color: AppColors.inkFaint),
              const SizedBox(width: 9),
              Expanded(
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search ${p.unit}s…',
                    hintStyle: TextStyle(color: AppColors.inkFaint),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                'No ${p.unit}s match “$_query”.',
                style: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          )
        else
          for (final r in filtered) ...[
            _RepoItem(
              repo: r,
              provider: p,
              owner: _owner!,
              selected: _repo?.name == r.name,
              onTap: () => setState(() => _repo = r),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  // ── token fallback ─────────────────────────────────────────────────────
  Widget _tokenStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hint(
          icon: LucideIcons.info,
          child: Text(
            'For self-managed GitLab / GitHub Enterprise / Bitbucket Data Center. '
            'Generate a personal access token with api / repo scope and paste it '
            'below. The token is stored encrypted and used server-side only.',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.inkSoft),
          ),
        ),
        const SizedBox(height: 14),
        GlassField(
          label: 'Repository URL',
          child: TextField(
            controller: _urlCtrl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: glassInputDecoration(
              hint: 'https://gitlab.example.com/hinata/hinata-app',
            ),
          ),
        ),
        const SizedBox(height: 14),
        GlassField(
          label: 'Access token',
          child: TextField(
            controller: _tokenCtrl,
            obscureText: true,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontFamily: AppTheme.fontMono),
            decoration: glassInputDecoration(hint: 'glpat-••••••••••••••••••••'),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _step = _Step.provider),
            icon: Icon(LucideIcons.arrowLeft, size: 14, color: AppColors.inkSoft),
            label: Text(
              'Use OAuth instead',
              style: TextStyle(color: AppColors.inkSoft),
            ),
          ),
        ),
      ],
    );
  }

  // ── footer ─────────────────────────────────────────────────────────────
  Widget _footer() {
    final showBack =
        !widget.startToken &&
        (_step == _Step.authorize || _step == _Step.owner || _step == _Step.repo);
    final primary = _step == _Step.authorize
        ? (_unavailable
              ? _PrimaryAction(
                  label: 'Use URL & token',
                  icon: LucideIcons.keyRound,
                  busy: false,
                  onPressed: () => setState(() => _step = _Step.token),
                )
              : _PrimaryAction(
                  label: 'Authorize & install',
                  icon: LucideIcons.shieldCheck,
                  busy: _busy,
                  onPressed: _busy ? null : _authorize,
                ))
        : _PrimaryAction(
            label: _repo != null ? 'Connect ${_repo!.name}' : 'Connect',
            icon: LucideIcons.link,
            busy: _busy,
            onPressed: (_canFinish && !_busy)
                ? (_step == _Step.token ? _connectToken : _connect)
                : null,
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.hairline.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          if (showBack)
            TextButton.icon(
              onPressed: _busy ? null : _back,
              icon: Icon(LucideIcons.arrowLeft, size: 14, color: AppColors.inkSoft),
              label: Text('Back', style: TextStyle(color: AppColors.inkSoft)),
            ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          primary,
        ],
      ),
    );
  }

  Widget _hint({required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.accentStrong),
          const SizedBox(width: 9),
          Expanded(child: child),
        ],
      ),
    );
  }

  InlineSpan _linkSpan(String text, VoidCallback onTap) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.accentStrong,
          ),
        ),
      ),
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CardButton extends StatelessWidget {
  const _CardButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _OwnerItem extends StatelessWidget {
  const _OwnerItem({
    required this.owner,
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final GitOwner owner;
  final GitProvider provider;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _ListItem(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: providerBrand(provider),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              owner.name.length >= 2
                  ? owner.name.substring(0, 2).toUpperCase()
                  : owner.name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${owner.kind} · ${owner.repos} ${provider.unit}s',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: AppColors.accentStrong),
        ],
      ),
    );
  }
}

class _RepoItem extends StatelessWidget {
  const _RepoItem({
    required this.repo,
    required this.provider,
    required this.owner,
    required this.selected,
    required this.onTap,
  });

  final GitRepo repo;
  final GitProvider provider;
  final GitOwner owner;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ListItem(
      selected: selected,
      onTap: onTap,
      child: Row(
        children: [
          ProviderGlyph(provider: provider, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${owner.name}/',
                        style: TextStyle(
                          color: AppColors.inkFaint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextSpan(text: repo.name),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (repo.langColor != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _hexColor(repo.langColor!),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                    ],
                    Flexible(
                      child: Text(
                        [
                          if (repo.lang != null) repo.lang!,
                          if (repo.updated != null) 'updated ${repo.updated} ago',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Text(
              repo.isPrivate ? 'Private' : 'Public',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(LucideIcons.circleCheckBig, size: 18, color: AppColors.accentStrong),
          ],
        ],
      ),
    );
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({required this.child, required this.selected, required this.onTap});

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentSoft : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.hairline,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon, size: 15),
      label: Text(label),
    );
  }
}

Color _hexColor(String hex) {
  final cleaned = hex.replaceAll('#', '');
  final value = int.tryParse(cleaned, radix: 16) ?? 0x999999;
  return Color(0xFF000000 | value);
}
