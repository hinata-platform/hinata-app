import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Card that groups related admin settings with an icon, title and subtitle.
class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(icon, size: 18, color: AppColors.accentStrong),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline),
          // Fields
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled text field bound to a map key. Handles secret masking.
class AdminField extends StatelessWidget {
  const AdminField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.isSecret = false,
    this.hint,
    this.keyboardType,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool isSecret;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initialValue,
        obscureText: isSecret,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: isSecret ? _secretHint(context) : null,
        ),
        onChanged: onChanged,
      ),
    );
  }

  String _secretHint(BuildContext context) {
    // We reuse the existing translation key
    return 'Leave blank to keep the stored value';
  }
}

/// A numeric text field bound to a map key.
class AdminNumberField extends StatelessWidget {
  const AdminNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min,
    this.max,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String? suffix;
  final int? min;
  final int? max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: '$value',
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: suffix,
        ),
        onChanged: (v) {
          final parsed = int.tryParse(v);
          if (parsed == null) return;
          final clamped = min != null && parsed < min!
              ? min!
              : max != null && parsed > max!
                  ? max!
                  : parsed;
          onChanged(clamped);
        },
      ),
    );
  }
}

/// Enable/disable toggle row (used for SSO provider and feature blocks).
class AdminToggle extends StatelessWidget {
  const AdminToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: TextStyle(
                    fontSize: 12, color: AppColors.inkSoft))
            : null,
        value: value,
        activeTrackColor: AppColors.navy,
        onChanged: onChanged,
      ),
    );
  }
}

/// Expandable provider block: enable switch + form fields.
class ProviderTile extends StatefulWidget {
  const ProviderTile({
    super.key,
    required this.title,
    required this.section,
    required this.fields,
    required this.onChanged,
    this.subtitle,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final Map<String, dynamic> section;

  /// (jsonKey, label, isSecret)
  final List<(String, String, bool)> fields;
  final VoidCallback onChanged;
  final bool initiallyExpanded;

  @override
  State<ProviderTile> createState() => _ProviderTileState();
}

class _ProviderTileState extends State<ProviderTile> {
  @override
  Widget build(BuildContext context) {
    final enabled = widget.section['enabled'] == true;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                enabled ? AppColors.accentLine : AppColors.hairline2),
        ),
        margin: const EdgeInsets.only(bottom: 10),
        child: ExpansionTile(
          initiallyExpanded:
              widget.initiallyExpanded || enabled,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          title: Row(
            children: [
              Switch(
                value: enabled,
                activeTrackColor: AppColors.navy,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) {
                  setState(() => widget.section['enabled'] = value);
                  widget.onChanged();
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: enabled
                              ? AppColors.ink
                              : AppColors.inkSoft,
                        )),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.inkFaint)),
                  ],
                ),
              ),
            ],
          ),
          children: [
            for (final (key, label, secret) in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextFormField(
                  initialValue:
                      (widget.section[key] as String?) ?? '',
                  obscureText: secret,
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: secret
                        ? 'Leave blank to keep the stored value'
                        : null,
                  ),
                  onChanged: (value) => widget.section[key] = value,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
