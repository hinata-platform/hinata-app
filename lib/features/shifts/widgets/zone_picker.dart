import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import '../shift_zones.dart';

/// Picks an IANA zone for an event (HIN-160): a search field over every zone
/// the database knows, at the field on a wide window, a sheet on a phone.
Future<String?> showZonePicker(
  BuildContext context, {
  required Rect anchorRect,
  String? selected,
}) async {
  await ShiftZones.ensureLoaded();
  if (!context.mounted) return null;
  final zones = ShiftZones.all();
  Widget panel(BuildContext _) => _ZonePanel(zones: zones, selected: selected);
  if (MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint) {
    return showGlassAnchoredPopover<String>(
      context,
      anchorRect: anchorRect,
      width: 340,
      minHeight: 240,
      maxHeight: 440,
      builder: panel,
    );
  }
  return showGlassBottomSheet<String>(
    context,
    builder: (sheet) => ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 480),
      child: panel(sheet),
    ),
  );
}

class _ZonePanel extends StatefulWidget {
  const _ZonePanel({required this.zones, required this.selected});

  final List<String> zones;
  final String? selected;

  @override
  State<_ZonePanel> createState() => _ZonePanelState();
}

class _ZonePanelState extends State<_ZonePanel> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase().replaceAll(' ', '_');
    final hits = q.isEmpty
        ? widget.zones
        : [
            for (final z in widget.zones)
              if (z.toLowerCase().contains(q)) z,
          ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(LucideIcons.search, size: 16),
              hintText: context.t('shifts.plan.event.zoneSearch'),
              isDense: true,
            ),
          ),
        ),
        Flexible(
          child: hits.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.t('shifts.plan.event.zoneNone'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.inkSoft,
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: hits.length,
                  itemBuilder: (context, i) {
                    final zone = hits[i];
                    final picked = zone == widget.selected;
                    return Semantics(
                      button: true,
                      selected: picked,
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(zone),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: Icon(
                                  picked
                                      ? LucideIcons.circleCheck
                                      : LucideIcons.globe,
                                  size: 16,
                                  color: picked
                                      ? AppColors.accentInk
                                      : AppColors.inkSoft,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  zone.replaceAll('_', ' '),
                                  style: TextStyle(
                                    fontSize: AppType.label,
                                    color: AppColors.ink,
                                    fontWeight: picked
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
