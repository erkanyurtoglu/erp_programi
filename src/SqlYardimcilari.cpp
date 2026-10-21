#include "SqlYardimcilari.h"

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

bool manuelKoduMu(const QString &urunKodu)
{
    return urunKodu.trimmed().startsWith(QStringLiteral("MANUEL"), Qt::CaseInsensitive);
}

bool semaKolonuVarMi(QSqlDatabase &db, const QString &tablo, const QString &kolon)
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
