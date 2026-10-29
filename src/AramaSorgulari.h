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

// Yonetim / Roller ve Yetkiler ekrani. Donen harita:
//   "moduller": [{modulId, modulKodu, modulAdi}]
//   "roller":   [{rolId, rolAdi, sistemRolu (bool), toplamKisi (int, pasifler dahil),
//                 aktifPersonel (QStringList, ad soyad),
//                 yetkiler: {"<modulId>": {gorebilir, duzenleyebilir}}}]
// Sorgu calismazsa BOS harita doner.
QVariantMap rolYetkiListesiSorgusu(QSqlDatabase &db);

// Yonetim / Sistem Ayarlari ekrani. Donen harita:
//   "tabloVar": dbo.ayarlar var mi (db/17),
//   "ayarlar":  [{anahtar, tur ("sayi"/"metin"), grup, baslik, notMetni,
//                 guncellemeTarihi (string, bos olabilir), ve
//                 sayi icin:  birim, deger (double), enAz, enFazla, ondalik;
//                 metin icin: metin (kayitli metin; bos = fabrika metni), varsayilanMetin}]
//               -- ayarTanimlari() sirasiyla.
// Sorgu calismazsa BOS harita doner.
QVariantMap ayarListesiSorgusu(QSqlDatabase &db);

// Yonetim / Ozet (pano): secilen donemin teklif sayilari ve kabul edilen
// tutarlar. "donem": "buAy" | "gecenAy" | "buYil" | "tumu" | "ozel"; "ozel"de
// ozelBaslangic / ozelBitis ("yyyy-MM-dd", iki gun de dahil). Donen harita:
//   donem, baslangic, bitis (dd.MM.yyyy; "tumu"de bos), verilen, kabul, red, bekleyen (int),
//   kabulOrani (double, %, kabul / verilen; donemde teklif yoksa -1),
//   kabulTutarlari: [{paraBirimi, adet, tutar}]  (KDV haric, kura cevrilmez),
//   personeller:    [{kullaniciId, adSoyad, verilen, kabul, red, bekleyen,
//                     tutarlar: [{paraBirimi, tutar}]}]
// Sayim kurallari sorgunun ustunde (AramaSorgulari.cpp). Hata: bos harita.
QVariantMap panoOzetiSorgusu(QSqlDatabase &db, const QString &donem,
                              const QString &ozelBaslangic, const QString &ozelBitis);

// Yonetim / Islem Gecmisi: tum tekliflerin olaylari (olusturma / revizyon,
// durum degisikligi, duzeltme), yeniden eskiye, sayfali.
// "suzgec": kullaniciId (int, 0 = hepsi), tur ("" | "olusturma" | "durum" |
//   "duzeltme"), baslangic / bitis ("yyyy-MM-dd", iki gun de dahil, bos olabilir),
//   arama (Teklif No ya da firma adi).
// Donen: kayitlar [{tur, teklifId, teklifNo, firmaAdi, personel, tarih
//   (dd.MM.yyyy HH:mm), baslik, aciklama}], toplamKayit, toplamSayfa,
//   mevcutSayfa, personeller [{kullaniciId, adSoyad, aktifMi}].
// Hata: bos harita.
QVariantMap islemGecmisiSorgusu(QSqlDatabase &db, const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu);

// Muhasebe karti: siparise donusmus ("Kabul Edildi" / "Tamamlandı") teklifler.
// "suzgec": sekme ("faturalanacak" -> fatura no bos | "faturalanan"),
//   durum ("" | "Kabul Edildi" | "Tamamlandı"), arama (Teklif No ya da firma).
// Donen: kayitlar [{teklifId, teklifNo, firmaAdi, durum, kabulTarihi,
//   teslimatTarihi, teslimTarihi (dd.MM.yyyy), paraBirimi, genelToplam,
//   faturaDurumu ("eksik" | "hazir" | "faturalandi"), faturaNo, irsaliyeNo,
//   faturaTarihi (dd.MM.yyyy), personel}], toplamKayit, toplamSayfa,
//   mevcutSayfa. db/30 yoksa {hata}.
QVariantMap muhasebeListesiSorgusu(QSqlDatabase &db, const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu);

// Cihaz Maliyetleri listesi: [{cihazId, cihazAdi, karOrani, toplamMaliyetTL,
// satisFiyatiTL, aktifMi, kalemSayisi, guncellemeTarihi (dd.MM.yyyy),
// katalogFiyat (double veya null), katalogParaBirimi}]. db/17 yoksa bos.
QVariantList cihazListesiSorgusu(QSqlDatabase &db, const QString &arama, bool arsivDahil);

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
