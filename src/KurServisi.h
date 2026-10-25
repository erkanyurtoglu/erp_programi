#pragma once

#include <QObject>
#include <QDate>
#include <QHash>
#include <QString>

class QNetworkAccessManager;
class QNetworkReply;

// TCMB gunluk doviz kurlarini ceken kucuk servis.
//
// Neden var: kur elle giriliyordu. Elle girilen kur, Excel doneminde
// maliyetleri en cok bozan seydi -- bir kere yazilan kur gunler boyu
// kopyalanip duruyordu. Burada kur merkez bankasindan gelir, kullanici
// isterse uzerine yazabilir (ozel anlasmali kur olabilir).
//
// Kaynak: https://www.tcmb.gov.tr/kurlar/today.xml
// TCMB kurlari is gunlerinde ~15:30'da yayinlar; hafta sonu ve yayin
// oncesinde today.xml bulunamaz. Bu yuzden bulunamazsa son 7 gun geriye
// dogru tarihli adresler denenir (gecerli kur, son yayinlanan kurdur).
class KurServisi : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double usd       READ usd       NOTIFY kurlarDegisti)
    Q_PROPERTY(double eur       READ eur       NOTIFY kurlarDegisti)
    Q_PROPERTY(QString kurTarihi READ kurTarihi NOTIFY kurlarDegisti)
    Q_PROPERTY(bool yukleniyor  READ yukleniyor NOTIFY durumDegisti)
    Q_PROPERTY(QString hata     READ hata       NOTIFY durumDegisti)

public:
    explicit KurServisi(QObject *parent = nullptr);

    double usd() const { return m_kurlar.value(QStringLiteral("USD"), 0.0); }
    double eur() const { return m_kurlar.value(QStringLiteral("EUR"), 0.0); }
    QString kurTarihi() const { return m_kurTarihi; }
    bool yukleniyor() const { return m_yukleniyor; }
    QString hata() const { return m_hata; }

    // "TL" -> 1, "USD"/"EUR" -> o gunun kuru, bilinmiyorsa 0.
    // 0 donmesi "kur yok" demektir; cagiran taraf kullaniciya elle girdirir
    // (sessizce 1 varsaymak, dolar fiyatini TL sanmak olurdu).
    Q_INVOKABLE double kur(const QString &paraBirimi) const;

    // Kurlar o gun icin zaten alindiysa tekrar istek atmaz; zorla = true
    // kullanicinin "yenile" dugmesi icindir.
    Q_INVOKABLE void yenile(bool zorla = false);

signals:
    void kurlarDegisti();
    void durumDegisti();

private:
    // Sirayla denenecek adresleri uretir (today.xml + son gunler).
    QStringList adresleri() const;
    void sonrakiAdresiDene();
    void cevabiIsle(QNetworkReply *cevap);
    bool xmliAyristir(const QByteArray &xml);
    void durumuYaz(bool yukleniyor, const QString &hata);

    QNetworkAccessManager *m_ag = nullptr;
    QHash<QString, double> m_kurlar;
    QString m_kurTarihi;       // "gg.aa.yyyy" -- kurun ait oldugu gun
    QDate m_cekilenGun;        // kurlarin hangi takvim gununde alindigi
    QStringList m_sira;        // denenecek adresler
    int m_siradakiIndeks = 0;
    bool m_yukleniyor = false;
    QString m_hata;
};
