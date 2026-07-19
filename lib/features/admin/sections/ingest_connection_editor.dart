import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/ingest_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/hue_colors.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart';
import '../../sprint/modals/glass_modal.dart';

/// Result of the connection editor: the saved connection plus the picked
/// project option (so the list can label it without re-resolving).
typedef IngestEditResult = ({
  IngestConnection connection,
  IngestProjectOption project,
});

/// Opens the e-mail-to-ticket connection editor — a glass modal on wide
/// screens, a glass bottom sheet on phones. Pass [connection] to edit an
/// existing one; `null` creates a new connection. Resolves to the saved
/// connection or `null` when dismissed.
Future<IngestEditResult?> showIngestConnectionEditor(
  BuildContext context, {
  IngestConnection? connection,
  IngestProjectOption? initialProject,
}) {
  final editor = _IngestConnectionEditor(
    connection: connection ?? const IngestConnection(),
    initialProject: initialProject,
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide) {
    return showGlassModal<IngestEditResult>(
      context,
      width: 560,
      builder: (_) => editor,
    );
  }
  return showGlassBottomSheet<IngestEditResult>(
    context,
    builder: (_) => editor,
  );
}

class _IngestConnectionEditor extends StatefulWidget {
  const _IngestConnectionEditor({
    required this.connection,
    this.initialProject,
  });

  final IngestConnection connection;
  final IngestProjectOption? initialProject;

  @override
  State<_IngestConnectionEditor> createState() =>
      _IngestConnectionEditorState();
}

class _IngestConnectionEditorState extends State<_IngestConnectionEditor> {
  AdminRepository get _repo => context.read<AdminRepository>();

  late final _name = TextEditingController(text: widget.connection.name ?? '');
  late final _host = TextEditingController(text: widget.connection.host);
  late final _port = TextEditingController(text: '${widget.connection.port}');
  late final _username = TextEditingController(
    text: widget.connection.username,
  );
  late final _password = TextEditingController();
  late final _folder = TextEditingController(text: widget.connection.folder);
  late final _poll = TextEditingController(
    text: '${widget.connection.pollSeconds}',
  );

  late bool _ssl = widget.connection.ssl;
  late IngestProjectOption? _project = widget.initialProject;

  final _folderFieldKey = GlobalKey();
  final _projectFieldKey = GlobalKey();

  bool _scanning = false;
  bool _saving = false;

  bool get _isNew => widget.connection.id == null;

  /// A scan needs live credentials: either a freshly typed password or a
  /// stored one on an existing connection.
  bool get _canScan =>
      _host.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty &&
      (_password.text.isNotEmpty || widget.connection.passwordSet);

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _username,
      _password,
      _folder,
      _poll,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Rendered in the ROOT overlay so it stays visible above the glass modal's
  // blurred scrim (a Scaffold SnackBar would be buried underneath it).
  void _toast(String message, {GlassToastKind kind = GlassToastKind.warning}) {
    late GlassToastController toast;
    toast = showGlassToast(
      context,
      message,
      kind: kind,
      actionLabel: context.t('common.ok'),
      onAction: () => toast.close(),
    );
  }

  // ─── Folder scan (explicit consent, live IMAP folder listing) ────────

  Future<void> _scanFolders() async {
    if (!_canScan) {
      _toast(context.t('admin.ingest.scanNeedsCredentials'));
      return;
    }
    // Explicit consent: scanning opens a live connection to the mail server
    // with the entered credentials — never done silently.
    final consented = await showGlassConfirm(
      context,
      icon: LucideIcons.scanSearch,
      title: context.t('admin.ingest.scanConsentTitle'),
      message: context.t(
        'admin.ingest.scanConsentBody',
        variables: {'host': _host.text.trim()},
      ),
      confirmLabel: context.t('admin.ingest.scanConsentConfirm'),
      confirmIcon: LucideIcons.scanSearch,
    );
    if (consented != true || !mounted) return;
    setState(() => _scanning = true);
    try {
      final folders = await _repo.probeIngestFolders(
        connectionId: widget.connection.id,
        host: _host.text.trim(),
        port: int.tryParse(_port.text) ?? (_ssl ? 993 : 143),
        ssl: _ssl,
        username: _username.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      setState(() => _scanning = false);
      if (folders.isEmpty) {
        _toast(context.t('admin.ingest.noFoldersFound'));
        return;
      }
      final picked = await showGlassOptions<String>(
        context,
        title: context.t('admin.ingest.folder'),
        anchorRect: _anchorRect(_folderFieldKey),
        options: [
          for (final folder in folders)
            (
              value: folder,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.folder, size: 14, color: AppColors.inkSoft),
                  const SizedBox(width: 8),
                  Text(
                    folder,
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
                  ),
                ],
              ),
            ),
        ],
      );
      if (picked != null && mounted) {
        setState(() => _folder.text = picked);
      }
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _toast(context.t(failure.message), kind: GlassToastKind.error);
    }
  }

  Rect? _anchorRect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  // ─── Project picker (searchable, paginated) ──────────────────────────

  Future<void> _pickProject() async {
    final anchor = _anchorRect(_projectFieldKey);
    final panel = _ProjectSearchPanel(repo: _repo);
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    final picked = wide && anchor != null
        ? await showGlassAnchoredPopover<IngestProjectOption>(
            context,
            anchorRect: anchor,
            width: 360,
            minHeight: 180,
            maxHeight: 420,
            builder: (_) => panel,
          )
        : await showGlassBottomSheet<IngestProjectOption>(
            context,
            builder: (_) => SizedBox(height: 420, child: panel),
          );
    if (picked != null && mounted) {
      setState(() => _project = picked);
    }
  }

  // ─── Save ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_host.text.trim().isEmpty || _username.text.trim().isEmpty) {
      _toast(context.t('admin.ingest.fieldsRequired'));
      return;
    }
    if (_project == null) {
      _toast(context.t('admin.ingest.projectRequired'));
      return;
    }
    final draft = widget.connection.copyWith(
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? (_ssl ? 993 : 143),
      ssl: _ssl,
      username: _username.text.trim(),
      password: _password.text.isEmpty ? null : _password.text,
      folder: _folder.text.trim().isEmpty ? 'INBOX' : _folder.text.trim(),
      projectId: _project!.id,
      pollSeconds: int.tryParse(_poll.text) ?? 60,
      enabled: _isNew ? true : widget.connection.enabled,
    );
    setState(() => _saving = true);
    try {
      final saved = _isNew
          ? await _repo.createIngestConnection(draft)
          : await _repo.updateIngestConnection(draft);
      if (!mounted) return;
      Navigator.of(context).pop((connection: saved, project: _project!));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(context.t(failure.message), kind: GlassToastKind.error);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.inbox,
                size: 18,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t(
                    _isNew
                        ? 'admin.ingest.addConnection'
                        : 'admin.ingest.editConnection',
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _field(
            _name,
            context.t('admin.ingest.name'),
            hint: context.t('admin.ingest.nameHint'),
          ),
          _field(
            _host,
            context.t('admin.smtpHost'),
            hint: 'imap.example.com',
            keyboardType: TextInputType.url,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _field(
                  _port,
                  context.t('admin.smtpPort'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SSL/TLS',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      HiveSwitch(
                        value: _ssl,
                        onChanged: (v) => setState(() {
                          _ssl = v;
                          final defaultPort = v ? '143' : '993';
                          if (_port.text == defaultPort) {
                            _port.text = v ? '993' : '143';
                          }
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _field(
            _username,
            context.t('auth.identifier'),
            hint: 'support@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          _field(
            _password,
            context.t('setup.password'),
            obscure: true,
            helper: widget.connection.passwordSet
                ? context.t('admin.ingest.passwordStored')
                : null,
          ),
          // Folder: exact name by default; explicit-consent scan fills a
          // picker with the mailbox's real folders.
          TextFormField(
            key: _folderFieldKey,
            controller: _folder,
            decoration: InputDecoration(
              labelText: context.t('admin.ingest.folder'),
              hintText: 'INBOX',
              helperText: _scanning
                  ? context.t('admin.ingest.scanning')
                  : context.t('admin.ingest.folderHint'),
              helperMaxLines: 3,
              suffixIcon: _scanning
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: HiveLoader(size: 18, strokeWidth: 2),
                    )
                  : IconButton(
                      tooltip: context.t('admin.ingest.scanFolders'),
                      icon: Icon(
                        LucideIcons.scanSearch,
                        size: 18,
                        color: _canScan
                            ? AppColors.accentStrong
                            : AppColors.inkFaint,
                      ),
                      onPressed: _scanFolders,
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // Project: searchable, paginated picker instead of a raw id field.
          InkWell(
            key: _projectFieldKey,
            borderRadius: BorderRadius.circular(10),
            onTap: _pickProject,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: context.t('admin.ingest.project'),
                suffixIcon: const Icon(LucideIcons.chevronsUpDown, size: 16),
              ),
              child: _project == null
                  ? Text(
                      context.t('admin.ingest.pickProject'),
                      style: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: colorFromHex(_project!.color),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${_project!.key} · ${_project!.name}',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            _poll,
            context.t('admin.ingest.pollSeconds'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(context.t('common.cancel')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const HiveLoader(
                        size: 16,
                        strokeWidth: 2,
                        color: Colors.white,
                      )
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(context.t('common.save')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    String? helper,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    final noAutocorrect =
        obscure ||
        keyboardType == TextInputType.url ||
        keyboardType == TextInputType.emailAddress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: !noAutocorrect,
        enableSuggestions: !obscure,
        inputFormatters: keyboardType == TextInputType.number
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          helperMaxLines: 2,
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }
}

/// Searchable, server-paginated project list — the same inline picker UX as
/// the epic search popover, backed by the admin project-options endpoint.
class _ProjectSearchPanel extends StatefulWidget {
  const _ProjectSearchPanel({required this.repo});

  final AdminRepository repo;

  @override
  State<_ProjectSearchPanel> createState() => _ProjectSearchPanelState();
}

class _ProjectSearchPanelState extends State<_ProjectSearchPanel> {
  static const _debounceDelay = Duration(milliseconds: 180);
  static const _pageSize = 25;

  final _searchCtrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<IngestProjectOption> _results = [];
  final Set<String> _seen = {};
  String _query = '';
  int _page = 0;
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;

  /// Monotonic request token — a stale response never overwrites fresh results.
  int _reqSeq = 0;

  bool get _hasMore => _results.length < _total;

  @override
  void initState() {
    super.initState();
    _run(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 120 && !_loadingMore && _hasMore) {
        _run(reset: false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      _query = value.trim();
      _run(reset: true);
    });
  }

  Future<void> _run({required bool reset}) async {
    final seq = ++_reqSeq;
    setState(() {
      if (reset) {
        _loading = true;
        _page = 0;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final result = await widget.repo.ingestProjectOptions(
        query: _query,
        page: _page,
        size: _pageSize,
      );
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        if (reset) {
          _results.clear();
          _seen.clear();
        }
        for (final option in result.items) {
          if (_seen.add(option.id)) _results.add(option);
        }
        _total = result.total;
        _page++;
        _loading = false;
        _loadingMore = false;
      });
    } on ApiFailure {
      if (!mounted || seq != _reqSeq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              hintText: context.t('admin.ingest.searchProjects'),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: HiveLoader(size: 24))
              : _results.isEmpty
              ? Center(
                  child: Text(
                    context.t('common.noMatches'),
                    style: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _results.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _results.length) {
                      return const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(
                          child: HiveLoader(size: 18, strokeWidth: 2),
                        ),
                      );
                    }
                    final option = _results[index];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colorFromHex(option.color),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              option.key,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                option.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.ink,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
