#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QMarginsF>
#include <QDate>
#include <memory>

class QWebEnginePage;

// TeklifPdfOlusturucu: Teklif/Proforma ve Satis Sozlesmesi PDF'lerinin HTML
// sablonunu doldurup basma isinin TAMAMINI ustlenir. Veritabaniyla hicbir
// ilgisi yoktur -- Database sinifi sorgulari calistirip hazir veriyi
// (QVariantMap) buraya devreder, bu sinif sadece HTML uretip QtWebEngine
// (QWebEnginePage::printToPdf) ile PDF'e basar.
//
// ONIZLEME / INDIRME: *Uret fonksiyonlari PDF'i kullanicinin klasorune DEGIL,
// gecici onizleme klasorune (onizlemeKlasoru) basar. Kullanici onizleme
// penceresinde "İndir"e basarsa onizlemeyiKaydet ile kayitKlasoru'ne
// kopyalanir; basmazsa pencere kapanirken onizlemeyiSil ile silinir. Boylece
// her PDF goruntulemesi Belgelerim'e dosya birakmaz.
class TeklifPdfOlusturucu : public QObject
{
    Q_OBJECT

public:
    explicit TeklifPdfOlusturucu(QObject *parent = nullptr);
    ~TeklifPdfOlusturucu() override;

    // PDF basmakta kullanilan QtWebEngine sayfasini simdiden olusturur. Ilk
    // sayfa olusturulurken Chromium (tarayici sureci, profil, GPU) ayaga
    // kalkar -- olcumde ~1.8 sn ve bu sirada arayuz donar. Program acilirken
    // bir kez cagrilir (main.cpp), boylece ilk PDF butonunda beklenmez. Sayfa
    // tum PDF'lerde tekrar kullanilir. Cagrilmasa da htmlyiPdfeBas kendisi cagirir.
    void motoruHazirla() const;

    // Indirilen PDF'lerin klasoru: Belgelerim/Liya ERP Teklifler.
    static QString kayitKlasoru();

    // Onizleme icin basilan gecici PDF'lerin klasoru (%TEMP%/LiyaERP_Onizleme).
    static QString onizlemeKlasoru();

    // Onizleme PDF'ini (*Uret'in dondurdugu dosyaYolu) kayitKlasoru'ne
    // "dosyaAdi" adiyla kopyalar; ayni adda dosya varsa uzerine yazar.
    // Kaynak onizleme klasorunun disindaysa reddeder.
    // Donen: {basarili (bool), dosyaYolu (kaydedilen yol), klasor, hata}.
    static QVariantMap onizlemeyiKaydet(const QString &onizlemeYolu, const QString &dosyaAdi);

    // Onizleme PDF'ini siler (onizleme klasoru disindaki yollara dokunmaz).
    static void onizlemeyiSil(const QString &onizlemeYolu);

    // "veri" anahtarlari (Database::teklifPdfOlustur tarafindan doldurulur):
    //   firmaAdresi, ilgiliKisi, ilgiliKisiTelefonu, ilgiliKisiEposta,
    //   teslimatSekli, teslimatYeri, personelAdSoyad, personelTelefon,
    //   dil (TR/EN), paraBirimi (string: TL/USD/EUR), olusturmaTarihi (string, dd.MM.yyyy),
    //   genelIndirimOrani, kdvOrani, indirimliToplam, kdvTutari, genelToplam,
    //   paketlemeUcreti, tasimaUcreti (double),
    //   teslimatTarihi (string, dd.MM.yyyy, OPSIYONEL): planlanan teslim tarihi;
    //             doluysa teslimat blogunda gosterilir,
    //   kalemler (QVariantList<QVariantMap{adet, birimFiyat, indirimliBirimFiyat,
    //             toplamTutar, urunKodu, urunAciklamasi}>),
    //   kokTeklifNo (int) + revizyonNo (int): belgeye basilacak teklif numarasi
    //             (bkz. teklifNoMetni -- revizyonlarda "1203/Rev.2"),
    //   durum (string) + guncelRevizyonNo (int, OPSIYONEL): durum "Revize Edildi"
    //             ise belgenin ustune "gecerli degildir" bandi basilir ve bandda
    //             yerine gecen revizyonun numarasi yazilir,
    //   sozlesmeMetni (string, OPSIYONEL): teklifin son sayfasindaki satis
    //             sozlesmesi maddeleri (duz metin, bkz. varsayilanSozlesmeMetni).
    //             Bos birakilirsa dilin varsayilan metni kullanilir.
    // Donen: {basarili (bool), dosyaYolu (onizleme PDF'i), dosyaAdi (indirilince
    // verilecek ad), hata (string)}.
    QVariantMap teklifPdfUret(int teklifId, const QString &firmaAdi, const QVariantMap &veri);

    // Teklif PDF'inin son sayfasindaki satis sozlesmesi maddelerinin FABRIKA
    // VARSAYILANI (dil'e gore TR/EN). Bicim kasitli olarak DUZ METINDIR, cunku
    // kullanici bunu "Satış Sözleşmesi" penceresinde serbestce duzenliyor:
    //   - her satir bir numarali madde olur,
    //   - "- " ile baslayan satirlar, ustundeki maddenin alt madde isareti olur,
    //   - bos satirlar yok sayilir.
    // HTML'e cevirme isi sozlesmeMetniniHtmleCevir'de yapilir.
    static QString varsayilanSozlesmeMetni(bool ingilizce);

    // {{GECERLILIK_TARIHI}} gun sayisi verilmeden yazildiginda bugune eklenen gun.
    static constexpr int kVarsayilanGecerlilikGunu = 3;

    // Sozlesme metnindeki teklife bagli isaretleri doldurur (metin kullanici
    // tarafindan duzenlense de calisir, boylece gomulu "DOLAR", "KDV dahil"
    // gibi ifadeler teklifin secimleriyle celismez):
    //   Satir basi kosullar (saglanmazsa satir atilir; yan yana birden fazla yazilabilir):
    //     [DOVIZ] / [TL]                 -> para birimi USD/EUR mi, TL mi
    //     [KDV_DAHIL] / [KDV_HARIC]      -> kdvOrani > 0 mi
    //     [NAKLIYE_DAHIL] / [NAKLIYE_HARIC] -> tasimaUcreti > 0 mi
    //   Degiskenler:
    //     {{PARA_BIRIMI}} (ör. "Amerikan Doları (USD)"), {{PARA_KODU}} (USD/EUR/TL),
    //     {{KDV_DURUMU}} ("%20 KDV dahildir" / "KDV hariçtir"), {{KDV_ORANI}},
    //     {{TARIH}} (bugun), {{GECERLILIK_TARIHI}} (bugun + kVarsayilanGecerlilikGunu),
    //     {{GECERLILIK_TARIHI+N}} (bugun + N gun), {{TESLIMAT_SEKLI}}, {{TESLIMAT_YERI}}.
    // Tarihler TR'de dd.MM.yyyy, EN'de dd/MM/yyyy yazilir.
    static QString sozlesmeDegiskenleriniUygula(const QString &metin, const QVariantMap &veri,
                                                bool ingilizce, const QDate &bugun);

    // varsayilanSozlesmeMetni'nde anlatilan duz metin bicimini, teklif.html'deki
    // {{SOZLESME_MADDELERI}} yer tutucusuna girecek <ol>/<ul> yapisina cevirir.
    // Metin HTML olarak kacislanir -- kullanicinin yazdigi "&" veya "<" gibi
    // karakterler sablonu bozmaz.
    static QString sozlesmeMetniniHtmleCevir(const QString &metin);

    // "veri" anahtarlari (Database::satisSozlesmesiOlustur tarafindan doldurulur):
    //   firmaAdi, firmaAdresi, ilgiliKisi, teslimatSekli, teslimatYeri,
    //   paraBirimi, dil (TR/EN), genelToplam (double),
    //   kalemler (QVariantList<QVariantMap{aciklama, adet, indirimliBirimFiyat, toplamTutar}>)
    // Donen: {basarili (bool), dosyaYolu (onizleme PDF'i), dosyaAdi, hata (string)}.
    QVariantMap satisSozlesmesiUret(const QVariantMap &veri);

    // Teknik ekibe verilecek URETIM PDF'i. teklifPdfUret ile ayni "veri"
    // haritasini ve ayni antetli sablonu (teklif.html) kullanir, ancak:
    //   - kapak sayfasi ve satis sozlesmesi sayfasi cikarilir,
    //   - hicbir fiyat/toplam basilmaz (sadece No, Urun Kodu, Aciklama, Adet),
    //   - teklifin diline bakilmaksizin HER ZAMAN Turkce basilir (EN teklifte
    //     kalem aciklamasi icin katalogdaki TR metin -- "urunAciklamasiTr" -- kullanilir),
    //   - bilgi blogunda kabul tarihi, planlanan teslim tarihi, teslimat
    //     sekli/yeri; tablonun altinda uretim notu (varsa) yer alir. Teklif notu,
    //     musterinin ilgili kisi/telefon bilgisi ve "kac kalem bitti" ozeti basilmaz.
    // Ek "veri" anahtarlari: uretimNotu, teslimatTarihi, kabulTarihi (string, dd.MM.yyyy).
    // Donen: {basarili (bool), dosyaYolu (onizleme PDF'i), dosyaAdi, hata (string)}.
    QVariantMap uretimPdfUret(int teklifId, const QString &firmaAdi, const QVariantMap &veri);

    // TEKLIF NUMARASI -- PDF'lerde VE programin her yerinde (liste, mesajlar,
    // bkz. Database::teklifNoGetir) gosterilen tek numara. Bir revizyon
    // veritabaninda yeni bir TeklifId ile durur, ama kok numara uzerinden
    // "1203/Rev.2" seklinde gosterilir -- aksi halde revizyon ayri bir teklif
    // gibi gorunur ve ikisi ayni anda gecerli sanilirdi. Revizyon olmayan
    // tekliflerde sadece "1203" yazilir.
    // dosyaAdiIcin=true, dosya adinda kullanilamayan "/" yerine "-" koyar
    // ("Teklif_1203-Rev2_Firma.pdf").
    // veri anahtarlari: kokTeklifNo (int), revizyonNo (int) -- bkz. Database::pdfVerisiniOku.
    static QString teklifNoMetni(int teklifId, const QVariantMap &veri, bool dosyaAdiIcin = false);

private:
    // HTML sablon dosyasini diskten okur. Debug derlemede once proje kaynak
    // agacindaki pdf_sablonlari/ klasorunden (PDF_SABLON_KAYNAK_DIZINI define'i
    // ile), oradan bulunamazsa exe'nin yanindaki kopyadan okur.
    QString sabloniOku(const QString &dosyaAdi, QString &hataOut) const;

    // "{{ANAHTAR}}" bicimli yer tutuculari, "degerler" haritasindaki
    // karsiliklarla degistirir (basit string replace).
    QString yerKoyucuDoldur(QString sablon, const QVariantMap &degerler) const;

    // Teklif urun kalemleri icin <tr> satirlarini uretir (zebra deseni dahil).
    QString kalemSatirlariUret(const QVariantList &kalemler, bool indirimVar,
                                double genelIndirimOrani, double &rawToplamOut,
                                const QString &paraBirimi) const;

    // Satis sozlesmesi urun kalemleri icin <tr> satirlarini uretir.
    QString sozlesmeKalemSatirlariUret(const QVariantList &kalemler, const QString &paraBirimi) const;

    // Toplam blogu satirlarini uretir (indirim/KDV/paketleme/tasima sadece
    // degeri > 0 ise gosterilir).
    QString toplamSatirlariUret(bool indirimVar, bool kdvVar, bool paketlemeVar, bool tasimaVar,
                                 double genelIndirimOrani, double kdvOrani,
                                 double rawToplam, double indirimliToplam,
                                 double kdvTutari, double paketlemeUcreti, double tasimaUcreti,
                                 double genelToplam, bool ingilizce, const QString &paraBirimi) const;

    // "html" icerigini QWebEnginePage ile PDF'e basar (A4). Kenar bosluklari
    // varsayilan olarak 15mm'dir; teklif.html gibi antetli kagit uzerine basilan
    // sablonlarda kenar bosluklari 0 gecilir, gercek bosluk sablonun kendi CSS
    // padding'i ile verilir (boylece antet/altbilgi bantlari sayfa kenarina
    // tam dayanabilir). printToPdf asenkron oldugu icin icerde bir QEventLoop
    // ile senkron hale getirilir.
    bool htmlyiPdfeBas(const QString &html, const QString &dosyaYolu, QString &hataOut,
                        QMarginsF kenarBosluklariMm = QMarginsF(15, 15, 15, 15)) const;

    // "html"i onizleme klasorune benzersiz adla basar ve *Uret'lerin ortak
    // donus haritasini ({basarili, dosyaYolu, dosyaAdi, hata}) hazirlar.
    // Ayni HTML daha once basildiysa onbellekteki PDF kopyalanir.
    QVariantMap onizlemeyeBas(const QString &html, const QString &dosyaAdi,
                               QMarginsF kenarBosluklariMm) const;

    // motoruHazirla ile olusturulan, tum PDF'lerde tekrar kullanilan sayfa.
    mutable std::unique_ptr<QWebEnginePage> m_sayfa;

    // TR locale (nokta/virgul) ile sayiyi bicimlendirip, "paraBirimi"ne (TL/USD/EUR)
    // gore dogru sembolu (₺/$/€) sonuna ekler -- ekrandaki (TeklifVerPage.qml
    // paraFormat + paraBirimiSembol) ile ayni gosterim kurali.
    static QString paraFormati(double tutar, const QString &paraBirimi);

    // Dosya adindaki yasak karakterleri "_" yapar.
    static QString dosyaAdiTemizle(const QString &ad);
};
