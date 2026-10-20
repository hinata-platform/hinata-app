import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import 'person_profile_screen.dart';

/// Makes a person's face a way to their profile (HIN-165).
///
/// For an avatar beside a name the row already shows: a shortcut for the
/// pointer and a named button for a screen reader ("Open Mia Berger's
/// profile"), never the only way to the person.
class PersonLink extends StatelessWidget {
  const PersonLink({
    super.key,
    required this.personId,
    required this.name,
    required this.child,
  });

  final String personId;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (personId.isEmpty) return child;
    void open() => unawaited(openPersonProfile(context, personId));
    return Semantics(
      button: true,
      label: context.t('people.open', variables: {'name': name}),
      excludeSemantics: true,
      onTap: open,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: open,
          customBorder: const CircleBorder(),
          child: child,
        ),
      ),
    );
  }
}
