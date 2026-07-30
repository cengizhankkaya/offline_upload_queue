/// Metadata için şifreleme/çözme sağlayan codec arayüzü.
///
/// Veritabanının tamamını (`encryptionKey` / Sembast codec) şifrelemek
/// istemiyorsanız, ancak hassas PII içeren `metadata` alanını korumak
/// istiyorsanız bu sınıfı `UploadQueue`'ya enjekte edin.
class MetadataCodec {
  /// Orijinal JSON verisini şifreleyerek string'e dönüştürür.
  final String Function(String plainJson) encode;

  /// Şifrelenmiş string'i çözerek orijinal JSON'a döndürür.
  final String Function(String cipherText) decode;

  const MetadataCodec({required this.encode, required this.decode});
}
