import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_lz4/dart_lz4.dart';
import 'package:pointycastle/export.dart';

/// Wire format used by 115 upload v4: P-224 ECDH, AES-CBC, then LZ4.
/// Protocol reference: SheltonZhu/115driver pkg/crypto/ec115/cipher.go.
class Cloud115UploadCipher {
  Cloud115UploadCipher({BigInt? privateKey}) {
    final curve = ECDomainParameters('secp224r1');
    final random = Random.secure();
    final scalar = privateKey ??
        (BigInt.parse(
                    List.generate(28, (_) => random.nextInt(256))
                        .map((b) => b.toRadixString(16).padLeft(2, '0'))
                        .join(),
                    radix: 16) %
                (curve.n - BigInt.one)) +
            BigInt.one;
    if (scalar <= BigInt.zero || scalar >= curve.n) {
      throw ArgumentError('Invalid P-224 key');
    }
    final remote = curve.curve.decodePoint(
        _hex('0457a29257cd2320e5d6d143322fa4bb8a3cf9d3cc623ef5edac62b767'
            '8a89c91a83ba800d6129f522d034c895dd2465243addc250953beeba'))!;
    final public = (curve.G * scalar)!;
    _public = Uint8List.fromList([29, ...public.getEncoded(true)]);
    final secret = _hex((remote * scalar)!
        .x!
        .toBigInteger()!
        .toRadixString(16)
        .padLeft(56, '0'));
    _key = Uint8List.sublistView(secret, 0, 16);
    _iv = Uint8List.sublistView(secret, 12, 28);
  }

  late final Uint8List _public;
  late final Uint8List _key;
  late final Uint8List _iv;

  String token(int milliseconds) {
    final time = ByteData(4)
      ..setUint32(0, milliseconds & 0xffffffff, Endian.little);
    final bytes = <int>[
      ..._public.take(15),
      0,
      0x73,
      0,
      0,
      0,
      ...time.buffer.asUint8List(),
      ..._public.skip(15),
      0,
      1,
      0,
      0,
      0,
    ];
    final crc = ByteData(4)
      ..setUint32(
          0,
          getCrc32([...ascii.encode('^j>WD3Kr?J2gLFjD4W2y@'), ...bytes]),
          Endian.little);
    return base64Encode([...bytes, ...crc.buffer.asUint8List()]);
  }

  Uint8List encrypt(List<int> plain) {
    final padding = 16 - plain.length % 16;
    return _cbc(
        Uint8List.fromList([
          ...plain,
          ...List.filled(padding, padding),
        ]),
        true);
  }

  Uint8List decrypt(Uint8List encrypted) {
    if (encrypted.length < 16) throw const FormatException('Upload cipher');
    final raw = _cbc(
        Uint8List.sublistView(
            encrypted, 0, encrypted.length - encrypted.length % 16),
        false);
    final length = ByteData.sublistView(raw).getUint16(0, Endian.little);
    if (length == 0 || length + 2 > raw.length) {
      throw const FormatException('Upload block length');
    }
    final output = Uint8List(64 * 1024);
    final size =
        lz4DecompressInto(Uint8List.sublistView(raw, 2, 2 + length), output);
    return Uint8List.sublistView(output, 0, size);
  }

  Uint8List _cbc(Uint8List input, bool encrypting) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(encrypting, ParametersWithIV(KeyParameter(_key), _iv));
    final output = Uint8List(input.length);
    for (var offset = 0; offset < input.length; offset += 16) {
      cipher.processBlock(input, offset, output, offset);
    }
    return output;
  }

  static Uint8List _hex(String value) => Uint8List.fromList([
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ]);
}
