# Rankly

Kişisel kullanım için App Store anahtar kelime sıra takipçisi (macOS 14+, SwiftUI + SwiftData).

## Özellikler
- Uygulama ekleme: ad, App Store ID veya App Store linki ile
- Anahtar kelime başına günlük sıra (ilk 250 sonuç), 53 ülke
- Değişim (dünden bugüne), sıra geçmişi grafiği, trend çizgisi
- Zorluk (0–100): ilk 10 uygulamanın puan sayısı + adında kelimeyi geçirme oranı
- Popülerlik (~5–100, **tahmini**): App Store otomatik tamamlamasında kelimenin kaç harfte ve kaçıncı sırada çıktığına göre
- Kelime önerileri (App Store autocomplete), tek tıkla ekleme
- Bir kelimede sıralanan uygulamalar listesi; "Takip et" ile rakip ekleme
- **Analiz sekmesi** (otomatik ASO analizi):
  - Ad, alt başlık ve açıklamadan aday kelimeler çıkarılır, otomatik tamamlama ile genişletilir ve App Store'da aranır
  - Uygulamanın sıralandığı kelimeler; ad/alt başlıkta olup sıralanmadığı kelimeler
  - Rakipler: senin kelimelerinde sık üst sıralarda çıkan, aynı kategorideki uygulamalar (takip ettiğin rakipler her zaman dahil)
  - Fırsatlar: rakiplerin ilk 30'da olup senin olmadığın kelimeler; popülerlik, zorluk ve rakip sayısıyla puanlanır. Marka aramaları elenir
  - 100 karakterlik keyword alanı önerisi (ad/alt başlıktaki kelimeler tekrar edilmez)
  - Sonuçlar ülke başına kaydedilir; bir analiz ~1–2 dakika sürer
  - **Çok ülkeli analiz**: uygulamanın desteklediği diller App Store'dan çekilir, bu dillerde arama yapılan
    mağazalar önerilir; seçilen ülkeler arka planda sırayla, o ülkenin yerelleştirilmiş adı/açıklamasıyla analiz edilir.
    "Tüm ülkeler" görünümü ülke özetlerini ve ülkeler arası en iyi fırsatları gösterir
- Açılışta ve sonra saatlik kontrolle günde bir otomatik yenileme, ⌘R ile elle yenileme

Veriler yalnızca bu Mac'te (SwiftData) tutulur. Hesap gerekmez.

## Çalıştırma
```bash
xcodegen generate
xcodebuild -project Rankly.xcodeproj -scheme Rankly -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Rankly.app
```
Kalıcı kullanım için `build/Build/Products/Release/Rankly.app` dosyasını `/Applications` klasörüne kopyalayabilirsin.

## Veri kaynakları (Apple'ın herkese açık uç noktaları)
- Sıra: `search.itunes.apple.com/WebObjects/MZStore.woa/wa/search` (+ `X-Apple-Store-Front` başlığı)
- Uygulama bilgisi: `itunes.apple.com/lookup` ve `/search`
- Öneriler: `search.itunes.apple.com/WebObjects/MZSearchHints.woa/wa/hints`

Bunlar resmî olarak belgelenmiş API'ler değil; Apple değiştirirse `AppStoreClient.swift` güncellenmeli.
Sıralar iPhone App Store aramasına göredir.

**İstek sınırı:** Apple, arama uç noktasına çok sık istek gelirse ağı geçici olarak engeller (HTTP 403).
Rankly arama isteklerini yavaş gönderir (başlangıçta 1,5 sn arayla); 403 alınca 1 saat durur ve aralığı ikiye katlar
(en fazla 8 sn, kalıcı olarak saklanır). Çok ülkeli analiz engellenirse kalan ülkeler "Kalanlarla devam et" ile sürdürülür.

Not: Apple, uygulamaların gizli 100 karakterlik keyword alanını yayınlamaz; analiz bunun yerine
uygulamanın **gerçekten sıralandığı** kelimeleri bulur.
