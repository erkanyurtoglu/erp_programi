#include "KurServisi.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QXmlStreamReader>
#include <QLocale>
#include <QDebug>

namespace
{
    // TCMB XML'inde sayilar nokta ondalikli ("34.1234"); sistem yeresel
    // ayari virgullu oldugu icin C yereli ile cevriliyor.
    double sayiyaCevir(const QString &metin)
    {
        bool oldu = false;
        const double deger = QLocale::c().toDouble(metin.trimmed(), &oldu);
        return oldu ? deger : 0.0;
    }
}

KurServisi::KurServisi(QObject *parent)
    : QObject(parent)
    , m_ag(new QNetworkAccessManager(this))
{
}

double KurServisi::kur(const QString &paraBirimi) const
{
    const QString kod = paraBirimi.trimmed().toUpper();
    if (kod.isEmpty() || kod == QStringLiteral("TL") || kod == QStringLiteral("TRY"))
        return 1.0;
    return m_kurlar.value(kod, 0.0);
}

void KurServisi::yenile(bool zorla)
{
    if (m_yukleniyor)
        return;
    // Ayni gun icinde ikinci kez cekmenin anlami yok: TCMB gunde bir kez
    // yayinliyor.
    if (!zorla && m_cekilenGun == QDate::currentDate() && !m_kurlar.isEmpty())
        return;

    m_sira = adresleri();
    m_siradakiIndeks = 0;
    durumuYaz(true, QString());
    sonrakiAdresiDene();
}

QStringList KurServisi::adresleri() const
{
    QStringList adres;
    adres << QStringLiteral("https://www.tcmb.gov.tr/kurlar/today.xml");

    // today.xml yoksa (hafta sonu / yayin saatinden once) son yayinlanan
    // kuru bulana kadar geriye gidiyoruz.
    QDate gun = QDate::currentDate();
    for (int i = 0; i < 7; ++i)
    {
        adres << QStringLiteral("https://www.tcmb.gov.tr/kurlar/%1/%2.xml")
                     .arg(gun.toString(QStringLiteral("yyyyMM")),
                          gun.toString(QStringLiteral("ddMMyyyy")));
        gun = gun.addDays(-1);
    }
    return adres;
}

void KurServisi::sonrakiAdresiDene()
{
    if (m_siradakiIndeks >= m_sira.size())
    {
        qWarning() << "TCMB kuru alinamadi; son 7 gunun hicbirinde yayin bulunamadi.";
        durumuYaz(false, QStringLiteral("Güncel kur alınamadı; lütfen elle girin."));
        return;
    }

    QNetworkRequest istek{QUrl(m_sira.at(m_siradakiIndeks++))};
    istek.setTransferTimeout(8000);   // ag yoksa ekran kilitlenmesin
    istek.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                       QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply *cevap = m_ag->get(istek);
    connect(cevap, &QNetworkReply::finished, this, [this, cevap]() {
        cevabiIsle(cevap);
        cevap->deleteLater();
    });
}

void KurServisi::cevabiIsle(QNetworkReply *cevap)
{
    if (cevap->error() != QNetworkReply::NoError)
    {
        // Bulunamayan tarih normaldir (tatil gunu): bir onceki gune geciyoruz.
        // Ag/SSL hatasi ise sebebi gunlukte gorunsun.
        if (cevap->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 404)
            qWarning() << "TCMB kur istegi basarisiz:" << cevap->url().toString() << cevap->errorString();
        sonrakiAdresiDene();
        return;
    }

    if (!xmliAyristir(cevap->readAll()))
    {
        sonrakiAdresiDene();
        return;
    }

    m_cekilenGun = QDate::currentDate();
    qInfo() << "TCMB kuru alindi:" << m_kurTarihi << "USD" << usd() << "EUR" << eur();
    durumuYaz(false, QString());
    emit kurlarDegisti();
}

bool KurServisi::xmliAyristir(const QByteArray &xml)
{
    QHash<QString, double> bulunan;
    QString tarih;
    QString aktifKod;

    QXmlStreamReader okuyucu(xml);
    while (!okuyucu.atEnd())
    {
        okuyucu.readNext();
        if (!okuyucu.isStartElement())
            continue;

        if (okuyucu.name() == QStringLiteral("Tarih_Date"))
        {
            // Ornek: Tarih="24.10.2026"
            tarih = okuyucu.attributes().value(QStringLiteral("Tarih")).toString();
        }
        else if (okuyucu.name() == QStringLiteral("Currency"))
        {
            aktifKod = okuyucu.attributes().value(QStringLiteral("CurrencyCode")).toString();
        }
        else if (okuyucu.name() == QStringLiteral("ForexSelling") && !aktifKod.isEmpty())
        {
            // Satinalmada doviz SATIS kuru kullanilir: doviz almak gerektiginde
            // odenecek olan budur.
            const double deger = sayiyaCevir(okuyucu.readElementText());
            if (deger > 0.0)
                bulunan.insert(aktifKod, deger);
        }
    }

    if (okuyucu.hasError() || bulunan.isEmpty())
        return false;

    m_kurlar = bulunan;
    m_kurTarihi = tarih;
    return true;
}

void KurServisi::durumuYaz(bool yukleniyor, const QString &hata)
{
    if (m_yukleniyor == yukleniyor && m_hata == hata)
        return;
    m_yukleniyor = yukleniyor;
    m_hata = hata;
    emit durumDegisti();
}
