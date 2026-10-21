#pragma once

#include <QVariantList>
#include <QVariantMap>
#include <QString>

class QSqlDatabase;

// Teklif Ver ekranindaki canli arama (firma + urun) ile Musterilerim /
// Urunlerim / Personellerim ekranlarindaki SAYFALI liste sorgularinin SQL
// mantigi. Hem Database (ana baglanti, senkron cagri yolu) hem de AramaWorker
// (ayri thread + ayri baglanti, async yol) tarafindan paylasilir -- boylece
// sorgu SQL'i tek yerde tanimli kalir.

// ---- Teklif Ver: canli arama (ilk N eslesme) ----
QVariantList musteriAraSorgusu(QSqlDatabase &db, const QString &arama, int limit);
QVariantList urunAraSorgusu(QSqlDatabase &db, const QString &arama, int limit, const QString &dil);

// ---- Sayfali listeler ----
// Hepsi ayni sekilde doner: {"kayitlar", "toplamKayit", "toplamSayfa", "mevcutSayfa"}.
// Sayfalama ve filtreleme SQL Server tarafinda yapilir (COUNT + OFFSET/FETCH);
// hicbiri tum tabloyu bellege cekmez.
//
// "arsivliDahil" / "pasifDahil" false iken yalnizca aktif kayitlar donulur.
// Arsiv/pasif bayragi sutunu semada yoksa (db/13 calistirilmamissa) filtre
// sessizce uygulanmaz ve tum kayitlar aktif sayilir.

QVariantMap musteriListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                   int sayfaNo, int sayfaBoyutu, bool arsivliDahil);

QVariantMap urunListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                int sayfaNo, int sayfaBoyutu, bool arsivliDahil);

QVariantMap personelListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                    int sayfaNo, int sayfaBoyutu, bool pasifDahil);

// Satinalma / Tedarikcilerim: musteriListesiSorgusu ile ayni desen. Donen
// kayitlarin anahtarlari musteriyle ayni tutuldu (firmaAdi, firmaAdresi,
// firmaTelefonu, firmaEposta, ...) -- boylece QML formu paylasilabilir.
QVariantMap tedarikciListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                    int sayfaNo, int sayfaBoyutu, bool arsivliDahil);

// Personel ekle/duzenle formundaki rol secim listesi. Kucuk bir tablo olmasina
// ragmen asenkron yola tasindi: sunucu yogunken bu tek sorgu bile UI thread'ini
// 27 saniye bekletebiliyordu (bkz. gunlukteki [YAVAS] rolListesiGetir kaydi).
QVariantList rolListesiSorgusu(QSqlDatabase &db);

// ---- Gecmis Teklifler (Giden / Alinan / Biten Tekliflerim) ----
// Donen haritanin sekli ve kayit anahtarlari icin bkz. Database::gecmisTekliflerGetir.
// Bu sorgu da ayni dosyaya tasindi cunku UI thread'inde calistiginda
// (ozellikle arama metni varken: teklif_kalemleri uzerinde EXISTS + LIKE)
// pencereyi saniyelerce donduruyordu -- artik AramaWorker uzerinden async
// calisir (bkz. Database::gecmisTekliflerGetirBaslat).
QVariantMap teklifListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                 const QString &tarihFiltresi,
                                 const QString &baslangicTarihi,
                                 const QString &bitisTarihi,
                                 int sayfaNo, int sayfaBoyutu,
                                 const QString &durumFiltresi);
