#include "TeklifPdfOlusturucu.h"

#include <QCoreApplication>
#include <QFile>
#include <QTextStream>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDateTime>
#include <QLocale>
#include <QEventLoop>
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
    if (ingilizce)
    {
        return QStringLiteral(
            "Our prices are quoted in USD and are VAT-inclusive. Payment of this invoice must be made in "
            "Turkish Lira, converted at the CBRT (Central Bank of the Republic of Turkey) foreign exchange "
            "effective selling rate on the payment date. Otherwise, an invoice for the resulting exchange "
            "rate difference will be issued and collected.\n"
            "Equipment payment: 30% in advance upon order placement, with the remaining balance due upon delivery.\n"
            "The equipment carries a free service warranty of 1 year for mechanical parts and 2 years for "
            "electronic parts. Paid technical service and training will be provided for a period of 10 years.\n"
            "Equipment Delivery: Delivered within 1 week of the order.\n"
            "Quotation Validity: 3 days from the date of the quotation.\n"
            "Shipping: To be borne by the buyer.\n"
            "The prices of equipment offered as alternatives are not included in the total quotation amount.\n"
            "Our Bank Details: Liya Laboratuvar Test Cihazları İmalat ve Dış Ticaret A.Ş.\n"
            "- İŞ BANKASI TR16 0006 4000 0014 1520 1653 38\n"
            "- HALK BANKASI TR51 0001 2009 4140 0010 2645 69");
    }

    return QStringLiteral(
        "Fiyatımız DOLAR cinsinden belirtilmiş olup, KDV dahildir. İş bu fatura ödemesinin, ödeme "
        "tarihindeki TCMB DÖVİZ EFEKTİF SATIŞ KURU ile Türk Lirası’na çevrilerek yapılması "
        "gerekmektedir. Aksi durumda kesilecek kur farkı faturasının tahsili yapılacaktır.\n"
        "Cihaz ücreti: %30’u sipariş sırasında peşin, kalan tutar teslimatta ödenecektir.\n"
        "Cihazlar; 1 yıl mekanik, 2 yıl elektronik parça olarak ücretsiz servis garantilidir. 10 yıl "
        "süreyle ücreti karşılığı teknik servis ve eğitim hizmeti verilecektir.\n"
        "Cihaz Teslimatı: Siparişe istinaden 1 hafta içinde teslim.\n"
        "Teklif Opsiyonu: Teklif tarihinden itibaren 3 gündür.\n"
        "Nakliye: Alıcı firmaya aittir.\n"
        "Alternatif olarak sunulan cihaz bedelleri, toplam teklif tutarına dahil edilmemiştir.\n"
        "Banka Bilgilerimiz: Liya Laboratuvar Test Cihazları İmalat ve Dış Ticaret A.Ş.\n"
        "- İŞ BANKASI TR16 0006 4000 0014 1520 1653 38\n"
        "- HALK BANKASI TR51 0001 2009 4140 0010 2645 69");
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

    sayfa.load(geciciUrl);
    if (!tamamlandiMi)
        dongu.exec();
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
    if (!teslimatSekli.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTeslimatSekli, teslimatSekli.toHtmlEscaped());
    if (!teslimatYeri.trimmed().isEmpty())
        solBlokHtml += QStringLiteral("<div><b>%1:</b> %2</div>").arg(etkTeslimatYeri, teslimatYeri.toHtmlEscaped());

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

    // Son sayfadaki satis sozlesmesi maddeleri: teklife ozel bir metin
    // kaydedilmisse o, kaydedilmemisse dilin fabrika varsayilani kullanilir.
    const QString sozlesmeMetni = veri.value("sozlesmeMetni").toString().trimmed();
    degerler["SOZLESME_MADDELERI"] = sozlesmeMetniniHtmleCevir(
        sozlesmeMetni.isEmpty() ? varsayilanSozlesmeMetni(ingilizce) : sozlesmeMetni);

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
