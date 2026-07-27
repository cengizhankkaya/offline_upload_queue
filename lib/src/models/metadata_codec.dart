/// Metadata için şifreleme/çözme sağlayan codec arayüzü.
///
/// Eğer veritabanını tamamen (SQLCipher ile) şifrelemek istemiyorsanız
/// ancak hassas PII verilerini içeren `metadata` alanını korumak
/// istiyorsanız bu sınıfı kullanarak `UploadQueue`'ya enjekte edebilirsiniz.
class MetadataCodec {
  /// Orijinal JSON verisini şifreleyerek string'e dönüştürür.
  final String Function(String plainJson) encode;

  /// Şifrelenmiş string'i çözerek orijinal JSON'a döndürür.
  final String Function(String cipherText) decode;

  const MetadataCodec({required this.encode, required this.decode});
}
