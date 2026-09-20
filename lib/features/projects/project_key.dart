import 'package:flutter/services.dart';

/// The shape a project key has to hold: one letter, then one to nine letters or
/// digits, upper case.
///
/// The server is the authority ([ProjectService.create] refuses anything else
/// and answers 409 for a key already taken), and this is the form a field checks
/// so nobody fills in a sheet to be told afterwards. One copy, because three
/// screens ask the same question — create a project, rename one, copy one — and
/// three copies had already drifted into two different answers about whether
/// lower case is acceptable input.
final RegExp kProjectKeyPattern = RegExp(r'^[A-Z][A-Z0-9]{1,9}$');

/// Whether [key] is a key the server will take. An empty key is *not* a match:
/// a field that may be left blank decides that for itself.
bool isProjectKey(String key) => kProjectKeyPattern.hasMatch(key.toUpperCase());

/// Uppercases and strips anything outside `[A-Z0-9]` as a project key is typed,
/// so the field always holds exactly what would be stored.
class ProjectKeyFormatter extends TextInputFormatter {
  const ProjectKeyFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
