# offline_upload_queue — Agent Context

Bu paket için detaylı plan `docs/` altında bölünmüş haldedir:
- docs/offline_upload_queue_plan-2.md → tam plan, tüm kararların gerekçesi (yalnızca gerektiğinde bak)
- docs/asama-1-cekirdek.md → Aşama 1 iş listesi
- docs/asama-2-dayaniklilik.md → Aşama 2 iş listesi
- docs/asama-3-arka-plan.md → Aşama 3 iş listesi
- docs/asama-4-cilalama-paketleme.md → Aşama 4 iş listesi
- docs/asama-5-yayin-sonrasi.md → Aşama 5 iş listesi

## Kural
Herhangi bir implementasyon görevine başlamadan önce, o görevin ait
olduğu asama-N dosyasını oku. Eğer bir kararın gerekçesi/edge-case
detayı asama dosyasında yoksa, plan-2.md içinde ilgili "Bölüm N"
başlığını ara.

## Şu an aktif aşama
Aşama 5 — Yayın sonrası (docs/asama-5-yayin-sonrasi.md).

Aşama 1–4 tamamlandı:
- Aşama 1: çekirdek kuyruk + PersistenceRepository
- Aşama 2: dayanıklılık / hata yönetimi
- Aşama 3: arka plan (iOS BGTaskScheduler + Android Workmanager) + kilit
- Aşama 4: cilalama, example, README, manuel checklist

Notlar:
- Persistence: Drift → Sembast geçişi tamamlandı; cross-isolate semantiği
  Alternatif A (handoff) olarak doğrulandı.
- `copyToSandbox`: hardlink-önce (`ln`) + byte-kopyalama fallback v1'de
  (shell `ln`; native platform channel yok).
