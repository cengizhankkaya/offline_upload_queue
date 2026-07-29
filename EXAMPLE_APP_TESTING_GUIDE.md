# Örnek Uygulama (Example App) UI Test Rehberi

Bu rehber, `offline_upload_queue` paketinin özelliklerini `/example` klasöründeki demo uygulaması üzerinden manuel olarak test etmek için adım adım talimatlar içerir. 

Uygulama çalıştırıldığında alt kısımda 4 ana sekme bulunur:
1. **Kuyruk:** Temel yükleme işlemleri ve liste takibi.
2. **Cellular:** Sadece Wi-Fi ayarı ve hücresel veri senaryoları.
3. **Hata:** Kasıtlı hata fırlatma senaryoları.
4. **Disk:** Disk kullanımı ve uyarı mekanizması senaryoları.

*Not: Uygulama gerçek bir sunucu kullanmaz, `MockUploadAdapter` ile 2 saniyelik sahte yükleme simülasyonu yapar.*

---

## 1. Temel Yükleme ve Sıralı İşleme (Kuyruk Sekmesi)

### Senaryo 1.1: Tek Dosya Yükleme (A1)
1. **Kuyruk** sekmesinde sağ alttaki **"Fotoğraf Ekle"** butonuna basın.
2. Galeriden 1 adet fotoğraf seçin.
3. Ekranda dosyanın önce turuncu **(pending)**, sonra mavi **(uploading)** ve yanındaki ilerleme çubuğunun dolmasıyla yeşil **(completed)** durumuna geçtiğini doğrulayın.
4. Üstteki panoda "Tamamlandı" sayısının 1 arttığını görün.

### Senaryo 1.2: Çoklu Dosya ve Sıralı İşleme (A2)
1. **"Fotoğraf Ekle"** butonuna basıp 4-5 adet fotoğraf seçin.
2. Listeye eklendiklerinde **aynı anda sadece 1 görevin** mavi (uploading) olduğunu doğrulayın.
3. Diğer görevlerin turuncu (pending) olarak beklediğini ve yükleme tamamlandıkça sırayla işleme alındığını gözlemleyin (Paralel yükleme yapılmaz).

### Senaryo 1.3: Çökme/Kapatılma Kurtarması (Cold Start - A3)
1. Listeye tekrar 4-5 adet fotoğraf ekleyin.
2. Yükleme işlemi devam ederken (mavi ikon varken) uygulamayı **görev yöneticisinden (Task Switcher) tamamen kapatın** (kill edin).
3. Uygulamayı yeniden başlatın.
4. Yarıda kesilen işlemlerin kaybolmadığını, hataya düşmediğini ve tekrar **pending** durumuna dönüp kaldığı yerden sırayla yüklendiğini doğrulayın.

---

## 2. Hata Yönetimi ve Kalıcılık (Hata Sekmesi)

### Senaryo 2.1: Var Olmayan Dosya ve Kalıcı Hata (B3)
1. Alt menüden **Hata** sekmesine geçin.
2. Ekranda bulunan **"Var Olmayan Dosya Ekle"** (veya benzeri) butonuna basın. Bu işlem bilerek sahte bir dosya yolunu kuyruğa ekler.
3. Görevin tekrar tekrar denenmeden (backoff yapılmadan) **doğrudan kırmızı (permanentlyFailed)** durumuna geçtiğini doğrulayın.
4. Çöp kutusu (Purge) ikonuna basarak bu kalıcı hatayı listeden silin.

### Senaryo 2.2: Ağ Kesintisi ve Exponential Backoff (B1)
1. **Kuyruk** sekmesine dönüp bir fotoğraf ekleyin.
2. İşlem maviye (uploading) döndüğü an cihazı/emülatörü **Uçak Moduna** alın (İnterneti kesin).
3. Görevin durduğunu ve sarı/kehribar rengi **(failed)** durumuna düştüğünü görün.
4. Görevin bir süre sonra tekrar deneneceğini (retry süresinin loglarda giderek arttığını) fark edin.
5. Uçak modunu kapatın; bağlantı geldiğinde görevin otomatik devam edip **completed** olduğunu doğrulayın.

---

## 3. Bağlantı Tipi Kısıtlamaları (Cellular Sekmesi)

### Senaryo 3.1: Sadece Wi-Fi Beklentisi (F1)
1. Alt menüden **Cellular** sekmesine geçin. Bu ekrandaki kuyruk `wifiOnly: true` (sadece Wi-Fi) kısıtlamasıyla çalışır.
2. Cihazınızın Wi-Fi bağlantısını kapatın (Sadece hücresel veri veya internetsiz durumda bırakın).
3. Ekrana yeni fotoğraf ekleyin.
4. Görevlerin işlemeye başlamadığını ve turuncu **(pending)** olarak beklediğini doğrulayın.
5. Wi-Fi bağlantısını geri açın; görevlerin anında tetiklenip yüklenmeye başladığını görün.

---

## 4. Disk Kontrolü ve Sandbox (Disk Sekmesi)

### Senaryo 4.1: Disk Limit Uyarısı (D3)
1. Alt menüden **Disk** sekmesine geçin. Bu ekranda disk kullanımı takip edilir ve düşük bir uyarı eşiği (örneğin 50MB) vardır.
2. Cihazın internetini kesin (dosyalar biriksin diye).
3. Boyutu büyük 4-5 dosyayı (veya videoyu) kuyruğa ekleyin.
4. Uygulamanın debug konsoluna bakın veya ekranda beliriyorsa UI üzerinden **"Disk uyarısı!"** mesajının tetiklendiğini doğrulayın.
5. Görevleri UI'daki ikonlar üzerinden (veya Purge All tuşlarıyla) temizlediğinizde diskin rahatladığını doğrulayın.

---

## 5. İptal, Duraklatma ve Temizlik İşlemleri

### Senaryo 5.1: Aktif Görevi İptal Etme (Cancel)
1. **Kuyruk** sekmesinde 3 dosya ekleyin.
2. Mavi olan (uploading) görevin yanındaki **"İptal" (Çarpı)** butonuna basın.
3. Görevin anında durduğunu ve gri **(cancelled)** durumuna geçtiğini görün.
4. Sıradaki diğer pending görevin otomatik olarak yüklenmeye başladığını doğrulayın.

### Senaryo 5.2: Tüm Görevleri Temizleme (Purge All)
1. Listede farklı durumlarda (completed, cancelled, permanentlyFailed) birçok görev oluşturun.
2. "Hata" sekmesindeki veya "Disk" sekmesindeki toplu silme tuşlarını kullanarak (veya test dosyasına ekleyerek) sadece belirli durumdaki görevlerin temizlendiğini (örn: sadece hataları sil) ve `pending` olanların etkilenmediğini gözlemleyin.
