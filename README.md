# Liya Teklif Programı — Qt/QML sürümü (1. adım)

Bu klasör, mevcut WPF uygulamasının yanına eklenen **ayrı ve bağımsız** bir Qt/QML
projesidir. WPF projesine dokunmuyor; ikisi de aynı SQL Server veritabanını
(`EXCALIBUR\SQLEXPRESS` / `LiyaTeklifVeriTabani`) kullanıyor, veri kaybı yok.

İlk adımda sadece **Geçmiş Teklifler** ekranı uçtan uca kuruldu: arama, tarih
filtresi ve sayfalama SQL Server tarafında yapılıyor (WPF tarafında geçen sefer
kurduğumuz mantığın aynısı — 20 bin+ kayıtta donma yaşanmaması için).

## VS Code'da açma ve çalıştırma

1. Uzantılar: **CMake Tools** (`ms-vscode.cmake-tools`) ve **C/C++**
   (`ms-vscode.cpptools`) kurulu olmalı — VS Code bu klasörü açınca otomatik önerecek.
2. `File > Open Folder` ile **bu klasörü** (`erp_programi`) aç — repo kökünü değil.
3. VS Code CMake Tools "qt-mingw" preset'ini otomatik algılamalı. Algılamazsa:
   `Ctrl+Shift+P` → `CMake: Select Configure Preset` → `qt-mingw`.
4. `Ctrl+Shift+P` → `CMake: Build` (veya alt durum çubuğundaki "Build" butonu).
5. Derleme bitince `Ctrl+Shift+P` → `CMake: Run Without Debugging` ile çalıştır.

Qt'nin DLL'lerini bulabilmesi için PATH ayarı `.vscode/settings.json` içinde zaten
yapılandırıldı (`C:\Qt\6.7.3\mingw_64\bin`); yine de "DLL bulunamadı" hatası alırsan
bu klasörü sistem PATH'ine ekle veya `windeployqt` çalıştır.

## Veritabanı bağlantısı

`src/Database.cpp` içinde `EXCALIBUR\SQLEXPRESS` sunucusuna Windows Integrated
Security (kullanıcı adı/şifre yok) ile QODBC üzerinden bağlanıyor — WPF'teki
`App.config`'daki `TeklifDb` bağlantı dizesiyle aynı sunucu/veritabanı. Sırasıyla
"ODBC Driver 18", "17" ve son çare olarak Windows'ta her zaman hazır gelen "SQL
Server" sürücüsünü dener.

Uygulama açılınca bağlanamazsa ekranın üstünde kırmızı bir uyarı çubuğu çıkar —
bu durumda VS Code'un "Debug Console" / terminal çıktısındaki `qWarning()`
satırlarına bakarak asıl ODBC hatasını görebiliriz.

## Şu an eksik olanlar (bilerek, sıradaki adımlar için bırakıldı)

- Silme işleminde WPF'teki şifre onayı yok (sadece Evet/Hayır onayı var).
- Detay penceresi, PDF üretimi, diğer ekranlar (Alınan/Biten Teklifler, Ürünler,
  Müşteriler, Personeller, Teklif Ver...) henüz yok.
- Tema/renkler WPF'teki gibi elle (hardcoded) — ortak bir `Theme.qml` sonraki
  adımlarda eklenebilir.

Bu ekran çalışınca mimariyi onaylamış oluruz ve diğer ekranları aynı desenle
(yeni bir `XxxSayfasi.qml` + `Database` sınıfına yeni `Q_INVOKABLE` metotlar)
hızlıca ekleriz.
