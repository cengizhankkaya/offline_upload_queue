# offline_upload_queue — Fonksiyonel Manuel Test Senaryoları

> Bu doküman, `offline_upload_queue` paketinin **özellik bazlı** (feature-level) davranışlarını
> gerçek cihaz/emülatörde manuel olarak doğrulamak içindir. Repo kökündeki `MANUAL_TESTING.md`
> yalnızca OS-seviyesi (BGTaskScheduler, Workmanager, Sembast handoff) senaryoları kapsıyor;
> bu doküman ise kütüphanenin public API'sini uçtan uca test eder.
>
> Test ortamı önerisi: `example/` uygulamasını kullanın, sunucu tarafı için
> [httpbin.org](https://httpbin.org) veya kendi mock REST endpoint'inizi (ör. basit bir
> Node/Express sunucusu) kullanabilirsiniz — böylece 4xx/5xx/timeout gibi durumları
> kontrollü şekilde tetikleyebilirsiniz.

## Nasıl kullanılır

Her senaryo şu yapıda:
- **Ön koşul** — teste başlamadan önce hazır olması gerekenler
- **Adımlar** — sırayla uygulanacak eylemler
- **Beklenen sonuç** — gözlemlenmesi gereken davranış
- **Kayıt şablonu** — test sonucunu yazacağınız kutu

Test sırasında `queue.watchSummary()` ve `queue.watchTasks()` çıktısını ekrana yazdıran
basit bir debug panel (örnekte muhtemelen zaten var) veya `onLog` callback'ini konsola
basan bir kurulum kullanmanız önerilir — çoğu senaryonun "beklenen sonuç" kısmı bu loglara
dayanıyor.

---

## Bölüm A — Temel Kuyruk Akışı

### A1. Tek dosya enqueue → upload → completed

**Ön koşul:** Sunucu erişilebilir, cihaz online.

**Adımlar:**
1. `queue.init()` çağır.
2. `queue.enqueue(filePath: <geçerli bir resim>, metadata: {'test': 'A1'})` çağır, dönen `taskId`'yi not al.
3. `queue.watchTasks()` stream'ini dinle.

**Beklenen sonuç:**
- Görev sırasıyla `pending → uploading → completed` durumlarından geçmeli.
- `completed` sonrası sandbox kopyası otomatik silinmeli (dosya sistemi kontrolü: `ApplicationSupportDirectory/<boxName>/sandbox/` altında dosya kalmamalı).
- `watchSummary()` içinde `completed` sayacı 1 artmalı.

**Kayıt şablonu:**
```
SONUÇ:
Tarih:
Cihaz:
taskId:
Geçen durumlar (sırayla):
Sandbox temizlendi mi (E/H):
```

---

### A2. Çoklu dosya — sıralı (sequential) işleme doğrulaması

**Ön koşul:** 5 farklı boyutta dosya hazırla (ör. 100KB, 1MB, 5MB, 10MB, 20MB).

**Adımlar:**
1. 5 dosyayı art arda `enqueue()` ile ekle (aralarında bekleme koyma).
2. `watchTasks(statuses: {UploadStatus.uploading})` ile aynı anda kaç görevin `uploading` durumunda olduğunu izle.

**Beklenen sonuç:**
- **Aynı anda yalnızca 1 görev** `uploading` durumunda olmalı (paket "sequential" olarak pazarlanıyor — paralel değil).
- Görevler `enqueue()` sırasına göre (sequenceNumber sırasına göre) işlenmeli.

**Kayıt şablonu:**
```
SONUÇ:
Aynı anda uploading olan görev sayısı (beklenen: 1):
İşlenme sırası enqueue sırasıyla eşleşti mi (E/H):
```

---

### A3. Uygulama kapat/aç (cold start) sonrası kuyruk kalıcılığı

**Ön koşul:** A1 senaryosu tamamlanmadan (dosya `pending` veya `uploading` iken) uygulamayı zorla kapat.

**Adımlar:**
1. 3 dosya enqueue et, hemen ardından (upload tamamlanmadan) uygulamayı **force-kill** et (task switcher'dan kapat, sadece arka plana alma).
2. Uygulamayı yeniden aç, `queue.init()` çağrılsın.

**Beklenen sonuç:**
- Kapatılmadan önce `uploading` durumunda olan görev, yeniden açılışta **`pending`**'e dönmüş olmalı (crash recovery — README'de belirtilen `uploading → pending` davranışı).
- Hiçbir görev kaybolmamalı; hepsi worker tarafından tekrar işlenmeli.

**Kayıt şablonu:**
```
SONUÇ:
Kapatma anındaki durumlar:
Yeniden açılıştaki durumlar:
Görev kaybı oldu mu (E/H):
```

---

## Bölüm B — Retry, Backoff ve Hata Sınıflandırması

### B1. Geçici ağ hatası → otomatik retry

**Ön koşul:** Mock sunucu, belirli bir endpoint için ilk 2 istekte `500` dönüp 3. istekte `200` dönecek şekilde ayarlanmış olsun. Ya da cihazda uçak modunu kısa süreliğine aç/kapa yaparak network hatası simüle et.

**Adımlar:**
1. Dosyayı enqueue et.
2. İlk upload denemesinde ağı kes (uçak modu) → görev `failed` olmalı.
3. `onLog` / `watchTasks` ile `nextRetryAt` zaman damgasını gözlemle.
4. Backoff süresi dolana kadar bekle, ağı geri aç.

**Beklenen sonuç:**
- Görev `failed` durumuna geçmeli, `retryCount` artmalı.
- Backoff süresi **exponential** olarak artmalı (varsayılan: 2sn taban, 10dk tavan) — art arda başarısızlıklarda bekleme süresi 2sn, ~4sn, ~8sn... şeklinde büyümeli (jitter nedeniyle tam değil, yaklaşık).
- Backoff süresi dolduğunda worker otomatik tekrar denemeli, ağ varsa `completed` olmalı.

**Kayıt şablonu:**
```
SONUÇ:
Deneme 1 → nextRetryAt (yaklaşık gecikme):
Deneme 2 → nextRetryAt (yaklaşık gecikme):
Deneme 3 → nextRetryAt (yaklaşık gecikme):
Exponential artış gözlemlendi mi (E/H):
```

---

### B2. maxAttempts aşımı → permanentlyFailed

**Ön koşul:** `UploadQueue(maxAttempts: 3, ...)` ile küçük bir maxAttempts ayarla. Sunucu her zaman `500` dönsün (kalıcı hata değil, geçici — ama sürekli tekrar edecek).

**Adımlar:**
1. Dosyayı enqueue et, sunucunun her istekte `500` döndüğünden emin ol.
2. 3 deneme tamamlanana kadar bekle (backoff süreleri toplamı kadar).

**Beklenen sonuç:**
- 3. başarısız denemeden sonra görev **`permanentlyFailed`**'e geçmeli, artık otomatik retry denenmemeli.
- `watchSummary().permanentlyFailed` sayacı 1 artmalı.

**Kayıt şablonu:**
```
SONUÇ:
Toplam deneme sayısı:
Son durum:
Otomatik retry durdu mu (E/H):
```

---

### B3. FailureType sınıflandırması — kalıcı hatalar (permanent)

Bu senaryoyu her `FailureType` için ayrı ayrı çalıştır. Kalıcı olanlar **ilk denemede** doğrudan `permanentlyFailed`'e geçmeli, backoff/retry olmamalı.

| Test | Nasıl tetiklenir | Beklenen FailureType | Beklenen davranış |
|---|---|---|---|
| B3.1 | Enqueue sonrası, upload başlamadan dosyayı fiziksel olarak sil (`copyToSandbox: false` iken) | `fileNotFound` | Doğrudan `permanentlyFailed`, retry yok |
| B3.2 | Bozuk/okunamaz bir dosya enqueue et (ör. yarım kalmış binary) | `corruptFile` | 3 denemeden sonra `permanentlyFailed` (README: "3 attempts sonrası") |
| B3.3 | Sunucu `413 Payload Too Large` dönsün | `payloadTooLarge` | Doğrudan `permanentlyFailed` |
| B3.4 | Sunucu `400`/`422` gibi diğer 4xx dönsün | `badRequest` | Doğrudan `permanentlyFailed` |

**Kayıt şablonu (her satır için tekrarla):**
```
Test: B3.x
SONUÇ:
Gözlemlenen FailureType:
permanentlyFailed'e geçiş (E/H):
Retry denemesi oldu mu (Hayır olmalı):
```

---

### B4. FailureType sınıflandırması — geçici hatalar (temporary)

| Test | Nasıl tetiklenir | Beklenen FailureType | Beklenen davranış |
|---|---|---|---|
| B4.1 | Ağ bağlantısını kes | `network` | `failed`, backoff ile retry |
| B4.2 | Sunucu `503` dönsün | `serverError` | `failed`, backoff ile retry |
| B4.3 | Sunucu `429` + `Retry-After: 10` header'ı dönsün | `rateLimited` | Retry **tam olarak `Retry-After` süresine** saygı göstermeli (backoff'u değil header değerini kullanmalı) |
| B4.4 | Sunucu `401` dönsün, `onAuthExpired` callback tanımlı | `authExpired` | `onAuthExpired` tetiklenmeli, callback başarılı olursa görev otomatik re-queue edilmeli |

**Kayıt şablonu:**
```
Test: B4.x
SONUÇ:
Gözlemlenen FailureType:
Retry davranışı beklentiyle uyuştu mu (E/H):
[B4.3 için] Retry-After süresine uyuldu mu, ölçülen gecikme:
[B4.4 için] onAuthExpired çağrıldı mı, sonraki deneme başarılı oldu mu:
```

---

## Bölüm C — Checksum ve Veri Bütünlüğü

### C1. verifyChecksum: true — checksum uyuşmazlığı

**Ön koşul:** Mock sunucu, gerçek dosya checksum'ından **farklı** bir `remoteChecksum` dönsün.

**Adımlar:**
1. `verifyChecksum: true` (varsayılan) ile enqueue et.
2. Upload tamamlansın, sunucu yanlış checksum dönsün.

**Beklenen sonuç:**
- Görev `completed` olmamalı; checksum uyuşmazlığı bir hata olarak ele alınmalı (kodda hangi FailureType'a düştüğünü doğrula — README'de açıkça belirtilmemiş, kaynağa bakılmalı).

**Kayıt şablonu:**
```
SONUÇ:
Gözlemlenen davranış:
Görev hangi duruma geçti:
```

---

### C2. checksum hesaplama zamanı — enqueue vs uploading

**Ön koşul:** `pinChecksumAtEnqueue: false` (varsayılan).

**Adımlar:**
1. Bir dosyayı enqueue et (`copyToSandbox: false` ile — dosyanın orijinal yolunu kullansın).
2. Görev henüz `pending` iken (upload başlamadan) **dosya içeriğini değiştir** (ör. içine birkaç byte ekle).
3. Worker'ın dosyayı işlemesini bekle.

**Beklenen sonuç:**
- README'ye göre: checksum `uploading` anında hesaplanacağı için **değişmiş içerik** gönderilmeli ve bu `corruptFile` olarak **flag'lenmemeli** (sessizce değişmiş içerik yüklenir).
- `pinChecksumAtEnqueue: true` ile **aynı test tekrarlandığında**: checksum enqueue anında sabitlendiği için, değişen dosya içeriği ile sabitlenen checksum uyuşmayacak — bunun nasıl ele alındığını gözlemle (hata mı veriyor, yoksa sadece yanlış checksum mu gönderiliyor).

**Kayıt şablonu:**
```
SONUÇ:
pinChecksumAtEnqueue: false → Gözlem:
pinChecksumAtEnqueue: true → Gözlem:
```

---

## Bölüm D — Sandbox / Disk Davranışı

### D1. copyToSandbox: true — orijinal dosya silindiğinde upload devam ediyor mu

**Adımlar:**
1. `copyToSandbox: true` (varsayılan) ile bir dosyayı enqueue et.
2. Upload başlamadan **orijinal dosyayı sil**.
3. Worker'ın işlemesini bekle.

**Beklenen sonuç:**
- Upload **başarılı** olmalı (sandbox kopyası kullanıldığı için orijinal dosyanın silinmesi etkilememeli).

**Kayıt şablonu:**
```
SONUÇ:
Upload başarılı oldu mu (E/H):
```

---

### D2. copyToSandbox: false — orijinal dosya silindiğinde fileNotFound

**Adımlar:**
1. `copyToSandbox: false` ile bir dosyayı enqueue et.
2. Upload başlamadan orijinal dosyayı sil.

**Beklenen sonuç:**
- Görev `permanentlyFailed` + `FailureType.fileNotFound` olmalı (README'de belirtildiği gibi, retry yapılmaz).

**Kayıt şablonu:**
```
SONUÇ:
FailureType:
Durum:
```

---

### D3. Disk kullanımı — ~2x doğrulaması ve uyarı eşiği

**Ön koşul:** `advanced: UploadQueueAdvancedOptions(diskUsageWarningBytes: 5 * 1024 * 1024, onDiskUsageWarning: (current, limit) { ... })` ile 5MB eşik koy.

**Adımlar:**
1. Ağı kapat (görevler `pending`'de birikip yüklenmesin).
2. Toplam boyutu 6MB'ı aşacak şekilde dosyalar enqueue et.
3. `estimatedDiskUsageBytes` değerini ve `onDiskUsageWarning` callback'inin tetiklenip tetiklenmediğini gözlemle.
4. Dosya sistemi seviyesinde sandbox klasörünün gerçek boyutunu ölç, `estimatedDiskUsageBytes` ile karşılaştır.

**Beklenen sonuç:**
- `onDiskUsageWarning` eşik aşıldığında bir kez (veya her kontrol döngüsünde) tetiklenmeli.
- Gerçek disk kullanımı, orijinal dosya boyutlarının kabaca **2 katı** olmalı (sandbox kopyası + varsa orijinal hâlâ duruyorsa).

**Kayıt şablonu:**
```
SONUÇ:
Toplam orijinal dosya boyutu:
estimatedDiskUsageBytes:
Gerçek disk kullanımı (du -sh ile ölçülen):
Oran (gerçek/orijinal):
onDiskUsageWarning tetiklendi mi (E/H), kaç kez:
```

---

## Bölüm E — Kontrol Metodları (cancel / pause / resume / retry / purge)

### E1. cancel() — aktif upload'ı durdurma

**Adımlar:**
1. Büyük bir dosya (ör. 50MB) enqueue et, `uploading` durumuna geçmesini bekle.
2. Upload devam ederken `queue.cancel(taskId)` çağır.

**Beklenen sonuç:**
- HTTP isteği **hemen** iptal edilmeli (sunucu tarafında bağlantı kesintisi gözlemlenebilir — ör. sunucu loglarında "connection reset").
- Görev `cancelled` durumuna geçmeli, otomatik retry yapılmamalı.

**Kayıt şablonu:**
```
SONUÇ:
İptal anındaki upload yüzdesi:
Görev durumu:
HTTP bağlantısı gerçekten kesildi mi (sunucu log kontrolü):
```

---

### E2. pause() / resume()

**Adımlar:**
1. Birkaç dosya enqueue et.
2. `queue.pause()` çağır — o anda `uploading` olan görevin davranışını gözlemle.
3. Yeni bir dosya daha enqueue et — işlenmeye başlıyor mu?
4. `queue.resume()` çağır.

**Beklenen sonuç:**
- `pause()` sonrası worker yeni görev almamalı (mevcut aktif upload'ın devam edip etmediğini not al — README bunu netleştirmiyor, gözlemle).
- `resume()` sonrası kuyruk kaldığı yerden devam etmeli.
- Uygulamayı restart ettiğinde `pause` durumu **sıfırlanmalı** (README: "in-memory, resets on restart").

**Kayıt şablonu:**
```
SONUÇ:
pause() anında aktif upload'a etkisi:
pause() sonrası yeni görev alındı mı (Hayır olmalı):
resume() sonrası devam etti mi (E/H):
Restart sonrası pause durumu sıfırlandı mı (E/H):
```

---

### E3. retry() — permanentlyFailed / cancelled görevi yeniden kuyruğa alma

**Adımlar:**
1. B2 senaryosundaki gibi bir görevi `permanentlyFailed` durumuna getir.
2. Bu sırada başka bir görevi de normal şekilde `pending` olarak ekle (retry edilenden **sonra** ekle).
3. `queue.retry(taskId)` çağır.

**Beklenen sonuç:**
- `retryCount` ve `nextRetryAt` sıfırlanmalı.
- README'ye göre retry edilen görev, **sequence ordering** önceliğinden dolayı sonradan eklenen `pending` görevden **önce** işlenebilir — bunu doğrula (sequenceNumber sıfırlanmıyor, sadece retry state'i sıfırlanıyor; işlenme sırasının nasıl etkilendiğini gözlemle).

**Kayıt şablonu:**
```
SONUÇ:
retry() öncesi retryCount / nextRetryAt:
retry() sonrası retryCount / nextRetryAt:
İşlenme sırası (retry edilen mi önce işlendi, yoksa sonradan eklenen mi):
```

---

### E4. purge / purgeAllFailed / purgeAllCancelled / purgeAllCompleted

**Adımlar:**
1. Her durumdan (`permanentlyFailed`, `cancelled`, `completed`, `pending`) en az 2 görev oluştur.
2. Sırayla `purgeAllFailed()`, `purgeAllCancelled()`, `purgeAllCompleted()` çağır.
3. Her çağrıdan sonra `watchTasks()` ile kalan görevleri ve dosya sistemindeki sandbox klasörünü kontrol et.

**Beklenen sonuç:**
- Her `purgeAllX()` yalnızca ilgili durumdaki görevleri silmeli, diğerlerine dokunmamalı.
- `permanentlyFailed` ve `cancelled` görevler silinirken **sandbox kopyaları da diskten silinmeli**.
- `completed` görevler zaten sandbox kopyası olmadığı için sadece DB kaydı silinmeli.
- `pending` görevler hiçbirinden etkilenmemeli.

**Kayıt şablonu:**
```
SONUÇ:
purgeAllFailed() → silinen görev sayısı, sandbox temizlendi mi:
purgeAllCancelled() → silinen görev sayısı, sandbox temizlendi mi:
purgeAllCompleted() → silinen görev sayısı:
pending görevler etkilendi mi (Hayır olmalı):
```

---

## Bölüm F — Wi-Fi Only ve Bağlantı Yönetimi

### F1. wifiOnly: true — hücresel veride işlem yapmama

**Adımlar:**
1. `UploadQueue(wifiOnly: true, ...)` ile kuyruk oluştur.
2. Wi-Fi'ı kapat, yalnızca hücresel veriye geç.
3. Dosya enqueue et.

**Beklenen sonuç:**
- Görev `pending`'de beklemeli, worker Wi-Fi gelene kadar denememeli.

**Kayıt şablonu:**
```
SONUÇ:
Hücresel veride görev durumu (beklenen: pending, değişmiyor):
```

---

### F2. forceUploadOnce() — anlık snapshot davranışı

**Adımlar:**
1. `wifiOnly: true`, hücresel veride 2 dosya enqueue et (ikisi de `pending`).
2. `queue.forceUploadOnce()` çağır.
3. `forceUploadOnce()` çağrısından **hemen sonra**, işlem tamamlanmadan 3. bir dosya daha enqueue et.

**Beklenen sonuç:**
- İlk 2 dosya hücresel veri üzerinden yüklenmeli.
- 3. dosya (snapshot alındıktan sonra eklenen) **yüklenmemeli**, Wi-Fi bekleyecek — README'de belirtilen "snapshot" davranışı.

**Kayıt şablonu:**
```
SONUÇ:
İlk 2 dosya durumu:
3. dosya durumu (beklenen: pending, hücreselde işlenmedi):
```

---

### F3. Çevrimiçi/çevrimdışı geçiş sırasında ortadaki upload

**Adımlar:**
1. Büyük bir dosya upload'ı `uploading` durumundayken (%50 civarı) uçak modunu aç.
2. Ağın kesilmesinin görevi nasıl etkilediğini gözlemle.
3. Uçak modunu kapat.

**Beklenen sonuç:**
- Görev `failed`'e düşmeli (FailureType: `network`), backoff ile retry başlamalı.
- Ağ geri geldiğinde otomatik devam etmeli — **baştan mı** yoksa **kaldığı yerden mi** yüklendiğini not al (Dio'nun resume desteği olup olmadığı README'de belirtilmemiş).

**Kayıt şablonu:**
```
SONUÇ:
Kesinti anındaki yüzde:
Yeniden bağlanınca baştan mı devam mı:
```

---

## Bölüm G — Çoklu Kuyruk (boxName)

### G1. İki bağımsız kuyruğun izolasyonu

**Adımlar:**
1. `photoQueue = UploadQueue(adapter: ..., boxName: 'photos')` ve `docQueue = UploadQueue(adapter: ..., boxName: 'documents')` oluştur, ikisini de `init()` et.
2. Her ikisine de farklı dosyalar enqueue et.
3. `photoQueue.pause()` çağır — `docQueue`'nun etkilenip etkilenmediğini kontrol et.
4. Dosya sistemi seviyesinde iki ayrı sembast dosyasının oluştuğunu doğrula.

**Beklenen sonuç:**
- Kuyruklar birbirinden tamamen bağımsız çalışmalı — pause, worker lock, disk kullanımı hiçbiri karışmamalı.

**Kayıt şablonu:**
```
SONUÇ:
İki ayrı DB dosyası oluştu mu (E/H), dosya adları:
photoQueue.pause() docQueue'yu etkiledi mi (Hayır olmalı):
```

---

## Bölüm H — dispose() ve Lifecycle

### H1. dispose() sırasında aktif upload

**Adımlar:**
1. Büyük dosya upload'ı `uploading` durumundayken `queue.dispose()` çağır.

**Beklenen sonuç:**
- HTTP isteği iptal edilmeli.
- Görev **`cancelled` değil, `pending`**'e dönmeli (README'de özellikle vurgulanan davranış — `cancel()`'dan farklı).
- Yeni bir `init()` çağrıldığında bu görev tekrar işlenmeli.

**Kayıt şablonu:**
```
SONUÇ:
dispose() sonrası görev durumu (beklenen: pending):
Yeniden init() sonrası tekrar işlendi mi (E/H):
```

---

## Bölüm I — Şifreleme (encryptionKey) — README'de Belgelenmemiş Özellik

> Not: Bu özellik mevcut README'de dokümante edilmemiş; kaynak kodda (`upload_queue.dart`,
> `sembast_codec.dart`) mevcut. Test ederken kod içi uyarıyı unutmayın: kullanılan codec
> (Salsa20+SHA256) bağımsız güvenlik denetiminden geçmemiştir.

### I1. encryptionKey verildiğinde DB dosyasının düz metin olmaması

**Adımlar:**
1. `UploadQueue(encryptionKey: 'test-anahtar-123', ...)` ile bir kuyruk oluştur, birkaç görev enqueue et (metadata'ya belirgin bir string koy, ör. `{'secret': 'PLAINTEXT_MARKER_XYZ'}`).
2. Uygulamayı kapat.
3. Cihaz/emülatör dosya sisteminde sembast DB dosyasını bul (`adb pull` veya simulator dosya gezgini ile).
4. Dosyayı bir metin editörüyle aç, `PLAINTEXT_MARKER_XYZ` string'ini ara.

**Beklenen sonuç:**
- `encryptionKey` **verilmediğinde**: marker düz metin olarak DB dosyasında bulunmalı (bu da README'nin "plaintext SQLite" uyarısının Sembast için de geçerli olduğunu teyit eder).
- `encryptionKey` **verildiğinde**: marker bulunamamalı, dosya şifreli/anlamsız veri içermeli.

**Kayıt şablonu:**
```
SONUÇ:
encryptionKey YOK → marker bulundu mu (Evet olmalı):
encryptionKey VAR → marker bulundu mu (Hayır olmalı):
```

### I2. Yanlış encryptionKey ile açma denemesi

**Adımlar:**
1. `encryptionKey: 'dogru-anahtar'` ile veriler oluştur, uygulamayı kapat.
2. Uygulamayı `encryptionKey: 'yanlis-anahtar'` ile yeniden başlat.

**Beklenen sonuç:**
- `init()` bir hata fırlatmalı veya en azından okunabilir veri döndürmemeli (davranışı gözlemleyip not edin — kaynak kodda bu durumun nasıl ele alındığı net değil).

**Kayıt şablonu:**
```
SONUÇ:
Gözlemlenen davranış (hata mı, sessiz veri kaybı mı, vs.):
```

---

## Bölüm J — Yapılandırma Doğrulamaları (ArgumentError durumları)

### J1. staleLockThreshold < heartbeatInterval × 3

**Adımlar:**
1. `advanced: UploadQueueAdvancedOptions(heartbeatInterval: Duration(seconds: 30), staleLockThreshold: Duration(seconds: 60))` gibi kuralı ihlal eden bir kombinasyon ver (60 < 30×3=90).
2. `queue.init()` çağır.

**Beklenen sonuç:**
- `ArgumentError` fırlatılmalı, uygulama bunu yakalayabilmeli.

**Kayıt şablonu:**
```
SONUÇ:
ArgumentError fırlatıldı mı (E/H):
Hata mesajı:
```

### J2. maxAttempts < 1

**Adımlar:**
1. `UploadQueue(maxAttempts: 0, ...)` ile `init()` çağır.

**Beklenen sonuç:**
- `ArgumentError` fırlatılmalı.

**Kayıt şablonu:**
```
SONUÇ:
ArgumentError fırlatıldı mı (E/H):
```

---

## Bölüm K — Kayıt / Loglama (onLog)

### K1. onLog yalnızca beklenmedik olaylarda tetikleniyor mu

**Adımlar:**
1. `onLog` callback'ini konsola basacak şekilde bağla.
2. Normal bir upload akışı çalıştır (A1 senaryosu) — logları izle.
3. Ardından bir kilit devralma (stale lock takeover), bir `authTimeout` ve bir `corruptFile` senaryosu tetikle.

**Beklenen sonuç:**
- Normal akışta (A1) **hiç log gelmemeli** (README: "Routine upload flow is not logged").
- Lock takeover, auth timeout, corruptFile downgrade, sandbox delete failure durumlarında log gelmeli.

**Kayıt şablonu:**
```
SONUÇ:
Normal akışta log geldi mi (Hayır olmalı):
Lock takeover logu geldi mi (E/H):
Auth timeout logu geldi mi (E/H):
corruptFile logu geldi mi (E/H):
```

---

## Bölüm L — UI Referans Senaryoları

### L1. sequenceNumber vs list index

**Adımlar:**
1. 5 görev enqueue et.
2. Ortadaki 2. görevi `purge()` ile sil.
3. Kalan görevleri hem `sequenceNumber` hem de `watchTasks()` listesindeki index'e göre ekrana yazdır.

**Beklenen sonuç:**
- `sequenceNumber` değerlerinde **boşluk** oluşmalı (silinen görevin numarası atlanmalı).
- UI'da "Fotoğraf N / Toplam" göstermek için **list index** kullanılmalı, sequenceNumber değil — README'nin uyardığı hata bu şekilde somutlaşmalı.

**Kayıt şablonu:**
```
SONUÇ:
Silme sonrası sequenceNumber dizisi (boşluk var mı):
list index sürekli/sıralı mı (Evet olmalı):
```

---

## Genel Test Özeti Tablosu

Tüm senaryoları tamamladıktan sonra bu tabloyu doldurup PR'a ekleyin:

| # | Senaryo | Durum (✅/❌/⚠️) | Not |
|---|---|---|---|
| A1 | Tek dosya enqueue → completed | | |
| A2 | Sıralı işleme | | |
| A3 | Cold start kalıcılığı | | |
| B1 | Otomatik retry / backoff | | |
| B2 | maxAttempts → permanentlyFailed | | |
| B3 | Kalıcı hata sınıflandırması | | |
| B4 | Geçici hata sınıflandırması | | |
| C1 | Checksum uyuşmazlığı | | |
| C2 | Checksum hesaplama zamanı | | |
| D1 | copyToSandbox: true dayanıklılık | | |
| D2 | copyToSandbox: false fileNotFound | | |
| D3 | Disk kullanımı ~2x + uyarı | | |
| E1 | cancel() | | |
| E2 | pause()/resume() | | |
| E3 | retry() | | |
| E4 | purge işlemleri | | |
| F1 | wifiOnly | | |
| F2 | forceUploadOnce snapshot | | |
| F3 | Bağlantı kesintisi ortasında | | |
| G1 | Çoklu kuyruk izolasyonu | | |
| H1 | dispose() → pending | | |
| I1 | Şifreleme doğrulama | | |
| I2 | Yanlış şifreleme anahtarı | | |
| J1 | staleLockThreshold validasyonu | | |
| J2 | maxAttempts validasyonu | | |
| K1 | onLog seçiciliği | | |
| L1 | sequenceNumber vs index | | |

---

*Bu doküman repo kökündeki `MANUAL_TESTING.md`'yi tamamlayıcı niteliktedir; onun yerine geçmez.
OS-seviyesi background sync testleri için `MANUAL_TESTING.md`'ye bakın.*