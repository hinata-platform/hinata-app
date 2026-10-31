import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/pdf/pdf_syntax.dart';
import 'package:hinata/core/pdf/pdf_unlock.dart';

/// Fixtures: one page saying "Geheimer Text HIN-180", an /Info title with
/// escaped parentheses and a UTF-16 author, encrypted by qpdf with the user
/// password `geheim` and the owner password `owner`.
Uint8List _fixture(String name) =>
    File('test/fixtures/pdf/$name.pdf').readAsBytesSync();

/// Every string and (inflated) stream payload in [pdf], as Latin-1 text: what
/// a reader of the document would see once it is decrypted.
String _visibleText(Uint8List pdf) {
  final out = StringBuffer();
  final text = latin1.decode(pdf);
  for (final m in RegExp(r'(\d+) (\d+) obj').allMatches(text)) {
    final object = PdfReader(pdf).readIndirect(m.start);
    void walk(PdfValue v) {
      switch (v) {
        case PdfString(:final bytes):
          out.writeln(latin1.decode(bytes));
        case PdfArray(:final items):
          items.forEach(walk);
        case PdfDict(:final entries):
          entries.values.forEach(walk);
        case PdfStream(:final dict, :final data):
          walk(dict);
          final flate = dict.nameOf('Filter') == 'FlateDecode';
          out.writeln(
            latin1.decode(flate ? const ZLibDecoder().decodeBytes(data) : data),
          );
        default:
          break;
      }
    }

    walk(object.value);
  }
  return out.toString();
}

void main() {
  const encrypted = [
    'rc4_40',
    'rc4_128',
    'aes_128',
    'aes_128_objstm',
    'aes_256',
    'aes_256_objstm',
  ];

  test('an unencrypted PDF is handed back untouched', () {
    final plain = _fixture('plain');
    final result = PdfUnlock.unlockSync(plain);
    expect(result, isA<PdfUnlocked>());
    expect(identical((result as PdfUnlocked).bytes, plain), isTrue);
  });

  for (final name in encrypted) {
    group(name, () {
      test('asks for a password, and says nothing about a wrong one yet', () {
        final result = PdfUnlock.unlockSync(_fixture(name));
        expect(result, isA<PdfNeedsPassword>());
        expect((result as PdfNeedsPassword).wrongPassword, isFalse);
      });

      test('rejects a wrong password', () {
        final result = PdfUnlock.unlockSync(_fixture(name), password: 'falsch');
        expect(result, isA<PdfNeedsPassword>());
        expect((result as PdfNeedsPassword).wrongPassword, isTrue);
      });

      for (final password in ['geheim', 'owner']) {
        test('opens with the ${password == 'owner' ? 'owner' : 'user'} '
            'password into a plain PDF', () {
          final source = _fixture(name);
          final result = PdfUnlock.unlockSync(source, password: password);
          expect(result, isA<PdfUnlocked>());
          final bytes = (result as PdfUnlocked).bytes;
          expect(latin1.decode(bytes), isNot(contains('/Encrypt')));
          // The copy is a plain PDF now: reading it again changes nothing.
          final again = PdfUnlock.unlockSync(bytes);
          expect(identical((again as PdfUnlocked).bytes, bytes), isTrue);
          final visible = _visibleText(bytes);
          expect(visible, contains('Geheimer Text HIN-180'));
          expect(visible, contains('Vertraulich (intern)'));
          expect(latin1.decode(source), isNot(contains('Vertraulich')));
        });
      }
    });
  }

  test('a non-Latin-1 password opens an AES-256 document', () {
    final file = _fixture('aes_256_unicode');
    expect(
      PdfUnlock.unlockSync(file, password: 'Grüsse'),
      isA<PdfNeedsPassword>(),
    );
    final result = PdfUnlock.unlockSync(file, password: 'Grüße€');
    expect(
      _visibleText((result as PdfUnlocked).bytes),
      contains('Geheimer Text HIN-180'),
    );
  });

  test('an owner-only PDF opens without a prompt', () {
    final result = PdfUnlock.unlockSync(_fixture('owner_only'));
    expect(result, isA<PdfUnlocked>());
    expect(
      _visibleText((result as PdfUnlocked).bytes),
      contains('Geheimer Text HIN-180'),
    );
  });

  test('a file that is not a PDF at all goes to the renderer as it is', () {
    final junk = Uint8List.fromList(latin1.encode('junk /Encrypt junk'));
    final result = PdfUnlock.unlockSync(junk);
    expect(identical((result as PdfUnlocked).bytes, junk), isTrue);
  });
}
