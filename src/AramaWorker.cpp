#include "AramaWorker.h"
#include "AramaSorgulari.h"
#include "Database.h"

#include <QDebug>

namespace
{
    const QString ARAMA_BAGLANTI_ADI = "erp_arama_baglantisi";
}

AramaWorker::AramaWorker(QObject *parent) : QObject(parent)
{
}

void AramaWorker::baglantiyiAc()
{
    // Bu slot, worker QThread'e tasindiktan sonra QThread::started sinyaliyle
    // cagrilir -- yani burasi zaten worker thread'i icinde calisir, dolayisiyla
    // acilan QSqlDatabase baglantisi da worker thread'ine ait olur (Database'in
    // ana baglantisindan tamamen bagimsiz, ayri bir ODBC oturumu).
    QString hata;
    m_sonBaglantiDenemesi.start();
    if (Database::baglantiAc(m_db, ARAMA_BAGLANTI_ADI, hata))
        m_sonKullanim.start();
    else
        qWarning() << "Arama worker veritabanina baglanamadi:" << hata;
}

bool AramaWorker::baglantiHazir()
{
    QString hata;
    return Database::baglantiyiHazirla(m_db, ARAMA_BAGLANTI_ADI, m_sonKullanim,
                                       m_sonBaglantiDenemesi, hata);
}

void AramaWorker::musteriAraCalistir(const QString &arama, int limit)
{
    if (!baglantiHazir())
    {
        emit musteriSonucHazir(arama, QVariantList());
        return;
    }
    emit musteriSonucHazir(arama, musteriAraSorgusu(m_db, arama, limit));
}

void AramaWorker::urunAraCalistir(const QString &arama, int limit, const QString &dil)
{
    if (!baglantiHazir())
    {
        emit urunSonucHazir(arama, dil, QVariantList());
        return;
    }
    emit urunSonucHazir(arama, dil, urunAraSorgusu(m_db, arama, limit, dil));
}
