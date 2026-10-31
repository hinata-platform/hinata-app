import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart' show ArchiveException, ZLibDecoder;
import 'package:flutter/foundation.dart' show compute, debugPrint;

import 'pdf_security.dart';
import 'pdf_syntax.dart';

/// What opening a PDF came to.
sealed class PdfUnlockResult {
  const PdfUnlockResult();
}

/// Bytes a renderer can draw: the file itself when it was never encrypted (or
/// could not be read here), otherwise a decrypted copy.
final class PdfUnlocked extends PdfUnlockResult {
  const PdfUnlocked(this.bytes);
  final Uint8List bytes;
}

/// The document needs a password. [wrongPassword] is true when one was given
/// and it opened nothing.
final class PdfNeedsPassword extends PdfUnlockResult {
  const PdfNeedsPassword({required this.wrongPassword});
  final bool wrongPassword;
}

/// Opens password-protected PDFs, so they can be shown at all (HIN-180).
///
/// None of the renderers the app rasterizes with takes a password through the
/// `printing` package — not Core Graphics, not Android's `PdfRenderer`, not
/// pdfium, not pdf.js — so a document with a user password failed to render on
/// every platform. Decrypting here, in Dart, is the one way that works the same
/// everywhere: the file is rewritten without its encryption and the renderer
/// gets a plain PDF.
///
/// Documents that only carry an owner password (open freely, restricted
/// printing or copying) go to the renderer as they are: every one of them
/// opens those itself. Whatever this reader cannot handle goes there unchanged
/// too, which is how such a file was shown before.
class PdfUnlock {
  const PdfUnlock._();

  /// Runs [unlockSync] off the UI isolate: a large document means a lot of
  /// AES, and R6 key checks are deliberately slow. The look for encryption
  /// comes first and stays here, so the PDFs that have none — nearly all of
  /// them — are handed back as they are, without a copy into an isolate.
  static Future<PdfUnlockResult> unlock(
    Uint8List bytes, {
    String password = '',
  }) async {
    if (!_mayBeEncrypted(bytes)) return PdfUnlocked(bytes);
    return compute(_unlockMessage, (bytes: bytes, password: password));
  }

  static PdfUnlockResult _unlockMessage(
    ({Uint8List bytes, String password}) m,
  ) => unlockSync(m.bytes, password: m.password);

  static PdfUnlockResult unlockSync(Uint8List bytes, {String password = ''}) {
    if (!_mayBeEncrypted(bytes)) return PdfUnlocked(bytes);
    final _Document doc;
    final PdfSecurityHandler handler;
    try {
      doc = _Document.read(bytes);
      final encrypt = doc.trailer['Encrypt'];
      if (encrypt == null) return PdfUnlocked(bytes);
      final dict = doc.resolve(encrypt);
      if (dict is! PdfDict) throw const PdfSyntaxException('bad /Encrypt');
      handler = PdfSecurityHandler.parse(dict, doc.firstId);
    } on Object catch (e) {
      debugPrint('PDF unlock: cannot read security settings: $e');
      return PdfUnlocked(bytes);
    }
    final decryptor = handler.authenticate(password);
    if (decryptor == null) {
      return PdfNeedsPassword(wrongPassword: password.isNotEmpty);
    }
    // Opened by the empty password: there is no user password, and every
    // renderer opens such a file itself.
    if (password.isEmpty) return PdfUnlocked(bytes);
    return PdfUnlocked(doc.rewriteDecrypted(decryptor));
  }

  static final Uint8List _encryptKey = latin1.encode('/Encrypt');

  /// Whether the document's last trailer can name an `/Encrypt` dictionary.
  ///
  /// Every update of an encrypted file has to repeat the key in its trailer
  /// (ISO 32000-2, 7.5.6), so two windows are enough instead of the whole
  /// file: its end, where a classic trailer sits, and the start of the section
  /// `startxref` points to, which is where a cross-reference stream keeps its
  /// dictionary (and a linearized file its first-page trailer).
  static bool _mayBeEncrypted(Uint8List bytes) {
    final tailStart = math.max(0, bytes.length - 4096);
    final tail = Uint8List.sublistView(bytes, tailStart);
    if (indexOfBytes(tail, _encryptKey) >= 0) return true;
    final match = RegExp(
      r'startxref\s+(\d{1,15})',
    ).allMatches(latin1.decode(tail)).lastOrNull;
    if (match == null) return false;
    final offset = int.parse(match.group(1)!);
    if (offset >= bytes.length) return false;
    final window = Uint8List.sublistView(
      bytes,
      offset,
      math.min(bytes.length, offset + 65536),
    );
    return indexOfBytes(window, _encryptKey) >= 0;
  }
}

/// Where the cross-reference data puts an object.
sealed class _Entry {
  const _Entry();
}

final class _AtOffset extends _Entry {
  const _AtOffset(this.offset);
  final int offset;
}

final class _InStream extends _Entry {
  const _InStream(this.stream, this.index);
  final int stream;
  final int index;
}

/// A PDF read through its cross-reference data, enough to copy it out again.
class _Document {
  _Document._(this._bytes);

  final Uint8List _bytes;
  final Map<int, _Entry> _entries = {};
  final Map<String, PdfValue> trailer = {};
  final Map<int, PdfIndirect> _objects = {};

  /// Every place in the file read so far, with what was found there (or why
  /// nothing could be). A file can list one offset under any number of object
  /// numbers; each place is still read once, and only the number its object
  /// header carries gets the object.
  final Map<int, Object> _atOffset = {};

  /// Upper bounds that keep a hostile file from running the reader in circles
  /// or out of memory; real documents are orders of magnitude below them.
  static const int _maxSections = 1024;
  static const int _maxObjects = 1000000;

  /// The largest object number ISO 32000 allows. The copy's cross-reference
  /// table has a row for every number up to the highest, so a file must not
  /// get to pick that number freely.
  static const int _maxObjectNumber = 8388607;

  /// What inflating cross-reference and object streams may produce, all
  /// together: generous for real files, where both are a fraction of the
  /// document, and a hard stop for a few kilobytes that inflate to gigabytes.
  late final int _inflateBudget = math.min(
    256 << 20,
    (1 << 20) + 64 * _bytes.length,
  );
  int _inflated = 0;

  static _Document read(Uint8List bytes) {
    final doc = _Document._(bytes);
    doc._readXref(doc._startXref());
    if (doc.trailer['Root'] == null) {
      throw const PdfSyntaxException('no /Root in trailer');
    }
    return doc;
  }

  Uint8List get firstId => switch (trailer['ID']) {
    PdfArray(:final items) when items.isNotEmpty && items.first is PdfString =>
      (items.first as PdfString).bytes,
    _ => Uint8List(0),
  };

  int _startXref() {
    final tail = latin1.decode(
      Uint8List.sublistView(
        _bytes,
        (_bytes.length - 2048).clamp(0, _bytes.length),
      ),
    );
    final at = tail.lastIndexOf('startxref');
    if (at < 0) throw const PdfSyntaxException('no startxref');
    final match = RegExp(r'startxref\s+(\d+)').matchAsPrefix(tail, at);
    if (match == null) throw const PdfSyntaxException('bad startxref');
    return int.parse(match.group(1)!);
  }

  void _readXref(int start) {
    final seen = <int>{};
    int? next = start;
    while (next != null) {
      if (!seen.add(next) || seen.length > _maxSections) {
        throw const PdfSyntaxException('cross-reference loop');
      }
      final reader = PdfReader(_bytes)..pos = next;
      reader.skipWhite();
      final PdfDict section;
      if (reader.lookingAt('xref')) {
        reader.pos += 4;
        section = _readTable(reader);
        // A hybrid file keeps its compressed objects in a stream next to
        // the table.
        final hybrid = section.intOf('XRefStm');
        if (hybrid != null && seen.add(hybrid)) _readXrefStream(hybrid);
      } else {
        section = _readXrefStream(next);
      }
      for (final key in const ['Root', 'Info', 'ID', 'Encrypt']) {
        final value = section[key];
        if (value != null) trailer.putIfAbsent(key, () => value);
      }
      next = section.intOf('Prev');
    }
  }

  // Free entries are skipped rather than recorded: an object a later update
  // deleted then comes back from an older section, which costs an unused
  // object in the copy and nothing else, while recording them would hide the
  // compressed objects a hybrid file lists as free in its table.
  void _put(int num, _Entry entry) {
    if (num < 0 || num > _maxObjectNumber) {
      throw PdfSyntaxException('object number $num out of range');
    }
    if (_entries.length >= _maxObjects) {
      throw const PdfSyntaxException('too many objects');
    }
    _entries.putIfAbsent(num, () => entry);
  }

  PdfDict _readTable(PdfReader r) {
    while (true) {
      r.skipWhite();
      if (r.lookingAt('trailer')) {
        r.pos += 'trailer'.length;
        final dict = r.readValue();
        if (dict is! PdfDict) throw const PdfSyntaxException('bad trailer');
        return dict;
      }
      final first = r.readInt();
      final count = r.readInt();
      for (var i = 0; i < count; i++) {
        final offset = r.readInt();
        r.readInt(); // generation, read again from the object header
        r.skipWhite();
        if (r.atEnd) throw const PdfSyntaxException('truncated xref');
        final kind = r.bytes[r.pos++];
        if (kind == 0x6E && offset > 0) _put(first + i, _AtOffset(offset)); // n
      }
    }
  }

  PdfDict _readXrefStream(int offset) {
    final object = PdfReader(_bytes).readIndirect(offset);
    final stream = object.value;
    if (stream is! PdfStream || stream.dict.nameOf('Type') != 'XRef') {
      throw PdfSyntaxException('no cross-reference at $offset');
    }
    final dict = stream.dict;
    final w = switch (dict['W']) {
      PdfArray(:final items) when items.length == 3 => [
        for (final i in items) i is PdfNumber ? (i.asInt ?? 0) : 0,
      ],
      _ => throw const PdfSyntaxException('bad /W'),
    };
    if (w.any((n) => n < 0 || n > 8)) throw const PdfSyntaxException('bad /W');
    final rowLength = w[0] + w[1] + w[2];
    final size = dict.intOf('Size') ?? 0;
    final index = switch (dict['Index']) {
      PdfArray(:final items) => [
        for (final i in items) i is PdfNumber ? (i.asInt ?? 0) : 0,
      ],
      _ => [0, size],
    };
    final data = _decodeStream(stream);
    var at = 0;
    int field(int width, int fallback) {
      if (width == 0) return fallback;
      var v = 0;
      for (var i = 0; i < width; i++) {
        v = (v << 8) | data[at++];
      }
      return v;
    }

    for (var s = 0; s + 1 < index.length; s += 2) {
      for (var i = 0; i < index[s + 1]; i++) {
        if (rowLength == 0 || at + rowLength > data.length) return dict;
        final type = field(w[0], 1);
        final a = field(w[1], 0);
        final b = field(w[2], 0);
        final num = index[s] + i;
        if (type == 1 && a > 0) _put(num, _AtOffset(a));
        if (type == 2) _put(num, _InStream(a, b));
      }
    }
    return dict;
  }

  /// Follows a reference to the top-level object it names. Objects packed into
  /// an object stream come back null here; [rewriteDecrypted] reads those
  /// through [_compressed], which needs the decryptor.
  PdfValue? resolve(PdfValue value) =>
      value is PdfRef ? _object(value.num)?.value : value;

  final Set<int> _resolving = {};

  PdfIndirect? _object(int num) {
    final cached = _objects[num];
    if (cached != null) return cached;
    final entry = _entries[num];
    if (entry == null || !_resolving.add(num)) return null;
    try {
      final object = switch (entry) {
        _AtOffset(:final offset) => _readAt(offset),
        _InStream() => null, // only reached through [_compressed]
      };
      if (object == null || object.num != num) return null;
      _objects[num] = object;
      return object;
    } finally {
      _resolving.remove(num);
    }
  }

  PdfIndirect _readAt(int offset) {
    final known = _atOffset[offset];
    if (known is PdfIndirect) return known;
    if (known != null) throw known;
    try {
      return _atOffset[offset] = PdfReader(_bytes).readIndirect(
        offset,
        streamLength: (v) => switch (resolve(v)) {
          PdfNumber n => n.asInt,
          _ => null,
        },
      );
    } on PdfSyntaxException catch (e) {
      _atOffset[offset] = e;
      rethrow;
    }
  }

  /// The objects packed into the object stream [num], decrypted and inflated,
  /// by their index in it: each with the object number the stream's header
  /// gives, which has to match the cross-reference entry that led there.
  final Map<int, List<(int, PdfValue)>> _streams = {};

  List<(int, PdfValue)> _compressed(int num, PdfDecryptor decryptor) =>
      _streams.putIfAbsent(num, () {
        final object = _object(num);
        final stream = object?.value;
        if (object == null || stream is! PdfStream) return const [];
        final plain = _decodeStream(
          PdfStream(
            stream.dict,
            decryptor.decryptStream(stream.data, object.num, object.gen),
          ),
        );
        final count = stream.dict.intOf('N') ?? 0;
        final first = stream.dict.intOf('First') ?? 0;
        final reader = PdfReader(plain);
        final headers = <(int, int)>[];
        for (var i = 0; i < count; i++) {
          headers.add((reader.readInt(), reader.readInt()));
        }
        return [
          for (final (objNum, offset) in headers)
            (objNum, (reader..pos = first + offset).readValue()),
        ];
      });

  /// Writes the whole document out again without its encryption: every
  /// object at the top level (object streams unpacked), a classic
  /// cross-reference table, and a trailer without `/Encrypt`.
  Uint8List rewriteDecrypted(PdfDecryptor decryptor) {
    final encryptRef = trailer['Encrypt'];
    final encryptNum = encryptRef is PdfRef ? encryptRef.num : null;
    final out = PdfWriter()
      ..ascii('${_header()}\n%')
      ..raw(Uint8List.fromList(const [0xE2, 0xE3, 0xCF, 0xD3]))
      ..ascii('\n');
    final offsets = <int, (int, int)>{};
    final nums = _entries.keys.toList()..sort();
    for (final num in nums) {
      if (num == encryptNum) continue;
      final PdfValue value;
      var gen = 0;
      try {
        switch (_entries[num]!) {
          case _AtOffset():
            final object = _object(num);
            if (object == null) continue;
            final v = object.value;
            if (v is PdfStream) {
              final type = v.dict.nameOf('Type');
              // Both are the old file's bookkeeping; the copy brings its own.
              if (type == 'XRef' || type == 'ObjStm') continue;
            }
            gen = object.gen;
            value = _decrypt(v, decryptor, num, gen);
          case _InStream(:final stream, :final index):
            final objects = _compressed(stream, decryptor);
            if (index >= objects.length || objects[index].$1 != num) continue;
            // Strings inside an object stream were encrypted with the stream.
            value = objects[index].$2;
        }
      } on PdfSyntaxException catch (e) {
        // One unreadable object is the renderer's problem, as it would have
        // been in the original; it should not cost the whole document.
        debugPrint('PDF unlock: skipping object $num: ${e.message}');
        continue;
      }
      offsets[num] = (out.length, gen);
      out
        ..ascii('$num $gen obj\n')
        ..value(value)
        ..ascii('\nendobj\n');
    }
    final size = (nums.isEmpty ? 0 : nums.last) + 1;
    final xref = out.length;
    final table = StringBuffer('xref\n0 $size\n');
    for (var n = 0; n < size; n++) {
      final at = offsets[n];
      table.write(
        at == null
            ? '0000000000 65535 f \n'
            : '${at.$1.toString().padLeft(10, '0')} '
                  '${at.$2.toString().padLeft(5, '0')} n \n',
      );
    }
    out
      ..ascii(table.toString())
      ..ascii('trailer\n')
      ..value(
        PdfDict({
          'Size': PdfNumber('$size'),
          for (final key in const ['Root', 'Info', 'ID'])
            if (trailer[key] != null) key: trailer[key]!,
        }),
      )
      ..ascii('\nstartxref\n$xref\n%%EOF\n');
    return out.takeBytes();
  }

  String _header() {
    final first = latin1.decode(
      Uint8List.sublistView(_bytes, 0, _bytes.length.clamp(0, 16)),
    );
    final match = RegExp(r'%PDF-\d\.\d').firstMatch(first);
    return match?.group(0) ?? '%PDF-1.7';
  }

  PdfValue _decrypt(PdfValue v, PdfDecryptor d, int num, int gen) =>
      switch (v) {
        PdfString(:final bytes) => PdfString(d.decryptString(bytes, num, gen)),
        PdfArray(:final items) => PdfArray([
          for (final item in items) _decrypt(item, d, num, gen),
        ]),
        PdfDict(:final entries) => PdfDict({
          for (final MapEntry(:key, :value) in entries.entries)
            key: _decrypt(value, d, num, gen),
        }),
        PdfStream(:final dict, :final data) => PdfStream(
          _decrypt(dict, d, num, gen) as PdfDict,
          _streamIsClear(dict, d) ? data : d.decryptStream(data, num, gen),
        ),
        _ => v,
      };

  /// Streams the security handler leaves alone: metadata when the document
  /// says so, and anything routed through its own crypt filter (in practice
  /// `/Identity`, the only one this reader would meet).
  static bool _streamIsClear(PdfDict dict, PdfDecryptor d) {
    if (!d.encryptsMetadata && dict.nameOf('Type') == 'Metadata') return true;
    return _filters(dict).contains('Crypt');
  }

  static List<String> _filters(PdfDict dict) => switch (dict['Filter']) {
    PdfName(:final name) => [name],
    PdfArray(:final items) => [
      for (final i in items)
        if (i is PdfName) i.name,
    ],
    _ => const [],
  };

  /// Undoes the filters of the two stream types this reader looks inside:
  /// cross-reference and object streams. Both are Flate in practice, often
  /// with a PNG predictor.
  Uint8List _decodeStream(PdfStream stream) {
    var data = stream.data;
    final filters = _filters(stream.dict);
    for (final f in filters) {
      if (f != 'FlateDecode' && f != 'Fl') {
        throw PdfSyntaxException('unsupported filter $f');
      }
      try {
        data = const ZLibDecoder().decodeBytes(
          data,
          maxOutputSize: _inflateBudget - _inflated,
        );
      } on ArchiveException catch (e) {
        throw PdfSyntaxException('cannot inflate stream: ${e.message}');
      }
      _inflated += data.length;
    }
    final parms = switch (stream.dict['DecodeParms']) {
      PdfDict d => d,
      PdfArray(:final items) when items.isNotEmpty && items.first is PdfDict =>
        items.first as PdfDict,
      _ => null,
    };
    final predictor = parms?.intOf('Predictor') ?? 1;
    if (predictor >= 10) {
      data = _unpredictPng(
        data,
        columns: parms?.intOf('Columns') ?? 1,
        colors: parms?.intOf('Colors') ?? 1,
        bits: parms?.intOf('BitsPerComponent') ?? 8,
      );
    } else if (predictor != 1) {
      throw PdfSyntaxException('unsupported predictor $predictor');
    }
    return data;
  }

  static Uint8List _unpredictPng(
    Uint8List data, {
    required int columns,
    required int colors,
    required int bits,
  }) {
    final bpp = ((colors * bits) / 8).ceil().clamp(1, 32);
    final rowLength = ((columns * colors * bits) / 8).ceil();
    if (rowLength <= 0) throw const PdfSyntaxException('bad predictor row');
    final rows = data.length ~/ (rowLength + 1);
    final out = Uint8List(rows * rowLength);
    for (var r = 0; r < rows; r++) {
      final type = data[r * (rowLength + 1)];
      final src = r * (rowLength + 1) + 1;
      final dst = r * rowLength;
      for (var i = 0; i < rowLength; i++) {
        final x = data[src + i];
        final left = i >= bpp ? out[dst + i - bpp] : 0;
        final up = r > 0 ? out[dst - rowLength + i] : 0;
        final upLeft = r > 0 && i >= bpp ? out[dst - rowLength + i - bpp] : 0;
        out[dst + i] =
            switch (type) {
              1 => x + left,
              2 => x + up,
              3 => x + ((left + up) >> 1),
              4 => x + _paeth(left, up, upLeft),
              _ => x,
            } &
            0xFF;
      }
    }
    return out;
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }
}
