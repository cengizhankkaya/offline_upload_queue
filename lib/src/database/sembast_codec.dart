import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:sembast/sembast.dart';

/// Bu codec sembast kaynak deposundaki örnek koda (Salsa20+SHA256) dayanır.
/// Bağımsız güvenlik denetiminden geçmemiştir; ayrıca kimlik doğrulama
/// (MAC/AEAD) yoktur — veri kurcalanması saptanmaz. HIPAA/GDPR gibi
/// senaryolar için bağımsız denetlenmiş bir şifreleme çözümü tercih edin.
class _EncryptEncoder extends Converter<Object?, String> {
  final Salsa20 salsa20;
  _EncryptEncoder(this.salsa20);

  @override
  String convert(Object? input) {
    final encrypter = Encrypter(salsa20);
    // Rastgele 8-byte IV (Salsa20 için standart)
    final iv = IV.fromSecureRandom(8);
    // JSON'a çevir, şifrele, Base64 yap
    final jsonStr = json.encode(input);
    final encrypted = encrypter.encrypt(jsonStr, iv: iv);
    // IV ile birlikte Base64 olarak sakla
    return '${iv.base64}:${encrypted.base64}';
  }
}

class _EncryptDecoder extends Converter<String, Object?> {
  final Salsa20 salsa20;
  _EncryptDecoder(this.salsa20);

  @override
  Object? convert(String input) {
    final encrypter = Encrypter(salsa20);
    final parts = input.split(':');
    if (parts.length != 2) {
      throw FormatException('Geçersiz şifrelenmiş veri formatı');
    }
    final iv = IV.fromBase64(parts[0]);
    final encrypted = Encrypted.fromBase64(parts[1]);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return json.decode(decrypted);
  }
}

class _EncryptCodec extends Codec<Object?, String> {
  final _EncryptEncoder _encoder;
  final _EncryptDecoder _decoder;

  _EncryptCodec(String password)
    : _encoder = _EncryptEncoder(_getSalsa20(password)),
      _decoder = _EncryptDecoder(_getSalsa20(password));

  @override
  Converter<String, Object?> get decoder => _decoder;

  @override
  Converter<Object?, String> get encoder => _encoder;

  static Salsa20 _getSalsa20(String password) {
    // Şifreden 32-byte anahtar üretmek için SHA-256 kullan
    final keyBytes = sha256.convert(utf8.encode(password)).bytes;
    return Salsa20(Key(Uint8List.fromList(keyBytes)));
  }
}

/// Sembast veritabanını Salsa20 ile şifreleyen bir [SembastCodec] döndürür.
///
/// **UYARI:** Bu codec bağımsız güvenlik denetiminden geçmemiştir.
SembastCodec getEncryptSembastCodec({required String password}) {
  return SembastCodec(signature: 'salsa20', codec: _EncryptCodec(password));
}
