#pragma once

#include <QList>
#include <QString>

class QSqlDatabase;

// Database (ana baglanti) ile AramaSorgulari/AramaWorker (ayri thread + ayri
// baglanti) arasinda PAYLASILAN kucuk SQL yardimcilari. Ayni mantigin iki
// yerde kopyalanmamasi icin burada tek yerde duruyorlar.

// LIKE desenindeki joker karakterleri ('%', '_', '[') etkisizlestirir.
// Kullanici arama kutusuna "%" yazdiginda TUM kayitlar, "_" yazdiginda tek
// karakterlik joker eslesmesi donuyordu. Donen desen SQL'de her zaman
// ESCAPE N'\' ile birlikte kullanilmalidir.
QString likeIcinKacir(const QString &metin);

// Aramada kullanilan "%...%" deseni (jokerler kacirilmis, bosluklar kirpilmis).
QString likeDeseni(const QString &arama);

// "MANUEL-<teklifId>" kodlu satirlar, sepete manuel eklenen kalemler icin
// FOREIGN KEY zorunlulugu yuzunden dbo.urunler'e yazilan, teklife ozel GECICI
// kayitlardir; urun katalogu liste ve aramalarindan filtrelenirler. Bu yuzden
// onek REZERVEDIR: kullanici elle bu kodla urun girerse kayit veritabanina
// yazilir ama hicbir listede gorunmez -- duzenlenemez/silinemez bir hayalet
// kayit olusur (bkz. Database::urunEkle).
bool manuelKoduMu(const QString &urunKodu);

// Bir sutun semada var mi? (Migration scriptleri calistirilmamis olabilir --
// ör. db/12 ve db/13 ile eklenen SifreSalt / AktifMi sutunlari.) Program bu
// sutunlar olmadan da calismaya devam etsin diye sorgular buna gore kurulur.
//
// Sonuc tablo+sutun bazinda onbelleklenir: script program ACIKKEN
// calistirilirsa programin yeniden baslatilmasi gerekir (kopyaKolonuVarMi ile
// ayni davranis). Onbellek thread-guvenlidir -- ana baglanti ile arama
// worker'inin baglantisi ayni onbellegi paylasir.
bool semaKolonuVarMi(QSqlDatabase &db, const QString &tablo, const QString &kolon);

// "Yönetici" ve goc donemindeki "Göç - Geçici Tam Yetkili" rolleri SISTEM
// rolleridir: yonetici sifresi dogrulamasi ve "son yonetici" korumalari
// (Database::yoneticiSifresiDogrula / aktifYoneticiSayisi) bu rolleri ADIYLA
// tanir. Bu yuzden Roller ve Yetkiler ekraninda adlari ve yetkileri
// degistirilemez; "Yönetici" silinemez, goc rolu ise kimseye atanmamissa
// silinebilir.
bool sistemRoluMu(const QString &rolAdi);

// Yonetim / Sistem Ayarlari ekraninda duzenlenebilen dbo.ayarlar anahtarlari.
// Ekran bu listeye gore kurulur; kaydetmede deger buradaki sinirlarla
// denetlenir. Yeni bir ayar icin listeye satir eklemek yeterlidir (degeri
// okuyan yer Database::ayarSayiGetir / ayarMetniGetir'i kullanir). Tabloda
// satiri olmayan ayar varsayilan degeriyle gosterilir ve calisir.
//
// Iki tur var:
//   "sayi"  -> varsayilan / enAz / enFazla / ondalik / birim kullanilir.
//   "metin" -> uzun duz metin (ör. varsayilan satis sozlesmesi). Bos ya da
//              varsayilanMetin ile ayni deger kaydedilmez (NULL yazilir):
//              boylece koddaki fabrika metni guncellenirse ayar onu izler.
struct AyarTanimi
{
    QString anahtar;
    QString tur;        // "sayi" | "metin"
    QString grup;       // ekrandaki bolum basligi
    QString baslik;
    QString notMetni;   // bos olabilir
    QString birim;      // "%", "TL", "gün" (yalnizca sayi)
    double varsayilan;
    double enAz;
    double enFazla;
    int ondalik;
    QString varsayilanMetin;    // yalnizca metin
};

// Varsayilan satis sozlesmesi ayar anahtari (dil: "TR" / "EN").
QString sozlesmeAyarAnahtari(const QString &dil);

const QList<AyarTanimi> &ayarTanimlari();
// Bulunamazsa nullptr.
const AyarTanimi *ayarTanimiBul(const QString &anahtar);
