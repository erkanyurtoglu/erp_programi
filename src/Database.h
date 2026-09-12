#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QThread>
#include <QPointer>

#include "TeklifPdfOlusturucu.h"

class AramaWorker;

// Database: SQL Server'daki yeni "LiyaErpVeriTabani" veritabanina QODBC ile
// baglanir ve QML ekranlarinin ihtiyac duydugu sorgulari Q_INVOKABLE metodlar olarak sunar.
//
// Onemli tasarim karari: WPF tarafinda 20 bin kayitta donma yasandigi icin oradaki
// GecmisTekliflerViewModel'i sayfalama + SQL tarafinda filtreleme yapacak sekilde
// yeniden yazmistik. Burada da ayni prensip gecerli: hicbir metot tum tabloyu
// bellege cekmez; filtreleme (WHERE) ve sayfalama (OFFSET/FETCH) SQL Server'da yapilir.
class Database : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool baglantiHazir READ baglantiHazirMi CONSTANT)

public:
    explicit Database(QObject *parent = nullptr);
    ~Database() override;

    bool baglantiHazirMi() const { return m_baglantiHazir; }
    QString sonHataMesaji() const { return m_sonHataMesaji; }

    // Giris ekrani icin kimlik dogrulama.
    // Donen QVariantMap anahtarlari:
    //   "basarili" (bool), "hata" (string, basarisizsa),
    //   "kullaniciId" (int), "adSoyad" (string), "kullaniciAdi" (string),
    //   "moduller" (QVariantList<QVariantMap{modulKodu, modulAdi, duzenleyebilir}>)
    //     -> kullanicinin GOREBILDIGI moduller; "duzenleyebilir" o modulde
    //        duzenleme yetkisi olup olmadigini belirtir (roller birlesik/OR'lanmis halde).
    Q_INVOKABLE QVariantMap girisYap(const QString &kullaniciAdi, const QString &sifre);

    // Gecmis Teklifler ekrani icin filtrelenmis + sayfalanmis liste. "Giden Tekliflerim"
    // durumdan bagimsiz TUM kayitlari gosterir (durumFiltresi bos birakilir); "Alinan
    // Tekliflerim" / "Biten Tekliflerim" sekmeleri ayni metodu durumFiltresi ile cagirir
    // ("Kabul Edildi" / "Tamamlandi").
    // Donen QVariantMap anahtarlari: "kayitlar" (QVariantList<QVariantMap>,
    // her kayitta ayrica "anaTeklifId" (int, 0 ise orijinal teklif) ve
    // "revizyonNo" (int, 0 ise orijinal) da bulunur -- bkz. teklifKaydet),
    // "toplamKayit" (int), "toplamSayfa" (int), "mevcutSayfa" (int).
    Q_INVOKABLE QVariantMap gecmisTekliflerGetir(const QString &arama,
                                                  const QString &tarihFiltresi,
                                                  const QString &baslangicTarihi,
                                                  const QString &bitisTarihi,
                                                  int sayfaNo,
                                                  int sayfaBoyutu = 50,
                                                  const QString &durumFiltresi = QString());

    // Tek bir teklifi kalicalarak siler. Basariliysa true doner.
    Q_INVOKABLE bool teklifSil(int teklifId);

    // Teklif Ver ekrani: musteri/urun arama (canli, kucuk sonuc kumesi -- LIKE ile
    // ilk N eslesme). arama bos ise en son eklenen N kayit donulur (listeyi tamamen
    // bos gostermemek icin).
    //
    // ONEMLI: Bu ikisi ASYNC calisir (ayri bir thread + ayri SQL baglantisi
    // uzerinde) -- QML tarafinda sonuc DOGRUDAN donmez, calisma bitince
    // musteriSonuclariHazir/urunSonuclariHazir sinyali gelir. Boylece yazarken
    // (veya sayfa acilirken) SQL Server yavas/erisilemez olsa bile UI thread'i
    // bloke olmaz -- WPF tarafinda da benzer sekilde arka planda calistirilirdi.
    Q_INVOKABLE void musteriAraBaslat(const QString &arama, int limit = 20);
    // "dil": "TR" veya "EN". EN secilirse UrunAciklamasiEn doner (bossa TR'ye
    // otomatik geri duser, boylece EN cevirisi girilmemis urunler bos gorunmez).
    Q_INVOKABLE void urunAraBaslat(const QString &arama, int limit = 30, const QString &dil = QString("TR"));

    // Yeni bir teklifi (teklifler + teklif_kalemleri + teklif_toplamlari) TEK
    // transaction icinde kaydeder. "teklif" QVariantMap anahtarlari:
    //   musteriId (int), kullaniciId (int), genelIndirimOrani, kdvOrani (double),
    //   paketlemeUcreti, tasimaUcreti (double), paraBirimi (string: TL/USD/EUR),
    //   dil (string: TR/EN), ilgiliKisi, ilgiliKisiTelefonu, ilgiliKisiEposta,
    //   teslimatSekli, teslimatYeri, musteriNotu (string),
    //   indirimliToplam, kdvTutari, genelToplam (double, QML tarafinda hesaplanmis),
    //   kalemler (QVariantList<QVariantMap{urunId (0 ise manuel kalem), urunKodu,
    //             aciklama, adet, birimFiyat, indirimliBirimFiyat, toplamTutar,
    //             maliyetFiyati, paraBirimi, kur}>),
    //   anaTeklifId (int, OPSIYONEL): >0 verilirse bu YENI teklif, o teklifin
    //             (veya zaten bir revizyonsa onun kok teklifinin) bir REVIZYONU
    //             olarak kaydedilir -- orijinal teklif SATIRI hic degismez/silinmez,
    //             sadece yeni bir TeklifId ile AnaTeklifId/RevizyonNo doldurulmus
    //             ayri bir kayit eklenir. Bos/0 birakilirsa (normal "Teklif Ver"
    //             akisi) eskisi gibi tamamen bagimsiz, AnaTeklifId'si NULL bir
    //             teklif olusur -- davranis degismez.
    // Donen QVariantMap: "basarili" (bool), "teklifId" (int), "hata" (string).
    Q_INVOKABLE QVariantMap teklifKaydet(const QVariantMap &teklif);

    // Giden/Alınan/Biten Tekliflerim'deki "Detay" butonu icin: bir teklifin
    // KAYITLI TUM verisini, Teklif Ver ekranini (TeklifVerPage.duzenlemeyeBasla)
    // AYNEN DOLDURACAK sekilde geri doner -- boylece "Detay" o teklifi Teklif Ver
    // ekraninda acar, kullanici degisiklik yapip kaydedince teklifKaydet()'e
    // anaTeklifId ile bir REVIZYON olarak gonderilir.
    // Donen QVariantMap anahtarlari: "basarili" (bool), "hata" (string),
    //   "teklifId", "anaTeklifId" (int, kok teklif; revizyon degilse teklifId'nin
    //   kendisi), "revizyonNo" (int), "musteriId" (int), "musteriAdi",
    //   "genelIndirimOrani", "kdvOrani", "paraBirimi", "dil", "ilgiliKisi",
    //   "ilgiliKisiTelefonu", "ilgiliKisiEposta", "teslimatSekli", "teslimatYeri",
    //   "paketlemeUcretiTl", "tasimaUcretiTl", "kur" (double, TL'ye cevirmek icin),
    //   "kalemler" (QVariantList<QVariantMap{urunId (0 ise manuel), urunKodu,
    //             aciklama, adet (int), birimFiyatTl, maliyet (double)}>).
    Q_INVOKABLE QVariantMap teklifDuzenlemeVerisiGetir(int teklifId);

    // Teklifin durumunu degistirir. Gecerli durumlar: "Beklemede", "Kabul Edildi",
    // "Reddedildi", "Tamamlandı" (bkz. gecerliDurumlar()).
    //
    // ONEMLI: Gecisler TEK YONLU DEGILDIR -- musteri once kabul edip sonra
    // vazgecebilir ("Kabul Edildi" -> "Reddedildi"), kararsiz kalip bekletebilir
    // ("Kabul Edildi" -> "Beklemede"), yanlislikla tamamlanmis bir teklif geri
    // alinabilir ("Tamamlandı" -> "Kabul Edildi"). Bu yuzden her gecis, YENI
    // duruma ait tarihi yazarken ARTIK GECERSIZ olan durum alanlarini da temizler
    // (ornegin "Reddedildi"den "Beklemede"ye donuste RedTarihi/RedSebebi NULL'lanir);
    // aksi halde listelerde ve PDF'lerde birbiriyle celisen tarihler kalirdi.
    //
    // Alanlar ustune yazildigi icin gecmis kaybolmasin diye her degisim ayrica
    // dbo.teklif_durum_gecmisi tablosuna loglanir (bkz. db/05_teklif_durum_gecmisi.sql).
    // Loglama "best effort"tur: tablo yoksa/yazilamazsa durum guncellemesi yine basarili sayilir.
    //
    // redSebebi yalnizca "Reddedildi" gecisinde kullanilir; kullaniciId 0 ise log
    // satirina NULL yazilir.
    Q_INVOKABLE bool teklifDurumGuncelle(int teklifId, const QString &durum,
                                         const QString &redSebebi = QString(),
                                         int kullaniciId = 0);

    // Bir teklifin durum degisim gecmisi (en yeni ustte). Her eleman:
    // {"eskiDurum", "yeniDurum", "aciklama", "personel", "tarih"} (hepsi string).
    // Tablo henuz olusturulmadiysa bos liste doner (hata degil).
    Q_INVOKABLE QVariantList teklifDurumGecmisiGetir(int teklifId);

    // QML'deki durum menusunun beslendigi tek kaynak; boylece gecerli durum
    // listesi C++ ile QML arasinda ikiye bolunmez.
    Q_INVOKABLE QStringList gecerliDurumlar() const;

    // ------------------------------------------------------------------
    // Musterilerim / Urunlerim (WPF'teki Firmalarim + Urunlerim ekranlarinin
    // Qt/QML karsiligi). Ayni sayfalama deseni: COUNT + OFFSET/FETCH.
    // Donen "liste" QVariantMap'leri gecmisTekliflerGetir ile ayni sekle sahip:
    // "kayitlar", "toplamKayit", "toplamSayfa", "mevcutSayfa".
    // ------------------------------------------------------------------
    Q_INVOKABLE QVariantMap musteriListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu = 50);

    // "musteri" anahtarlari: firmaAdi, firmaAdresi, firmaTelefonu, firmaEposta,
    // vergiDairesi, vergiNumarasi, ilgiliKisi, ilgiliKisiTelefonu.
    // Donen: {basarili, musteriId, hata}.
    Q_INVOKABLE QVariantMap musteriEkle(const QVariantMap &musteri);
    Q_INVOKABLE QVariantMap musteriGuncelle(int musteriId, const QVariantMap &musteri);
    // Donen: {basarili, hata}. Bu musteriye ait teklif(ler) varsa FK kisitlamasi
    // nedeniyle basarisiz olur -- hata alaninda kullaniciya anlasilir mesaj doner.
    Q_INVOKABLE QVariantMap musteriSil(int musteriId);

    Q_INVOKABLE QVariantMap urunListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu = 50);

    // "urun" anahtarlari: urunKodu, kategori, urunAciklamasi, urunAciklamasiEn,
    // birimFiyat (TL), maliyet (TL). ParaBirimi her zaman 'TL' olarak kaydedilir
    // (goc kararinda alindigi gibi -- fiyatlar tek para biriminde tutulur,
    // USD/EUR gosterimi ekran tarafinda kur ile hesaplanir).
    // Donen: {basarili, urunId, hata}.
    Q_INVOKABLE QVariantMap urunEkle(const QVariantMap &urun);
    Q_INVOKABLE QVariantMap urunGuncelle(int urunId, const QVariantMap &urun);
    // Donen: {basarili, hata}. Bu urunu iceren teklif_kalemleri varsa FK
    // kisitlamasi nedeniyle basarisiz olur -- hata alaninda kullaniciya
    // anlasilir mesaj doner.
    Q_INVOKABLE QVariantMap urunSil(int urunId);

    // ------------------------------------------------------------------
    // Personellerim (WPF'teki Personellerim + PersonelEkle/PersonelDetayWindow
    // karsiligi). Kullanicilar + rolleri birlikte yonetilir. Kalici DELETE
    // yerine AktifMi bayragi kullaniliyor -- bir personel silinirse ona ait
    // gecmis tekliflerin KullaniciId referansi kirilmasin diye (ON DELETE yok).
    // ------------------------------------------------------------------
    Q_INVOKABLE QVariantList rolListesiGetir();

    // "kayitlar" icindeki her personel: kullaniciId, adSoyad, kullaniciAdi,
    // telefon, pozisyon, aktifMi, rolIdListesi (QVariantList<int>), rolAdlari (string, virgullu).
    Q_INVOKABLE QVariantMap personelListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu = 50);

    // "personel" anahtarlari: adSoyad, kullaniciAdi, sifre (bos ise -- sadece
    // guncellemede -- sifre degistirilmez), telefon, pozisyon, rolIdListesi (QVariantList<int>).
    // Donen: {basarili, kullaniciId, hata}.
    Q_INVOKABLE QVariantMap personelEkle(const QVariantMap &personel);
    Q_INVOKABLE QVariantMap personelGuncelle(int kullaniciId, const QVariantMap &personel);
    Q_INVOKABLE bool personelAktifDurumDegistir(int kullaniciId, bool aktif);

    // Teklif Ver + Giden Tekliflerim ekranlarindan PDF uretimi. SQL sorgularini burada
    // calistirir, sonucu TeklifPdfOlusturucu'ya devreder (HTML/PDF uretiminin tamami
    // orada); dosya Belgelerim/Liya ERP Teklifler altina kaydedilir.
    // Donen: {basarili, dosyaYolu, hata}.
    Q_INVOKABLE QVariantMap teklifPdfOlustur(int teklifId);

    // Teklif Ver ekranindaki "Satış Sözleşmesi" butonu icin: HENUZ KAYDEDILMEMIS
    // (formda doldurulmus) teklif verisinden basit bir satis sozlesmesi PDF'i
    // uretir -- teklifin veritabaninda var olmasini gerektirmez. "teklif" ayni
    // teklifKaydet() anahtarlarini kullanir (musteriId yerine musteriAdi da
    // kabul edilir, cunku musteri henuz kaydedilmemis/secilmemis olabilir).
    // Donen: {basarili, dosyaYolu, hata}.
    Q_INVOKABLE QVariantMap satisSozlesmesiOlustur(const QVariantMap &teklif);

    // musteriAraBaslat/urunAraBaslat icin sonuc sinyalleri. "arama" (ve urun icin
    // "dil") istegi yapan tarafa aynen geri gonderilir; QML tarafi bunu arama
    // kutusunun O ANKI metniyle karsilastirip eskimis sonuclari gormezden gelir.
    Q_SIGNAL void musteriSonuclariHazir(const QString &arama, const QVariantList &sonuclar);
    Q_SIGNAL void urunSonuclariHazir(const QString &arama, const QString &dil, const QVariantList &sonuclar);

    // AramaWorker (ve ana baglanti) tarafindan paylasilan ODBC baglanti-acma mantigi.
    // "baglantiAdi", ayni isimde birden fazla QSqlDatabase baglantisi acilabilmesi
    // icin (ana baglanti + arama worker'inin kendi baglantisi) benzersiz olmalidir.
    static bool baglantiAc(QSqlDatabase &db, const QString &baglantiAdi, QString &hataMesajiOut);

private:
    bool baglan();
    // Ortak WHERE kosullarini (tarih + arama filtresi + durum filtresi) hem COUNT
    // hem de veri sorgusunda ayni sekilde kullanabilmek icin tek yerde uretir.
    void whereKosullariniOlustur(const QString &arama,
                                  const QString &tarihFiltresi,
                                  const QString &baslangicTarihi,
                                  const QString &bitisTarihi,
                                  const QString &durumFiltresi,
                                  QString &whereClauseOut,
                                  QVariantMap &parametrelerOut) const;

    // Kullanicinin gorebildigi modul listesini (roller birlesik) getirir.
    QVariantList kullaniciModulleriniGetir(int kullaniciId);

    // teklifDurumGuncelle'nin gecmis kaydi; hata durumunda sadece uyari basar
    // (bkz. .cpp icindeki "best effort" notu).
    void durumDegisiminiLogla(int teklifId, const QString &eskiDurum, const QString &yeniDurum,
                              const QString &aciklama, int kullaniciId);

    QSqlDatabase m_db;
    bool m_baglantiHazir = false;
    QString m_sonHataMesaji;

    // Firma/urun canli aramasini UI thread'inden ayirmak icin: worker, kendi
    // QSqlDatabase baglantisiyla bu ayri thread uzerinde yasar (bkz. AramaWorker.h).
    QThread m_aramaThread;
    QPointer<AramaWorker> m_aramaWorker;

    TeklifPdfOlusturucu m_pdfOlusturucu;
};
