#include "SqlYardimcilari.h"
// Varsayilan satis sozlesmesi ayarinin fabrika metni.
#include "TeklifPdfOlusturucu.h"

#include <QHash>
#include <QMutex>
#include <QMutexLocker>
#include <QSqlDatabase>
#include <QSqlError>
#include <QSqlQuery>
#include <QDebug>

QString likeIcinKacir(const QString &metin)
{
    QString s = metin;
    // Once ters bolu: sonraki replace'lerin ekledigi kacis karakterlerini
    // tekrar kacirmamak icin sirasi onemli.
    s.replace('\\', QStringLiteral("\\\\"));
    s.replace('%', QStringLiteral("\\%"));
    s.replace('_', QStringLiteral("\\_"));
    s.replace('[', QStringLiteral("\\["));
    return s;
}

QString likeDeseni(const QString &arama)
{
    return QStringLiteral("%") + likeIcinKacir(arama.trimmed()) + QStringLiteral("%");
}

namespace
{
    const QString urunKoduAyiricilari = QStringLiteral("- ./_");
}

QString urunKoduSqlIfadesi(const QString &sutun)
{
    QString ifade = sutun;
    for (const QChar c : urunKoduAyiricilari)
        ifade = QStringLiteral("REPLACE(%1, N'%2', N'')").arg(ifade, c);
    return ifade;
}

QString urunKoduDeseni(const QString &arama)
{
    QString sade = arama;
    for (const QChar c : urunKoduAyiricilari)
        sade.remove(c);
    // Yalnizca ayiricidan olusan arama ("-") bos desene, yani her seye
    // eslesmesin: ayiricisiz kodda bulunamayan orijinal desen kullanilir.
    return sade.isEmpty() ? likeDeseni(arama) : likeDeseni(sade);
}

bool manuelKoduMu(const QString &urunKodu)
{
    return urunKodu.trimmed().startsWith(QStringLiteral("MANUEL"), Qt::CaseInsensitive);
}

bool semaKolonuVarMi(const QSqlDatabase &db, const QString &tablo, const QString &kolon)
{
    static QMutex kilit;
    static QHash<QString, bool> onbellek;

    const QString anahtar = tablo.toLower() + QLatin1Char('.') + kolon.toLower();
    {
        QMutexLocker kilitli(&kilit);
        const auto it = onbellek.constFind(anahtar);
        if (it != onbellek.constEnd())
            return it.value();
    }

    QSqlQuery query(db);
    query.prepare("SELECT 1 FROM sys.columns "
                  "WHERE object_id = OBJECT_ID(:tablo) AND name = :kolon");
    query.bindValue(":tablo", tablo);
    query.bindValue(":kolon", kolon);

    if (!query.exec())
    {
        // Sorgu calismadiysa onbellege YAZMIYORUZ: gecici bir baglanti sorunu
        // yuzunden "sutun yok" kararini programin kalan omru boyunca tasimak
        // istemeyiz. Bu cagri icin guvenli taraf: yok varsay.
        qWarning() << "semaKolonuVarMi basarisiz (" << tablo << "." << kolon << "):"
                   << query.lastError().text();
        return false;
    }

    const bool varMi = query.next();
    {
        QMutexLocker kilitli(&kilit);
        onbellek.insert(anahtar, varMi);
    }
    return varMi;
}

bool sistemRoluMu(const QString &rolAdi)
{
    return rolAdi == QStringLiteral("Yönetici")
        || rolAdi == QStringLiteral("Göç - Geçici Tam Yetkili");
}

const QList<AyarTanimi> &ayarTanimlari()
{
    static const QList<AyarTanimi> tanimlar = {
        { QStringLiteral("TEKLIF_VARSAYILAN_KDV_ORANI"),
          QStringLiteral("sayi"),
          QStringLiteral("Satış"),
          QStringLiteral("Yeni teklifte varsayılan KDV"),
          QString(),
          QStringLiteral("%"),
          20.0, 0.0, 100.0, 2, QString() },
        // Yeni teklif kaydedilirken teklifin ICINE yazilir (db/25); kayitli
        // tekliflerin suresi degismez. Gunu saklanmamis eski teklifler 3 gun
        // sayilir (TeklifPdfOlusturucu::kVarsayilanGecerlilikGunu).
        { QStringLiteral("TEKLIF_GECERLILIK_GUNU"),
          QStringLiteral("sayi"),
          QStringLiteral("Satış"),
          QStringLiteral("Teklif geçerlilik süresi"),
          QStringLiteral("Yeni tekliflere uygulanır; kayıtlı tekliflerin süresi değişmez."),
          QStringLiteral("gün"),
          10.0, 1.0, 365.0, 0, QString() },
        // Yeni teklif kaydedilirken o anki metin teklifin ICINE yazilir
        // (bkz. Database::teklifKaydet); bu ayari degistirmek kayitli
        // tekliflerin sozlesmesini degistirmez.
        { sozlesmeAyarAnahtari(QStringLiteral("TR")),
          QStringLiteral("metin"),
          QStringLiteral("Satış Sözleşmesi"),
          QStringLiteral("Varsayılan sözleşme (Türkçe)"),
          QStringLiteral("Bundan sonra kaydedilen yeni tekliflerde kullanılır; kayıtlı teklifler değişmez."),
          QString(),
          0.0, 0.0, 0.0, 0, TeklifPdfOlusturucu::varsayilanSozlesmeMetni(false) },
        { sozlesmeAyarAnahtari(QStringLiteral("EN")),
          QStringLiteral("metin"),
          QStringLiteral("Satış Sözleşmesi"),
          QStringLiteral("Varsayılan sözleşme (İngilizce)"),
          QStringLiteral("Bundan sonra kaydedilen yeni tekliflerde kullanılır; kayıtlı teklifler değişmez."),
          QString(),
          0.0, 0.0, 0.0, 0, TeklifPdfOlusturucu::varsayilanSozlesmeMetni(true) },
        // Satir yoksa 0 (onay istenmez): satinalmaOnayEsigiGetir'in eski
        // davranisiyla ayni. db/17 bu satiri 50000 ile ekler.
        { QStringLiteral("SATINALMA_PATRON_ONAY_ESIGI_TL"),
          QStringLiteral("sayi"),
          QStringLiteral("Satınalma"),
          QStringLiteral("Patron onayı eşiği"),
          QStringLiteral("Bu tutarın üzerindeki siparişler patron onayı bekler. 0 = onay istenmez."),
          QStringLiteral("TL"),
          0.0, 0.0, 1000000000.0, 2, QString() },
    };
    return tanimlar;
}

QString sozlesmeAyarAnahtari(const QString &dil)
{
    return dil.compare(QStringLiteral("EN"), Qt::CaseInsensitive) == 0
        ? QStringLiteral("SATIS_SOZLESME_METNI_EN")
        : QStringLiteral("SATIS_SOZLESME_METNI_TR");
}

const AyarTanimi *ayarTanimiBul(const QString &anahtar)
{
    for (const AyarTanimi &t : ayarTanimlari())
        if (t.anahtar == anahtar)
            return &t;
    return nullptr;
}
