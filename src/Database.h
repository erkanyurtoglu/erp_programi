#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QElapsedTimer>
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
    // Q_INVOKABLE: false donen islemlerin (ornegin revize edilmis teklifin durumunu
    // degistirmeye calismak) sebebini QML kullaniciya aynen gosterebilsin diye.
    Q_INVOKABLE QString sonHataMesaji() const { return m_sonHataMesaji; }

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
    // her kayitta ayrica "anaTeklifId" (int, 0 ise orijinal teklif),
    // "revizyonNo" (int, 0 ise orijinal) ve revizyon zincirinin EN SON kaydini
    // gosteren "guncelTeklifId"/"guncelRevizyonNo" (int) da bulunur; durumu
    // "Revize Edildi" olan satirda bu ikisi o teklifin YERINE GECEN teklifi
    // isaret eder -- bkz. teklifKaydet),
    // Her kayitta ayrica "kopyaKaynakTeklifId" (int, 0 ise elle olusturulmus)
    // bulunur: bu teklif baska bir teklifin KOPYASI olarak olusturulduysa
    // kaynagin TeklifId'si (bkz. teklifKaydet / db/07_teklif_kopya_kaynagi.sql).
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
    //   teslimatTarihi (string, "yyyy-MM-dd" veya bos): PLANLANAN teslim tarihi,
    //             TeslimatTarihi sutununa yazilir (gercek teslim tarihi olan
    //             TeslimTarihi ise "Tamamlandı" durumunda otomatik dolar),
    //   sozlesmeMetni (string, OPSIYONEL): "Satış Sözleşmesi" penceresinde
    //             duzenlenmis sozlesme maddeleri. Bos gelirse SatisSozlesmesiMetni
    //             NULL kaydedilir ve PDF'te dilin varsayilan metni kullanilir.
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
    //   kopyaKaynakTeklifId (int, OPSIYONEL): >0 verilirse bu yeni teklif, o
    //             teklifin KOPYASI olarak olusturulmus demektir; deger yalnizca
    //             iz olarak KopyaKaynakTeklifId sutununa yazilir. Revizyondan
    //             farki: hicbir is kurali tetiklenmez -- kaynak teklife
    //             DOKUNULMAZ, "Revize Edildi" yapilmaz, zincire baglanmaz; kayit
    //             her yonuyle bagimsiz yeni bir teklif olur (AnaTeklifId NULL,
    //             RevizyonNo 0). anaTeklifId ile birlikte gelirse (olmamasi
    //             gereken bir durum) revizyon kazanir, kopya izi yazilmaz.
    //             KopyaKaynakTeklifId sutunu veritabaninda yoksa (07 numarali
    //             script calistirilmamissa) kayit normal sekilde olusur, sadece
    //             iz tutulmaz.
    //
    // REVIZYON = ESKISINI GECERSIZ KILAR: bir revizyon kaydedildiginde ayni koke
    // bagli ONCEKI teklifler (kok + eski revizyonlar) "Revize Edildi" durumuna
    // alinir. Boylece musteriye gonderilmis eski teklif ile yeni revizyon ayni
    // anda gecerliymis gibi gorunmez; eski kayit listede ayirt edilir ve PDF'i
    // yeniden uretilirse ustune "gecerli degildir" bandi basilir. Kilitli
    // (Kabul Edildi / Tamamlandı) teklifler bu isaretlemenin DISINDADIR.
    // Donen QVariantMap: "basarili" (bool), "teklifId" (int), "hata" (string),
    //   "revizeEdilenTeklifIdler" (QVariantList<int>, bu kayit yuzunden
    //   "Revize Edildi" durumuna alinan eski tekliflerin id'leri; bos olabilir).
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
    //             aciklama, adet (int), birimFiyatTl, maliyet (double)}>),
    //   "sozlesmeMetni" (string; teklife ozel bir sozlesme metni kaydedilmemisse bos),
    //   "musteriNotu" (string, teklif notu), "uretimNotu" (string),
    //   "teslimatTarihi" (string, "yyyy-MM-dd" veya bos), "durum" (string).
    //
    // AYNI metot "Kopya" akisinda da kullanilir (bkz. TeklifVerPage.kopyalamayaBasla):
    // orada donen veri ayni sekilde forma doldurulur, ancak musteriye/teklife ozel
    // alanlar (musteri, ilgili kisi, notlar, teslim tarihi, durum) QML tarafinda
    // bosaltilir ve kayit anaTeklifId YERINE kopyaKaynakTeklifId ile gonderilir.
    // Bu metot hicbir sey YAZMADIGI icin kilitli teklifte de guvenle cagrilabilir.
    Q_INVOKABLE QVariantMap teklifDuzenlemeVerisiGetir(int teklifId);

    // KILIT KURALI: "Kabul Edildi" ve "Tamamlandı" durumundaki teklifler
    // kilitlidir -- kabul edilmis bir teklifin icerigi (teklif notu, sozlesme
    // metni) degistirilemez, teklif silinemez. Durum degisikligi (teklifDurumGuncelle)
    // bu kuralin disindadir; gerekirse teklif once "Beklemede"ye alinir.
    //
    // Istisna: planlanan teslim tarihi ve uretim notu teklifin ticari icerigi
    // degil, uretim planlamasidir ve genelde kabulden SONRA belli olur -- bu yuzden
    // "Kabul Edildi"de de yazilabilir, yalnizca "Tamamlandı"da kilitlenir.
    //
    // Asagidaki uc metot kayitli teklifi YERINDE gunceller (revizyon olusturmaz);
    // kilitli teklifte false doner.
    // teslimatTarihi: "yyyy-MM-dd" veya bos (bos -> NULL). Basariliysa true.
    Q_INVOKABLE bool teklifTeslimatTarihiGuncelle(int teklifId, const QString &teslimatTarihi);
    // Teklif notu (MusteriNotu): yalnizca satis tarafinda gorunur, uretim PDF'ine basilmaz.
    Q_INVOKABLE bool teklifMusteriNotuGuncelle(int teklifId, const QString &musteriNotu);
    // Uretim notu (UretimNotu): uretim PDF'ine basilir.
    Q_INVOKABLE bool teklifUretimNotuGuncelle(int teklifId, const QString &uretimNotu);

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
    //
    // REVIZE EDILMIS TEKLIF DEGISTIRILEMEZ: durumu "Revize Edildi" olan ve zincirde
    // kendisinden daha yeni bir revizyonu BULUNAN teklif icin bu metot false doner
    // (sebep sonHataMesaji()'nda). Aksi halde teklifin eski surumu "Kabul Edildi"
    // olurken guncel surumu "Beklemede" kalabilir, yani ayni teklifin iki fiyatli
    // surumu ayni anda gecerli gorunurdu. Yeni revizyon silinmisse kayit yeniden
    // zincirin sonu olur ve normal sekilde islenebilir.
    Q_INVOKABLE bool teklifDurumGuncelle(int teklifId, const QString &durum,
                                         const QString &redSebebi = QString(),
                                         int kullaniciId = 0);

    // Bir teklifin durum degisim gecmisi (en yeni ustte). Her eleman:
    // {"eskiDurum", "yeniDurum", "aciklama", "personel", "tarih"} (hepsi string).
    // Tablo henuz olusturulmadiysa bos liste doner (hata degil).
    Q_INVOKABLE QVariantList teklifDurumGecmisiGetir(int teklifId);

    // QML'deki durum menusunun beslendigi tek kaynak; boylece gecerli durum
    // listesi C++ ile QML arasinda ikiye bolunmez.
    //
    // NOT: "Revize Edildi" bu listede YOKTUR -- elle secilen bir durum degildir,
    // yalnizca teklifKaydet bir revizyon olustururken sistem tarafindan yazilir.
    // Bu durumdaki bir teklifin durumu elle DEGISTIRILEMEZ de (bkz.
    // teklifDurumGuncelle notu); islem her zaman guncel revizyon uzerinden yapilir.
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

    // Teklif Ver ekranindaki sepet satirinda maliyet elle degistirildiginde
    // cagrilir: girilen maliyet yalnizca o teklifin kalemine yazilmaz, urunun
    // KATALOGDAKI guncel maliyeti de (dbo.urunler.GuncelMaliyetTL) ayni degere
    // cekilir -- boylece ayni urun bir sonraki teklife de guncel maliyetiyle
    // gelir. Urunun diger alanlarina (kod, aciklama, birim fiyat) dokunmaz.
    //
    // maliyetTl TL olmalidir: katalog maliyeti her zaman TL tutulur (bkz.
    // urunEkle notu), teklif ekrani ise tutarlari secili para biriminde
    // gosterir -- cagiran taraf degeri TL'ye cevirip gonderir.
    //
    // Manuel kalemler icin olusturulan "MANUEL-<teklifId>" kodlu gecici satirlar
    // katalog urunu degildir; bu metot onlari bilincli olarak disarida birakir
    // (urunId <= 0 olan manuel kalemler zaten buraya hic gelmez).
    // Guncelleme yapildiysa true; urun bulunamazsa/manuelse veya SQL hatasi
    // olursa false doner (hata varsa sebebi sonHataMesaji()'nda).
    Q_INVOKABLE bool urunMaliyetiGuncelle(int urunId, double maliyetTl);

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

    // Alınan/Biten Tekliflerim'deki "Üretim" butonu: teknik ekibe verilecek
    // FIYATSIZ PDF (kapak ve sozlesme sayfasi yok; firma/teslimat/tarih bilgileri,
    // urun kodu/aciklama/adet ve uretim notu var; teklif notu YOK). Basariliysa teklifin
    // UretimPdfTarihi alani simdiki zamanla doldurulur -- bu alan SADECE burada
    // yazilir (normal teklif PDF'i ona dokunmaz).
    // Donen: {basarili, dosyaYolu, hata}.
    Q_INVOKABLE QVariantMap uretimPdfOlustur(int teklifId);

    // Teklif Ver ekranindaki "Satış Sözleşmesi" butonu icin: HENUZ KAYDEDILMEMIS
    // (formda doldurulmus) teklif verisinden basit bir satis sozlesmesi PDF'i
    // uretir -- teklifin veritabaninda var olmasini gerektirmez. "teklif" ayni
    // teklifKaydet() anahtarlarini kullanir (musteriId yerine musteriAdi da
    // kabul edilir, cunku musteri henuz kaydedilmemis/secilmemis olabilir).
    // Donen: {basarili, dosyaYolu, hata}.
    Q_INVOKABLE QVariantMap satisSozlesmesiOlustur(const QVariantMap &teklif);

    // ------------------------------------------------------------------
    // Satis sozlesmesi metni (teklif PDF'inin son sayfasindaki maddeler).
    //
    // Metin artik teklif.html icine GOMULU DEGIL: varsayilani C++ tarafinda
    // (TeklifPdfOlusturucu::varsayilanSozlesmeMetni) duruyor, kullanicinin
    // "Satış Sözleşmesi" penceresinde yaptigi degisiklik ise TEKLIF BASINA
    // dbo.teklifler.SatisSozlesmesiMetni sutununda saklaniyor. Boylece eski
    // tekliflerin sozlesmesi, varsayilan metin ileride degistirilse bile
    // kaydedildigi haliyle kalir.
    //
    // "dil": "TR" veya "EN" -- varsayilan metnin dilini secer.
    // ------------------------------------------------------------------
    Q_INVOKABLE QString varsayilanSozlesmeMetni(const QString &dil) const;

    // Teklife kayitli metni doner; yoksa (veya teklif henuz kaydedilmemisse,
    // yani teklifId <= 0 ise) dilin varsayilan metnini doner -- pencere her
    // durumda dolu acilir.
    Q_INVOKABLE QString teklifSozlesmeMetniGetir(int teklifId, const QString &dil);

    // Kayitli bir teklifin sozlesme metnini gunceller ("Satış Sözleşmesi"
    // penceresi, Giden Tekliflerim -> Detay akisinda acildiginda). metin bos
    // ise sutun NULL'lanir (varsayilana doner). Basariliysa true.
    Q_INVOKABLE bool teklifSozlesmeMetniKaydet(int teklifId, const QString &metin);

    // ------------------------------------------------------------------
    // Sevk ve irsaliye bilgileri (Alınan/Biten Tekliflerim'deki "İrsaliye"
    // butonu; WPF'teki SevkBilgileriWindow'un karsiligi).
    //
    // Siparis kesinlestikten SONRA netlesen bilgiler burada tutulur: faturanin
    // ve irsaliyenin hangi baslik/adres/vergi bilgileriyle kesilecegi, siparis
    // sartlari (KDV, fatura sekli, garanti, teslimat, odeme, nakliye,
    // kalibrasyon, egitim, referans no, ek fatura notu, siparis tarihi) ve
    // sevkiyat aciklamasi. Satis personeli ile buro personeli ayni kaydi
    // doldurur, sonradan ayni pencereden okur.
    //
    // dbo.sevk_bilgileri.TeklifId UNIQUE oldugu icin teklif basina TEK kayit
    // vardir (bkz. db/01_yeni_veritabani_ve_sema.sql). Aciklamalar alani ayrica
    // teklif listesindeki "AÇIKLAMALAR" sutununu besler (gecmisTekliflerGetir).
    // ------------------------------------------------------------------

    // Kayitli sevk bilgilerini doner. Kayit (veya bir alan) yoksa FATURA
    // bilgileri musteri kartindan ve teklifin ilgili kisisinden, KDV ise
    // teklifin KDV oranindan ON DOLDURULUR -- bu degerler yalnizca formda
    // gosterilir, kullanici "Kaydet" demeden veritabanina YAZILMAZ.
    // Donen QVariantMap: "basarili" (bool), "hata" (string),
    //   "kayitVarMi" (bool; false ise form tamamen on doldurulmus demektir),
    //   ve alanlar: faturaBasligi, faturaAdresi, faturaVergiDairesi,
    //   faturaVergiNo, faturaYetkili, faturaTelefon, faturaFax, faturaEposta,
    //   irsaliyeBasligi, irsaliyeAdresi, irsaliyeVergiDairesi, irsaliyeVergiNo,
    //   irsaliyeYetkili, irsaliyeTelefon, irsaliyeEposta, siparisKdv,
    //   faturaSekli, garanti, teslimat, odeme, nakliye, kalibrasyon, egitim,
    //   referansNumarasi, ekFaturaNotu, aciklamalar (hepsi string),
    //   "siparisTarihi" (string, "yyyy-MM-dd" veya bos).
    Q_INVOKABLE QVariantMap sevkBilgileriGetir(int teklifId);

    // Formdaki alanlari teklifin TEK sevk kaydina yazar (kayit yoksa olusturur,
    // varsa gunceller). Bos birakilan alanlar NULL kaydedilir.
    //
    // KILIT KURALI: bu bilgiler kabulden sonra netlestigi icin "Kabul Edildi"
    // teklifte serbestce doldurulur; is bitip teklif "Tamamlandı"ya gectikten
    // sonra degistirilemez (planlanan teslim tarihi / uretim notuyla ayni kural,
    // bkz. teklifTeslimatTarihiGuncelle ustundeki not).
    // Donen: {basarili (bool), hata (string)}.
    Q_INVOKABLE QVariantMap sevkBilgileriKaydet(int teklifId, const QVariantMap &sevk);

    // musteriAraBaslat/urunAraBaslat icin sonuc sinyalleri. "arama" (ve urun icin
    // "dil") istegi yapan tarafa aynen geri gonderilir; QML tarafi bunu arama
    // kutusunun O ANKI metniyle karsilastirip eskimis sonuclari gormezden gelir.
    Q_SIGNAL void musteriSonuclariHazir(const QString &arama, const QVariantList &sonuclar);
    Q_SIGNAL void urunSonuclariHazir(const QString &arama, const QString &dil, const QVariantList &sonuclar);

    // AramaWorker (ve ana baglanti) tarafindan paylasilan ODBC baglanti-acma mantigi.
    // "baglantiAdi", ayni isimde birden fazla QSqlDatabase baglantisi acilabilmesi
    // icin (ana baglanti + arama worker'inin kendi baglantisi) benzersiz olmalidir.
    static bool baglantiAc(QSqlDatabase &db, const QString &baglantiAdi, QString &hataMesajiOut);

    // Her sorgudan once cagrilir. Baglanti bir sure bosta kaldiysa (bilgisayar uykuya
    // gecti, Wi-Fi koptu, SQL Server yeniden basladi...) "SELECT 1" ile yoklar; kopmussa
    // baglantiyi kapatip yeniden acar. Eskiden kopmus baglanti hic yenilenmiyordu:
    // sonraki her sorgu TCP zaman asimina kadar UI thread'ini bekletip "Yanıt Vermiyor"a
    // dusuruyordu. Basarisiz yeniden baglanma denemeleri sonDeneme ile seyreltilir ki
    // sunucu erisilemezken her tiklamada tekrar tekrar login zaman asimi beklenmesin.
    static bool baglantiyiHazirla(QSqlDatabase &db, const QString &baglantiAdi,
                                  QElapsedTimer &sonKullanim, QElapsedTimer &sonDeneme,
                                  QString &hataMesajiOut);

private:
    bool baglan();
    // baglantiyiHazirla()'nin ana baglanti icin kisayolu; m_baglantiHazir'i gunceller.
    bool baglantiHazir();
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

    // teklifPdfOlustur ve uretimPdfOlustur'un ortak kismi: teklifin baslik +
    // kalem verisini TeklifPdfOlusturucu'nun bekledigi "veri" haritasina okur.
    // Basarisizsa false doner ve hataOut doldurulur.
    bool pdfVerisiniOku(int teklifId, QString &firmaAdiOut, QVariantMap &veriOut, QString &hataOut);

    // teklifDurumGuncelle'nin gecmis kaydi; hata durumunda sadece uyari basar
    // (bkz. .cpp icindeki "best effort" notu).
    void durumDegisiminiLogla(int teklifId, const QString &eskiDurum, const QString &yeniDurum,
                              const QString &aciklama, int kullaniciId);

    // Kilit kurali (bkz. teklifTeslimatTarihiGuncelle ustundeki not): "Kabul Edildi"
    // ve "Tamamlandı" teklifler kilitlidir.
    static bool teklifKilitliMi(const QString &durum);
    // Teklifin guncel durumu; teklif bulunamazsa bos string.
    QString teklifDurumuGetir(int teklifId);
    // dbo.teklifler.KopyaKaynakTeklifId sutunu var mi? (db/07_teklif_kopya_kaynagi.sql
    // calistirilmadiysa yoktur.) Sonuc bir kez sorgulanip saklanir -- script
    // program acikken calistirilirsa programin yeniden baslatilmasi gerekir. Kolon yoksa
    // "Kopya" akisi calismaya devam eder, yalnizca kaynak izi yazilmaz/okunmaz --
    // yani eksik script yuzunden teklif listesi veya kayit akisi BOZULMAZ.
    bool kopyaKolonuVarMi();

    // Bu teklifin YERINE GECEN (ayni revizyon zincirinde daha yeni) teklifin
    // TeklifId'si; zincirin en son uyesi buysa 0. Revize edilmis bir teklif
    // uzerinde islem yapilip yapilamayacagi buna gore belirlenir.
    int teklifYerineGecenIdGetir(int teklifId);

    QSqlDatabase m_db;
    bool m_baglantiHazir = false;
    QString m_sonHataMesaji;
    QElapsedTimer m_sonKullanim;
    QElapsedTimer m_sonBaglantiDenemesi;

    // kopyaKolonuVarMi() onbellegi: -1 henuz sorgulanmadi, 0 yok, 1 var.
    int m_kopyaKolonuDurumu = -1;

    // Firma/urun canli aramasini UI thread'inden ayirmak icin: worker, kendi
    // QSqlDatabase baglantisiyla bu ayri thread uzerinde yasar (bkz. AramaWorker.h).
    QThread m_aramaThread;
    QPointer<AramaWorker> m_aramaWorker;

    TeklifPdfOlusturucu m_pdfOlusturucu;
};
