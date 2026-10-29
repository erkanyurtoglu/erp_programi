#include "AramaWorker.h"
#include "AramaSorgulari.h"
#include "Database.h"

#include <QDebug>

AramaWorker::AramaWorker(const QString &baglantiAdi, QObject *parent)
    : QObject(parent)
    , m_baglantiAdi(baglantiAdi)
{
}

void AramaWorker::baglantiyiAc()
{
    // Bu slot, worker QThread'e tasindiktan sonra QThread::started sinyaliyle
    // cagrilir -- yani burasi zaten worker thread'i icinde calisir, dolayisiyla
    // acilan QSqlDatabase baglantisi da worker thread'ine ait olur (Database'in
    // ana baglantisindan tamamen bagimsiz, ayri bir ODBC oturumu).
    QString hata;
    QElapsedTimer olcum;
    olcum.start();
    m_sonBaglantiDenemesi.start();
    if (Database::baglantiAc(m_db, m_baglantiAdi, hata))
        m_sonKullanim.start();
    else
        qWarning() << "Worker veritabanina baglanamadi (" << m_baglantiAdi << "):" << hata;
    qInfo() << "[olcum] worker baglantisi acildi (" << m_baglantiAdi << "):" << olcum.elapsed() << "ms";
}

bool AramaWorker::baglantiHazir()
{
    QString hata;
    return Database::baglantiyiHazirla(m_db, m_baglantiAdi, m_sonKullanim,
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
    QElapsedTimer olcum;
    olcum.start();
    if (!baglantiHazir())
    {
        qWarning() << "[olcum] urunAra: baglanti HAZIR DEGIL," << olcum.elapsed() << "ms";
        emit urunSonucHazir(arama, dil, QVariantList());
        return;
    }
    const qint64 baglantiMs = olcum.elapsed();
    const QVariantList sonuclar = urunAraSorgusu(m_db, arama, limit, dil);
    qInfo() << "[olcum] urunAra arama=" << arama << "dil=" << dil
            << "baglanti:" << baglantiMs << "ms, sorgu:" << (olcum.elapsed() - baglantiMs)
            << "ms, satir:" << sonuclar.size();
    emit urunSonucHazir(arama, dil, sonuclar);
}

// Baglanti kurulamadiginda da MUTLAKA sonuc yayinlanir (bos liste): aksi halde
// cagiran sayfa "yukleniyor" durumunda sonsuza kadar asili kalirdi.
void AramaWorker::musteriListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                          int sayfaBoyutu, bool arsivliDahil)
{
    if (!baglantiHazir())
    {
        emit musteriListesiHazir(istekNo, QVariantMap());
        return;
    }
    emit musteriListesiHazir(istekNo,
                             musteriListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, arsivliDahil));
}

void AramaWorker::urunListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                       int sayfaBoyutu, bool arsivliDahil)
{
    if (!baglantiHazir())
    {
        emit urunListesiHazir(istekNo, QVariantMap());
        return;
    }
    emit urunListesiHazir(istekNo,
                          urunListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, arsivliDahil));
}

void AramaWorker::personelListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                           int sayfaBoyutu, bool pasifDahil)
{
    if (!baglantiHazir())
    {
        emit personelListesiHazir(istekNo, QVariantMap());
        return;
    }
    emit personelListesiHazir(istekNo,
                              personelListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, pasifDahil));
}

void AramaWorker::tedarikciListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                           int sayfaBoyutu, bool arsivliDahil)
{
    if (!baglantiHazir())
    {
        emit tedarikciListesiHazir(istekNo, QVariantMap());
        return;
    }
    emit tedarikciListesiHazir(istekNo,
                               tedarikciListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, arsivliDahil));
}

void AramaWorker::rolListesiCalistir()
{
    if (!baglantiHazir())
    {
        emit rolListesiHazir(QVariantList());
        return;
    }
    emit rolListesiHazir(rolListesiSorgusu(m_db));
}

void AramaWorker::rolYetkiListesiCalistir()
{
    if (!baglantiHazir())
    {
        emit rolYetkiListesiHazir(QVariantMap());
        return;
    }
    emit rolYetkiListesiHazir(rolYetkiListesiSorgusu(m_db));
}

void AramaWorker::ayarListesiCalistir()
{
    if (!baglantiHazir())
    {
        emit ayarListesiHazir(QVariantMap());
        return;
    }
    emit ayarListesiHazir(ayarListesiSorgusu(m_db));
}

void AramaWorker::panoOzetiCalistir(int istekNo, const QString &donem,
                                    const QString &ozelBaslangic, const QString &ozelBitis)
{
    if (!baglantiHazir())
    {
        emit panoOzetiHazir(istekNo, QVariantMap());
        return;
    }
    emit panoOzetiHazir(istekNo, panoOzetiSorgusu(m_db, donem, ozelBaslangic, ozelBitis));
}

void AramaWorker::islemGecmisiCalistir(int istekNo, const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu)
{
    if (!baglantiHazir())
    {
        emit islemGecmisiHazir(istekNo, QVariantMap());
        return;
    }
    emit islemGecmisiHazir(istekNo, islemGecmisiSorgusu(m_db, suzgec, sayfaNo, sayfaBoyutu));
}

void AramaWorker::muhasebeListesiCalistir(int istekNo, const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu)
{
    if (!baglantiHazir())
    {
        emit muhasebeListesiHazir(istekNo, QVariantMap());
        return;
    }
    emit muhasebeListesiHazir(istekNo, muhasebeListesiSorgusu(m_db, suzgec, sayfaNo, sayfaBoyutu));
}

void AramaWorker::cihazListesiCalistir(int istekNo, const QString &arama, bool arsivDahil)
{
    if (!baglantiHazir())
    {
        emit cihazListesiHazir(istekNo, QVariantList());
        return;
    }
    emit cihazListesiHazir(istekNo, cihazListesiSorgusu(m_db, arama, arsivDahil));
}

void AramaWorker::teklifListesiCalistir(int istekNo, const QString &arama,
                                        const QString &tarihFiltresi,
                                        const QString &baslangicTarihi,
                                        const QString &bitisTarihi, int sayfaNo,
                                        int sayfaBoyutu, const QString &durumFiltresi)
{
    if (!baglantiHazir())
    {
        emit teklifListesiHazir(istekNo, QVariantMap());
        return;
    }
    QElapsedTimer olcum;
    olcum.start();
    const QVariantMap sonuc = teklifListesiSorgusu(m_db, arama, tarihFiltresi, baslangicTarihi,
                                                   bitisTarihi, sayfaNo, sayfaBoyutu, durumFiltresi);
    qInfo() << "[olcum] teklif listesi arama=" << arama << "durum=" << durumFiltresi
            << "sorgu:" << olcum.elapsed() << "ms, toplam:" << sonuc.value("toplamKayit").toInt();
    emit teklifListesiHazir(istekNo, sonuc);
}
