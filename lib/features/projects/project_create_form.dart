import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'project_key.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/repositories/user_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/hue_colors.dart';
import '../../core/util/keys.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../../core/widgets/person_picker.dart';
import '../sprint/modals/glass_modal.dart';

/// Everything a new project needs before it exists, in one place.
///
/// A project is created from two screens — the project list and a team's
/// settings — and they used to carry a form each. They drifted, as two copies
/// of a form do: one grew a key that types itself, a warning for a key already
/// taken, eight accent swatches and a searchable lead picker, while the other
/// kept four-character keys, six swatches and a dropdown holding the whole
/// directory open. This is the one form; the screens own only the chrome around
/// it and what they do with the result.
class ProjectDraft extends ChangeNotifier {
  ProjectDraft({required this.takenKeys, int? hue, this.meId})
    : hue = hue ?? kProjectHues.first.hue {
    name.addListener(_onNameChanged);
    key.addListener(_onKeyChanged);
  }

  /// Keys already in use, so the suggested one doesn't walk into a conflict the
  /// server would only report after the form is submitted. Best effort — the
  /// server stays the authority (it answers 409 for a key this list missed).
  final Set<String> takenKeys;

  /// The signed-in user, who leads the project until somebody says otherwise.
  final String? meId;

  final name = TextEditingController();
  final key = TextEditingController();
  final description = TextEditingController();

  int hue;

  /// The chosen lead. Held as the person, not just an id: the field shows a
  /// face and a name, and the picker that set it is the only thing that knows
  /// them — there is no directory in memory here to look an id up in.
  DirectoryUser? lead;

  /// The picture chosen before the project exists, uploaded right after it does.
  PickedImage? pendingAvatar;

  /// While true the key follows the name. The first edit of the key field ends
  /// that for good — a key somebody typed is theirs to keep.
  bool _keyFollowsName = true;

  static final _keyPattern = kProjectKeyPattern;

  @override
  void dispose() {
    name.dispose();
    key.dispose();
    description.dispose();
    super.dispose();
  }

  /// Types the key along with the name — the whole point being that nobody has
  /// to invent one, while it stays a plain text field they can overrule.
  void _onNameChanged() {
    if (_keyFollowsName) {
      final suggestion = suggestKey(name.text, taken: takenKeys);
      if (suggestion != key.text) {
        // Set through the controller's value so the caret stays at the end.
        key.value = TextEditingValue(
          text: suggestion,
          selection: TextSelection.collapsed(offset: suggestion.length),
        );
        return; // the key listener notifies
      }
    }
    notifyListeners();
  }

  void _onKeyChanged() {
    // Only a *typed* key breaks the link; the one we just wrote does not.
    if (_keyFollowsName &&
        key.text != suggestKey(name.text, taken: takenKeys)) {
      _keyFollowsName = false;
    }
    notifyListeners();
  }

  void setHue(int value) {
    if (hue == value) return;
    hue = value;
    notifyListeners();
  }

  void setLead(DirectoryUser? value) {
    if (lead?.id == value?.id) return;
    lead = value;
    notifyListeners();
  }

  void setAvatar(PickedImage? value) {
    pendingAvatar = value;
    notifyListeners();
  }

  /// A key the client already knows is taken — surfaced before the round trip.
  bool get keyTaken => takenKeys.contains(trimmedKey);

  bool get valid =>
      trimmedName.isNotEmpty && _keyPattern.hasMatch(trimmedKey) && !keyTaken;

  String get trimmedName => name.text.trim();
  String get trimmedKey => key.text.trim().toUpperCase();
  String? get trimmedDescription =>
      description.text.trim().isEmpty ? null : description.text.trim();
  String get colorHex => hexForHue(hue);
}

/// The fields of [ProjectDraft], laid out: picture + name + key, description,
/// lead and accent, and the note about the workflow the project starts with.
///
/// Brings no header, no footer and no submit — a caller wraps it in whatever
/// modal it already has and decides what "create" means (a project of its own,
/// or one that belongs to a team).
class ProjectCreateFields extends StatefulWidget {
  const ProjectCreateFields({
    super.key,
    required this.draft,
    this.autofocus = true,
  });

  final ProjectDraft draft;

  /// Off where the form shares its modal with something else that should have
  /// the caret first — a tab strip the user may still be choosing between.
  final bool autofocus;

  @override
  State<ProjectCreateFields> createState() => _ProjectCreateFieldsState();
}

class _ProjectCreateFieldsState extends State<ProjectCreateFields> {
  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_onDraftChanged);
    _loadMe();
  }

  @override
  void dispose() {
    widget.draft.removeListener(_onDraftChanged);
    super.dispose();
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  /// Whoever is creating the project leads it until they say otherwise, so the
  /// field opens filled. One request for one person, not the whole directory:
  /// the picker pages the rest when it is opened.
  Future<void> _loadMe() async {
    final meId = widget.draft.meId;
    if (meId == null || widget.draft.lead != null) return;
    try {
      final found = await context.read<UserRepository>().usersByIds([meId]);
      if (mounted && found.isNotEmpty) widget.draft.setLead(found.first);
    } on ApiFailure {
      // The field stays empty and the picker is still one tap away.
    }
  }

  Future<void> _pickLead(Rect anchor) async {
    final draft = widget.draft;
    final picked = await showPersonPicker(
      context,
      anchorRect: anchor,
      selectedId: draft.lead?.id,
      meId: draft.meId,
    );
    if (picked != null && mounted) draft.setLead(picked);
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _identityRow(compact),
        const SizedBox(height: 16),
        GlassField(
          label: context.t('projects.descriptionOptional'),
          child: TextField(
            controller: widget.draft.description,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: glassInputDecoration(
              hint: context.t('projectSettings.descHint'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _leadAndColor(compact),
        const SizedBox(height: 16),
        GlassInfoLine(
          icon: LucideIcons.info,
          child: Text(
            context.t('projects.defaultWorkflowInfo'),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.inkSoft,
            ),
          ),
        ),
      ],
    );
  }

  Widget _identityRow(bool compact) {
    final draft = widget.draft;
    // The key/colour tile doubles as the picture field: a project being created
    // has no id yet and the avatar endpoints are addressed by id, so the pick is
    // held in memory and uploaded the moment the project exists.
    // Dropped past the field's label so the tile lines up with the input beside
    // it rather than with the label above it. On the row, not inside the glyph:
    // the avatar field clips its fallback to a 52×52 box, so an offset in there
    // comes out of the tile's own height — which is exactly how it shipped as a
    // pill. [_kFieldLabelHeight] is GlassField's label line plus its 7-pixel gap.
    final glyph = Padding(
      padding: const EdgeInsets.only(top: _kFieldLabelHeight),
      child: PendingAvatarField(
        picked: draft.pendingAvatar,
        size: 52,
        radius: 15,
        strings: EntityAvatarStrings.project,
        fallback: ProjectGlyphPreview(hue: draft.hue, keyText: draft.key.text),
        onPicked: draft.setAvatar,
      ),
    );
    final nameField = GlassField(
      label: context.t('projects.name'),
      child: TextField(
        controller: draft.name,
        autofocus: widget.autofocus,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        decoration: glassInputDecoration(
          hint: context.t('projects.namePlaceholder'),
        ),
      ),
    );
    final keyField = GlassField(
      label: context.t('projects.key'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: draft.key,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: 10,
            style: const TextStyle(fontFamily: AppTheme.fontMono),
            inputFormatters: const [ProjectKeyFormatter()],
            decoration: glassInputDecoration(
              hint: 'BILL',
            ).copyWith(counterText: ''),
          ),
          // Said here rather than after a round trip that fails.
          if (draft.keyTaken)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.t('projects.keyTaken'),
                style: const TextStyle(fontSize: 11.5, color: AppColors.danger),
              ),
            ),
        ],
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              glyph,
              const SizedBox(width: 12),
              Expanded(child: nameField),
            ],
          ),
          const SizedBox(height: 14),
          keyField,
        ],
      );
    }
    return Row(
      // start, not end: the key field grows a "key taken" line beneath it, and
      // bottom-aligning would shove the picture tile and the name field down by
      // that line's height every time the message appears.
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        glyph,
        const SizedBox(width: 12),
        Expanded(child: nameField),
        const SizedBox(width: 12),
        SizedBox(width: 104, child: keyField),
      ],
    );
  }

  Widget _leadAndColor(bool compact) {
    final draft = widget.draft;
    final lead = GlassField(
      label: context.t('projects.projectLead'),
      child: PersonPickerField(
        person: draft.lead,
        isMe: draft.lead != null && draft.lead!.id == draft.meId,
        placeholderKey: 'projects.picker.chooseLead',
        onTap: _pickLead,
      ),
    );
    final color = GlassField(
      label: context.t('projects.color'),
      child: _AccentSwatches(selected: draft.hue, onPick: draft.setHue),
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [lead, const SizedBox(height: 16), color],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: lead),
        const SizedBox(width: 16),
        Flexible(child: color),
      ],
    );
  }
}

/// GlassField's label line (11.5 pt) plus the 7-pixel gap below it — how far a
/// control beside a labelled field has to drop to sit level with its input.
const double _kFieldLabelHeight = 22;

/// The project's key on its colour, standing in for a picture that has not been
/// chosen.
///
/// Deliberately unsized: it fills whatever box it is given. It used to carry its
/// own 54×54 and a 22-pixel top margin, from when it stood alone in the row and
/// had to be pushed down past the field's label. Inside [PendingAvatarField]
/// that margin ate 22 of the 52 available pixels and the tile came out as a
/// 52×30 pill — the default state of every new project, and it shipped. A
/// fallback has no business knowing how big it is; the field that frames it
/// does.
class ProjectGlyphPreview extends StatelessWidget {
  const ProjectGlyphPreview({
    super.key,
    required this.hue,
    required this.keyText,
  });

  final int hue;
  final String keyText;

  @override
  Widget build(BuildContext context) {
    final label = keyText.isEmpty
        ? 'P'
        : keyText.substring(0, keyText.length.clamp(0, 3));
    return ColoredBox(
      color: hueSoft(hue),
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: hueChipText(hue),
          ),
        ),
      ),
    );
  }
}

/// Static accent-color swatch row for the create modal.
class _AccentSwatches extends StatelessWidget {
  const _AccentSwatches({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in kProjectHues)
          GestureDetector(
            onTap: () => onPick(c.hue),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: hueSwatch(c.hue),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: c.hue == selected ? AppColors.ink : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
