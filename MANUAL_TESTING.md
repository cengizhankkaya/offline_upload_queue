# Manual Testing Checklist

> [!CAUTION]
> CI'ın yeşil olması bu maddelerin tamamlandığı anlamına gelmez.
> Aşağıdaki senaryolar CI ortamında otomatikleştirilemez.
> **Sürüm etiketi (`git tag`) bu maddeler tamamlanmadan basılmamalı.**

## Versiyon: `0.1.0`

---

## 1. Çevrimiçi/Çevrimdışı Geçiş — Gerçek Cihaz

- [ ] Uygulamayı başlat, birkaç dosyayı kuyruğa ekle (`enqueue`)
- [ ] **Uçak modunu aç** — `watchSummary()` `pending` sayısının değişmediğini doğrula
- [ ] Upload girişimi olmadığını doğrula (log / `watchTasks` ile)
- [ ] **Uçak modunu kapat** — worker'ın otomatik olarak devreye girdiğini ve
      görevlerin `uploading → completed` geçtiğini doğrula
- [ ] Sonuç (ekran görüntüsü / log) bu dosyaya ekle:

```
SONUÇ:
Tarih:
Cihaz:
iOS/Android sürümü:
Gözlem:
```

---

## 2. iOS — BGTaskScheduler Zincirleme Submit Sıklığı

> [!IMPORTANT]
> Bu test **birkaç takvim günü** gerektirir (iş saati değil, gerçek bekleme süresi).
> Aşama 3 implementasyonu bittiği anda başlatılmalı — sürüm aşamasının sonuna bırakılmamalı.

- [ ] Test cihazına gerçek build kuruldu (TestFlight veya doğrudan)
- [ ] Xcode → Signing & Capabilities → Background Modes'ta iki seçenek işaretli:
  - ✅ Background fetch
  - ✅ Background processing
- [ ] Cihazda en az birkaç görev `pending` durumunda bırakıldı
- [ ] Cihaz birkaç gün şarjsız ve farklı ağ koşullarında (Wi-Fi / cellular) kullanıldı
- [ ] `BGTaskScheduler` zincirleme submit'lerin uygun sıklıkta tetiklendiği gözlemlendi
      (Xcode → Instruments veya log aracılığıyla)
- [ ] Apple'ın dokümante edilmemiş throttling davranışı not edildi (varsa)

```
SONUÇ:
Tarih (başlangıç – bitiş):
Cihaz:
iOS sürümü:
BGAppRefreshTask tetiklenme sayısı ve zamanları:
BGProcessingTask tetiklenme sayısı ve zamanları:
Throttling gözlemi:
```

---

## 3. iOS — Xcode Background Modes Kurulum Doğrulaması

- [ ] Xcode → [Hedef] → Signing & Capabilities → Background Modes açıldı
- [ ] **Background fetch** işaretli mi? ✅ / ❌
- [ ] **Background processing** işaretli mi? ✅ / ❌
- [ ] Gerçek cihazda uygulama arka planda iken bir BGTask tetiklendi
      (Xcode debug console'dan: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.app.upload_refresh"]`)
- [ ] Dart `onAppRefresh` / `onProcessing` callback'lerinin çağrıldığı doğrulandı

```
SONUÇ:
Tarih:
Cihaz:
iOS sürümü:
Xcode sürümü:
Background fetch işaretli: Evet/Hayır
Background processing işaretli: Evet/Hayır
BGTask tetikleme başarılı: Evet/Hayır
```

---

## 4. Android — Workmanager Gerçek Cihaz Testi

- [ ] Debug build ile gerçek Android cihazda test edildi
- [ ] `AndroidBackgroundRunner.scheduleNextRun()` çağrısı sonrası görevin
      Workmanager tarafından tetiklendiği doğrulandı
- [ ] Doze modu etkin cihazda (`adb shell dumpsys deviceidle force-idle`)
      gecikmeli de olsa tetiklendiği gözlemlendi (veya throttle edildiği not edildi)

```
SONUÇ:
Tarih:
Cihaz + Android sürümü:
Gözlem:
```

---

## 5. Sembast Bellek Profili (1000+ Görev)

- [ ] `UploadQueue`'ya art arda (for döngüsüyle) 1000 adet `pending` görev ekle
- [ ] Uygulamayı kapatıp aç (cold start)
- [ ] Açılışta (`init()` sonrası) bellek tüketimini gözlemle (Flutter DevTools → Memory)
- [ ] Bellek kullanımının (RSS) makul seviyelerde kaldığını doğrula (sembast tüm veriyi belleğe yükler)

```
SONUÇ:
Tarih:
Cihaz:
1000 görev ekleme süresi:
Açılışta max bellek kullanımı (MB):
```

---

## 6. Sembast El Değiştirme (Handoff) Testi

- [ ] Arka plan görevi çalışırken ana `UploadQueue` dispose edilip yeniden başlatıldığında (`init`), veritabanı kilitlenmesi veya erişim hatası yaşanmadığını doğrula.
- [ ] Sembast transaction'larının arka plan ve ön plan arasında hatasız devredildiğini teyit et.

```
SONUÇ:
Tarih:
Cihaz:
Durum (Başarılı/Hata):
```

---

*Bu dosya `docs/` altına alınmamıştır — proje köküne bilerek yerleştirildi, çünkü
CI ve PR süreçlerinde görünür olması gerekir.*
