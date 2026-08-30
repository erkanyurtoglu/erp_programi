#include "AramaWorker.h"
#include "AramaSorgulari.h"
#include "Database.h"

#include <QDebug>

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
    m_baglantiHazir = Database::baglantiAc(m_db, "erp_arama_baglantisi", hata);
    if (!m_baglantiHazir)
        qWarning() << "Arama worker veritabanina baglanamadi:" << hata;
}

void AramaWorker::musteriAraCalistir(const QString &arama, int limit)
{
    if (!m_baglantiHazir)
    {
        emit musteriSonucHazir(arama, QVariantList());
        return;
    }
    emit musteriSonucHazir(arama, musteriAraSorgusu(m_db, arama, limit));
}

void AramaWorker::urunAraCalistir(const QString &arama, int limit, const QString &dil)
{
    if (!m_baglantiHazir)
    {
        emit urunSonucHazir(arama, dil, QVariantList());
        return;
    }
    emit urunSonucHazir(arama, dil, urunAraSorgusu(m_db, arama, limit, dil));
}
