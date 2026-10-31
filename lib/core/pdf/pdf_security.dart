import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

import 'pdf_syntax.dart';

/// How one class of data (strings or streams) is encrypted.
enum _Cipher { identity, rc4, aes128, aes256 }

/// The PDF standard security handler (ISO 32000-2, 7.6.4): checks a password
/// and decrypts strings and streams with the key it yields.
///
/// Covers every revision a reader still meets — R2 and R3 (RC4, 40 to 128
/// bit), R4 (RC4 or AES-128 through crypt filters) and R5/R6 (AES-256).
/// Public-key security handlers are not supported; [PdfSecurityHandler.parse]
/// rejects them, and the viewer then hands the file to the renderer unchanged.
class PdfSecurityHandler {
  PdfSecurityHandler._({
    required int revision,
    required int keyLength,
    required Uint8List owner,
    required Uint8List user,
    required int permissions,
    required Uint8List firstId,
    required bool encryptMetadata,
    required _Cipher strings,
    required _Cipher streams,
    Uint8List? ownerKey,
    Uint8List? userKey,
  }) : _revision = revision,
       _keyLength = keyLength,
       _o = owner,
       _u = user,
       _p = permissions,
       _id = firstId,
       _encryptMetadata = encryptMetadata,
       _strings = strings,
       _streams = streams,
       _oe = ownerKey,
       _ue = userKey;

  final int _revision;
  final int _keyLength;
  final Uint8List _o;
  final Uint8List _u;
  final int _p;
  final Uint8List _id;
  final bool _encryptMetadata;
  final _Cipher _strings;
  final _Cipher _streams;
  final Uint8List? _oe;
  final Uint8List? _ue;

  /// Reads the `/Encrypt` dictionary. [firstId] is the first element of the
  /// trailer's `/ID`, which the older revisions mix into the key.
  static PdfSecurityHandler parse(PdfDict encrypt, Uint8List firstId) {
    if (encrypt.nameOf('Filter') != 'Standard') {
      throw const PdfSyntaxException('unsupported security handler');
    }
    final v = encrypt.intOf('V') ?? 0;
    final r = encrypt.intOf('R') ?? 0;
    if (r < 2 || r > 6) {
      throw PdfSyntaxException('unsupported security revision $r');
    }
    var keyLength = v == 1 ? 5 : (encrypt.intOf('Length') ?? 40) ~/ 8;
    var strings = _Cipher.rc4;
    var streams = _Cipher.rc4;
    if (v >= 4) {
      final filters = encrypt['CF'] is PdfDict
          ? encrypt['CF']! as PdfDict
          : null;
      _Cipher filter(String key) {
        final name = encrypt.nameOf(key) ?? 'Identity';
        if (name == 'Identity') return _Cipher.identity;
        final f = filters?[name];
        if (f is! PdfDict) {
          throw PdfSyntaxException('missing crypt filter $name');
        }
        final length = f.intOf('Length');
        if (length != null && v == 4) {
          // Bytes per the spec, bits in plenty of files.
          keyLength = length <= 32 ? length : length ~/ 8;
        }
        return switch (f.nameOf('CFM')) {
          'V2' => _Cipher.rc4,
          'AESV2' => _Cipher.aes128,
          'AESV3' => _Cipher.aes256,
          'None' || null => _Cipher.identity,
          final other => throw PdfSyntaxException('unsupported CFM $other'),
        };
      }

      strings = filter('StrF');
      streams = filter('StmF');
    }
    if (r >= 5) keyLength = 32;
    if (keyLength < 5 || keyLength > 32) {
      throw PdfSyntaxException('bad key length $keyLength');
    }
    Uint8List bytesOf(String key) => switch (encrypt[key]) {
      PdfString(:final bytes) => bytes,
      _ => Uint8List(0),
    };
    final o = bytesOf('O');
    final u = bytesOf('U');
    final minLength = r >= 5 ? 48 : 32;
    if (o.length < minLength || u.length < minLength) {
      throw const PdfSyntaxException('truncated /O or /U');
    }
    return PdfSecurityHandler._(
      revision: r,
      keyLength: keyLength,
      owner: o,
      user: u,
      permissions: encrypt.intOf('P') ?? 0,
      firstId: firstId,
      encryptMetadata: switch (encrypt['EncryptMetadata']) {
        PdfBool(:final value) => value,
        _ => true,
      },
      strings: strings,
      streams: streams,
      ownerKey: r >= 5 ? bytesOf('OE') : null,
      userKey: r >= 5 ? bytesOf('UE') : null,
    );
  }

  /// Tries [password] as the user password, then as the owner password. A
  /// decryptor holding the file key when either opens the document, null when
  /// neither does.
  PdfDecryptor? authenticate(String password) {
    final key = _revision >= 5
        ? _authenticateAes256(password)
        : _authenticateLegacy(password);
    return key == null ? null : PdfDecryptor._(this, key);
  }

  // ── R2–R4 ─────────────────────────────────────────────────────────────────

  static const List<int> _padding = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ];

  /// The legacy revisions take the password in PDFDocEncoding, which matches
  /// Latin-1 for everything a keyboard is likely to type into it.
  static Uint8List _legacyPasswordBytes(String password) {
    final units = password.codeUnits;
    if (units.every((c) => c < 0x100)) return Uint8List.fromList(units);
    return Uint8List.fromList(utf8.encode(password));
  }

  static Uint8List _pad(Uint8List password) {
    final out = Uint8List(32);
    final n = password.length.clamp(0, 32);
    out.setRange(0, n, password);
    out.setRange(n, 32, _padding);
    return out;
  }

  Uint8List? _authenticateLegacy(String password) {
    final padded = _pad(_legacyPasswordBytes(password));
    final asUser = _fileKey(padded);
    if (_isUserKey(asUser)) return asUser;
    // Algorithm 7: the owner password decrypts /O back to the user password.
    var hash = _md5(padded);
    if (_revision >= 3) {
      for (var i = 0; i < 50; i++) {
        hash = _md5(hash);
      }
    }
    final ownerKey = Uint8List.sublistView(hash, 0, _keyLength);
    var user = Uint8List.fromList(_o.sublist(0, 32));
    if (_revision == 2) {
      user = _rc4(ownerKey, user);
    } else {
      for (var i = 19; i >= 0; i--) {
        user = _rc4(_xorKey(ownerKey, i), user);
      }
    }
    final asOwner = _fileKey(user);
    return _isUserKey(asOwner) ? asOwner : null;
  }

  /// Algorithm 2.
  Uint8List _fileKey(Uint8List paddedPassword) {
    final input = BytesBuilder(copy: false)
      ..add(paddedPassword)
      ..add(_o.sublist(0, 32))
      ..add([_p & 0xFF, (_p >> 8) & 0xFF, (_p >> 16) & 0xFF, (_p >> 24) & 0xFF])
      ..add(_id);
    if (_revision >= 4 && !_encryptMetadata) {
      input.add(const [0xFF, 0xFF, 0xFF, 0xFF]);
    }
    var hash = _md5(input.takeBytes());
    if (_revision >= 3) {
      for (var i = 0; i < 50; i++) {
        hash = _md5(Uint8List.sublistView(hash, 0, _keyLength));
      }
    }
    return Uint8List.fromList(hash.sublist(0, _keyLength));
  }

  /// Algorithms 4 and 5: does [key] reproduce /U?
  bool _isUserKey(Uint8List key) {
    if (_revision == 2) {
      return _equal(_rc4(key, Uint8List.fromList(_padding)), _u, 32);
    }
    var x = _md5(Uint8List.fromList([..._padding, ..._id]));
    for (var i = 0; i < 20; i++) {
      x = _rc4(_xorKey(key, i), x);
    }
    return _equal(x, _u, 16);
  }

  static Uint8List _xorKey(Uint8List key, int i) =>
      Uint8List.fromList([for (final b in key) b ^ i]);

  // ── R5/R6 ─────────────────────────────────────────────────────────────────

  Uint8List? _authenticateAes256(String password) {
    var pw = Uint8List.fromList(utf8.encode(password));
    if (pw.length > 127) pw = Uint8List.sublistView(pw, 0, 127);
    final u48 = Uint8List.sublistView(_u, 0, 48);
    // Owner first is what the spec's Algorithm 2.A does; the order only matters
    // for a password that happens to be both.
    final ownerHash = _hash(pw, Uint8List.sublistView(_o, 32, 40), u48);
    if (_equal(ownerHash, _o, 32) && _oe != null && _oe.length >= 32) {
      final k = _hash(pw, Uint8List.sublistView(_o, 40, 48), u48);
      return _aesCbcRaw(
        k,
        Uint8List(16),
        Uint8List.sublistView(_oe, 0, 32),
        encrypt: false,
      );
    }
    final userHash = _hash(pw, Uint8List.sublistView(_u, 32, 40), Uint8List(0));
    if (_equal(userHash, _u, 32) && _ue != null && _ue.length >= 32) {
      final k = _hash(pw, Uint8List.sublistView(_u, 40, 48), Uint8List(0));
      return _aesCbcRaw(
        k,
        Uint8List(16),
        Uint8List.sublistView(_ue, 0, 32),
        encrypt: false,
      );
    }
    return null;
  }

  /// SHA-256 for R5, Algorithm 2.B for R6.
  Uint8List _hash(Uint8List password, Uint8List salt, Uint8List userData) {
    var k = _sha(256, Uint8List.fromList([...password, ...salt, ...userData]));
    if (_revision == 5) return k;
    var round = 0;
    while (true) {
      final block = Uint8List.fromList([...password, ...k, ...userData]);
      final k1 = Uint8List(block.length * 64);
      for (var i = 0; i < 64; i++) {
        k1.setRange(i * block.length, (i + 1) * block.length, block);
      }
      final e = _aesCbcRaw(
        Uint8List.sublistView(k, 0, 16),
        Uint8List.sublistView(k, 16, 32),
        k1,
        encrypt: true,
      );
      var sum = 0;
      for (var i = 0; i < 16; i++) {
        sum += e[i];
      }
      k = _sha(const [256, 384, 512][sum % 3], e);
      round++;
      if (round >= 64 && e.last <= round - 32) break;
    }
    return Uint8List.fromList(k.sublist(0, 32));
  }

  // ── Primitives ────────────────────────────────────────────────────────────

  static Uint8List _md5(List<int> data) =>
      Uint8List.fromList(crypto.md5.convert(data).bytes);

  static Uint8List _sha(int bits, List<int> data) => Uint8List.fromList(
    switch (bits) {
      256 => crypto.sha256,
      384 => crypto.sha384,
      _ => crypto.sha512,
    }.convert(data).bytes,
  );

  static bool _equal(Uint8List a, Uint8List b, int n) {
    if (a.length < n || b.length < n) return false;
    var diff = 0;
    for (var i = 0; i < n; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Uint8List _rc4(Uint8List key, Uint8List data) {
    final s = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      s[i] = i;
    }
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 0xFF;
      final t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final out = Uint8List(data.length);
    var a = 0;
    var b = 0;
    for (var n = 0; n < data.length; n++) {
      a = (a + 1) & 0xFF;
      b = (b + s[a]) & 0xFF;
      final t = s[a];
      s[a] = s[b];
      s[b] = t;
      out[n] = data[n] ^ s[(s[a] + s[b]) & 0xFF];
    }
    return out;
  }

  /// AES-CBC as PDF stores it: a 16-byte IV in front, PKCS#5 padding at the
  /// end. Lenient about both, because a renderer would be too: a ragged tail is
  /// cut to whole blocks and padding that does not check out is left on.
  static Uint8List _aesCbcDecrypt(Uint8List key, Uint8List data) {
    if (data.length < 32) return Uint8List(0);
    final body = data.length - 16 - (data.length - 16) % 16;
    final plain = _aesCbcRaw(
      key,
      Uint8List.sublistView(data, 0, 16),
      Uint8List.sublistView(data, 16, 16 + body),
      encrypt: false,
    );
    final pad = plain.last;
    if (pad >= 1 && pad <= 16 && pad <= plain.length) {
      var valid = true;
      for (var i = plain.length - pad; i < plain.length; i++) {
        if (plain[i] != pad) valid = false;
      }
      if (valid) return Uint8List.sublistView(plain, 0, plain.length - pad);
    }
    return plain;
  }

  /// Unpadded AES-CBC over whole blocks.
  static Uint8List _aesCbcRaw(
    Uint8List key,
    Uint8List iv,
    Uint8List data, {
    required bool encrypt,
  }) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(data.length);
    for (var off = 0; off + 16 <= data.length; off += 16) {
      cipher.processBlock(data, off, out, off);
    }
    return out;
  }
}

/// Decrypts the strings and streams of one document with its file key, which
/// only [PdfSecurityHandler.authenticate] hands out.
class PdfDecryptor {
  PdfDecryptor._(this._handler, this._key);

  final PdfSecurityHandler _handler;
  final Uint8List _key;

  /// Whether streams of `/Type /Metadata` are encrypted too.
  bool get encryptsMetadata => _handler._encryptMetadata;

  Uint8List decryptString(Uint8List data, int num, int gen) =>
      _decrypt(_handler._strings, data, num, gen);

  Uint8List decryptStream(Uint8List data, int num, int gen) =>
      _decrypt(_handler._streams, data, num, gen);

  /// Algorithm 1 derives a key per object, and every string and stream of
  /// that object shares it; the document is written object by object, so the
  /// last one derived is the one asked for next.
  (int, int, bool, Uint8List)? _objectKey;

  Uint8List _decrypt(_Cipher cipher, Uint8List data, int num, int gen) {
    switch (cipher) {
      case _Cipher.identity:
        return data;
      case _Cipher.aes256:
        return PdfSecurityHandler._aesCbcDecrypt(_key, data);
      case _Cipher.rc4:
      case _Cipher.aes128:
        final aes = cipher == _Cipher.aes128;
        final key = _keyFor(num, gen, aes);
        return aes
            ? PdfSecurityHandler._aesCbcDecrypt(key, data)
            : PdfSecurityHandler._rc4(key, data);
    }
  }

  Uint8List _keyFor(int num, int gen, bool aes) {
    final cached = _objectKey;
    if (cached != null &&
        cached.$1 == num &&
        cached.$2 == gen &&
        cached.$3 == aes) {
      return cached.$4;
    }
    final material = BytesBuilder(copy: false)
      ..add(_key)
      ..add([num & 0xFF, (num >> 8) & 0xFF, (num >> 16) & 0xFF])
      ..add([gen & 0xFF, (gen >> 8) & 0xFF]);
    if (aes) material.add(const [0x73, 0x41, 0x6C, 0x54]); // sAlT
    final digest = PdfSecurityHandler._md5(material.takeBytes());
    final key = Uint8List.sublistView(
      digest,
      0,
      (_key.length + 5).clamp(0, 16),
    );
    _objectKey = (num, gen, aes, key);
    return key;
  }
}
