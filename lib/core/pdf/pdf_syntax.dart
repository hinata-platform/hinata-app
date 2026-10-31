import 'dart:convert';
import 'dart:typed_data';

/// The handful of PDF object types (ISO 32000-2, 7.3) the unlocker has to read
/// and write back. Numbers and names keep their source spelling, so a document
/// passes through unchanged everywhere except the strings and streams that are
/// actually decrypted.
sealed class PdfValue {
  const PdfValue();
}

final class PdfNull extends PdfValue {
  const PdfNull();
}

final class PdfBool extends PdfValue {
  const PdfBool(this.value);
  final bool value;
}

final class PdfNumber extends PdfValue {
  const PdfNumber(this.raw);

  /// The number as written in the file, e.g. `-4` or `.5`.
  final String raw;

  int? get asInt => int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
}

final class PdfName extends PdfValue {
  const PdfName(this.name);

  /// Decoded: `#20` is already a space here. One char per byte (latin1).
  final String name;
}

final class PdfString extends PdfValue {
  const PdfString(this.bytes);
  final Uint8List bytes;
}

final class PdfArray extends PdfValue {
  const PdfArray(this.items);
  final List<PdfValue> items;
}

final class PdfDict extends PdfValue {
  const PdfDict(this.entries);

  /// Keyed by the decoded name, without the slash.
  final Map<String, PdfValue> entries;

  PdfValue? operator [](String key) => entries[key];

  String? nameOf(String key) => switch (entries[key]) {
    PdfName(:final name) => name,
    _ => null,
  };

  int? intOf(String key) => switch (entries[key]) {
    PdfNumber n => n.asInt,
    _ => null,
  };
}

final class PdfRef extends PdfValue {
  const PdfRef(this.num, this.gen);
  final int num;
  final int gen;
}

final class PdfStream extends PdfValue {
  const PdfStream(this.dict, this.data);
  final PdfDict dict;

  /// The bytes between `stream` and `endstream`, still filtered (and still
  /// encrypted, until the unlocker has been at them).
  final Uint8List data;
}

/// Malformed input, or a feature this reader does not handle.
class PdfSyntaxException implements Exception {
  const PdfSyntaxException(this.message);
  final String message;

  @override
  String toString() => 'PdfSyntaxException: $message';
}

/// An indirect object as it sits in the file: `num gen obj … endobj`.
typedef PdfIndirect = ({int num, int gen, PdfValue value});

/// Reads PDF objects straight off the file's bytes.
///
/// Recursive descent over the token grammar, nothing more: no repair of broken
/// files, which is the renderer's job once the unlocker has handed a document
/// on. Nesting is capped so a hostile file cannot overflow the stack.
class PdfReader {
  PdfReader(this.bytes);

  final Uint8List bytes;
  int pos = 0;

  static const int _maxDepth = 128;

  bool get atEnd => pos >= bytes.length;

  static bool isWhite(int c) =>
      c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0;

  static bool isDelimiter(int c) =>
      c == 0x28 || // (
      c == 0x29 || // )
      c == 0x3C || // <
      c == 0x3E || // >
      c == 0x5B || // [
      c == 0x5D || // ]
      c == 0x7B || // {
      c == 0x7D || // }
      c == 0x2F || // /
      c == 0x25; // %

  void skipWhite() {
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < bytes.length && bytes[pos] != 0x0A && bytes[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// Whether [word] starts at [pos] as a whole token.
  bool lookingAt(String word) {
    final end = pos + word.length;
    if (end > bytes.length) return false;
    for (var i = 0; i < word.length; i++) {
      if (bytes[pos + i] != word.codeUnitAt(i)) return false;
    }
    return end == bytes.length ||
        isWhite(bytes[end]) ||
        isDelimiter(bytes[end]);
  }

  void expectKeyword(String word) {
    skipWhite();
    if (!lookingAt(word)) {
      throw PdfSyntaxException('expected "$word" at $pos');
    }
    pos += word.length;
  }

  int readInt() {
    skipWhite();
    final start = pos;
    while (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
      pos++;
    }
    if (pos == start) throw PdfSyntaxException('expected integer at $start');
    return int.parse(latin1.decode(bytes.sublist(start, pos)));
  }

  /// `num gen obj <value> [stream … endstream] endobj` at [offset].
  ///
  /// [streamLength] resolves a `/Length` the dictionary gives as a reference.
  PdfIndirect readIndirect(
    int offset, {
    int? Function(PdfValue)? streamLength,
  }) {
    if (offset < 0 || offset >= bytes.length) {
      throw PdfSyntaxException('object offset $offset out of range');
    }
    pos = offset;
    final num = readInt();
    final gen = readInt();
    expectKeyword('obj');
    var value = readValue();
    skipWhite();
    if (value is PdfDict && lookingAt('stream')) {
      pos += 'stream'.length;
      // The keyword is followed by CRLF or LF; a bare CR is not allowed but
      // turns up, and dropping it is what every reader does.
      if (pos < bytes.length && bytes[pos] == 0x0D) pos++;
      if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
      value = PdfStream(value, _streamData(value, streamLength));
    }
    return (num: num, gen: gen, value: value);
  }

  Uint8List _streamData(PdfDict dict, int? Function(PdfValue)? resolve) {
    final start = pos;
    final lengthValue = dict['Length'];
    final length = lengthValue == null
        ? null
        : lengthValue is PdfNumber
        ? lengthValue.asInt
        : resolve?.call(lengthValue);
    if (length != null && length >= 0 && start + length <= bytes.length) {
      pos = start + length;
      skipWhite();
      if (lookingAt('endstream')) {
        pos += 'endstream'.length;
        return Uint8List.sublistView(bytes, start, start + length);
      }
    }
    // A /Length that does not land on `endstream` is common enough in the wild
    // that trusting it would lose documents; the keyword is the fallback.
    final end = _indexOf('endstream', start);
    if (end < 0) throw PdfSyntaxException('unterminated stream at $start');
    var dataEnd = end;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0A) dataEnd--;
    if (dataEnd > start && bytes[dataEnd - 1] == 0x0D) dataEnd--;
    pos = end + 'endstream'.length;
    return Uint8List.sublistView(bytes, start, dataEnd);
  }

  int _indexOf(String word, int from) {
    final first = word.codeUnitAt(0);
    outer:
    for (var i = from; i <= bytes.length - word.length; i++) {
      if (bytes[i] != first) continue;
      for (var j = 1; j < word.length; j++) {
        if (bytes[i + j] != word.codeUnitAt(j)) continue outer;
      }
      return i;
    }
    return -1;
  }

  PdfValue readValue([int depth = 0]) {
    if (depth > _maxDepth) throw const PdfSyntaxException('nesting too deep');
    skipWhite();
    if (atEnd) throw const PdfSyntaxException('unexpected end of file');
    final c = bytes[pos];
    switch (c) {
      case 0x2F: // /
        return _readName();
      case 0x28: // (
        return _readLiteralString();
      case 0x3C: // <
        if (pos + 1 < bytes.length && bytes[pos + 1] == 0x3C) {
          return _readDict(depth);
        }
        return _readHexString();
      case 0x5B: // [
        return _readArray(depth);
    }
    if (_isNumberStart(c)) return _readNumberOrRef();
    if (lookingAt('true')) {
      pos += 4;
      return const PdfBool(true);
    }
    if (lookingAt('false')) {
      pos += 5;
      return const PdfBool(false);
    }
    if (lookingAt('null')) {
      pos += 4;
      return const PdfNull();
    }
    throw PdfSyntaxException(
      'unexpected byte 0x${c.toRadixString(16)} at $pos',
    );
  }

  static bool _isNumberStart(int c) =>
      (c >= 0x30 && c <= 0x39) || c == 0x2B || c == 0x2D || c == 0x2E;

  PdfValue _readNumberOrRef() {
    final start = pos;
    pos++;
    while (pos < bytes.length) {
      final c = bytes[pos];
      if ((c >= 0x30 && c <= 0x39) || c == 0x2E) {
        pos++;
      } else {
        break;
      }
    }
    final raw = latin1.decode(bytes.sublist(start, pos));
    final first = int.tryParse(raw);
    if (first == null || first < 0 || raw.startsWith('+')) {
      return PdfNumber(raw);
    }
    // `12 0 R` — two non-negative integers and an R make a reference; anything
    // else means the first number stands on its own.
    final save = pos;
    skipWhite();
    final genStart = pos;
    while (pos < bytes.length && bytes[pos] >= 0x30 && bytes[pos] <= 0x39) {
      pos++;
    }
    if (pos > genStart) {
      final gen = int.parse(latin1.decode(bytes.sublist(genStart, pos)));
      skipWhite();
      if (lookingAt('R')) {
        pos++;
        return PdfRef(first, gen);
      }
    }
    pos = save;
    return PdfNumber(raw);
  }

  PdfName _readName() {
    pos++; // /
    final out = StringBuffer();
    while (pos < bytes.length) {
      final c = bytes[pos];
      if (isWhite(c) || isDelimiter(c)) break;
      if (c == 0x23 && pos + 2 < bytes.length) {
        final hex = int.tryParse(
          latin1.decode(bytes.sublist(pos + 1, pos + 3)),
          radix: 16,
        );
        if (hex != null) {
          out.writeCharCode(hex);
          pos += 3;
          continue;
        }
      }
      out.writeCharCode(c);
      pos++;
    }
    return PdfName(out.toString());
  }

  PdfString _readLiteralString() {
    pos++; // (
    final out = BytesBuilder(copy: false);
    var depth = 1;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      switch (c) {
        case 0x28:
          depth++;
          out.addByte(c);
        case 0x29:
          if (--depth == 0) return PdfString(out.takeBytes());
          out.addByte(c);
        case 0x0D:
          // An unescaped end of line is a single LF, whatever the file used.
          if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
          out.addByte(0x0A);
        case 0x5C:
          _readEscape(out);
        default:
          out.addByte(c);
      }
    }
    throw const PdfSyntaxException('unterminated string');
  }

  void _readEscape(BytesBuilder out) {
    if (pos >= bytes.length) return;
    final e = bytes[pos++];
    switch (e) {
      case 0x6E: // n
        out.addByte(0x0A);
      case 0x72: // r
        out.addByte(0x0D);
      case 0x74: // t
        out.addByte(0x09);
      case 0x62: // b
        out.addByte(0x08);
      case 0x66: // f
        out.addByte(0x0C);
      case 0x0D: // line continuation
        if (pos < bytes.length && bytes[pos] == 0x0A) pos++;
      case 0x0A:
        break;
      default:
        if (e >= 0x30 && e <= 0x37) {
          var value = e - 0x30;
          for (var i = 0; i < 2 && pos < bytes.length; i++) {
            final d = bytes[pos];
            if (d < 0x30 || d > 0x37) break;
            value = value * 8 + d - 0x30;
            pos++;
          }
          out.addByte(value & 0xFF);
        } else {
          // `\(`, `\)`, `\\` — and, per the spec, any other escaped byte is
          // the byte itself.
          out.addByte(e);
        }
    }
  }

  PdfString _readHexString() {
    pos++; // <
    final out = BytesBuilder(copy: false);
    int? high;
    while (pos < bytes.length) {
      final c = bytes[pos++];
      if (c == 0x3E) {
        if (high != null) out.addByte(high << 4);
        return PdfString(out.takeBytes());
      }
      final v = _hexValue(c);
      if (v < 0) continue;
      if (high == null) {
        high = v;
      } else {
        out.addByte((high << 4) | v);
        high = null;
      }
    }
    throw const PdfSyntaxException('unterminated hex string');
  }

  static int _hexValue(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x37;
    if (c >= 0x61 && c <= 0x66) return c - 0x57;
    return -1;
  }

  PdfArray _readArray(int depth) {
    pos++; // [
    final items = <PdfValue>[];
    while (true) {
      skipWhite();
      if (atEnd) throw const PdfSyntaxException('unterminated array');
      if (bytes[pos] == 0x5D) {
        pos++;
        return PdfArray(items);
      }
      items.add(readValue(depth + 1));
    }
  }

  PdfDict _readDict(int depth) {
    pos += 2; // <<
    final entries = <String, PdfValue>{};
    while (true) {
      skipWhite();
      if (atEnd) throw const PdfSyntaxException('unterminated dictionary');
      if (bytes[pos] == 0x3E &&
          pos + 1 < bytes.length &&
          bytes[pos + 1] == 0x3E) {
        pos += 2;
        return PdfDict(entries);
      }
      final key = readValue(depth + 1);
      if (key is! PdfName) {
        throw PdfSyntaxException('dictionary key is not a name at $pos');
      }
      entries[key.name] = readValue(depth + 1);
    }
  }
}

/// Serializes [PdfValue]s back into file syntax.
///
/// Strings always come out as hex: it is the one spelling that needs no
/// escaping, whatever bytes decryption produced.
class PdfWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  int get length => _out.length;

  void ascii(String s) => _out.add(latin1.encode(s));

  void raw(Uint8List bytes) => _out.add(bytes);

  Uint8List takeBytes() => _out.takeBytes();

  void value(PdfValue v) {
    switch (v) {
      case PdfNull():
        ascii('null');
      case PdfBool(:final value):
        ascii(value ? 'true' : 'false');
      case PdfNumber(:final raw):
        ascii(raw);
      case PdfName(:final name):
        _name(name);
      case PdfString(:final bytes):
        _hex(bytes);
      case PdfArray(:final items):
        ascii('[');
        for (final item in items) {
          ascii(' ');
          value(item);
        }
        ascii(' ]');
      case PdfDict():
        _dict(v);
      case PdfRef(:final num, :final gen):
        ascii('$num $gen R');
      case PdfStream(:final dict, :final data):
        _dict(
          PdfDict({...dict.entries, 'Length': PdfNumber('${data.length}')}),
        );
        ascii('\nstream\n');
        raw(data);
        ascii('\nendstream');
    }
  }

  void _dict(PdfDict d) {
    ascii('<<');
    for (final MapEntry(:key, :value) in d.entries.entries) {
      ascii(' ');
      _name(key);
      ascii(' ');
      this.value(value);
    }
    ascii(' >>');
  }

  void _name(String name) {
    final b = StringBuffer('/');
    for (final c in name.codeUnits) {
      if (c < 0x21 || c > 0x7E || c == 0x23 || PdfReader.isDelimiter(c)) {
        b.write('#${c.toRadixString(16).padLeft(2, '0')}');
      } else {
        b.writeCharCode(c);
      }
    }
    ascii(b.toString());
  }

  static const _hexDigits = '0123456789abcdef';

  void _hex(Uint8List bytes) {
    final b = StringBuffer('<');
    for (final byte in bytes) {
      b
        ..write(_hexDigits[byte >> 4])
        ..write(_hexDigits[byte & 0x0F]);
    }
    b.write('>');
    ascii(b.toString());
  }
}
