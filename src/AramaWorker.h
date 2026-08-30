#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QVariantList>

// TeklifVerPage'deki firma/urun canli aramasini ayri bir thread + ayri bir SQL
// baglantisi uzerinde calistirir. Amac: kullanici yazarken (veya sayfa acilirken)
// atilan sorgular, ana (UI) thread'i bloke etmesin -- once bu ayni sorgular
// dogrudan Database uzerinden, UI thread'inden senkron calisiyordu ve ag/SQL
// Server yavasladiginda tum pencere "Yanit Vermiyor" durumuna dusuyordu.
//
// Onemli: QSqlDatabase baglantilari, acildiklari thread'e "aittir" -- bu yuzden
// baglanti, worker QThread'e tasindiktan SONRA, o thread icinde (baglantiyiAc
// slotu araciligiyla) acilir; Database'in ana baglantisiyla PAYLASILMAZ.
class AramaWorker : public QObject
{
    Q_OBJECT
public:
    explicit AramaWorker(QObject *parent = nullptr);

public slots:
    // QThread::started sinyaline baglanip thread'in kendi icinde cagrilir.
    void baglantiyiAc();

    void musteriAraCalistir(const QString &arama, int limit);
    void urunAraCalistir(const QString &arama, int limit, const QString &dil);

signals:
    // "arama" (ve urun icin "dil") istegi yapan tarafa aynen geri gonderilir;
    // boylece QML tarafi, kullanici yazmaya devam ettiyse gecikmis/eskimis
    // sonucu gormezden gelebilir (arama kutusunun guncel metniyle karsilastirarak).
    void musteriSonucHazir(const QString &arama, const QVariantList &sonuclar);
    void urunSonucHazir(const QString &arama, const QString &dil, const QVariantList &sonuclar);

private:
    QSqlDatabase m_db;
    bool m_baglantiHazir = false;
};
