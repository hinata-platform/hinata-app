import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZLibDecoder, ZLibEncoder;
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

  test('an owner-only PDF goes to the renderer as it is, without a prompt', () {
    // Every renderer opens a file without a user password itself; decrypting
    // it here would only cost time and memory on each view.
    final file = _fixture('owner_only');
    final result = PdfUnlock.unlockSync(file);
    expect(identical((result as PdfUnlocked).bytes, file), isTrue);
  });

  group('a hostile file', () {
    /// [_fixture] with an incremental update appended: [objects] (already
    /// serialized) and a trailer or cross-reference stream ([section]),
    /// which `startxref` then points at.
    Uint8List update(
      String name,
      String Function(int at) section, {
      List<int> objects = const [],
    }) {
      final base = _fixture(name);
      final out = BytesBuilder()
        ..add(base)
        ..add(objects);
      final at = out.length;
      out
        ..add(latin1.encode(section(at)))
        ..add(latin1.encode('\nstartxref\n$at\n%%EOF\n'));
      return out.takeBytes();
    }

    test('cannot make the copy as long as the object numbers it claims', () {
      // One entry with the largest number the syntax can carry would have the
      // rewrite write ten billion rows of cross-reference table.
      final file = update(
        'aes_256',
        (_) =>
            'xref\n9999999999 1\n0000000010 00000 n \n'
            'trailer\n<< /Size 10000000000 /Root 1 0 R /Prev 1286 /Encrypt 7 0 R >>',
      );
      final watch = Stopwatch()..start();
      final result = PdfUnlock.unlockSync(file, password: 'geheim');
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
      // Unreadable here, so it goes to the renderer as it was.
      expect(identical((result as PdfUnlocked).bytes, file), isTrue);
    });

    test('cannot inflate a few kilobytes into gigabytes', () {
      // A cross-reference stream is inflated before any password is checked.
      // 64 MB of zeros compress to some 64 KB; the budget for a file this
      // small is a fraction of that.
      final bomb = const ZLibEncoder().encodeBytes(Uint8List(64 << 20));
      final file = update(
        'aes_256',
        (_) => '',
        objects: [
          ...latin1.encode(
            '99 0 obj\n<< /Type /XRef /W [1 4 2] /Size 100 /Root 1 0 R /Encrypt 7 0 R '
            '/Prev 1286 /Filter /FlateDecode /Length ${bomb.length} >>\n'
            'stream\n',
          ),
          ...bomb,
          ...latin1.encode('\nendstream\nendobj\n'),
        ],
      );
      // Point startxref at the stream object rather than at the empty section.
      final text = latin1.decode(file);
      final at = text.lastIndexOf('99 0 obj');
      final bytes = Uint8List.fromList([
        ...file.sublist(0, text.lastIndexOf('startxref')),
        ...latin1.encode('startxref\n$at\n%%EOF\n'),
      ]);
      final result = PdfUnlock.unlockSync(bytes, password: 'geheim');
      // Unreadable here, so it goes to the renderer as it was.
      expect(identical((result as PdfUnlocked).bytes, bytes), isTrue);
    });

    test('cannot have one object read once per entry pointing at it', () {
      // Every entry of this section names the place of object 1. Honouring
      // them all would read that object once per entry and copy it 50 000
      // times; it is read once, and kept under its own number only.
      final at = latin1.decode(_fixture('aes_256')).indexOf('1 0 obj');
      final row = '${'$at'.padLeft(10, '0')} 00000 n \n';
      final file = update(
        'aes_256',
        (_) =>
            'xref\n100 50000\n${List.filled(50000, row).join()}'
            'trailer\n<< /Size 50100 /Root 1 0 R /Prev 1286 '
            '/Encrypt 7 0 R >>',
      );
      final result = PdfUnlock.unlockSync(file, password: 'geheim');
      final copy = latin1.decode((result as PdfUnlocked).bytes);
      expect(RegExp(r'\d+ 0 obj').allMatches(copy).length, lessThan(10));
      expect(copy, contains('1 0 obj\n<< /Extensions'));
      expect(_visibleText(result.bytes), contains('Geheimer Text HIN-180'));
    });
  });

  test('a file that is not a PDF at all goes to the renderer as it is', () {
    final junk = Uint8List.fromList(latin1.encode('junk /Encrypt junk'));
    final result = PdfUnlock.unlockSync(junk);
    expect(identical((result as PdfUnlocked).bytes, junk), isTrue);
  });
}
