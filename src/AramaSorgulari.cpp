#include "AramaSorgulari.h"

#include <QSqlDatabase>
#include <QSqlQuery>
#include <QSqlError>
#include <QVariantMap>
#include <QDebug>

QVariantList musteriAraSorgusu(QSqlDatabase &db, const QString &arama, int limit)
{
    QVariantList sonuc;
    const QString aramaTrim = arama.trimmed();

    QSqlQuery query(db);
    if (aramaTrim.isEmpty())
    {
        // Arama kutusu bosken listeyi bomboş gostermemek icin en son eklenen
        // musterileri getiriyoruz (kullanici genelde en yeni firmalarla calisir).
        query.prepare(QString(
            "SELECT TOP (%1) MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
            "       IlgiliKisi, IlgiliKisiTelefonu "
            "FROM dbo.musteriler ORDER BY MusteriId DESC").arg(limit));
    }
    else
    {
        query.prepare(QString(
            "SELECT TOP (%1) MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
            "       IlgiliKisi, IlgiliKisiTelefonu "
            "FROM dbo.musteriler "
            "WHERE FirmaAdi LIKE :aramaLike OR IlgiliKisi LIKE :aramaLike "
            "ORDER BY FirmaAdi").arg(limit));
        query.bindValue(":aramaLike", "%" + aramaTrim + "%");
    }

    if (!query.exec())
    {
        qWarning() << "musteriAra basarisiz:" << query.lastError().text();
        return sonuc;
    }

    while (query.next())
    {
        QVariantMap m;
        m["musteriId"] = query.value("MusteriId").toInt();
        m["firmaAdi"] = query.value("FirmaAdi").toString();
        m["firmaAdresi"] = query.value("FirmaAdresi").toString();
        m["firmaTelefonu"] = query.value("FirmaTelefonu").toString();
        m["firmaEposta"] = query.value("FirmaEposta").toString();
        m["ilgiliKisi"] = query.value("IlgiliKisi").toString();
        m["ilgiliKisiTelefonu"] = query.value("IlgiliKisiTelefonu").toString();
        sonuc << m;
    }
    return sonuc;
}

QVariantList urunAraSorgusu(QSqlDatabase &db, const QString &arama, int limit, const QString &dil)
{
    QVariantList sonuc;

    const QString aramaTrim = arama.trimmed();
    const bool ingilizce = dil.compare("EN", Qt::CaseInsensitive) == 0;

    // "MANUEL-<teklifId>" kodlu satirlar, sepete manuel eklenen kalemler icin
    // FOREIGN KEY zorunlulugu yuzunden urunler tablosuna yazilan, teklife ozel
    // gecici satirlardir -- normal urun kataloğu arama/listelemesinde gorunmemeli.
    QSqlQuery query(db);
    if (aramaTrim.isEmpty())
    {
        query.prepare(QString(
            "SELECT TOP (%1) UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, "
            "       BirimFiyat, ParaBirimi, GuncelMaliyetTL "
            "FROM dbo.urunler WHERE UrunKodu NOT LIKE N'MANUEL%' ORDER BY UrunId DESC").arg(limit));
    }
    else
    {
        query.prepare(QString(
            "SELECT TOP (%1) UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, "
            "       BirimFiyat, ParaBirimi, GuncelMaliyetTL "
            "FROM dbo.urunler "
            "WHERE UrunKodu NOT LIKE N'MANUEL%' "
            "  AND (UrunKodu LIKE :aramaLike OR UrunAciklamasi LIKE :aramaLike "
            "   OR UrunAciklamasiEn LIKE :aramaLike) "
            "ORDER BY UrunKodu").arg(limit));
        query.bindValue(":aramaLike", "%" + aramaTrim + "%");
    }

    if (!query.exec())
    {
        qWarning() << "urunAra basarisiz:" << query.lastError().text();
        return sonuc;
    }

    while (query.next())
    {
        QVariantMap u;
        u["urunId"] = query.value("UrunId").toInt();
        u["urunKodu"] = query.value("UrunKodu").toString();
        u["kategori"] = query.value("Kategori").toString();
        const QString aciklamaTr = query.value("UrunAciklamasi").toString();
        const QString aciklamaEn = query.value("UrunAciklamasiEn").toString();
        // EN seciliyse ve EN cevirisi girilmisse onu, yoksa TR'ye geri duserek gosterir.
        u["urunAciklamasi"] = (ingilizce && !aciklamaEn.trimmed().isEmpty()) ? aciklamaEn : aciklamaTr;
        u["birimFiyat"] = query.value("BirimFiyat").toDouble();
        u["paraBirimi"] = query.value("ParaBirimi").toString();
        u["maliyet"] = query.value("GuncelMaliyetTL").isNull() ? 0.0 : query.value("GuncelMaliyetTL").toDouble();
        sonuc << u;
    }
    return sonuc;
}
