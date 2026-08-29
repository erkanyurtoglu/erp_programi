#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>

// Database: SQL Server'daki yeni "LiyaErpVeriTabani" veritabanina QODBC ile
// baglanir ve QML ekranlarinin ihtiyac duydugu sorgulari Q_INVOKABLE metodlar olarak sunar.
//
// Onemli tasarim karari: WPF tarafinda 20 bin kayitta donma yasandigi icin oradaki
// GecmisTekliflerViewModel'i sayfalama + SQL tarafinda filtreleme yapacak sekilde
// yeniden yazmistik. Burada da ayni prensip gecerli: hicbir metot tum tabloyu
// bellege cekmez; filtreleme (WHERE) ve sayfalama (OFFSET/FETCH) SQL Server'da yapilir.
class Database : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool baglantiHazir READ baglantiHazirMi CONSTANT)

public:
    explicit Database(QObject *parent = nullptr);
    ~Database() override;

    bool baglantiHazirMi() const { return m_baglantiHazir; }
    QString sonHataMesaji() const { return m_sonHataMesaji; }

    // Giris ekrani icin kimlik dogrulama.
    // Donen QVariantMap anahtarlari:
    //   "basarili" (bool), "hata" (string, basarisizsa),
    //   "kullaniciId" (int), "adSoyad" (string), "kullaniciAdi" (string),
    //   "moduller" (QVariantList<QVariantMap{modulKodu, modulAdi, duzenleyebilir}>)
    //     -> kullanicinin GOREBILDIGI moduller; "duzenleyebilir" o modulde
    //        duzenleme yetkisi olup olmadigini belirtir (roller birlesik/OR'lanmis halde).
    Q_INVOKABLE QVariantMap girisYap(const QString &kullaniciAdi, const QString &sifre);

    // Gecmis Teklifler ekrani icin filtrelenmis + sayfalanmis liste.
    // Donen QVariantMap anahtarlari: "kayitlar" (QVariantList<QVariantMap>),
    // "toplamKayit" (int), "toplamSayfa" (int), "mevcutSayfa" (int).
    Q_INVOKABLE QVariantMap gecmisTekliflerGetir(const QString &arama,
                                                  const QString &tarihFiltresi,
                                                  const QString &baslangicTarihi,
                                                  const QString &bitisTarihi,
                                                  int sayfaNo,
                                                  int sayfaBoyutu = 50);

    // Tek bir teklifi kalicalarak siler. Basariliysa true doner.
    Q_INVOKABLE bool teklifSil(int teklifId);

private:
    bool baglan();
    // Ortak WHERE kosullarini (tarih + arama filtresi) hem COUNT hem de veri
    // sorgusunda ayni sekilde kullanabilmek icin tek yerde uretir.
    void whereKosullariniOlustur(const QString &arama,
                                  const QString &tarihFiltresi,
                                  const QString &baslangicTarihi,
                                  const QString &bitisTarihi,
                                  QString &whereClauseOut,
                                  QVariantMap &parametrelerOut) const;

    // Kullanicinin gorebildigi modul listesini (roller birlesik) getirir.
    QVariantList kullaniciModulleriniGetir(int kullaniciId);

    QSqlDatabase m_db;
    bool m_baglantiHazir = false;
    QString m_sonHataMesaji;
};
