#include "TeklifPdfOlusturucu.h"

#include <QCoreApplication>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDateTime>
#include <QDate>
#include <QHash>
#include <QLocale>
#include <QEventLoop>
#include <QTimer>
#include <QWebEnginePage>
#include <QPageLayout>
#include <QPageSize>
#include <QMarginsF>
#include <QTemporaryFile>
#include <QUrl>

TeklifPdfOlusturucu::TeklifPdfOlusturucu(QObject *parent) : QObject(parent)
{
}

QString TeklifPdfOlusturucu::sabloniOku(const QString &dosyaAdi, QString &hataOut) const
{
    auto oku = [](const QString &yol) -> QString {
        QFile dosya(yol);
        if (!dosya.exists() || !dosya.open(QIODevice::ReadOnly | QIODevice::Text))
            return QString();
        QTextStream akis(&dosya);
        akis.setEncoding(QStringConverter::Utf8);
        return akis.readAll();
    };

#ifdef PDF_SABLON_KAYNAK_DIZINI
    const QString kaynakYolu = QStringLiteral(PDF_SABLON_KAYNAK_DIZINI "/") + dosyaAdi;
    const QString kaynakIcerik = oku(kaynakYolu);
    if (!kaynakIcerik.isEmpty())
        return kaynakIcerik;
#endif

    const QString deployYolu = QCoreApplication::applicationDirPath() + "/pdf_sablonlari/" + dosyaAdi;
    const QString icerik = oku(deployYolu);
    if (icerik.isEmpty())
        hataOut = QStringLiteral("PDF sablonu bulunamadi: %1").arg(deployYolu);
    return icerik;
}

QString TeklifPdfOlusturucu::yerKoyucuDoldur(QString sablon, const QVariantMap &degerler) const
{
    for (auto it = degerler.constBegin(); it != degerler.constEnd(); ++it)
        sablon.replace(QStringLiteral("{{%1}}").arg(it.key()), it.value().toString());
    return sablon;
}

QString TeklifPdfOlusturucu::kalemSatirlariUret(const QVariantList &kalemler, bool indirimVar,
                                                 double genelIndirimOrani, double &rawToplamOut,
                                                 const QString &paraBirimi) const
{
    Q_UNUSED(genelIndirimOrani);

    QString html;
    rawToplamOut = 0.0;
    int satirNo = 0;
    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap k = kalemVar.toMap();
        ++satirNo;
        const int adet = k.value("adet").toInt();
        const double birimFiyat = k.value("birimFiyat").toDouble();
        const double indirimliBirimFiyat = k.value("indirimliBirimFiyat").toDouble();
        const double toplamTutar = k.value("toplamTutar").toDouble();
        rawToplamOut += birimFiyat * adet;

        // Zebra deseni satirNo'ya (sorgudaki/listedeki sira) gore hesaplanir.
        const QString satirSinifi = (satirNo % 2 == 0) ? QStringLiteral(" class='zebra'") : QString();
        html += QStringLiteral("<tr%1>").arg(satirSinifi);
        html += QStringLiteral("<td>%1</td>").arg(satirNo);
        html += QStringLiteral("<td>%1</td>").arg(k.value("urunKodu").toString().toHtmlEscaped());
        html += QStringLiteral("<td>%1</td>").arg(k.value("urunAciklamasi").toString().toHtmlEscaped());
        html += QStringLiteral("<td class='sag'>%1</td>").arg(adet);
        html += QStringLiteral("<td class='sag'>%1</td>").arg(paraFormati(birimFiyat, paraBirimi));
        if (indirimVar)
            html += QStringLiteral("<td class='sag'>%1</td>").arg(paraFormati(indirimliBirimFiyat, paraBirimi));
        html += QStringLiteral("<td class='sag'>%1</td>").arg(paraFormati(toplamTutar, paraBirimi));
        html += QStringLiteral("</tr>");
    }
    return html;
}

QString TeklifPdfOlusturucu::sozlesmeKalemSatirlariUret(const QVariantList &kalemler, const QString &paraBirimi) const
{
    QString html;
    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap k = kalemVar.toMap();
        html += QStringLiteral(
            "<tr>"
            "<td>%1</td>"
            "<td class='orta'>%2</td>"
            "<td class='sag'>%3</td>"
            "<td class='sag'>%4</td>"
            "</tr>")
            .arg(k.value("aciklama").toString().toHtmlEscaped())
            .arg(k.value("adet").toInt())
            .arg(paraFormati(k.value("indirimliBirimFiyat").toDouble(), paraBirimi))
            .arg(paraFormati(k.value("toplamTutar").toDouble(), paraBirimi));
    }
    return html;
}

QString TeklifPdfOlusturucu::varsayilanSozlesmeMetni(bool ingilizce)
{
    // ONEMLI: Bu maddeler eskiden teklif.html/teklif_en.html icine GOMULU idi ve
    // degistirilebilmesi icin sablonun elle duzenlenmesi gerekiyordu. Artik
    // sablonda sadece {{SOZLESME_MADDELERI}} yer tutucusu var; varsayilan metin
    // burada duruyor ve kullanici "Satış Sözleşmesi" penceresinden teklif basina
    // degistirebiliyor (degisiklik dbo.teklifler.SatisSozlesmesiMetni'ne yazilir).
    //
    // Para birimi, KDV, nakliye ve gecerlilik tarihi GOMULU YAZILMAZ: metin
    // {{DEGISKEN}} ve satir basi [KOSUL] isaretleri icerir, PDF basilirken
    // sozlesmeDegiskenleriniUygula() bunlari teklifteki secimlere gore doldurur.
    if (ingilizce)
    {
        return QStringLiteral(
            "Prices are given in {{PARA_BIRIMI}}, {{KDV_DURUMU}}.\n"
            "Mode of payment: 100% bank transfer in advance as order confirmation.\n"
            "Warranty: 1 year.\n"
            "Delivery: Ex-Works Ankara, Turkey in 2–3 weeks after payment date.\n"
            "Quotation valid until {{GECERLILIK_TARIHI}}.\n"
            "[NAKLIYE_HARIC] Freight costs are given as Ex-Works.\n"
            "[NAKLIYE_DAHIL] Freight costs are included in the quotation.\n"
            "Calibration will be charged separately.\n"
            "Installation of equipment and training will be charged separately. The air freight and "
            "accommodation belong to buyer. 150 USD subsistence should be paid for a technical personnel per day.\n"
            "Bank details:\n"
            "- Bank name: Türkiye Halkbankası A.Ş.\n"
            "- Bank address: İvedik Mah. 1368. Cad. Daire:61/C Yenimahalle/Ankara/Turkey\n"
            "- Branch name: İvedik Organize Sanayi\n"
            "- Branch code: 0414\n"
            "- Account name: Liya Test Laboratuvar Cih. İmlt Dış Tic. Ltd. Şti.\n"
            "- Swift code: TRHBTR2A\n"
            "- IBAN number: TR68 0001 2009 4140 0053 0008 14 (USD)\n"
            "- IBAN number: TR74 0001 2009 4140 0058 0006 68 (EUR)");
    }

    return QStringLiteral(
        "[DOVIZ] Fiyatımız {{PARA_BIRIMI}} cinsinden belirtilmiş olup, {{KDV_DURUMU}}. İş bu fatura "
        "ödemesinin, ödeme tarihindeki TCMB DÖVİZ EFEKTİF SATIŞ KURU ile Türk Lirası’na çevrilerek "
        "yapılması gerekmektedir. Aksi durumda kesilecek kur farkı faturasının tahsili yapılacaktır.\n"
        "[TL] Fiyatımız {{PARA_BIRIMI}} cinsinden belirtilmiş olup, {{KDV_DURUMU}}.\n"
        "Cihaz ücreti: %30’u sipariş sırasında peşin, kalan tutar teslimatta ödenecektir.\n"
        "Cihazlar; 1 yıl mekanik, 2 yıl elektronik parça olarak ücretsiz servis garantilidir. 10 yıl "
        "süreyle ücreti karşılığı teknik servis ve eğitim hizmeti verilecektir.\n"
        "Cihaz Teslimatı: Siparişe istinaden 1 hafta içinde teslim.\n"
        "Teklif Opsiyonu: Teklif {{GECERLILIK_TARIHI}} tarihine kadar geçerlidir.\n"
        "[NAKLIYE_HARIC] Nakliye: Alıcı firmaya aittir.\n"
        "[NAKLIYE_DAHIL] Nakliye: Teklif tutarına dahildir.\n"
        "Alternatif olarak sunulan cihaz bedelleri, toplam teklif tutarına dahil edilmemiştir.\n"
        "Banka Bilgilerimiz: Liya Laboratuvar Test Cihazları İmalat ve Dış Ticaret A.Ş.\n"
        "- İŞ BANKASI TR16 0006 4000 0014 1520 1653 38\n"
        "- HALK BANKASI TR51 0001 2009 4140 0010 2645 69");
}

QString TeklifPdfOlusturucu::sozlesmeDegiskenleriniUygula(const QString &metin, const QVariantMap &veri,
                                                          bool ingilizce, const QDate &bugun)
{
    const QString paraBirimi = veri.value("paraBirimi").toString().trimmed().toUpper();
    const double kdvOrani = veri.value("kdvOrani").toDouble();
    const bool dovizMi = paraBirimi == QStringLiteral("USD") || paraBirimi == QStringLiteral("EUR");
    const bool kdvDahil = kdvOrani > 0.0001;
    const bool nakliyeDahil = veri.value("tasimaUcreti").toDouble() > 0.0001;

    // --- Satir basi kosullari: kosulu saglamayan satir tamamen atilir ---
    const QHash<QString, bool> kosullar = {
        { QStringLiteral("DOVIZ"), dovizMi },
        { QStringLiteral("TL"), !dovizMi },
        { QStringLiteral("KDV_DAHIL"), kdvDahil },
        { QStringLiteral("KDV_HARIC"), !kdvDahil },
        { QStringLiteral("NAKLIYE_DAHIL"), nakliyeDahil },
        { QStringLiteral("NAKLIYE_HARIC"), !nakliyeDahil },
    };

    static const QRegularExpression kosulDeseni(QStringLiteral("^\\s*(-\\s+|•\\s+)?\\[([A-Z_]+)\\]\\s*"));
    QStringList cikti;
    for (QString satir : metin.split(QRegularExpression("\r\n|\n|\r")))
    {
        bool gecerli = true;
        // Birden fazla kosul yan yana yazilabilir: "[DOVIZ] [KDV_DAHIL] ..." (hepsi saglanmali).
        // Tanimsiz koseli parantezler ("[Not] ...") dokunulmadan metinde kalir.
        forever
        {
            const QRegularExpressionMatch m = kosulDeseni.match(satir);
            if (!m.hasMatch() || !kosullar.contains(m.captured(2)))
                break;
            gecerli = gecerli && kosullar.value(m.captured(2));
            // Alt madde isareti ("- ") varsa korunur, sadece kosul etiketi silinir.
            satir = m.captured(1) + satir.mid(m.capturedEnd());
        }
        if (gecerli)
            cikti << satir;
    }
    QString sonuc = cikti.join(QLatin1Char('\n'));

    // --- {{DEGISKEN}} yer tutuculari ---
    QString paraBirimiAdi;
    if (paraBirimi == QStringLiteral("USD"))
        paraBirimiAdi = ingilizce ? QStringLiteral("US Dollars (USD)") : QStringLiteral("Amerikan Doları (USD)");
    else if (paraBirimi == QStringLiteral("EUR"))
        paraBirimiAdi = ingilizce ? QStringLiteral("Euro (EUR)") : QStringLiteral("Euro (EUR)");
    else
        paraBirimiAdi = ingilizce ? QStringLiteral("Turkish Lira (TRY)") : QStringLiteral("Türk Lirası (TL)");

    static const QLocale trLocale(QLocale::Turkish, QLocale::Turkey);
    static const QLocale enLocale(QLocale::English, QLocale::UnitedStates);
    const QString kdvOraniYazi = (ingilizce ? enLocale : trLocale).toString(kdvOrani, 'g', 4);
    const QString kdvDurumu = kdvDahil
        ? (ingilizce ? QStringLiteral("including %1% VAT").arg(kdvOraniYazi)
                     : QStringLiteral("%%1 KDV dahildir").arg(kdvOraniYazi))
        : (ingilizce ? QStringLiteral("excluding VAT") : QStringLiteral("KDV hariçtir"));

    const QString tarihBicimi = ingilizce ? QStringLiteral("dd/MM/yyyy") : QStringLiteral("dd.MM.yyyy");

    sonuc.replace(QStringLiteral("{{PARA_BIRIMI}}"), paraBirimiAdi);
    sonuc.replace(QStringLiteral("{{PARA_KODU}}"), paraBirimi.isEmpty() ? QStringLiteral("TL") : paraBirimi);
    sonuc.replace(QStringLiteral("{{KDV_ORANI}}"), kdvOraniYazi);
    sonuc.replace(QStringLiteral("{{KDV_DURUMU}}"), kdvDurumu);
    sonuc.replace(QStringLiteral("{{TARIH}}"), bugun.toString(tarihBicimi));
    sonuc.replace(QStringLiteral("{{TESLIMAT_SEKLI}}"), veri.value("teslimatSekli").toString().trimmed());
    sonuc.replace(QStringLiteral("{{TESLIMAT_YERI}}"), veri.value("teslimatYeri").toString().trimmed());

    // {{GECERLILIK_TARIHI}} = bugun + varsayilan gun; {{GECERLILIK_TARIHI+N}} = bugun + N gun.
    static const QRegularExpression gecerlilikDeseni(QStringLiteral("\\{\\{GECERLILIK_TARIHI(?:\\s*\\+\\s*(\\d{1,4}))?\\}\\}"));
    QString doldurulmus;
    qsizetype son = 0;
    auto it = gecerlilikDeseni.globalMatch(sonuc);
    while (it.hasNext())
    {
        const QRegularExpressionMatch m = it.next();
        const int gun = m.captured(1).isEmpty() ? kVarsayilanGecerlilikGunu : m.captured(1).toInt();
        doldurulmus += sonuc.mid(son, m.capturedStart() - son);
        doldurulmus += bugun.addDays(gun).toString(tarihBicimi);
        son = m.capturedEnd();
    }
    doldurulmus += sonuc.mid(son);

    return doldurulmus;
}

QString TeklifPdfOlusturucu::sozlesmeMetniniHtmleCevir(const QString &metin)
{
    const QStringList satirlar = metin.split(QRegularExpression("\r\n|\n|\r"));

    QString html = QStringLiteral("<ol>");
    bool maddeAcikMi = false;   // <li> kapatilmayi bekliyor mu
    bool altListeAcikMi = false; // alt maddeler icin <ul> acik mi

    for (const QString &hamSatir : satirlar)
    {
        const QString satir = hamSatir.trimmed();
        if (satir.isEmpty())
            continue;

        // "- " / "• " ile baslayan satirlar, ustundeki maddenin alt maddesidir
        // (varsayilan metindeki banka hesaplari boyle yaziliyor).
        const bool altMadde = satir.startsWith(QStringLiteral("- ")) || satir.startsWith(QStringLiteral("• "));
        if (altMadde && maddeAcikMi)
        {
            if (!altListeAcikMi)
            {
                html += QStringLiteral("<ul>");
                altListeAcikMi = true;
            }
            html += QStringLiteral("<li>%1</li>").arg(satir.mid(2).trimmed().toHtmlEscaped());
            continue;
        }

        // Yeni bir ana madde: once acik olan alt liste/madde kapatilir.
        if (altListeAcikMi)
        {
            html += QStringLiteral("</ul>");
            altListeAcikMi = false;
        }
        if (maddeAcikMi)
            html += QStringLiteral("</li>");

        // Ilk satir alt madde isaretiyle basliyorsa (ustunde ana madde yok)
        // isareti atip normal madde gibi yaziyoruz -- yapisi bozuk metin de
        // PDF'i bozmasin.
        const QString icerik = altMadde ? satir.mid(2).trimmed() : satir;
        html += QStringLiteral("<li>%1").arg(icerik.toHtmlEscaped());
        maddeAcikMi = true;
    }

    if (altListeAcikMi)
        html += QStringLiteral("</ul>");
    if (maddeAcikMi)
        html += QStringLiteral("</li>");
    html += QStringLiteral("</ol>");

    return html;
}

QString TeklifPdfOlusturucu::toplamSatirlariUret(bool indirimVar, bool kdvVar, bool paketlemeVar, bool tasimaVar,
                                                  double genelIndirimOrani, double kdvOrani,
                                                  double rawToplam, double indirimliToplam,
                                                  double kdvTutari, double paketlemeUcreti, double tasimaUcreti,
                                                  double genelToplam, bool ingilizce, const QString &paraBirimi) const
{
    const QString etkToplamFiyat = ingilizce ? QStringLiteral("Total Price") : QStringLiteral("Toplam Fiyat");
    const QString etkIndirimliToplamEtk = ingilizce ? QStringLiteral("Discounted Total") : QStringLiteral("İndirimli Toplam");
    const QString etkKdv = ingilizce ? QStringLiteral("VAT") : QStringLiteral("KDV");
    const QString etkPaketleme = ingilizce ? QStringLiteral("Packaging Fee") : QStringLiteral("Paketleme Ücreti");
    const QString etkTasima = ingilizce ? QStringLiteral("Shipping Fee") : QStringLiteral("Taşıma Ücreti");
    const QString etkGenelToplam = ingilizce ? QStringLiteral("Grand Total") : QStringLiteral("Genel Toplam");

    QString html;
    auto satirEkle = [&](const QString &etiket, const QString &deger, bool kalinMi)
    {
        const QString satirSinifi = kalinMi ? QStringLiteral(" class='genel-toplam'") : QString();
        html += QStringLiteral("<tr%1><td>%2:</td><td class='sag'>%3</td></tr>")
            .arg(satirSinifi, etiket, deger);
    };

    // Sira SABIT: Toplam Fiyat -> (varsa) Indirimli Toplam -> (varsa) Paketleme ->
    // (varsa) Tasima -> (varsa) KDV -> Genel Toplam (her zaman, en altta, kalin).
    satirEkle(etkToplamFiyat, paraFormati(rawToplam, paraBirimi), false);
    if (indirimVar)
        satirEkle(etkIndirimliToplamEtk + QStringLiteral("(%") + QString::number(genelIndirimOrani, 'f', 0) + QStringLiteral(")"),
                   paraFormati(indirimliToplam, paraBirimi), false);
    if (paketlemeVar)
        satirEkle(etkPaketleme, paraFormati(paketlemeUcreti, paraBirimi), false);
    if (tasimaVar)
        satirEkle(etkTasima, paraFormati(tasimaUcreti, paraBirimi), false);
    if (kdvVar)
        satirEkle(etkKdv + QStringLiteral("(%") + QString::number(kdvOrani, 'f', 0) + QStringLiteral(")"),
                   paraFormati(kdvTutari, paraBirimi), false);
    satirEkle(etkGenelToplam, paraFormati(genelToplam, paraBirimi), true);

    return html;
}

bool TeklifPdfOlusturucu::htmlyiPdfeBas(const QString &html, const QString &dosyaYolu, QString &hataOut,
                                         QMarginsF kenarBosluklariMm) const
{
    // setHtml() Chromium tarafinda dahili olarak data: URL'ine cevrilir ve bu
    // URL'ler ~2 MB ile sinirlidir; kapak sayfasi gibi buyuk base64 resim
    // iceren sablonlarda sessizce (loadFinished(false)) basarisiz olur. Bu
    // sinirdan tamamen kacinmak icin HTML'i gecici bir dosyaya yazip
    // dosyadan (file://) yukluyoruz -- boyut siniri yok.
    QTemporaryFile geciciDosya(QDir::tempPath() + "/teklif_pdf_XXXXXX.html");
    if (!geciciDosya.open())
    {
        hataOut = "Gecici HTML dosyasi olusturulamadi.";
        return false;
    }
    geciciDosya.write(html.toUtf8());
    geciciDosya.close();
    const QUrl geciciUrl = QUrl::fromLocalFile(geciciDosya.fileName());

    QWebEnginePage sayfa;
    bool basariliMi = false;
    bool tamamlandiMi = false;
    QEventLoop dongu;

    QObject::connect(&sayfa, &QWebEnginePage::loadFinished, &sayfa, [&](bool yukleBasarili) {
        if (!yukleBasarili)
        {
            hataOut = "PDF sablonu (HTML) yuklenemedi.";
            tamamlandiMi = true;
            dongu.quit();
            return;
        }
        QPageLayout duzen(QPageSize(QPageSize::A4), QPageLayout::Portrait,
                           kenarBosluklariMm, QPageLayout::Millimeter);
        QObject::connect(&sayfa, &QWebEnginePage::pdfPrintingFinished, &sayfa,
                          [&](const QString &, bool basari) {
            basariliMi = basari;
            if (!basari)
                hataOut = "PDF dosyaya yazilamadi.";
            tamamlandiMi = true;
            dongu.quit();
        });
        sayfa.printToPdf(dosyaYolu, duzen);
    });

    // Chromium sureci takilir/cokerse sinyaller hic gelmeyebilir; o durumda donguden
    // hic cikilmaz ve PDF butonu bir daha calismazdi.
    QTimer zamanAsimi;
    zamanAsimi.setSingleShot(true);
    QObject::connect(&zamanAsimi, &QTimer::timeout, &dongu, [&]() {
        if (tamamlandiMi)
            return;
        hataOut = "PDF oluşturma zaman aşımına uğradı.";
        tamamlandiMi = true;
        dongu.quit();
    });

    sayfa.load(geciciUrl);
    if (!tamamlandiMi)
    {
        zamanAsimi.start(60 * 1000);
        // Kullanici girdisi bu surede islenmez: PDF uretilirken ayni butona tekrar
        // basilip bu fonksiyona ic ice yeniden girilmesi (ve ayni dosyaya iki kez
        // yazilmasi) engellenir. Pencere yine de cizilmeye devam eder.
        dongu.exec(QEventLoop::ExcludeUserInputEvents);
    }
    return basariliMi;
}

QString TeklifPdfOlusturucu::paraFormati(double tutar, const QString &paraBirimi)
{
    static const QLocale trLocale(QLocale::Turkish, QLocale::Turkey);
    QString sembol;
    if (paraBirimi.compare(QStringLiteral("USD"), Qt::CaseInsensitive) == 0)
        sembol = QStringLiteral("$");
    else if (paraBirimi.compare(QStringLiteral("EUR"), Qt::CaseInsensitive) == 0)
        sembol = QStringLiteral("€");
    else
        sembol = QStringLiteral("₺");
    return trLocale.toString(tutar, 'f', 2) + QStringLiteral(" ") + sembol;
}

QString TeklifPdfOlusturucu::dosyaAdiTemizle(const QString &ad)
{
    QString temiz = ad;
    temiz.replace(QRegularExpression("[\\\\/:*?\"<>|]"), "_");
    return temiz;
}

QVariantMap TeklifPdfOlusturucu::teklifPdfUret(int teklifId, const QString &firmaAdi, const QVariantMap &veri)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    const bool ingilizce = veri.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;

    QString hata;
    // EN icin ayri bir sablon kullanilir: kapak/antet/sozlesme sayfalarindaki
    // gomulu resimler (arka plan) ve sozlesme maddeleri de İngilizce'dir --
    // bunlar yerKoyucuDoldur ile degistirilebilecek basit metin degil.
    const QString sablon = sabloniOku(ingilizce ? QStringLiteral("teklif_en.html") : QStringLiteral("teklif.html"), hata);
    if (sablon.isEmpty())
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    const QString firmaAdresi = veri.value("firmaAdresi").toString();
    const QString ilgiliKisi = veri.value("ilgiliKisi").toString();
    const QString ilgiliKisiTel = veri.value("ilgiliKisiTelefonu").toString();
    const QString ilgiliKisiEposta = veri.value("ilgiliKisiEposta").toString();
    const QString teslimatSekli = veri.value("teslimatSekli").toString();
    const QString teslimatYeri = veri.value("teslimatYeri").toString();
    const QString personelAdSoyad = veri.value("personelAdSoyad").toString();
    const QString personelTelefon = veri.value("personelTelefon").toString();
    const QString paraBirimi = veri.value("paraBirimi").toString();
    const QString olusturmaTarihi = veri.value("olusturmaTarihi").toString();
    const double genelIndirimOrani = veri.value("genelIndirimOrani").toDouble();
    const double kdvOrani = veri.value("kdvOrani").toDouble();
    const double indirimliToplam = veri.value("indirimliToplam").toDouble();
    const double kdvTutari = veri.value("kdvTutari").toDouble();
    const double genelToplam = veri.value("genelToplam").toDouble();
    const double paketlemeUcreti = veri.value("paketlemeUcreti").toDouble();
    const double tasimaUcreti = veri.value("tasimaUcreti").toDouble();
    const QVariantList kalemler = veri.value("kalemler").toList();

    // Bos/sifir olan alanlar PDF'de hic gosterilmez (kullanici talebi):
    // indirim/KDV/paketleme/tasima uygulanmadiysa ilgili satirlar/sutunlar
    // tamamen kaldirilir, iletisim alanlari da yalnizca doluysa yazilir.
    const bool indirimVar = genelIndirimOrani > 0.0001;
    const bool kdvVar = kdvOrani > 0.0001;
    const bool paketlemeVar = paketlemeUcreti > 0.0001;
    const bool tasimaVar = tasimaUcreti > 0.0001;

    // Basliklar Dil alanina (TR/EN) gore secilir.
    const QString etkBaslik = ingilizce ? QStringLiteral("PROFORMA INVOICE") : QStringLiteral("PROFORMA FATURA");
    const QString etkFirmaAdi = ingilizce ? QStringLiteral("Customer Name") : QStringLiteral("Firma Adı");
    const QString etkTeklifTarihi = ingilizce ? QStringLiteral("Quotation Date") : QStringLiteral("Teklif Tarihi");
    const QString etkTeklifNo = ingilizce ? QStringLiteral("Quotation No") : QStringLiteral("Teklif No");
    const QString etkIlgiliKisi = ingilizce ? QStringLiteral("Contact Person") : QStringLiteral("İlgili Kişi");
    const QString etkTelefon = ingilizce ? QStringLiteral("Phone") : QStringLiteral("Telefon");
    const QString etkEposta = ingilizce ? QStringLiteral("E-mail") : QStringLiteral("E-posta");
    const QString etkTeklifiYapan = ingilizce ? QStringLiteral("Prepared By") : QStringLiteral("Teklifi Yapan");
    const QString etkPersonelTelefon = ingilizce ? QStringLiteral("Staff Phone") : QStringLiteral("Personel Telefon");
    const QString etkTeslimatSekli = ingilizce ? QStringLiteral("Delivery Method") : QStringLiteral("Teslimat Şekli");
    const QString etkTeslimatYeri = ingilizce ? QStringLiteral("Delivery Location") : QStringLiteral("Teslimat Yeri");
    const QString etkTeslimatTarihi = ingilizce ? QStringLiteral("Delivery Date") : QStringLiteral("Teslimat Tarihi");
    const QString etkUrunlerBaslik = ingilizce ? QStringLiteral("Quoted Products") : QStringLiteral("Teklif Edilen Ürünler");
    const QString etkNo = QStringLiteral("No");
    const QString etkUrunKodu = ingilizce ? QStringLiteral("Product Code") : QStringLiteral("Ürün Kodu");
    const QString etkAciklama = ingilizce ? QStringLiteral("Description") : QStringLiteral("Açıklama");
    const QString etkAdet = ingilizce ? QStringLiteral("Qty") : QStringLiteral("Adet");
    const QString etkBirimFiyat = ingilizce ? QStringLiteral("Unit Sales Price") : QStringLiteral("Birim Satış Fiyatı");
    const QString etkIndirimliBirimFiyat = ingilizce ? QStringLiteral("Discounted Unit Price") : QStringLiteral("İndirimli Birim Satış Fiyatı");
    const QString etkToplamFiyat = ingilizce ? QStringLiteral("Total Price") : QStringLiteral("Toplam Fiyat");

    // --- Urun kalemleri basligi (indirim yoksa "Indirimli Birim Fiyat" sutunu hic yok) ---
    QString kalemBaslikHtml =
        QStringLiteral("<th>%1</th>").arg(etkNo) +
        QStringLiteral("<th>%1</th>").arg(etkUrunKodu) +
        QStringLiteral("<th>%1</th>").arg(etkAciklama) +
        QStringLiteral("<th class='sag'>%1</th>").arg(etkAdet) +
        QStringLiteral("<th class='sag'>%1</th>").arg(etkBirimFiyat);
    if (indirimVar)
        kalemBaslikHtml += QStringLiteral("<th class='sag'>%1(%%2)</th>")
            .arg(etkIndirimliBirimFiyat, QString::number(genelIndirimOrani, 'f', 0));
    kalemBaslikHtml += QStringLiteral("<th class='sag'>%1</th>").arg(etkToplamFiyat);

    double rawToplam = 0.0;
    const QString kalemSatirlariHtml = kalemSatirlariUret(kalemler, indirimVar, genelIndirimOrani, rawToplam, paraBirimi);

    // --- Firma / teklif bilgi bloklari (bos alanlar tamamen gizlenir) ---
    QString solBlokHtml = QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkFirmaAdi, firmaAdi.toHtmlEscaped());
    if (!firmaAdresi.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div>%1</div>").arg(firmaAdresi.toHtmlEscaped());
    if (!ilgiliKisi.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkIlgiliKisi, ilgiliKisi.toHtmlEscaped());
    if (!ilgiliKisiTel.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTelefon, ilgiliKisiTel.toHtmlEscaped());
    if (!ilgiliKisiEposta.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkEposta, ilgiliKisiEposta.toHtmlEscaped());

    // Teslimat sekli/yeri: eski programdaki yerlesime uyacak sekilde ust bilgi
    // blogunda degil, GENEL TOPLAM satirinin ALTINDA -- ve ayni tablonun satirlari
    // olarak (bkz. sablondaki {{TESLIMAT_BLOK}}) yazilir; boylece etiketler toplam
    // etiketleriyle, degerler tutar kolonuyla tam alt alta gelir. Ilk satira,
    // toplam blogundan gorsel olarak ayrilmasi icin ekstra bosluk veren
    // "teslimat-ilk" sinifi konur. Bos olan alan hic basilmaz.
    QString teslimatBlokHtml;
    auto teslimatSatiriEkle = [&](const QString &etiket, const QString &deger) {
        if (deger.trimmed().isEmpty())
            return;
        const QString sinif = teslimatBlokHtml.isEmpty()
            ? QStringLiteral(" class='teslimat-ilk'")
            : QString();
        teslimatBlokHtml += QStringLiteral("<tr%1><td><b>%2:</b></td><td>%3</td></tr>")
            .arg(sinif, etiket, deger.trimmed().toHtmlEscaped());
    };
    teslimatSatiriEkle(etkTeslimatSekli, teslimatSekli);
    teslimatSatiriEkle(etkTeslimatYeri, teslimatYeri);
    // Planlanan teslim tarihi (Teklif Ver ekranindaki tarih secici). EN'de
    // sozlesme tarihleriyle ayni dd/MM/yyyy bicimi kullanilir.
    const QString teslimatTarihi = veri.value("teslimatTarihi").toString();
    teslimatSatiriEkle(etkTeslimatTarihi, ingilizce ? QString(teslimatTarihi).replace('.', '/') : teslimatTarihi);

    QString sagBlokHtml = QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTeklifTarihi, olusturmaTarihi);
    sagBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTeklifNo, QString::number(teklifId));
    if (!personelAdSoyad.trimmed().isEmpty())
        sagBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTeklifiYapan, personelAdSoyad.toHtmlEscaped());
    if (!personelTelefon.trimmed().isEmpty())
        sagBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkPersonelTelefon, personelTelefon.toHtmlEscaped());

    // --- Toplam blogu (sifir/kullanilmayan kalemler tamamen atlanir) ---
    const QString toplamSatirlariHtml = toplamSatirlariUret(indirimVar, kdvVar, paketlemeVar, tasimaVar,
                                                              genelIndirimOrani, kdvOrani, rawToplam, indirimliToplam,
                                                              kdvTutari, paketlemeUcreti, tasimaUcreti, genelToplam,
                                                              ingilizce, paraBirimi);

    const int sutunSayisi = indirimVar ? 7 : 6;
    QString kolonGrubu;
    for (int i = 0; i < sutunSayisi; ++i)
        kolonGrubu += QStringLiteral("<col/>");

    QVariantMap degerler;
    degerler["BASLIK"] = etkBaslik;
    degerler["SOL_BLOK"] = solBlokHtml;
    degerler["SAG_BLOK"] = sagBlokHtml;
    degerler["URUNLER_BASLIK"] = etkUrunlerBaslik;
    degerler["INDIRIM_SINIFI"] = indirimVar ? QStringLiteral("indirim-var") : QStringLiteral("indirim-yok");
    degerler["KOLON_GRUBU"] = kolonGrubu;
    degerler["KALEM_BASLIK"] = kalemBaslikHtml;
    degerler["KALEM_SATIRLARI"] = kalemSatirlariHtml;
    degerler["TOPLAM_SATIRLARI"] = toplamSatirlariHtml;
    degerler["TESLIMAT_BLOK"] = teslimatBlokHtml;

    // Son sayfadaki satis sozlesmesi maddeleri: teklife ozel bir metin
    // kaydedilmisse o, kaydedilmemisse dilin fabrika varsayilani kullanilir.
    // Metindeki {{DEGISKEN}}/[KOSUL] isaretleri bu teklifin para birimi, KDV,
    // nakliye secimleri ve bilgisayarin bugunku tarihiyle doldurulur.
    const QString sozlesmeMetni = veri.value("sozlesmeMetni").toString().trimmed();
    degerler["SOZLESME_MADDELERI"] = sozlesmeMetniniHtmleCevir(sozlesmeDegiskenleriniUygula(
        sozlesmeMetni.isEmpty() ? varsayilanSozlesmeMetni(ingilizce) : sozlesmeMetni,
        veri, ingilizce, QDate::currentDate()));

    const QString html = yerKoyucuDoldur(sablon, degerler);

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/Liya ERP Teklifler";
    QDir().mkpath(klasor);
    const QString dosyaYolu = QStringLiteral("%1/Teklif_%2_%3.pdf").arg(klasor, QString::number(teklifId), dosyaAdiTemizle(firmaAdi));

    // Kenar bosluklari 0: sablonun kendi CSS padding'i (25mm ust/alt, 15mm sol/sag)
    // gercek bosluk gorevi goruyor, boylece antetli kagit (teklifSayfa.pdf) bantlari
    // sayfa kenarina tam dayanabiliyor.
    QString basHata;
    if (!htmlyiPdfeBas(html, dosyaYolu, basHata, QMarginsF(0, 0, 0, 0)))
    {
        sonuc["hata"] = basHata;
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["dosyaYolu"] = dosyaYolu;
    return sonuc;
}

QVariantMap TeklifPdfOlusturucu::uretimPdfUret(int teklifId, const QString &firmaAdi, const QVariantMap &veri)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    // Teknik ekip icin her zaman TR sablon: antet/altbilgi teklif PDF'iyle ayni kalsin.
    QString hata;
    QString sablon = sabloniOku(QStringLiteral("teklif.html"), hata);
    if (sablon.isEmpty())
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    // --- Kapak ve sozlesme sayfalarini sablondan cikar ---
    // Kapak: tek bir <img> iceren <div class="kapak-sayfa">...</div>.
    // Sozlesme: govdenin en sonundaki, ic ice div'ler iceren blok -- </body>'ye kadar atilir.
    const QString kapakBasi = QStringLiteral("<div class=\"kapak-sayfa\">");
    qsizetype bas = sablon.indexOf(kapakBasi);
    if (bas >= 0)
    {
        const qsizetype son = sablon.indexOf(QStringLiteral("</div>"), bas);
        if (son >= 0)
            sablon.remove(bas, son + 6 - bas);
    }
    bas = sablon.indexOf(QStringLiteral("<div class=\"sozlesme-sayfa\">"));
    const qsizetype govdeSonu = sablon.lastIndexOf(QStringLiteral("</body>"));
    if (bas >= 0 && govdeSonu > bas)
        sablon.remove(bas, govdeSonu - bas);

    // Fiyatsiz 4 sutunluk tablo ve uretim notu kutusu icin ek stiller.
    sablon.replace(QStringLiteral("</style>"), QStringLiteral(
        "    table.uretim col:nth-child(1) { width: 7%; }\n"
        "    table.uretim col:nth-child(2) { width: 18%; }\n"
        "    table.uretim col:nth-child(3) { width: 63%; }\n"
        "    table.uretim col:nth-child(4) { width: 12%; }\n"
        "    .uretim-not { margin-top: 16px; border: 1px solid #333; padding: 8px 10px; }\n"
        "    .uretim-not .etiket { font-weight: bold; margin-bottom: 4px; }\n"
        "    .uretim-not .metin { white-space: pre-wrap; }\n"
        "</style>"));

    const bool teklifIngilizce = veri.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
    const QVariantList kalemler = veri.value("kalemler").toList();

    // --- Kalemler: fiyat yok, sadece kod/aciklama/adet ---
    QString kalemSatirlariHtml;
    int satirNo = 0;
    int toplamAdet = 0;
    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap k = kalemVar.toMap();
        ++satirNo;
        const int adet = k.value("adet").toInt();
        toplamAdet += adet;

        const QString urunKodu = k.value("urunKodu").toString();
        const bool manuelMi = urunKodu.startsWith(QStringLiteral("MANUEL-"));
        const QString katalogTr = k.value("urunAciklamasiTr").toString();
        const QString aciklama = (teklifIngilizce && !manuelMi && !katalogTr.trimmed().isEmpty())
            ? katalogTr : k.value("urunAciklamasi").toString();

        const QString satirSinifi = (satirNo % 2 == 0) ? QStringLiteral(" class='zebra'") : QString();
        // Hucreler ayri ayri eklenir: zincirli .arg() kullanilsaydi aciklamadaki
        // "%5" gibi bir ifade sonraki argumanla degistirilirdi.
        kalemSatirlariHtml += QStringLiteral("<tr%1>").arg(satirSinifi);
        kalemSatirlariHtml += QStringLiteral("<td>%1</td>").arg(satirNo);
        kalemSatirlariHtml += QStringLiteral("<td>%1</td>").arg((manuelMi ? QString() : urunKodu).toHtmlEscaped());
        kalemSatirlariHtml += QStringLiteral("<td>%1</td>").arg(aciklama.toHtmlEscaped());
        kalemSatirlariHtml += QStringLiteral("<td class='sag'>%1</td></tr>").arg(adet);
    }
    kalemSatirlariHtml += QStringLiteral("<tr><td></td><td></td><td class='sag'><b>Toplam Adet:</b></td>"
                                         "<td class='sag'><b>%1</b></td></tr>").arg(toplamAdet);

    const QString kalemBaslikHtml = QStringLiteral(
        "<th>No</th><th>Ürün Kodu</th><th>Açıklama</th><th class='sag'>Adet</th>");

    // --- Bilgi bloklari (bos alanlar gizlenir) ---
    auto satir = [](const QString &etiket, const QString &deger) {
        return deger.trimmed().isEmpty()
            ? QString()
            : QStringLiteral("<div><b>%1:</b> %2</div>").arg(etiket, deger.trimmed().toHtmlEscaped());
    };

    QString solBlokHtml = satir(QStringLiteral("Firma Adı"), firmaAdi);
    const QString firmaAdresi = veri.value("firmaAdresi").toString();
    if (!firmaAdresi.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div>%1</div>").arg(firmaAdresi.toHtmlEscaped());
    solBlokHtml += satir(QStringLiteral("İlgili Kişi"), veri.value("ilgiliKisi").toString());
    solBlokHtml += satir(QStringLiteral("Telefon"), veri.value("ilgiliKisiTelefonu").toString());
    solBlokHtml += satir(QStringLiteral("Teslimat Şekli"), veri.value("teslimatSekli").toString());
    solBlokHtml += satir(QStringLiteral("Teslimat Yeri"), veri.value("teslimatYeri").toString());

    QString sagBlokHtml = satir(QStringLiteral("Teklif No"), QString::number(teklifId));
    sagBlokHtml += satir(QStringLiteral("Teklif Tarihi"), veri.value("olusturmaTarihi").toString());
    sagBlokHtml += satir(QStringLiteral("Kabul Tarihi"), veri.value("kabulTarihi").toString());
    // Planlanan teslim tarihi uretimin en kritik bilgisi: girilmemisse de
    // bos gecmek yerine acikca belirtilir.
    const QString teslimatTarihi = veri.value("teslimatTarihi").toString();
    sagBlokHtml += QStringLiteral("<div><b>Planlanan Teslim Tarihi:</b> %1</div>")
        .arg(teslimatTarihi.isEmpty() ? QStringLiteral("Belirtilmedi") : teslimatTarihi);
    sagBlokHtml += satir(QStringLiteral("Teklifi Yapan"), veri.value("personelAdSoyad").toString());
    sagBlokHtml += satir(QStringLiteral("Üretim Formu Tarihi"),
                         QDateTime::currentDateTime().toString(QStringLiteral("dd.MM.yyyy HH:mm")));

    // Yalnizca uretim notu basilir; teklif notu uretimciye gitmez.
    const QString uretimNotu = veri.value("uretimNotu").toString().trimmed();
    const QString notHtml = uretimNotu.isEmpty()
        ? QString()
        : QStringLiteral("<div class=\"uretim-not\"><div class=\"etiket\">Üretim Notu</div>"
                         "<div class=\"metin\">%1</div></div>").arg(uretimNotu.toHtmlEscaped());

    // Not kutusu tablonun hemen altina (toplam blogunun yerine) konur.
    const QString toplamBlokBasi = QStringLiteral("<div class=\"toplam-blok\">");
    if (sablon.contains(toplamBlokBasi))
        sablon.replace(toplamBlokBasi, notHtml + toplamBlokBasi);
    else
        solBlokHtml += notHtml;

    QVariantMap degerler;
    degerler["BASLIK"] = QStringLiteral("ÜRETİM FORMU");
    degerler["SOL_BLOK"] = solBlokHtml;
    degerler["SAG_BLOK"] = sagBlokHtml;
    degerler["URUNLER_BASLIK"] = QStringLiteral("Üretilecek Ürünler");
    degerler["INDIRIM_SINIFI"] = QStringLiteral("uretim");
    degerler["KOLON_GRUBU"] = QStringLiteral("<col/><col/><col/><col/>");
    degerler["KALEM_BASLIK"] = kalemBaslikHtml;
    degerler["KALEM_SATIRLARI"] = kalemSatirlariHtml;
    degerler["TOPLAM_SATIRLARI"] = QString();
    degerler["TESLIMAT_BLOK"] = QString();
    degerler["SOZLESME_MADDELERI"] = QString();

    const QString html = yerKoyucuDoldur(sablon, degerler);

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/Liya ERP Teklifler";
    QDir().mkpath(klasor);
    const QString dosyaYolu = QStringLiteral("%1/Uretim_%2_%3.pdf").arg(klasor, QString::number(teklifId), dosyaAdiTemizle(firmaAdi));

    QString basHata;
    if (!htmlyiPdfeBas(html, dosyaYolu, basHata, QMarginsF(0, 0, 0, 0)))
    {
        sonuc["hata"] = basHata;
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["dosyaYolu"] = dosyaYolu;
    return sonuc;
}

QVariantMap TeklifPdfOlusturucu::satisSozlesmesiUret(const QVariantMap &veri)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    QString hata;
    const QString sablon = sabloniOku(QStringLiteral("satis_sozlesmesi.html"), hata);
    if (sablon.isEmpty())
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    const QString firmaAdi = veri.value("firmaAdi").toString();
    const QString firmaAdresi = veri.value("firmaAdresi").toString();
    const QVariantList kalemler = veri.value("kalemler").toList();
    const QString paraBirimi = veri.value("paraBirimi").toString();
    const QString ilgiliKisi = veri.value("ilgiliKisi").toString();
    const QString teslimatSekli = veri.value("teslimatSekli").toString();
    const QString teslimatYeri = veri.value("teslimatYeri").toString();
    const double genelToplam = veri.value("genelToplam").toDouble();
    const bool ingilizce = veri.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;

    const QString bugununTarihi = QDateTime::currentDateTime().toString("dd.MM.yyyy");

    const QString baslikHtml = ingilizce ? QStringLiteral("SALES AGREEMENT") : QStringLiteral("SATIŞ SÖZLEŞMESİ");
    const QString etkTarih = ingilizce ? QStringLiteral("Date") : QStringLiteral("Tarih");
    const QString etkSatici = ingilizce ? QStringLiteral("Seller") : QStringLiteral("Satıcı");
    const QString etkAlici = ingilizce ? QStringLiteral("Buyer") : QStringLiteral("Alıcı");
    const QString etkIlgiliKisi = ingilizce ? QStringLiteral("Contact Person") : QStringLiteral("İlgili Kişi");
    const QString etkAcikMetin = ingilizce
        ? QStringLiteral("The products/services listed below are subject to sale under terms mutually agreed by the parties:")
        : QStringLiteral("Aşağıda belirtilen ürün/hizmetler, taraflar arasında mutabık kalınan şartlarla satışa konu edilmiştir:");
    const QString etkAciklama = ingilizce ? QStringLiteral("Description") : QStringLiteral("Açıklama");
    const QString etkAdet = ingilizce ? QStringLiteral("Qty") : QStringLiteral("Adet");
    const QString etkBirimFiyat = ingilizce ? QStringLiteral("Unit Price") : QStringLiteral("Birim Fiyat");
    const QString etkToplam = ingilizce ? QStringLiteral("Total") : QStringLiteral("Toplam");
    const QString etkTeslimatSekli = ingilizce ? QStringLiteral("Delivery Method") : QStringLiteral("Teslimat Şekli");
    const QString etkTeslimatYeri = ingilizce ? QStringLiteral("Delivery Location") : QStringLiteral("Teslimat Yeri");
    const QString etkParaBirimi = ingilizce ? QStringLiteral("Currency") : QStringLiteral("Para Birimi");
    const QString etkGenelToplam = ingilizce ? QStringLiteral("GRAND TOTAL") : QStringLiteral("GENEL TOPLAM");
    const QString etkKapanis = ingilizce
        ? QStringLiteral("The parties accept and undertake the terms of this agreement.")
        : QStringLiteral("Taraflar işbu sözleşme şartlarını kabul ve taahhüt eder.");

    const QString kalemSatirlariHtml = sozlesmeKalemSatirlariUret(kalemler, paraBirimi);

    QVariantMap degerler;
    degerler["BASLIK"] = baslikHtml;
    degerler["ETK_TARIH"] = etkTarih;
    degerler["TARIH"] = bugununTarihi;
    degerler["ETK_SATICI"] = etkSatici;
    degerler["SATICI_ADI"] = QStringLiteral("Liya Laboratuvar Cihazları");
    degerler["ETK_ALICI"] = etkAlici;
    degerler["ALICI_ADI"] = firmaAdi.toHtmlEscaped();
    degerler["ALICI_ADRESI"] = firmaAdresi.trimmed().isEmpty() ? QString() : (firmaAdresi.toHtmlEscaped() + QStringLiteral("<br/>"));
    degerler["ETK_ILGILI_KISI"] = etkIlgiliKisi;
    degerler["ILGILI_KISI"] = ilgiliKisi.toHtmlEscaped();
    degerler["ACIK_METIN"] = etkAcikMetin;
    degerler["ETK_ACIKLAMA"] = etkAciklama;
    degerler["ETK_ADET"] = etkAdet;
    degerler["ETK_BIRIM_FIYAT"] = etkBirimFiyat;
    degerler["ETK_TOPLAM"] = etkToplam;
    degerler["KALEM_SATIRLARI"] = kalemSatirlariHtml;
    degerler["ETK_TESLIMAT_SEKLI"] = etkTeslimatSekli;
    degerler["TESLIMAT_SEKLI"] = teslimatSekli.toHtmlEscaped();
    degerler["ETK_TESLIMAT_YERI"] = etkTeslimatYeri;
    degerler["TESLIMAT_YERI"] = teslimatYeri.toHtmlEscaped();
    degerler["ETK_PARA_BIRIMI"] = etkParaBirimi;
    degerler["PARA_BIRIMI"] = paraBirimi;
    degerler["ETK_GENEL_TOPLAM"] = etkGenelToplam;
    degerler["GENEL_TOPLAM"] = paraFormati(genelToplam, paraBirimi);
    degerler["ETK_KAPANIS"] = etkKapanis;

    const QString html = yerKoyucuDoldur(sablon, degerler);

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/Liya ERP Teklifler";
    QDir().mkpath(klasor);
    const QString dosyaYolu = QStringLiteral("%1/Satis_Sozlesmesi_%2_%3.pdf")
        .arg(klasor, dosyaAdiTemizle(firmaAdi), QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss"));

    QString basHata;
    if (!htmlyiPdfeBas(html, dosyaYolu, basHata))
    {
        sonuc["hata"] = basHata;
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["dosyaYolu"] = dosyaYolu;
    return sonuc;
}
