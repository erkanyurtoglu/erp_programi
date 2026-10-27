# Liya ERP — Qt/QML

Liya'nın teklif, satınalma ve yönetim işlerini yürüten masaüstü programı.
Qt 6.7.3 / QML ile yazıldı. Veriler SQL Server'daki `LiyaErpVeriTabani`
veritabanında tutulur. Eski WPF programının veritabanı (`LiyaTeklifVeriTabani`)
yalnızca veri göçü için kullanıldı.

## Modüller

Ana menüde kullanıcıya yalnızca rolünün yetkili olduğu modüller görünür
(Yönetim → Roller ve Yetkiler).

| Modül | Ekranlar |
|---|---|
| **Satış / Teklif** | Teklif Ver, Giden Tekliflerim, Alınan Tekliflerim, Biten Tekliflerim, Müşterilerim, Ürünlerim |
| **Satınalma** | Talep Oluştur, Talepler, Siparişler, Tedarikçilerim, Cihaz Maliyetleri |
| **Yönetim** | Özet, Personellerim, Roller ve Yetkiler, Sistem Ayarları, İşlem Geçmişi, Cihaz Maliyetleri |

Diğer özellikler:

- Teklif PDF'i (Türkçe/İngilizce kapak, sayfa ve satış sözleşmesi) ve üretim PDF'i;
  şablonlar `pdf_sablonlari/` klasöründe, program içinde önizlenir.
- Teklif revizyonu, kopyalama, durum geçmişi ve kalem bazında üretim takibi.
- TL / USD / EUR fiyatlar; günlük kur TCMB'den çekilir (`src/KurServisi.cpp`).
- Arama ve listeleme SQL Server tarafında, ayrı bir thread'de yapılır; büyük
  listelerde arayüz donmaz.

## Derleme ve çalıştırma

Gerekenler: Qt 6.7.3 (MSVC 2019 64-bit, WebEngine ve Qt PDF bileşenleriyle),
Visual Studio 2022, VS Code'da **CMake Tools** ve **C/C++** uzantıları.

1. VS Code'da `File > Open Folder` ile bu klasörü (`erp_programi`) aç.
2. `Ctrl+Shift+P` → `CMake: Select Configure Preset` → **`qt-msvc`**.
   (`qt-mingw` preset'i de var, ancak Qt WebEngine yalnızca MSVC ile geliyor.)
3. `CMake: Build`, ardından `CMake: Run Without Debugging`.

Her derlemeden sonra `windeployqt` gereken Qt DLL'lerini, CMake de
`pdf_sablonlari/` klasörünü exe'nin yanına kopyalar.

- **Debug** derlemede program bir konsol penceresiyle açılır, hata mesajları orada görünür.
- **Release** derlemede yalnızca program penceresi açılır.

İki durumda da tüm çıktı şu dosyaya da yazılır:
`%LOCALAPPDATA%\Liya\Liya Teklif Programi (Qt)\erp_gunluk.txt`

## Veritabanı bağlantısı

Program, Windows kimlik doğrulamasıyla (kullanıcı adı/şifre yok) QODBC üzerinden
bağlanır. Sırasıyla "ODBC Driver 18", "17" ve Windows'ta her zaman bulunan
"SQL Server" sürücüsü denenir.

Varsayılan sunucu `EXCALIBUR\SQLEXPRESS`, veritabanı `LiyaErpVeriTabani`'dır.
Başka bir sunucuya bağlanmak için exe'nin yanına `baglanti.ini` dosyası koyun:

```ini
[Veritabani]
Sunucu=BASKA-PC\SQLEXPRESS
Ad=LiyaErpVeriTabani
```

Bağlantı kurulamazsa ekranın üstünde kırmızı bir uyarı şeridi çıkar. Asıl ODBC
hatası günlük dosyasında yazar.

## Veritabanı betikleri (`db/`)

Betikler numara sırasıyla, SQL Server Management Studio'da ya da `sqlcmd` ile
elle çalıştırılır. Program bunları kendisi çalıştırmaz. Her betiğin başında ne yaptığı
ve önkoşulu yazar. Çoğu birden fazla kez çalıştırılabilir.

- `01` — yeni veritabanı ve şema
- `02` — eski WPF veritabanından veri göçü
- `03`–`27` — sonradan eklenen alanlar, tablolar ve veri düzeltmeleri

Program, bir betik henüz çalıştırılmamışsa ilgili alanı atlayarak çalışmaya devam
eder. Eksik betik gereken bir işlemde hangi betiğin çalıştırılması gerektiğini söyler.

## Klasör yapısı

```
main.cpp            Uygulama girişi
src/                C++ tarafı: Database (tüm sorgular), AramaWorker (arka plan
                    aramaları), TeklifPdfOlusturucu, PdfOnizleyici, KurServisi,
                    Tanilama (günlük dosyası)
qml/pages/          Ekranlar
qml/components/     Ortak bileşenler (tema butonu, tarih seçici, onay pencereleri…)
qml/Theme.qml       Renk, yazı tipi ve ölçüler
pdf_sablonlari/     Teklif PDF şablonları
db/                 Veritabanı betikleri
code_export/        Kodların PDF dökümü için yardımcı betik
```
