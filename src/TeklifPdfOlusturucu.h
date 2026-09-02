#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QMarginsF>

// TeklifPdfOlusturucu: Teklif/Proforma ve Satis Sozlesmesi PDF'lerinin HTML
// sablonunu doldurup basma isinin TAMAMINI ustlenir. Veritabaniyla hicbir
// ilgisi yoktur -- Database sinifi sorgulari calistirip hazir veriyi
// (QVariantMap) buraya devreder, bu sinif sadece HTML uretip QtWebEngine
// (QWebEnginePage::printToPdf) ile PDF'e basar.
class TeklifPdfOlusturucu : public QObject
{
    Q_OBJECT

public:
    explicit TeklifPdfOlusturucu(QObject *parent = nullptr);

    // "veri" anahtarlari (Database::teklifPdfOlustur tarafindan doldurulur):
    //   firmaAdresi, ilgiliKisi, ilgiliKisiTelefonu, ilgiliKisiEposta,
    //   teslimatSekli, teslimatYeri, personelAdSoyad, personelTelefon,
    //   dil (TR/EN), olusturmaTarihi (string, dd.MM.yyyy),
    //   genelIndirimOrani, kdvOrani, indirimliToplam, kdvTutari, genelToplam,
    //   paketlemeUcreti, tasimaUcreti (double),
    //   kalemler (QVariantList<QVariantMap{adet, birimFiyat, indirimliBirimFiyat,
    //             toplamTutar, urunKodu, urunAciklamasi}>)
    // Donen: {basarili (bool), dosyaYolu (string), hata (string)}.
    QVariantMap teklifPdfUret(int teklifId, const QString &firmaAdi, const QVariantMap &veri);

    // "veri" anahtarlari (Database::satisSozlesmesiOlustur tarafindan doldurulur):
    //   firmaAdi, firmaAdresi, ilgiliKisi, teslimatSekli, teslimatYeri,
    //   paraBirimi, dil (TR/EN), genelToplam (double),
    //   kalemler (QVariantList<QVariantMap{aciklama, adet, indirimliBirimFiyat, toplamTutar}>)
    // Donen: {basarili (bool), dosyaYolu (string), hata (string)}.
    QVariantMap satisSozlesmesiUret(const QVariantMap &veri);

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
                                double genelIndirimOrani, double &rawToplamOut) const;

    // Satis sozlesmesi urun kalemleri icin <tr> satirlarini uretir.
    QString sozlesmeKalemSatirlariUret(const QVariantList &kalemler) const;

    // Toplam blogu satirlarini uretir (indirim/KDV/paketleme/tasima sadece
    // degeri > 0 ise gosterilir).
    QString toplamSatirlariUret(bool indirimVar, bool kdvVar, bool paketlemeVar, bool tasimaVar,
                                 double genelIndirimOrani, double kdvOrani,
                                 double rawToplam, double indirimliToplam,
                                 double kdvTutari, double paketlemeUcreti, double tasimaUcreti,
                                 double genelToplam, bool ingilizce) const;

    // "html" icerigini QWebEnginePage ile PDF'e basar (A4). Kenar bosluklari
    // varsayilan olarak 15mm'dir; teklif.html gibi antetli kagit uzerine basilan
    // sablonlarda kenar bosluklari 0 gecilir, gercek bosluk sablonun kendi CSS
    // padding'i ile verilir (boylece antet/altbilgi bantlari sayfa kenarina
    // tam dayanabilir). printToPdf asenkron oldugu icin icerde bir QEventLoop
    // ile senkron hale getirilir.
    bool htmlyiPdfeBas(const QString &html, const QString &dosyaYolu, QString &hataOut,
                        QMarginsF kenarBosluklariMm = QMarginsF(15, 15, 15, 15)) const;

    // TR locale + ₺ sembolu ile parasal deger bicimlendirir.
    static QString paraFormati(double tutar);

    // Dosya adindaki yasak karakterleri "_" yapar.
    static QString dosyaAdiTemizle(const QString &ad);
};
