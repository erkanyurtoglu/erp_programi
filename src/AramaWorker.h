#pragma once

#include <QObject>
#include <QSqlDatabase>
#include <QElapsedTimer>
#include <QVariantList>
#include <QVariantMap>

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
    // "baglantiAdi" her worker icin BENZERSIZ olmalidir: her worker kendi
    // ODBC oturumunu acar ve hicbirini digeriyle paylasmaz.
    explicit AramaWorker(const QString &baglantiAdi, QObject *parent = nullptr);

public slots:
    // QThread::started sinyaline baglanip thread'in kendi icinde cagrilir.
    void baglantiyiAc();

    void musteriAraCalistir(const QString &arama, int limit);
    void urunAraCalistir(const QString &arama, int limit, const QString &dil);

    // Musterilerim / Urunlerim / Personellerim ekranlarindaki SAYFALI listeler.
    // Bunlar once UI thread'inde senkron calisiyordu: her tus vurusunda (350 ms
    // gecikmeyle de olsa) ve her sayfa degisiminde pencere sorgu boyunca
    // donuyordu -- urun listesinde nvarchar(MAX) sutunlar yuzunden bu sure
    // saniyelerle olculuyordu. Artik arama ile ayni thread/baglanti uzerinde.
    void musteriListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                 int sayfaBoyutu, bool arsivliDahil);
    void urunListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                              int sayfaBoyutu, bool arsivliDahil);
    void personelListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                  int sayfaBoyutu, bool pasifDahil);
    void tedarikciListesiCalistir(int istekNo, const QString &arama, int sayfaNo,
                                  int sayfaBoyutu, bool arsivliDahil);

    // Gecmis Teklifler (Giden / Alinan / Biten Tekliflerim). Bu liste de once
    // UI thread'inde senkron cekiliyordu ve en pahali sorgu oydu: arama metni
    // varken her teklif icin teklif_kalemleri + urunler uzerinde EXISTS + LIKE
    // calisiyor, 3000+ kayitli veritabaninda pencere saniyelerce donuyordu.
    void rolListesiCalistir();
    void rolYetkiListesiCalistir();
    void ayarListesiCalistir();
    void panoOzetiCalistir(int istekNo, const QString &donem,
                           const QString &ozelBaslangic, const QString &ozelBitis);
    void islemGecmisiCalistir(int istekNo, const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu);
    void cihazListesiCalistir(int istekNo, const QString &arama, bool arsivDahil);

    void teklifListesiCalistir(int istekNo, const QString &arama,
                               const QString &tarihFiltresi, const QString &baslangicTarihi,
                               const QString &bitisTarihi, int sayfaNo, int sayfaBoyutu,
                               const QString &durumFiltresi);

signals:
    // "arama" (ve urun icin "dil") istegi yapan tarafa aynen geri gonderilir;
    // boylece QML tarafi, kullanici yazmaya devam ettiyse gecikmis/eskimis
    // sonucu gormezden gelebilir (arama kutusunun guncel metniyle karsilastirarak).
    void musteriSonucHazir(const QString &arama, const QVariantList &sonuclar);
    void urunSonucHazir(const QString &arama, const QString &dil, const QVariantList &sonuclar);

    // Liste sonuclarinda eskimislik kontrolu "istekNo" ile yapilir: sayfa her
    // istegine artan bir numara verir ve YALNIZCA en son verdigi numarayla
    // donen sonucu ekrana basar. Arama metni karsilastirmak yetmezdi -- ayni
    // metinle farkli sayfa istekleri de yarisabilir.
    void musteriListesiHazir(int istekNo, const QVariantMap &sonuc);
    void urunListesiHazir(int istekNo, const QVariantMap &sonuc);
    void personelListesiHazir(int istekNo, const QVariantMap &sonuc);
    void tedarikciListesiHazir(int istekNo, const QVariantMap &sonuc);
    void teklifListesiHazir(int istekNo, const QVariantMap &sonuc);
    void rolListesiHazir(const QVariantList &roller);
    void rolYetkiListesiHazir(const QVariantMap &sonuc);
    void ayarListesiHazir(const QVariantMap &sonuc);
    void panoOzetiHazir(int istekNo, const QVariantMap &sonuc);
    void islemGecmisiHazir(int istekNo, const QVariantMap &sonuc);
    void cihazListesiHazir(int istekNo, const QVariantList &liste);

private:
    // Kopmus baglantiyi gerekirse yeniden acar (bkz. Database::baglantiyiHazirla).
    bool baglantiHazir();

    QString m_baglantiAdi;
    QSqlDatabase m_db;
    QElapsedTimer m_sonKullanim;
    QElapsedTimer m_sonBaglantiDenemesi;
};
