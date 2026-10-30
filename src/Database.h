#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QElapsedTimer>
#include <QThread>
#include <QPointer>
#include <atomic>

#include "TeklifPdfOlusturucu.h"

class AramaWorker;
class QSqlQuery;

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
    // Baglanilan SQL Server ornegi (baglanti.ini ya da varsayilan); hata seridi icin.
    Q_PROPERTY(QString sunucuAdi READ sunucuAdi CONSTANT)

public:
    explicit Database(QObject *parent = nullptr);
    ~Database() override;

    bool baglantiHazirMi() const { return m_baglantiHazir; }
    QString sunucuAdi() const;
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
    //   "koyuTema" (bool, yalnizca db/34 calistirilmissa) -> personelin temasi;
    //        kayitta tema secilmemisse (NULL) varsayilan koyu.
    Q_INVOKABLE QVariantMap girisYap(const QString &kullaniciAdi, const QString &sifre);

    // Oturumdaki kullanicinin kendi tema secimini (ekrandaki tema anahtari)
    // kaydina yazar; bir sonraki giriste bu tema uygulanir. db/34 yoksa ya da
    // oturum yoksa hicbir sey yapmaz.
    Q_INVOKABLE void temaTercihiKaydet(bool koyuTema);

    // Giris yapmis kullanicinin id'si (giris yapilmamissa 0). Oturumu QML
    // tarafi da tutuyor (Main.qml "oturum"), ancak bazi is kurallari
    // SUNUCUDA bilinmek zorunda -- ör. kullanicinin KENDI hesabini pasife
    // almasini engellemek (bkz. personelAktifDurumDegistir). QML'den gelen bir
    // kullaniciId'ye guvenmek yerine girisYap'in yazdigi degeri kullaniyoruz.
    Q_INVOKABLE int aktifKullaniciId() const { return m_aktifKullaniciId; }
    // "Cikis Yap"ta cagrilir; aktif oturum bilgisini temizler.
    Q_INVOKABLE void oturumuKapat() { m_aktifKullaniciId = 0; }

    // Silme / kayit duzenleme onayi: girilen sifre, aktif ve "Yönetici" (veya goc
    // donemindeki "Göç - Geçici Tam Yetkili") rolundeki herhangi bir kullanicinin
    // sifresiyle eslesiyorsa true (WPF'teki AdminPassword korumasinin karsiligi).
    Q_INVOKABLE bool yoneticiSifresiDogrula(const QString &sifre);

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
    // KULLANICIYA GOSTERILEN NUMARALAR: her kayitta "kokTeklifNo" (int, revizyon
    // eki olmadan), "teklifNo", "guncelTeklifNo"
    // ve "kopyaKaynakTeklifNo" (string, "1203" / "1203/Rev.2"; kopya degilse bos)
    // bulunur. Ekranda YALNIZCA bunlar gosterilir; *TeklifId alanlari sistemin ic
    // anahtaridir ve sadece islem yapmak icin kullanilir (bkz. teklifNoGetir).
    // "arama" bir Teklif No ise ("1203", "1203/Rev.2", "1203/2", "1203 R2")
    // numaraya gore bulunur: "1203" kok teklifi ve tum revizyonlarini getirir.
    // "toplamKayit" (int), "toplamSayfa" (int), "mevcutSayfa" (int).
    // Her kayitta ayrica "paraBirimi" (string) ve "genelToplam" (double, KDV dahil,
    // teklifin kendi para biriminde) bulunur.
    // SENKRON yol: sorgu suresince UI thread'i bloke olur. Ekranlar bunun
    // yerine gecmisTekliflerGetirBaslat'i kullanir (asagiya bkz.).
    Q_INVOKABLE QVariantMap gecmisTekliflerGetir(const QString &arama,
                                                  const QString &tarihFiltresi,
                                                  const QString &baslangicTarihi,
                                                  const QString &bitisTarihi,
                                                  int sayfaNo,
                                                  int sayfaBoyutu = 50,
                                                  const QString &durumFiltresi = QString());

    // ASENKRON yol (Giden / Alinan / Biten Tekliflerim). Sorgu, sayfali
    // listelerle ayni worker thread'i + ayri ODBC baglantisi uzerinde calisir;
    // sonuc teklifListesiHazir sinyaliyle gelir. Eskiden liste UI thread'inde
    // senkron cekiliyordu: 3000+ kayitta arama kutusuna yazarken sorgu
    // (teklif_kalemleri uzerindeki EXISTS + LIKE) saniyelerce surdugu icin
    // pencere "Yanıt Vermiyor" durumuna dusuyordu.
    // Donen istek numarasi sonuc sinyalinde aynen geri gelir; ekran YALNIZCA
    // en son verdigi numarayla donen sonucu basar (bkz. *ListesiGetirBaslat).
    Q_INVOKABLE int gecmisTekliflerGetirBaslat(const QString &arama,
                                                const QString &tarihFiltresi,
                                                const QString &baslangicTarihi,
                                                const QString &bitisTarihi,
                                                int sayfaNo,
                                                int sayfaBoyutu = 50,
                                                const QString &durumFiltresi = QString());

    // TEKLIF NO: kullanicinin gordugu tek numara. Musteriye giden PDF'teki,
    // listedeki ve mesajlardaki numara hep budur: orijinal teklifte "1203",
    // revizyonda kok teklifin numarasi + revizyon ("1203/Rev.2"). Numara
    // dbo.teklifler.TeklifNo'da tutulur ve TeklifId'den BAGIMSIZDIR: yeni teklif
    // en buyuk numara + 1 alir, revizyon numara harcamaz -- boylece numaralar
    // atlamaz (bkz. teklifKaydet, db/10_teklif_no.sql). TeklifId sistemin ic
    // anahtaridir ve kullaniciya hic gosterilmez.
    // Teklif bulunamazsa id'nin kendisi doner.
    Q_INVOKABLE QString teklifNoGetir(int teklifId);

    // Tek bir teklifi kalici olarak siler. Basariliysa true doner; degilse
    // sebebi sonHataMesaji()'ndadir. Kabul edilmis/tamamlanmis teklif ve
    // revizyonlari olan kok teklif silinemez (once revizyonlar silinmelidir).
    // Silinen kayit zincirin EN SON revizyonuysa, yeniden zincirin sonu olan
    // onceki surum "Revize Edildi"den "Beklemede"ye alinir (yine gecerli olur).
    // Teklife ozel "MANUEL-<teklifId>" urun satirlari da temizlenir.
    // Silmeden once teklifin tam hali, kim/ne zaman bilgisiyle
    // dbo.teklif_silme_gecmisi'ne yazilir (db/28); iz yazilamazsa silinmez.
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
    //             maliyetFiyati, paraBirimi, kur,
    //             tamamlandi (bool, OPSIYONEL; satirin uretimi bitti mi) ve
    //             uretimNotu (string, OPSIYONEL; o satira ozel uretim notu) --
    //             ikisi de verilmezse 0/NULL kaydedilir. Bunlar yalnizca
    //             REVIZYON (ve teklifDuzelt) akisinda dolu gelir: teklifin yeni surumu, eski
    //             surumunun uretim durumunu devralir; "Kopya" akisinda QML
    //             tarafi bilincli olarak sifirlar}>),
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
    //   revizyonSebebi (string, OPSIYONEL): revizyonda eski teklif(ler)in
    //             "Revize Edildi" satirina ve yeni revizyonun ilk satirina
    //             (teklif_durum_gecmisi.Aciklama) eklenir; Teklif Gecmisi'nde gorunur.
    //
    // REVIZYON = ESKISINI GECERSIZ KILAR: bir revizyon kaydedildiginde ayni koke
    // bagli ONCEKI teklifler (kok + eski revizyonlar) -- Beklemede, Kabul Edildi
    // veya Reddedildi olsun -- "Revize Edildi" durumuna alinir. Boylece ayni
    // teklifin iki surumu ayni anda gecerli (ör. biri kabul edilmis, digeri
    // beklemede) gorunemez; kabul edilmis bir teklif revize edildiyse yeni
    // revizyonun yeniden kabul edilmesi gerekir. Eski kayit listede ayirt edilir
    // ve PDF'i yeniden uretilirse ustune "gecerli degildir" bandi basilir.
    //
    // REVIZYON YALNIZCA GUNCEL SURUMDEN: yerine zaten yeni bir revizyon gecmis
    // bir tekliften revizyon alinamaz (eski icerikten guncel surum sessizce ezilmesin).
    //
    // TAMAMLANMIS IS REVIZE EDILEMEZ: zincirde "Tamamlandı" durumunda bir teklif
    // varsa revizyon reddedilir; once durum "Beklemede"ye geri alinmalidir.
    //
    // Indirim/KDV orani 0-100 arasinda, adet en az 1, tutarlar negatif olmamalidir;
    // kalem kuru pozitif olmalidir (dovizli teklifte kur bilinmiyorsa 1 gelir ve
    // maliyetFiyati TL'dir); kalem ve toplam
    // tutarlari sunucuda ayni kurallarla yeniden hesaplanip (1 kurus tolerans)
    // dogrulanir. Aksi halde kayit yapilmaz (bkz. teklifVerisiniDenetle).
    //
    // Revizyonda zincirdeki en guncel sevk/irsaliye kaydi yeni revizyona kopyalanir.
    // Donen QVariantMap: "basarili" (bool), "teklifId" (int), "teklifNo" (string),
    //   "hata" (string), "revizeEdilenTeklifIdler" (QVariantList<int>, bu kayit yuzunden
    //   "Revize Edildi" durumuna alinan eski tekliflerin id'leri; bos olabilir).
    Q_INVOKABLE QVariantMap teklifKaydet(const QVariantMap &teklif);

    // DUZELTME (revizyon DEGIL): kullanicinin kendi giris hatasini (yanlis firma,
    // yanlis KDV/indirim, yanlis ilgili kisi...) mevcut teklifin USTUNE yazar.
    // Ayni TeklifId korunur, RevizyonNo artmaz, eski surum "Revize Edildi" olmaz.
    // "teklif" haritasi teklifKaydet ile AYNI sekildedir (anaTeklifId /
    // kopyaKaynakTeklifId yok sayilir); kalemler ve toplamlar bastan yazilir.
    //
    // Yalnizca durumu "Beklemede" olan ve revizyon zincirinin en guncel uyesi
    // olan teklif duzeltilebilir. Kabul edilmis/tamamlanmis (kilitli),
    // reddedilmis ya da yerine yeni revizyon gecmis teklif yalnizca REVIZYON ile
    // degisir -- aksi halde musterinin elindeki belgeyle sistemdeki kayit sessizce
    // ayrisirdi.
    //
    // IZ ZORUNLUDUR: ustune yazmadan hemen once teklifin tam hali (baslik +
    // kalemler + toplamlar) sebep, kullanici ve zamanla birlikte
    // dbo.teklif_duzeltme_gecmisi'ne yazilir -- ayni transaction icinde. Bu tablo
    // yoksa (db/09_teklif_duzeltme_gecmisi.sql calistirilmamissa) veya iz
    // yazilamazsa duzeltme HIC yapilmaz. sebep bos olamaz.
    // Donen QVariantMap: "basarili" (bool), "teklifId" (int), "teklifNo" (string),
    //   "hata" (string).
    Q_INVOKABLE QVariantMap teklifDuzelt(int teklifId, const QVariantMap &teklif,
                                         const QString &sebep);

    // teklifKaydet / teklifDuzelt'in ARKA PLAN surumleri: kayit kendi thread'i
    // ve kendi ODBC baglantisi uzerinde yapilir, arayuz beklemez. SQL Server
    // yavasladiginda (bellek sikismasi vb.) pencere "Yanıt Vermiyor"a dusmesin
    // diye "Teklifi Kaydet" bunlari kullanir. Sonuc teklifKayitHazir ile gelir
    // (senkron surumlerin dondurdugu haritanin aynisi). Donen: istek numarasi.
    Q_INVOKABLE int teklifKaydetBaslat(const QVariantMap &teklif);
    Q_INVOKABLE int teklifDuzeltBaslat(int teklifId, const QVariantMap &teklif,
                                       const QString &sebep);
    Q_SIGNAL void teklifKayitHazir(int istekNo, const QVariantMap &sonuc);

    // Teklif Ver ekrani "Teklifi Kaydet"e basildiginda Duzeltme secenegini sunup
    // sunmayacagini buradan ogrenir (kurallar teklifDuzelt ile aynidir). Izin
    // yoksa sonHataMesaji() sebebi tasir.
    Q_INVOKABLE bool teklifDuzeltilebilirMi(int teklifId);

    // Giden/Alınan/Biten Tekliflerim'deki "Detay" butonu icin: bir teklifin
    // KAYITLI TUM verisini, Teklif Ver ekranini (TeklifVerPage.duzenlemeyeBasla)
    // AYNEN DOLDURACAK sekilde geri doner -- boylece "Detay" o teklifi Teklif Ver
    // ekraninda acar, kullanici degisiklik yapip kaydedince teklifKaydet()'e
    // anaTeklifId ile bir REVIZYON olarak gonderilir.
    // Donen QVariantMap anahtarlari: "basarili" (bool), "hata" (string),
    //   "teklifId", "anaTeklifId" (int, kok teklif; revizyon degilse teklifId'nin
    //   kendisi), "revizyonNo" (int), "teklifNo" (string, ekranda gosterilen
    //   numara), "musteriId" (int), "musteriAdi",
    //   "genelIndirimOrani", "kdvOrani", "paraBirimi", "dil", "ilgiliKisi",
    //   "ilgiliKisiTelefonu", "ilgiliKisiEposta", "teslimatSekli", "teslimatYeri",
    //   "paketlemeUcreti", "tasimaUcreti" (teklifin para biriminde),
    //   "kur" (double, teklifin kaydedildigi kur),
    //   "kalemler" (QVariantList<QVariantMap{urunId (0 ise manuel), urunKodu,
    //             aciklama, adet (int), birimFiyat (teklifin para biriminde),
    //             maliyet (double, TL),
    //             teklifKalemId (int, satirin kendi id'si -- satir bazli uretim
    //             bilgisini YERINDE guncellemek icin, bkz.
    //             teklifKalemTamamlandiGuncelle), tamamlandi (bool),
    //             uretimNotu (string, o satira ozel uretim notu)}>),
    //   "sozlesmeMetni" (string; teklife ozel bir sozlesme metni kaydedilmemisse bos),
    //   "musteriNotu" (string, teklif notu), "uretimNotu" (string),
    //   "teslimatTarihi" (string, "yyyy-MM-dd" veya bos), "durum" (string),
    //   "guncelSurum" (bool; false ise yerine yeni bir revizyon gecmistir --
    //             ekran salt goruntulemedir), "guncelTeklifNo" (string),
    //   "kurBilinmiyor" (bool; dovizli teklifte kayitli kur yok -- gocten gelen
    //             ya da kur alinamadan kaydedilen tekliflerde Kur=1 yazilir ve
    //             maliyet TL saklanir). Ekran bu durumda guncel kuru ceker.
    //   "kayitliToplamVar" (bool), "kayitliIndirimliToplam", "kayitliKdvTutari",
    //   "kayitliGenelToplam" (double, teklifin para biriminde): veritabanindaki
    //             (PDF'e basilan) toplamlar -- ekran eski KDV kuraliyla kaydedilmis
    //             teklifi tespit edip kayitli tutari gosterebilsin diye.
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

    // ------------------------------------------------------------------
    // SATIR BAZLI uretim takibi (dbo.teklif_kalemleri.Tamamlandi / UretimNotu).
    //
    // Bir teklifte birden fazla urun oldugunda teklifin TAMAMI icin tek bir
    // "bitti" bilgisi yetmiyor: 5 kalemin 3'u uretilmis olabilir, ya da yalnizca
    // bir urun icin ozel bir olcu/malzeme notu olabilir. Bu yuzden her teklif
    // KALEMI kendi "tamamlandi" bayragini ve kendi uretim notunu tasir. Teklifin
    // GENEL uretim notu (teklifUretimNotuGuncelle) bundan bagimsizdir ve tum
    // teklife dair notlar icin kullanilmaya devam eder; ikisi de uretim PDF'ine
    // basilir (bkz. TeklifPdfOlusturucu::uretimPdfUret).
    //
    // Her ikisi de kayitli teklifi YERINDE gunceller (revizyon olusturmaz).
    // KILIT KURALI, planlanan teslim tarihi/genel uretim notuyla AYNIDIR:
    // "Kabul Edildi" teklifte serbestce isaretlenir/yazilir -- uretim zaten
    // kabulden sonra basladigi icin bilgi o asamada olusur --, teklif
    // "Tamamlandı"ya gectikten sonra ARTIK DEGISTIRILEMEZ (false doner).
    //
    // teklifKalemId, teklifDuzenlemeVerisiGetir'in donen kalemlerindeki
    // "teklifKalemId" degeridir; 0/gecersizse (henuz kaydedilmemis teklif) false doner.
    Q_INVOKABLE bool teklifKalemTamamlandiGuncelle(int teklifKalemId, bool tamamlandi);
    // uretimNotu bos/bosluk ise sutun NULL'lanir (not kaldirilir).
    Q_INVOKABLE bool teklifKalemUretimNotuGuncelle(int teklifKalemId, const QString &uretimNotu);

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
    // ISTISNA: "Tamamlandı"ya yalnizca "Kabul Edildi"den gecilir; kabul edilmemis
    // teklif tamamlanamaz (false doner, sebep sonHataMesaji()'nda).
    // "Kabul Edildi" icin teklifin planlanan teslim tarihi (TeslimatTarihi) dolu
    // olmalidir; bos ise false doner.
    //
    // redSebebi yalnizca "Reddedildi" gecisinde kullanilir; kullaniciId 0 ise log
    // satirina NULL yazilir.
    //
    // REVIZE EDILMIS TEKLIF DEGISTIRILEMEZ: zincirde kendisinden daha yeni bir
    // revizyonu BULUNAN teklif icin -- durum sutunu ne olursa olsun -- bu metot
    // false doner (sebep sonHataMesaji()'nda). Aksi halde teklifin eski surumu "Kabul Edildi"
    // olurken guncel surumu "Beklemede" kalabilir, yani ayni teklifin iki fiyatli
    // surumu ayni anda gecerli gorunurdu. Yeni revizyon silinmisse kayit yeniden
    // zincirin sonu olur ve normal sekilde islenebilir.
    Q_INVOKABLE bool teklifDurumGuncelle(int teklifId, const QString &durum,
                                         const QString &redSebebi = QString(),
                                         int kullaniciId = 0);

    // Teklifin ait oldugu REVIZYON ZINCIRININ tamaminin gecmisi (kok + tum
    // revizyonlar), eskiden yeniye tek zaman cizelgesinde: olusturma/revizyon,
    // durum degisimleri ve duzeltmeler (bkz. teklifDuzelt). Otomatik
    // "→ Revize Edildi" kayitlari ayri satir olmaz; sebep olan revizyonun
    // satirinda gosterilir. Her eleman:
    // {"tur" ("olusturma" | "revizyon" | "durum" | "duzeltme"), "teklifId" (int),
    //  "teklifNo" (hangi surum, "1/Rev.2"), "baslik", "aciklama", "personel", "tarih"}.
    // Tablolardan biri henuz olusturulmadiysa o kisim bos gelir (hata degil).
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
    // "arsivliDahil" true verilirse arsivlenmis (AktifMi = 0) kayitlar da
    // listelenir -- ekrandaki "Arşivi göster" anahtari icin.
    //
    // ASENKRON KARDESI: musteriListesiGetirBaslat. Ekranlar onu kullanir;
    // bu senkron surum program ici diger cagrilar icin durur.
    Q_INVOKABLE QVariantMap musteriListesiGetir(const QString &arama, int sayfaNo,
                                                 int sayfaBoyutu = 50, bool arsivliDahil = false);

    // "musteri" anahtarlari: firmaAdi, firmaAdresi, firmaTelefonu, firmaEposta,
    // vergiDairesi, vergiNumarasi, ilgiliKisi, ilgiliKisiTelefonu. Tum metin
    // alanlari trim edilir; bos birakilanlar NULL kaydedilir.
    // E-posta, telefon ve vergi numarasi bicimi dogrulanir (bos olabilirler).
    //
    // MUKERRER FIRMA: ayni adda (buyuk/kucuk harf duyarsiz) bir musteri zaten
    // varsa kayit YAPILMAZ ve donen haritada ayrica "mukerrer" (bool) = true
    // ile "mukerrerAd" bulunur; ekran kullaniciya "bu isimde musteri var,
    // devam edilsin mi?" diye sorar. Kullanici onaylarsa ayni harita
    // "mukerrerOnayi" = true ile tekrar gonderilir ve kayit yapilir.
    // (Sert UNIQUE kisiti koymuyoruz: ayni ismi tasiyan farkli sube/tuzel
    // kisilerin ayri musteri olmasi gercek bir ihtiyac.)
    // Donen: {basarili, musteriId, hata, mukerrer, mukerrerAd}.
    Q_INVOKABLE QVariantMap musteriEkle(const QVariantMap &musteri);
    Q_INVOKABLE QVariantMap musteriGuncelle(int musteriId, const QVariantMap &musteri);
    // KALICI silme; yalnizca hicbir teklifte kullanilmamis musteri icin
    // mumkundur. Teklifi olan musteride FK kisitlamasi devreye girer ve donen
    // haritada "iliskiliKayitVar" (bool) = true olur -- ekran bu durumda
    // kullaniciya ARSIVLEMEYI onerir (bkz. musteriArsivDurumDegistir).
    // Diger hatalar (baglanti kopmasi, zaman asimi, yetki) artik FK ihlaliyle
    // KARISTIRILMAZ; gercek sebep hata alaninda doner.
    // Donen: {basarili, hata, iliskiliKayitVar}.
    Q_INVOKABLE QVariantMap musteriSil(int musteriId);
    // Arsivleme/geri alma: kayit yerinde kalir, yalnizca AktifMi degisir.
    // Boylece gecmis teklifler etkilenmeden katalog temizlenebilir.
    // Donen: {basarili, hata}.
    Q_INVOKABLE QVariantMap musteriArsivDurumDegistir(int musteriId, bool aktif);

    Q_INVOKABLE QVariantMap urunListesiGetir(const QString &arama, int sayfaNo,
                                              int sayfaBoyutu = 50, bool arsivliDahil = false);

    // "urun" anahtarlari: urunKodu, kategori, urunAciklamasi, urunAciklamasiEn,
    // birimFiyat (TL liste fiyati), fiyatUSD, fiyatEUR, maliyet (TL).
    // TL / USD / EUR fiyatlari BIRBIRINDEN BAGIMSIZDIR (1.000 TL'lik urun 60 $'a
    // satilabilir); teklifte secilen para biriminin fiyati dogrudan kullanilir,
    // kura bolunerek bulunmaz. fiyatUSD / fiyatEUR 0 ya da bos ise NULL
    // kaydedilir ("girilmemis"). db/26 calistirilmamissa yalnizca TL yazilir.
    //
    // URUN KODU: opsiyoneldir, ancak girildiyse (a) "MANUEL" onekiyle
    // baslayamaz -- o onek teklife ozel gecici satirlara ayrilmistir ve bu
    // kodla kaydedilen urun hicbir listede gorunmez (bkz. manuelKoduMu) --,
    // (b) baska bir urunde kullanilmis olamaz (bkz. urunKoduKullanimdaMi).
    //
    // Tekillik YALNIZCA burada, uygulama seviyesinde saglanir: dbo.urunler
    // uzerinde tekil bir indeks KURULAMIYOR, cunku "MANUEL-<teklifId>"
    // satirlari tasarim geregi kendi aralarinda cakisiyor (ayrintili gerekce:
    // db/14_urun_kodu_tekil.sql). Bu yuzden kontrol ile INSERT arasinda
    // teorik bir yaris penceresi vardir -- kucuk ekip/tek sunucu kurulumunda
    // kabul edilmis risk.
    // Donen: {basarili, urunId, hata}.
    Q_INVOKABLE QVariantMap urunEkle(const QVariantMap &urun);
    Q_INVOKABLE QVariantMap urunGuncelle(int urunId, const QVariantMap &urun);
    // musteriSil ile ayni kural: KALICI silme yalnizca hicbir teklifte
    // kullanilmamis urun icin mumkundur, aksi halde "iliskiliKayitVar" = true
    // doner ve ekran arsivlemeyi onerir.
    // Donen: {basarili, hata, iliskiliKayitVar}.
    Q_INVOKABLE QVariantMap urunSil(int urunId);
    // Donen: {basarili, hata}.
    Q_INVOKABLE QVariantMap urunArsivDurumDegistir(int urunId, bool aktif);

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
    // Rol listesi ASENKRON gelir (rolListesiHazir sinyali). Senkron surum
    // kaldirildi: sunucu yogunken bu tek sorgu, Personellerim sekmesine her
    // gecisde UI thread'ini on saniyelerce bekletiyordu.
    Q_INVOKABLE void rolListesiGetirBaslat();
    Q_SIGNAL void rolListesiHazir(const QVariantList &roller);

    // "kayitlar" icindeki her personel: kullaniciId, adSoyad, kullaniciAdi,
    // telefon, pozisyon, aktifMi, rolIdListesi (QVariantList<int>), rolAdlari (string, virgullu).
    // "pasifDahil" false iken yalnizca aktif personel donulur.
    Q_INVOKABLE QVariantMap personelListesiGetir(const QString &arama, int sayfaNo,
                                                  int sayfaBoyutu = 50, bool pasifDahil = true);

    // "personel" anahtarlari: adSoyad, kullaniciAdi, sifre (bos ise -- sadece
    // guncellemede -- sifre degistirilmez), telefon, pozisyon, rolIdListesi (QVariantList<int>),
    // koyuTema (bool; db/34 calistirilmamissa yok sayilir).
    //
    // EN AZ BIR ROL ZORUNLUDUR: rolsuz kullanici giris yapabiliyor ama hicbir
    // modul goremiyordu (kullaniciModulleriniGetir bos doner) -- kullanici
    // acisindan sebebi anlasilmaz bir "bos program" durumu.
    //
    // SIFRE kullanici basina rastgele bir tuzla hashlenir (bkz. db/12_personel_sifre_salt.sql).
    // Donen: {basarili, kullaniciId, hata}.
    Q_INVOKABLE QVariantMap personelEkle(const QVariantMap &personel);
    Q_INVOKABLE QVariantMap personelGuncelle(int kullaniciId, const QVariantMap &personel);

    // Personelin mevcut sifresini acik metin olarak doner (unutulan sifreyi
    // yonetici soyleyebilsin diye; bkz. db/29_personel_sifre_gorunur.sql).
    // YALNIZCA tek bir yetkili kullanici (SIFRE_GORUNTULEYEN_KULLANICI) ve
    // dogru PIN ile; 5 yanlis PIN'den sonra oturum boyunca kilitlenir. Kopya
    // henuz yoksa (personel db/29'dan beri giris yapmadi) hata metni doner.
    // Donen: {basarili, sifre, hata}.
    Q_INVOKABLE QVariantMap personelSifresiGetir(int kullaniciId, const QString &pin);

    // Oturumdaki kullanici personel sifrelerini gorebilen kisi mi? Personel
    // Duzenle'deki "Mevcut Şifre" satiri buna gore gosterilir.
    Q_INVOKABLE bool sifreGoruntuleyebilirMi();

    // Pasife alma / aktif etme. Iki korumasi var, cunku ikisinin de sonucu
    // programdan GERI DONUSU OLMAYAN bir kilitlenme:
    //   1) Kullanici KENDI hesabini pasife alamaz.
    //   2) Pasife alma sonrasi sistemde aktif yonetici KALMAYACAKSA islem
    //      reddedilir -- yoksa yonetici sifresi isteyen hicbir islem (teklif
    //      silme, personel kaydi, musteri duzenleme) bir daha yapilamazdi.
    // Donen: {basarili, hata} -- eskiden sadece bool donuyordu ve ekran
    // basarisizligin sebebini kullaniciya hic gosteremiyordu.
    Q_INVOKABLE QVariantMap personelAktifDurumDegistir(int kullaniciId, bool aktif);

    // ------------------------------------------------------------------
    // Yonetim / Roller ve Yetkiler. Hepsi YONETIM modulunde duzenleme
    // yetkisi ister (sunucuda denetlenir).
    // ------------------------------------------------------------------
    // Roller + modul bazinda yetkileri ASENKRON gelir (rolYetkiListesiHazir).
    // Sonucun sekli icin bkz. rolYetkiListesiSorgusu (AramaSorgulari.h);
    // baglanti yoksa bos harita gelir.
    Q_INVOKABLE void rolYetkiListesiGetirBaslat();
    Q_SIGNAL void rolYetkiListesiHazir(const QVariantMap &sonuc);

    // rolId <= 0 ise yeni rol eklenir. "rol" anahtarlari: rolAdi,
    // yetkiler (QVariantList<{modulId, gorebilir, duzenleyebilir}>).
    // Duzenleyebilir isaretli modul gorebilir de sayilir. En az bir modulde
    // gorme yetkisi zorunludur (yoksa bu roldeki personel bos program gorur).
    // Sistem rolleri (bkz. sistemRoluMu) degistirilemez.
    // Donen: {basarili, rolId, hata}.
    Q_INVOKABLE QVariantMap rolKaydet(int rolId, const QVariantMap &rol);

    // Yalnizca HICBIR personele (pasifler dahil) atanmamis rol silinebilir:
    // aksi halde kullanici_rolleri satirlari CASCADE ile sessizce gider ve
    // personel rolsuz kalabilir. "Yönetici" hic silinemez.
    // Donen: {basarili, hata}.
    Q_INVOKABLE QVariantMap rolSil(int rolId);

    // ------------------------------------------------------------------
    // Yonetim / Sistem Ayarlari (dbo.ayarlar). Duzenlenebilen anahtarlar ve
    // sinirlari SqlYardimcilari.h'deki ayarTanimlari() listesindedir.
    // ------------------------------------------------------------------
    // ASENKRON; sonucun sekli icin bkz. ayarListesiSorgusu (AramaSorgulari.h).
    Q_INVOKABLE void ayarListesiGetirBaslat();
    Q_SIGNAL void ayarListesiHazir(const QVariantMap &sonuc);

    // Tanimli bir ayarin sayisal degeri. Tablo/satir yoksa, deger bozuksa
    // ya da baglanti yoksa tanimdaki varsayilan doner (tanimsiz anahtar: 0).
    Q_INVOKABLE double ayarSayiGetir(const QString &anahtar);

    // Tanimli bir METIN ayarinin degeri; kayitli metin yoksa (veya baglanti
    // yoksa) tanimdaki fabrika metni doner.
    Q_INVOKABLE QString ayarMetniGetir(const QString &anahtar);

    // {anahtar: deger} haritasindaki ayarlari TEK islemde yazar; biri bile
    // gecersizse hicbiri yazilmaz. YONETIM duzenleme yetkisi ister.
    // Metin ayarinda deger string'dir; bos ya da fabrika metniyle ayni metin
    // NULL yazilir (= fabrika metni). 500 karakteri asan metin icin
    // db/23_ayar_degeri_uzun_metin.sql gerekir.
    // Donen: {basarili, hata}.
    Q_INVOKABLE QVariantMap ayarlariKaydet(const QVariantMap &degerler);

    // ------------------------------------------------------------------
    // Yonetim / Ozet (pano). Teklif tarafi ASENKRON (sonucun sekli ve sayim
    // kurallari: panoOzetiSorgusu, AramaSorgulari.h); satinalma tarafi icin
    // ekran satinalmaOzetiGetir'i kullanir. Donen istek numarasi sinyalde
    // geri gelir; ekran yalnizca en son istegin sonucunu basar.
    // ------------------------------------------------------------------
    Q_INVOKABLE int panoOzetiGetirBaslat(const QString &donem,
                                         const QString &ozelBaslangic = QString(),
                                         const QString &ozelBitis = QString());
    Q_SIGNAL void panoOzetiHazir(int istekNo, const QVariantMap &sonuc);

    // Yonetim / Islem Gecmisi: tum tekliflerin olaylari, sayfali ve ASENKRON.
    // "suzgec" ve sonucun sekli icin bkz. islemGecmisiSorgusu (AramaSorgulari.h).
    Q_INVOKABLE int islemGecmisiGetirBaslat(const QVariantMap &suzgec, int sayfaNo,
                                            int sayfaBoyutu = 50);
    Q_SIGNAL void islemGecmisiHazir(int istekNo, const QVariantMap &sonuc);

    // Muhasebe karti: faturalanacak / faturalanan teklifler, sayfali ve ASENKRON.
    // "suzgec" ve sonucun sekli icin bkz. muhasebeListesiSorgusu (AramaSorgulari.h).
    Q_INVOKABLE int muhasebeListesiGetirBaslat(const QVariantMap &suzgec, int sayfaNo,
                                               int sayfaBoyutu = 50);
    Q_SIGNAL void muhasebeListesiHazir(int istekNo, const QVariantMap &sonuc);

    // Muhasebe kartinin detay paneli: teklifin PDF'e basilan kalemleri ve
    // toplamlari (teklifin para biriminde). Hicbir sey yazmaz.
    // Donen: {basarili, hata, teklifNo, firmaAdi, paraBirimi, durum,
    //   kabulTarihi, teslimatTarihi, personelAdSoyad, genelIndirimOrani,
    //   kdvOrani, indirimliToplam, kdvTutari, genelToplam, paketlemeUcreti,
    //   tasimaUcreti, kalemler [{urunKodu, aciklama, adet, birimFiyat,
    //   indirimliBirimFiyat, toplamTutar}]}.
    Q_INVOKABLE QVariantMap muhasebeTeklifVerisiGetir(int teklifId);

    // Metni sistem panosuna yazar (Muhasebe kartindaki kopyala dugmeleri).
    Q_INVOKABLE void panoyaKopyala(const QString &metin);

    // ------------------------------------------------------------------
    // Cihaz Maliyetleri (Yonetim + Satinalma). Excel'deki cihaz maliyet
    // sayfalarinin karsiligi: cihaz basina recete, kar orani, satis fiyati
    // ve kendiliginden dolan maliyet gecmisi (db/17, urun eslesmesi db/24).
    // Yetki kademeleri icin bkz. Database.cpp "CIHAZ MALIYETLERI".
    // ------------------------------------------------------------------
    // {fiyatGorebilir, tamYetki, kalemDuzenleyebilir, semaHazir, urunEslesmesiVar}
    Q_INVOKABLE QVariantMap cihazYetkisi();

    // ASENKRON; liste sekli: cihazListesiSorgusu (AramaSorgulari.h). Fiyat
    // gorme yetkisi olmayana karOrani / satisFiyatiTL / katalog alanlari gitmez.
    Q_INVOKABLE int cihazListesiGetirBaslat(const QString &arama, bool arsivDahil);
    Q_SIGNAL void cihazListesiHazir(int istekNo, const QVariantList &liste);

    // {basarili, hata, cihaz: {cihazId, cihazAdi, aciklama, karOrani, toplamMaliyetTL,
    //   satisFiyatiTL, aktifMi, guncellemeTarihi, urunId, urunKodu, urunAciklamasi,
    //   katalogFiyat, katalogParaBirimi},
    //  kalemler: [{receteKalemId, grup, kalemTuru, kalemAdi, adet, birim, birimFiyat,
    //   paraBirimi, kur, birimFiyatTL, toplamTutarTL, tedarikciAdi, sonSatinalmaId,
    //   fiyatTarihi (yyyy-MM-dd), aciklama,
    //   oneri: null | {satinalmaId, birimFiyat, paraBirimi, kur, tarih, tedarikciAdi}}],
    //  gecmis: [{tarih, degisenKalemAdi, eskiBirimFiyatTL, yeniBirimFiyatTL,
    //   eskiToplamTL, yeniToplamTL, karOrani, yeniSatisFiyatiTL, tedarikciAdi,
    //   personel, aciklama}]}
    // "oneri": ayni adla, kalemin fiyat tarihinden SONRA yapilmis en son aktif
    // alim (fiyati farkliysa). Kabul edilirse istemci kalemi o alimin fiyati,
    // sonSatinalmaId'si ve tarihiyle gonderir.
    Q_INVOKABLE QVariantMap cihazGetir(int cihazId);

    // cihazId <= 0 ise yeni cihaz (yalnizca YONETIM duzenleyebilir). "veri":
    // cihazAdi, aciklama, karOrani, urunId, kalemler [cihazGetir'deki alanlar].
    // Recete TAMAMEN gonderilir: listede olmayan kalem silinir. TL karsiliklari,
    // toplam maliyet ve satis fiyati SUNUCUDA hesaplanir. Toplam maliyet ya da
    // kar orani degistiyse cihaz_maliyet_gecmisi'ne bir satir yazilir.
    // Yalnizca SATINALMA yetkisi olan kullanicida cihaz bilgileri (ad, kar,
    // urun) istemciden gelse de kayitli halleriyle korunur.
    // Donen: {basarili, cihazId, hata}.
    Q_INVOKABLE QVariantMap cihazKaydet(int cihazId, const QVariantMap &veri);

    // Arsivleme / geri alma (kalici silme yok). Yalnizca YONETIM duzenleyebilir.
    Q_INVOKABLE QVariantMap cihazAktifDurumDegistir(int cihazId, bool aktif);

    // Urun eslestirme kutusu: [{urunId, urunKodu, urunAciklamasi, birimFiyat, paraBirimi}], en fazla 20.
    Q_INVOKABLE QVariantList cihazUrunAra(const QString &arama);

    // Teklif Ver + Giden Tekliflerim ekranlarindan PDF uretimi. SQL sorgularini burada
    // calistirir, sonucu TeklifPdfOlusturucu'ya devreder (HTML/PDF uretiminin tamami
    // orada). PDF ONIZLEME klasorune basilir; kullanicinin klasorune ancak
    // onizlemede "İndir"e basilinca (pdfKaydet) kopyalanir.
    // Donen: {basarili, dosyaYolu (onizleme), dosyaAdi, tur ("teklif"), teklifId, hata}.
    Q_INVOKABLE QVariantMap teklifPdfOlustur(int teklifId);

    // Alınan/Biten Tekliflerim'deki "Üretim" butonu: teknik ekibe verilecek
    // FIYATSIZ PDF (kapak ve sozlesme sayfasi yok; firma/teslimat/tarih bilgileri,
    // urun kodu/aciklama/adet ve uretim notu var; teklif notu YOK). teklifPdfOlustur
    // gibi sadece onizleme uretir; UretimPdfTarihi indirilince (pdfKaydet) yazilir.
    // Donen: {basarili, dosyaYolu (onizleme), dosyaAdi, tur ("uretim"), teklifId, hata}.
    Q_INVOKABLE QVariantMap uretimPdfOlustur(int teklifId);

    // Onizleme penceresindeki "İndir": *PdfOlustur'un dondurdugu haritayi alir,
    // onizleme PDF'ini Belgelerim/Liya ERP Teklifler'e kopyalar. tur "uretim" ise
    // teklifin UretimPdfTarihi alani simdiki zamanla doldurulur -- bu alan SADECE
    // burada yazilir. Donen: {basarili, dosyaYolu (kaydedilen), klasor, hata}.
    Q_INVOKABLE QVariantMap pdfKaydet(const QVariantMap &pdf);

    // Onizleme penceresi kapanirken gecici PDF'i siler.
    Q_INVOKABLE void pdfOnizlemesiniSil(const QString &onizlemeYolu);

    // PDF motorunu (Chromium) simdiden ayaga kaldirir; bkz.
    // TeklifPdfOlusturucu::motoruHazirla. SU AN CAGRILMIYOR: motor ilk PDF
    // istendiginde hazirlanir (htmlyiPdfeBas). Erken hazirlamak UI thread'ini
    // birkac saniye dondurdugu icin acilisa/giris ekranina tasinmadi.
    void pdfMotorunuHazirla() { m_pdfOlusturucu.motoruHazirla(); }

    // ------------------------------------------------------------------
    // Satis sozlesmesi metni (teklif PDF'inin son sayfasindaki maddeler).
    //
    // Varsayilan metin Yonetim / Sistem Ayarlari'ndan (SATIS_SOZLESME_METNI_TR
    // / _EN) gelir; ayar bossa koddaki FABRIKA metni
    // (TeklifPdfOlusturucu::varsayilanSozlesmeMetni) kullanilir.
    //
    // Her yeni teklif kaydedilirken metin dbo.teklifler.SatisSozlesmesiMetni
    // sutununa YAZILIR (bkz. teklifKaydet); boylece varsayilan sonradan
    // degisse de kayitli teklifler kaydedildikleri metinle basilir. Sutunu
    // NULL olan teklifler bu kuraldan onceki kayitlardir ve hep fabrika
    // metniyle basilir -- bu yuzden fabrika metni kodda DEGISTIRILMEMELIDIR.
    //
    // "dil": "TR" veya "EN" -- varsayilan metnin dilini secer.
    // ------------------------------------------------------------------
    Q_INVOKABLE QString varsayilanSozlesmeMetni(const QString &dil);

    // Teklife kayitli metni doner. Kayitli teklifin metni bossa (eski kayit)
    // fabrika metnini, teklif henuz kaydedilmemisse (teklifId <= 0) dilin
    // o anki varsayilan metnini doner -- pencere her durumda dolu acilir.
    // NOT: Kayitli bir teklifin sozlesme metni YERINDE guncellenmez. Sozlesme
    // ticari icerigin parcasidir; degisikligi teklifin geri kalaniyla birlikte
    // ya duzeltme (iz birakarak, bkz. teklifDuzelt) ya da revizyon olarak
    // kaydedilir.
    Q_INVOKABLE QString teklifSozlesmeMetniGetir(int teklifId, const QString &dil);

    // "Satış Sözleşmesi" penceresi metni PDF'teki haliyle (numarali maddeler,
    // [KOSUL]'u tutmayan satirlar gizli, {{DEGISKEN}}'ler dolu) duzenletir.
    // Bunun icin duz metin satir satir parcalanir; her satir:
    //   etiketler (string)      : satir basi kosullar, ör. "[DOVIZ] " (gizli tutulur)
    //   hamIcerik (string)      : {{DEGISKEN}}'li ham icerik ("- " ve etiketler haric)
    //   orijinalGorunen (string): hamIcerik'in doldurulmus hali (degisiklik tespiti icin)
    //   gorunen (string)        : ekranda duzenlenen metin (baslangicta = orijinalGorunen)
    //   alt (bool)              : "- " ile baslayan alt madde mi
    //   gorunur (bool)          : kosullar bu teklifte saglaniyor mu (PDF'e basilir mi)
    // "teklif": teklifVerisiOlustur() haritasi (paraBirimi, kdvOrani, tasimaUcreti,
    // teslimatSekli, teslimatYeri, dil kullanilir).
    Q_INVOKABLE QVariantList sozlesmeSatirlari(const QString &metin, const QVariantMap &teklif) const;

    // sozlesmeSatirlari'nin tersi: duzenlenmis satirlardan kaydedilecek duz
    // metni geri kurar. Degismeyen satir ham haliyle yazilir; degisen satirda
    // eski doldurulmus degerler (ör. gecerlilik tarihi) metinde hala duruyorsa
    // yeniden {{DEGISKEN}}'e cevrilir, boylece tarih/para birimi sabitlenmez.
    // Icerigi bosaltilan satirlar atilir.
    Q_INVOKABLE QString sozlesmeSatirlarindanMetin(const QVariantList &satirlar, const QVariantMap &teklif) const;

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
    // Fatura takibi (db/30): "faturaAlanlariVar" (bool; betik calistirilmamissa
    // false), "irsaliyeNo", "faturaNo", "faturaTarihi" ("yyyy-MM-dd" veya bos).
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

    // Irsaliye No / Fatura No / Fatura Tarihi (db/30). sevkBilgileriKaydet'ten
    // AYRIDIR: fatura teslimden sonra da kesilebildigi icin "Tamamlandı"
    // teklifte de yazilabilir. Fatura No dolu teklif "Faturalandı" sayilir;
    // teklifin durumu degismez. Sevk kaydi yoksa yalnizca bu alanlarla olusturulur.
    // fatura: {irsaliyeNo, faturaNo, faturaTarihi ("yyyy-MM-dd" veya bos)}.
    // Donen: {basarili (bool), hata (string)}.
    Q_INVOKABLE QVariantMap faturaBilgisiKaydet(int teklifId, const QVariantMap &fatura);

    // ------------------------------------------------------------------
    // Sayfali listelerin ASENKRON yolu (Musterilerim / Urunlerim / Personellerim).
    //
    // Bu uc ekran once *ListesiGetir'i UI thread'inden senkron cagiriyordu:
    // her arama (350 ms gecikmeli de olsa) ve her sayfa degisimi boyunca
    // pencere donuyordu. Urun listesinde nvarchar(MAX) sutunlar yuzunden bu
    // sure saniyelerle olculebiliyor (bkz. urunListesiSorgusu'ndaki olcum
    // notu). Artik sorgu, canli aramayla ayni worker thread'i + ayri ODBC
    // baglantisi uzerinde calisir.
    //
    // Donus degeri olarak verilen istek numarasi sonuc sinyalinde aynen geri
    // gelir; ekran YALNIZCA en son verdigi numarayla donen sonucu basar,
    // boylece hizli yazarken gecikmis sonuc guncelini ezmez.
    // ------------------------------------------------------------------
    Q_INVOKABLE int musteriListesiGetirBaslat(const QString &arama, int sayfaNo,
                                               int sayfaBoyutu = 50, bool arsivliDahil = false);
    Q_INVOKABLE int urunListesiGetirBaslat(const QString &arama, int sayfaNo,
                                            int sayfaBoyutu = 50, bool arsivliDahil = false);
    Q_INVOKABLE int personelListesiGetirBaslat(const QString &arama, int sayfaNo,
                                                int sayfaBoyutu = 50, bool pasifDahil = true);

    // ---- SATINALMA: Tedarikcilerim (musteri ekraniyla ayni desen) ----
    // Liste asenkron yolla gelir (tedarikciListesiHazir). Yazma islemleri
    // SUNUCU TARAFINDA da yetki denetler: aktif kullanicinin SATINALMA
    // modulunde "duzenleyebilir" yetkisi yoksa reddedilir (ekran butonlari
    // gizlemekle yetinmez).
    Q_INVOKABLE int tedarikciListesiGetirBaslat(const QString &arama, int sayfaNo,
                                                 int sayfaBoyutu = 50, bool arsivliDahil = false);
    Q_INVOKABLE QVariantMap tedarikciEkle(const QVariantMap &tedarikci);
    Q_INVOKABLE QVariantMap tedarikciGuncelle(int tedarikciId, const QVariantMap &tedarikci);
    Q_INVOKABLE QVariantMap tedarikciSil(int tedarikciId);
    Q_INVOKABLE QVariantMap tedarikciArsivDurumDegistir(int tedarikciId, bool aktif);

    // ---- SATINALMA ----
    //
    // Akis (bkz. db/20_satinalma_talep_teklif_siparis.sql):
    //
    //   TALEP  ->  TEKLIF KARSILASTIRMA  ->  SIPARIS(LER)  ->  TESLIM  ->  FATURA
    //
    //   * Talep: satinalma mudurunun "ne lazim" listesi. Birimlerde PC olmadigi
    //     icin talebi isteyen kisi degil MUDUR girer; kimin, hangi birim icin,
    //     ne zamana istedigi talebin basligindadir. Kalemler serbest metindir
    //     ve her kalem "ne icin" (hangi cihaz) bilgisini tasir -- bir talebin
    //     kalemleri farkli cihazlara gidebilir.
    //   * Teklif: talebe firma eklenir (sutun), her kalem icin o firmanin
    //     birim fiyati girilir (hucre). Her kalemde kazanan firma secilir.
    //     Firma bir teklifi tek para biriminde verir; kur firma bazindadir.
    //   * Siparis: secilen hucreler FIRMA BAZINDA gruplanip her firma icin ayri
    //     bir satinalma siparisi (SA-0001) olusturulur. Uc kalem uc ayri
    //     firmadan alindiysa uc siparis olur; her birinin teslimati/kargosu
    //     kendisine aittir.
    //   * Teslim: kalem bazinda gelen miktar (kismi teslim desteklenir).
    //   * Fatura: fatura no/tarih/tutar; siparis tutariyla karsilastirilir.

    // Tedarikci secme kutusu icin ARSIVLENMEMIS tedarikcilerin kisa listesi:
    // [{tedarikciId, firmaAdi}]. Sayfali liste (tedarikciListesiGetirBaslat)
    // aksine tek seferde doner; tedarikci sayisi birkac yuzu gecmez.
    Q_INVOKABLE QVariantList tedarikciSecenekleriGetir();

    // Patron onayi esigi (TL). dbo.ayarlar'daki
    // SATINALMA_PATRON_ONAY_ESIGI_TL degeri; 0 = onay hic istenmez.
    Q_INVOKABLE double satinalmaOnayEsigiGetir();

    // Kalem adi yazilirken cikan oneriler: daha once ayni adla yapilmis
    // alimlarin en son hali -- [{kalemAdi, birim, birimFiyat, paraBirimi, kur,
    // tedarikciAdi, urunLinki, tarih}]. "Bunu en son kactan almistik?"
    Q_INVOKABLE QVariantList satinalmaKalemOnerileri(const QString &arama, int enFazla = 8);

    // "Ne icin" (pres / sliper / tiraslama...) yazilirken cikan oneriler.
    Q_INVOKABLE QStringList satinalmaNeIcinOnerileri(const QString &arama, int enFazla = 8);

    // Daha once alim yapilan / fiyat bakilan internet siteleri (direnc.net,
    // Hepsiburada...); "nereden" alaninda kayitli tedarikcilerle birlikte onerilir.
    Q_INVOKABLE QStringList satinalmaSiteleriGetir();

    // Talep listesi. durumFiltresi: "acik" (teklif toplanan + kismen
    // siparisteki), "tamam", "iptal", "tumu". Her satir:
    // {talepId, talepNo, talepTarihi, isteyenBirim, isteyenKisi, ihtiyacTarihi,
    //  ihtiyacGunuKaldi, aciklama, kalemSayisi, siparisliKalemSayisi,
    //  firmaSayisi, neIcinOzeti, kalemOzeti, durum}
    Q_INVOKABLE QVariantList talepListesiGetir(const QString &durumFiltresi,
                                               const QString &arama = QString());

    // Talebi tum parcalariyla okur:
    // {talepId, talepNo, talepTarihi, isteyenBirim, isteyenKisi, ihtiyacTarihi,
    //  aciklama, iptal, durum,
    //  kalemler: [{talepKalemId, kalemAdi, neIcin, miktar, birim, aciklama,
    //              siparisNo, satinalmaId}],      // siparisNo > 0 ise kilitli
    //  firmalar: [{teklifFirmaId, tedarikciId, firmaAdi, kaynak, teklifLinki,
    //              paraBirimi, kur, teslimSuresiGun, notu}],
    //  fiyatlar: [{talepKalemId, teklifFirmaId, birimFiyat, secildi}],
    //  siparisler: [{satinalmaId, siparisNo, firmaAdi, durum, toplamTutarTL}]}
    Q_INVOKABLE QVariantMap talepGetir(int talepId);

    // Talebi kaydeder (talepId = 0 ise yeni). Kalem ve firmalar istemcinin
    // verdigi "anahtar" ile tanimlanir; fiyatlar bu anahtarlarla eslenir:
    //   {talepId, isteyenBirim, isteyenKisi, ihtiyacTarihi, aciklama,
    //    kalemler: [{anahtar, talepKalemId, kalemAdi, neIcin, miktar, birim}],
    //    firmalar: [{anahtar, teklifFirmaId, tedarikciId, firmaAdi, kaynak,
    //                teklifLinki, paraBirimi, kur, teslimSuresiGun, notu}],
    //    fiyatlar: [{kalemAnahtar, firmaAnahtar, birimFiyat, secildi}]}
    // Siparise donusmus kalemler DEGISTIRILMEZ ve silinemez (fiyat/secimleri
    // de korunur): siparisin dayandigi karsilastirma sonradan bozulmasin.
    // Donen: {basarili, talepId, talepNo, hata}
    Q_INVOKABLE QVariantMap talepKaydet(const QVariantMap &talep);

    // Talebi iptal eder (aktif siparisi olan talep iptal edilemez).
    Q_INVOKABLE QVariantMap talepIptalEt(int talepId, const QString &sebep);

    // Talepte SECILMIS ve henuz siparise donusmemis hucrelerden, firma bazinda
    // siparis olusturur. siparisBilgileri, firma basina:
    //   [{teklifFirmaId, teslimatSekli, beklenenTeslimTarihi, patronOnayli}]
    // Patron onay esigi, bu talepten ayni yere verilmis aktif siparislerle
    // birlikte denetlenir (parca parca siparisle esik asilmasin).
    // Talep once talepKaydet ile kaydedilmis olmalidir.
    // Donen: {basarili, siparisler: [{satinalmaId, siparisNo, firmaAdi, durum}], hata}
    Q_INVOKABLE QVariantMap talepSiparisOlustur(int talepId, const QVariantList &siparisBilgileri);

    // Siparis listesi. filtre: "tumu", "acik" (teslim alinmamis), "onay",
    // "geciken", "kismi", "tamam", "iptal". arama: siparis no / firma /
    // kalem adi / ne icin. Her satir:
    // {satinalmaId, siparisNo, talepNo, tedarikciAdi, durum, teslimatSekli,
    //  satinalmaTarihi, beklenenTeslimTarihi, gecikmeGunu, kalemSayisi,
    //  kalemOzeti, neIcinOzeti, toplamTutarTL, kargoFirmasi, kargoTakipNo}
    Q_INVOKABLE QVariantList siparisListesiGetir(const QString &filtre,
                                                 const QString &arama = QString());

    // Siparisi kalemleri ve dayandigi teklif karsilastirmasiyla okur.
    // Bulunamazsa bos harita doner.
    Q_INVOKABLE QVariantMap satinalmaGetir(int satinalmaId);

    // Sevkiyat bilgisi: {teslimatSekli, kargoFirmasi, kargoTakipNo,
    // beklenenTeslimTarihi, yolaCikti}. yolaCikti true ise siparis "Kargoda"
    // (ekranda: yolda) durumuna gecer.
    Q_INVOKABLE QVariantMap satinalmaSevkiyatGuncelle(int satinalmaId, const QVariantMap &bilgi);

    // Fatura: {faturaNo, faturaTarihi, faturaTutariTL, muhasebeyeIletildi}.
    Q_INVOKABLE QVariantMap satinalmaFaturaGuncelle(int satinalmaId, const QVariantMap &bilgi);

    // Modul ozeti (genel bakis + menu rozetleri):
    // {acikTalep, onayBekleyen, acikSiparis, yolda, geciken, buAyTutarTL,
    //  faturasiEksik}
    // acikTalep: siparise DONUSMEMIS kalemi olan talepler (is bekleyenler);
    // Talepler'deki "Açık" sekmesi ayrica malini bekleyen talepleri de gosterir.
    Q_INVOKABLE QVariantMap satinalmaOzetiGetir();

    // Durum degistirme (Kargoda / İptal / Reddedildi / geri alma).
    //
    // Teslim bilgisi BURADAN degistirilmez: 'Teslim Alındı' ve 'Kısmi Teslim'
    // yalnizca satinalmaTeslimAl ile olusur, cunku ikisi de kalem bazindaki
    // gelen adetlerden hesaplanir. Teslim alinmis bir siparis 'Sipariş
    // Verildi' istenerek geri alinir: gelen adetler sifirlanir ve siparis
    // teslimden onceki durumuna ('Sipariş Verildi' / 'Kargoda') doner. Iptal
    // edilen siparisin kalemleri talepte yeniden "acik" sayilir.
    //
    // Gecisler sunucuda denetlenir: mali gelmis (kismi / tam teslim) siparis
    // iptal edilemez, iptal edilmis siparis yeniden acilamaz, onay bekleyen
    // siparis onaysiz verilmis sayilamaz.
    Q_INVOKABLE QVariantMap satinalmaDurumGuncelle(int satinalmaId, const QString &yeniDurum,
                                                    const QString &redSebebi = QString());

    // Patronun sozlu onayini mudur isaretler (patronun programda hesabi yok).
    Q_INVOKABLE QVariantMap satinalmaOnayiIsaretle(int satinalmaId);

    // Teslim alma. gelenAdetler: [{satinalmaKalemId, gelenAdet}] -- toplam
    // gelen miktar (o ana kadar gelenlerin hepsi). Durum burada hesaplanir.
    // Donen: {basarili, durum, hata}
    Q_INVOKABLE QVariantMap satinalmaTeslimAl(int satinalmaId, const QVariantList &gelenAdetler);

    // Kismi teslim edilmis siparisin kalanini beklemeden kapatir (sebep
    // zorunlu): siparis 'Teslim Alındı' olur, eksik kapatma izi yazilir.
    // eksikleriTalebeAc: eksik miktarlar talepte yeni kalem olarak acilir.
    // Donen: {basarili, acilanKalemSayisi, hata}
    Q_INVOKABLE QVariantMap satinalmaEksikKapat(int satinalmaId, const QString &sebep,
                                                bool eksikleriTalebeAc);

    // musteriAraBaslat/urunAraBaslat icin sonuc sinyalleri. "arama" (ve urun icin
    // "dil") istegi yapan tarafa aynen geri gonderilir; QML tarafi bunu arama
    // kutusunun O ANKI metniyle karsilastirip eskimis sonuclari gormezden gelir.
    Q_SIGNAL void musteriSonuclariHazir(const QString &arama, const QVariantList &sonuclar);
    Q_SIGNAL void urunSonuclariHazir(const QString &arama, const QString &dil, const QVariantList &sonuclar);

    // *ListesiGetirBaslat sonuclari. "sonuc" bos harita ise sorgu
    // calistirilamamistir (baglanti yok) -- ekran bunu hata olarak gosterir.
    Q_SIGNAL void musteriListesiHazir(int istekNo, const QVariantMap &sonuc);
    Q_SIGNAL void urunListesiHazir(int istekNo, const QVariantMap &sonuc);
    Q_SIGNAL void personelListesiHazir(int istekNo, const QVariantMap &sonuc);
    Q_SIGNAL void tedarikciListesiHazir(int istekNo, const QVariantMap &sonuc);
    // gecmisTekliflerGetirBaslat sonucu (bos harita = baglanti kurulamadi).
    Q_SIGNAL void teklifListesiHazir(int istekNo, const QVariantMap &sonuc);

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
    // Kayit thread'inde cagrilirsa o thread'in baglantisini hazirlar.
    bool baglantiHazir();
    // Cagiran thread'in baglantisi: kayit thread'inde m_kayitDb, digerlerinde m_db.
    // Yalnizca kayit yolundaki (teklifKaydet / teklifDuzelt ve yardimcilari)
    // fonksiyonlar bunu kullanir; geri kalan her sey UI thread'inde m_db ile calisir.
    QSqlDatabase aktifDb() const;
    // Kullanicinin gorebildigi modul listesini (roller birlesik) getirir.
    QVariantList kullaniciModulleriniGetir(int kullaniciId);
    // Aktif oturumdaki kullanici bu modulde "duzenleyebilir" yetkisine sahip mi?
    bool modulDuzenleyebilirMi(const QString &modulKodu);
    // Aktif oturumdaki kullanici bu modulu gorebiliyor mu?
    bool modulGorebilirMi(const QString &modulKodu);
    // Worker'dan gelen cihaz listesini yetkiye gore ayiklayip yayinlar.
    void cihazListesiAyikla(int istekNo, const QVariantList &liste);
    // cihazListesiGetirBaslat aninda okunan yetki (ayiklama icin).
    bool m_cihazFiyatGorebilir = false;

    // Sistemde kac AKTIF yonetici var? (yoneticiSifresiDogrula ile ayni rol
    // kumesi: "Yönetici" ve goc donemindeki "Göç - Geçici Tam Yetkili".)
    // haricKullaniciId > 0 ise o kullanici sayima katilmaz -- "bu kisiyi
    // pasife alirsam yonetici kalir mi?" sorusunu cevaplamak icin.
    // Sorgu calismazsa -1 doner (bilinmiyor); cagiran taraf bunu "riskli"
    // sayip islemi reddeder.
    int aktifYoneticiSayisi(int haricKullaniciId);

    // Musteri/urun kalici olarak silinmeye calisildi ve FK kisitlamasi
    // engelledi: kullaniciya arsivlemeyi onermek icin ortak sonuc uretir.
    static QVariantMap iliskiliKayitSonucu(const QString &mesaj);

    // Girilen urun kodu BASKA bir urunde kullanilmis mi? haricUrunId > 0 ise
    // o kayit sayilmaz (guncellemede urunun kendi kodu catisma degildir).
    // Kod bos ise her zaman false: kod opsiyoneldir ve kodsuz urunler
    // tekillik kapsaminda degildir.
    // Bulunursa sahipOut o urunun aciklamasini tasir.
    bool urunKoduKullanimdaMi(const QString &urunKodu, int haricUrunId, QString &sahipOut);

    // teklifPdfOlustur ve uretimPdfOlustur'un ortak kismi: teklifin baslik +
    // kalem verisini TeklifPdfOlusturucu'nun bekledigi "veri" haritasina okur.
    // Basarisizsa false doner ve hataOut doldurulur.
    bool pdfVerisiniOku(int teklifId, QString &firmaAdiOut, QVariantMap &veriOut, QString &hataOut);

    // teklifKaydet ve teklifDuzelt'in ortak kismi: "teklif" haritasindaki
    // kalemleri (manuel kalemlerin "MANUEL-<teklifId>" urun satirlariyla birlikte)
    // ve toplamlari verilen teklife EKLER. Acik bir transaction icinde
    // cagrilmalidir; hata olursa false doner, hataOut doldurulur, rollback
    // cagiranin isidir.
    bool teklifIceriginiYaz(int teklifId, const QVariantMap &teklif, QString &hataOut);

    // teklifKaydet (revizyon): zincirde sevk/irsaliye kaydi olan en guncel
    // surumun kaydini yeni revizyona kopyalar (kayit yoksa hicbir sey yapmaz).
    // Acik transaction icinde cagrilmalidir; hata olursa false + hataOut.
    bool sevkBilgileriniRevizyonaKopyala(int kokTeklifId, int yeniTeklifId, QString &hataOut);

    // teklifDuzelt / teklifDuzeltilebilirMi'nin ortak kurali. Duzeltilemiyorsa
    // sebebi hataOut'a yazar.
    bool duzeltmeKuraliniDenetle(int teklifId, QString &hataOut);

    // teklifDurumGuncelle'nin gecmis kaydi; hata durumunda sadece uyari basar
    // (bkz. .cpp icindeki "best effort" notu).
    void durumDegisiminiLogla(int teklifId, const QString &eskiDurum, const QString &yeniDurum,
                              const QString &aciklama, int kullaniciId);

    // Kilit kurali (bkz. teklifTeslimatTarihiGuncelle ustundeki not): "Kabul Edildi"
    // ve "Tamamlandı" teklifler kilitlidir.
    static bool teklifKilitliMi(const QString &durum);
    // Teklifin guncel durumu; teklif bulunamazsa bos string.
    QString teklifDurumuGetir(int teklifId);
    // Bu kalemin satir bazli uretim bilgisi (tamamlandi/uretim notu) su an
    // yazilabilir mi? Kalem yoksa ya da bagli oldugu teklif "Tamamlandı" ise
    // false doner (bkz. teklifKalemTamamlandiGuncelle ustundeki kilit kurali).
    bool teklifKalemiUretimeAcikMi(int teklifKalemId);
    // dbo.teklifler.KopyaKaynakTeklifId sutunu var mi? (db/07_teklif_kopya_kaynagi.sql
    // calistirilmadiysa yoktur.) Sonuc bir kez sorgulanip saklanir -- script
    // program acikken calistirilirsa programin yeniden baslatilmasi gerekir. Kolon yoksa
    // "Kopya" akisi calismaya devam eder, yalnizca kaynak izi yazilmaz/okunmaz --
    // yani eksik script yuzunden teklif listesi veya kayit akisi BOZULMAZ.
    bool kopyaKolonuVarMi();

    // dbo.teklifler.TeklifNo sutunu var mi? (db/10_teklif_no.sql calistirilmadiysa
    // yoktur.) kopyaKolonuVarMi gibi bir kez sorgulanip saklanir. Kolon yoksa
    // Teklif No eskisi gibi TeklifId'den turetilir -- program bozulmaz.
    bool teklifNoKolonuVarMi() const;
    // Verilen tablo takma adi icin Teklif No'yu (revizyon eki olmadan, int) veren
    // SQL ifadesi. Numara okuyan/arayan TUM sorgular bunu kullanir; boylece
    // kolonun varligi/yoklugu tek yerde ele alinir.
    QString teklifNoSql(const QString &alias) const;
    // Kok teklifin Teklif No'su (revizyon ayni numarayi tasir); bulunamazsa 0.
    int kokTeklifNoGetir(int kokTeklifId);
    // Teklif/revizyon numarasi verme kilidi (sp_getapplock, transaction sonuna
    // kadar). Ayni anda kaydedilen iki teklif ayni Teklif No'yu, ayni teklifin
    // iki revizyonu ayni RevizyonNo'yu almasin diye. Acik bir transaction icinde
    // cagrilmalidir; basarisizsa false doner ve hataOut doldurulur.
    bool numaraKilidiAl(QString &hataOut);
    // Yeni (bagimsiz) teklif icin siradaki numara: en buyuk numara + 1.
    // numaraKilidiAl'dan SONRA, ayni transaction icinde cagrilmalidir.
    // Basarisizsa 0 doner ve hataOut doldurulur.
    int yeniTeklifNoAl(QString &hataOut);

    // Bu teklifin YERINE GECEN (ayni revizyon zincirinde daha yeni) teklifin
    // TeklifId'si; zincirin en son uyesi buysa 0, sorgu calismazsa -1
    // (bilinmiyor). Revize edilmis bir teklif uzerinde islem yapilip
    // yapilamayacagi buna gore belirlenir: yazma islemleri "!= 0" ise reddeder.
    int teklifYerineGecenIdGetir(int teklifId);

    // Satinalma tablolari (db/20) kurulu mu? Kurulu degilse satinalma
    // ekranlari islem yapmaz, betigin calistirilmasi gerektigini soyler.
    bool satinalmaSemasiHazirMi();
    // Talep / siparis numarasi (sp_getapplock ile korunur; transaction icinde).
    int satinalmaNoAl(const QString &tablo, const QString &kolon, QString &hataOut);
    // "LiyaErp_<kaynak>" uygulama kilidini transaction sonuna kadar alir.
    bool satinalmaKilidiAl(const QString &kaynak, QString &hataOut);

    QSqlDatabase m_db;
    bool m_baglantiHazir = false;
    QString m_sonHataMesaji;
    // Giris yapmis kullanici (bkz. aktifKullaniciId); 0 = oturum yok.
    int m_aktifKullaniciId = 0;
    // personelSifresiGetir'de ust uste yanlis PIN sayisi (oturum boyunca).
    int m_sifrePinHataSayisi = 0;
    // *ListesiGetirBaslat'in verdigi artan istek numarasi.
    int m_listeIstekSayaci = 0;
    QElapsedTimer m_sonKullanim;
    QElapsedTimer m_sonBaglantiDenemesi;

    // kopyaKolonuVarMi() onbellegi: -1 henuz sorgulanmadi, 0 yok, 1 var.
    // Kayit thread'i de okudugu icin atomik.
    std::atomic<int> m_kopyaKolonuDurumu{-1};
    // teklifNoKolonuVarMi() onbellegi (ayni anlamlar). const sorgu
    // metodlarindan (whereKosullariniOlustur) de okunabilsin diye mutable.
    mutable std::atomic<int> m_teklifNoKolonuDurumu{-1};

    // Verilen thread'i baslatip uzerinde kendi ODBC baglantisina sahip bir
    // worker olusturur (bkz. Database.cpp'deki "UC AYRI WORKER" notu).
    AramaWorker *workerBaslat(QThread &thread, const QString &baglantiAdi);

    // Her biri KENDI thread'i + KENDI ODBC baglantisi uzerinde calisir, boylece
    // birinde yasanan yavaslik digerlerini bekletmez:
    //   arama  -> Teklif Ver ekranindaki canli firma/urun aramasi
    //   liste  -> Musterilerim / Urunlerim / Personellerim / Tedarikcilerim
    //   teklif -> Giden / Alinan / Biten Tekliflerim (en agir sorgu)
    QThread m_aramaThread;
    QPointer<AramaWorker> m_aramaWorker;
    QThread m_listeThread;
    QPointer<AramaWorker> m_listeWorker;
    QThread m_teklifThread;
    QPointer<AramaWorker> m_teklifWorker;

    // Arka plan kaydi (teklifKaydetBaslat / teklifDuzeltBaslat). m_kayitBaglami
    // kayit thread'inde yasar; isler ona kuyruklanir. m_kayitDb ve yaninda duran
    // durum YALNIZCA kayit thread'inden kullanilir.
    QThread m_kayitThread;
    QObject *m_kayitBaglami = nullptr;
    QSqlDatabase m_kayitDb;
    QElapsedTimer m_kayitSonKullanim;
    QElapsedTimer m_kayitSonBaglantiDenemesi;
    QString m_kayitHataMesaji;
    int m_kayitIstekSayaci = 0;

    TeklifPdfOlusturucu m_pdfOlusturucu;
};
