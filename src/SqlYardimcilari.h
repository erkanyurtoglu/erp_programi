#pragma once

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
