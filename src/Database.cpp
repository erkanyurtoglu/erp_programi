#include "Database.h"
#include "AramaWorker.h"
#include "AramaSorgulari.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>
#include <QDateTime>
#include <QDebug>
#include <QCryptographicHash>
#include <QHash>
#include <QRegularExpression>
#include <cmath>
#include <algorithm>
#include <utility>

namespace
{
    // Yeni ERP semasi: ayni SQL Server ornegi (EXCALIBUR\SQLEXPRESS) uzerinde,
    // eski LiyaTeklifVeriTabani'nden bagimsiz, yeniden tasarlanmis veritabani.
    const QString SUNUCU = R"(EXCALIBUR\SQLEXPRESS)";
    const QString VERITABANI = "LiyaErpVeriTabani";

    // Revize edilmis -- yani yerine yeni bir revizyon gecmis, artik gecerli
    // olmayan -- teklifin durumu. Bu deger gecerliDurumlar() listesinde YOKTUR:
    // kullanici durum menusunden secemez, yalnizca teklifKaydet bir revizyon
    // olustururken sistem tarafindan yazilir (bkz. Database.h'deki revizyon notu).
    const QString DURUM_REVIZE_EDILDI = QString::fromUtf8("Revize Edildi");

    const int LOGIN_ZAMAN_ASIMI_SN = 5;
    const int ISTEK_ZAMAN_ASIMI_SN = 30;
    // Bu sureden uzun bosta kalan baglanti kullanilmadan once "SELECT 1" ile yoklanir.
    const qint64 BOSTA_YOKLAMA_ESIGI_MS = 30 * 1000;
    // Sunucu erisilemezken yeniden baglanma en fazla bu aralikla denenir.
    const qint64 YENIDEN_BAGLANMA_ARALIGI_MS = 10 * 1000;

    QString tarihStr(const QVariant &v)
    {
        if (v.isNull())
            return QString();
        return v.toDateTime().date().toString("dd.MM.yyyy");
    }

    QString tarihSaatStr(const QVariant &v)
    {
        if (v.isNull())
            return QString();
        return v.toDateTime().toString("dd.MM.yyyy HH:mm");
    }

    // QML'deki tarih secicinin (TarihTakvimi) "yyyy-MM-dd" ciktisini DATETIME2
    // parametresine cevirir; bos veya gecersizse NULL baglanir.
    QVariant tarihParametresi(const QString &yyyyAaGg)
    {
        const QDate tarih = QDate::fromString(yyyyAaGg.trimmed(), "yyyy-MM-dd");
        if (!tarih.isValid())
            return QVariant(QMetaType(QMetaType::QDateTime));
        return QDateTime(tarih, QTime(0, 0));
    }

    // Kullanicinin gordugu TEK teklif numarasi ("1203", "1203/Rev.2"). TeklifId
    // yalnizca sistemin ic anahtaridir ve hic gosterilmez; numara dbo.teklifler.
    // TeklifNo'dan gelir (bkz. Database::teklifNoSql). Bicim PDF'tekiyle ayni
    // olsun diye TeklifPdfOlusturucu::teklifNoMetni kullanilir.
    QString teklifNoBicimle(int teklifNo, int revizyonNo)
    {
        QVariantMap veri;
        veri["kokTeklifNo"] = teklifNo;
        veri["revizyonNo"] = revizyonNo;
        return TeklifPdfOlusturucu::teklifNoMetni(teklifNo, veri);
    }

    // Sifreleri duz metin yerine SHA-256 hash olarak saklamak icin.
    QString sifreyiHashle(const QString &sifre)
    {
        return QString::fromLatin1(
            QCryptographicHash::hash(sifre.toUtf8(), QCryptographicHash::Sha256).toHex());
    }
}

Database::Database(QObject *parent) : QObject(parent)
{
    m_baglantiHazir = baglan();

    // Arama worker'i kendi thread'ine tasi; baglantisini ANCAK thread fiilen
    // baslayinca (kendi icinde) acar -- bkz. AramaWorker::baglantiyiAc().
    m_aramaWorker = new AramaWorker();
    m_aramaWorker->moveToThread(&m_aramaThread);
    connect(&m_aramaThread, &QThread::started, m_aramaWorker, &AramaWorker::baglantiyiAc);
    connect(m_aramaWorker, &AramaWorker::musteriSonucHazir, this, &Database::musteriSonuclariHazir);
    connect(m_aramaWorker, &AramaWorker::urunSonucHazir, this, &Database::urunSonuclariHazir);
    connect(&m_aramaThread, &QThread::finished, m_aramaWorker, &QObject::deleteLater);
    m_aramaThread.start();
}

Database::~Database()
{
    m_aramaThread.quit();
    m_aramaThread.wait();

    if (m_db.isOpen())
        m_db.close();
}

bool Database::baglantiAc(QSqlDatabase &db, const QString &baglantiAdi, QString &hataMesajiOut)
{
    // Windows'ta genelde birden fazla ODBC surucusu bulunabilir; en yeniden en eskiye
    // dogru sirayla dener, ilk basarili olani kullanir.
    const QStringList surucuAdaylari = {
        "ODBC Driver 18 for SQL Server",
        "ODBC Driver 17 for SQL Server",
        "SQL Server"
    };

    for (const QString &surucu : surucuAdaylari)
    {
        db = QSqlDatabase::addDatabase("QODBC", baglantiAdi);

        QString baglantiDizesi;
        if (surucu == "SQL Server")
        {
            // Windows'ta her zaman hazir gelen eski (ama guvenilir) surucu.
            baglantiDizesi = QString("DRIVER={%1};SERVER=%2;DATABASE=%3;Trusted_Connection=Yes;")
                                  .arg(surucu, SUNUCU, VERITABANI);
        }
        else
        {
            // Yeni ODBC suruculeri varsayilan olarak sifreli baglanti bekleyip
            // yerel/self-signed sertifikada hata verebiliyor; TrustServerCertificate
            // ile App.config'daki TrustServerCertificate=True ayarinin esdegerini kuruyoruz.
            baglantiDizesi = QString("DRIVER={%1};SERVER=%2;DATABASE=%3;"
                                      "Trusted_Connection=Yes;TrustServerCertificate=Yes;Encrypt=Yes;")
                                  .arg(surucu, SUNUCU, VERITABANI);
        }

        db.setDatabaseName(baglantiDizesi);
        // Varsayilan login zaman asimi ~15 sn ve 3 surucu sirayla deneniyor; sunucu
        // erisilemezken bu, UI thread'inde dakikaya yakin donma demekti.
        // CONNECTION_TIMEOUT: kopmus bir baglantida bekleyen istek sonsuza kadar
        // (TCP zaman asimina kadar) askida kalmasin.
        db.setConnectOptions(QString("SQL_ATTR_LOGIN_TIMEOUT=%1;SQL_ATTR_CONNECTION_TIMEOUT=%2")
                                 .arg(LOGIN_ZAMAN_ASIMI_SN).arg(ISTEK_ZAMAN_ASIMI_SN));

        if (db.open())
        {
            qInfo() << "Veritabanina baglanildi. Surucu:" << surucu << "Veritabani:" << VERITABANI
                     << "Baglanti:" << baglantiAdi;
            return true;
        }

        hataMesajiOut = db.lastError().text();

        // db'yi once bosaltip baglantiyi kapatiyoruz ki removeDatabase() cagrisi
        // "connection is still in use" uyarisi vermesin (db hala o baglantiya
        // referans tutan tek nesne, ustteki QSqlDatabase::addDatabase donusunden).
        db.close();
        db = QSqlDatabase();
        QSqlDatabase::removeDatabase(baglantiAdi);
    }

    qWarning() << "Veritabanina baglanilamadi (" << baglantiAdi << "):" << hataMesajiOut;
    return false;
}

bool Database::baglantiyiHazirla(QSqlDatabase &db, const QString &baglantiAdi,
                                 QElapsedTimer &sonKullanim, QElapsedTimer &sonDeneme,
                                 QString &hataMesajiOut)
{
    if (db.isValid() && db.isOpen())
    {
        // Yakin zamanda kullanilan baglantiyi her seferinde yoklamaya gerek yok.
        if (sonKullanim.isValid() && sonKullanim.elapsed() < BOSTA_YOKLAMA_ESIGI_MS)
        {
            sonKullanim.restart();
            return true;
        }

        {
            // Kapsam onemli: removeDatabase() cagrilmadan once bu sorgu yok edilmeli.
            QSqlQuery yokla(db);
            if (yokla.exec("SELECT 1"))
            {
                sonKullanim.restart();
                return true;
            }
            qWarning() << "Veritabani baglantisi kopmus (" << baglantiAdi << "), yeniden baglaniliyor:"
                       << yokla.lastError().text();
        }
    }

    if (sonDeneme.isValid() && sonDeneme.elapsed() < YENIDEN_BAGLANMA_ARALIGI_MS)
        return false;
    sonDeneme.restart();

    if (db.isValid())
        db.close();
    db = QSqlDatabase();
    QSqlDatabase::removeDatabase(baglantiAdi);

    if (!baglantiAc(db, baglantiAdi, hataMesajiOut))
        return false;

    sonKullanim.restart();
    return true;
}

bool Database::baglan()
{
    const bool basarili = baglantiAc(m_db, "erp_baglantisi", m_sonHataMesaji);
    m_sonBaglantiDenemesi.start();
    if (basarili)
        m_sonKullanim.start();
    return basarili;
}

bool Database::baglantiHazir()
{
    m_baglantiHazir = baglantiyiHazirla(m_db, "erp_baglantisi", m_sonKullanim,
                                        m_sonBaglantiDenemesi, m_sonHataMesaji);
    return m_baglantiHazir;
}

QVariantMap Database::girisYap(const QString &kullaniciAdi, const QString &sifre)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString kullaniciAdiTrim = kullaniciAdi.trimmed();
    if (kullaniciAdiTrim.isEmpty() || sifre.isEmpty())
    {
        sonuc["hata"] = "Kullanıcı adı ve şifre boş olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("SELECT KullaniciId, AdSoyad, KullaniciAdi, SifreHash, AktifMi "
                  "FROM dbo.kullanicilar WHERE KullaniciAdi = :kullaniciAdi");
    query.bindValue(":kullaniciAdi", kullaniciAdiTrim);

    if (!query.exec())
    {
        qWarning() << "girisYap sorgusu basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Giriş sırasında bir hata oluştu.";
        return sonuc;
    }

    // Kullanici bulunamadi ya da sifre yanlissa AYNI genel mesaji donuyoruz;
    // boylece disaridan "bu kullanici adi var mi yok mu" anlasilamaz.
    const QString genelHataMesaji = "Kullanıcı adı veya şifre hatalı.";

    if (!query.next())
    {
        sonuc["hata"] = genelHataMesaji;
        return sonuc;
    }

    const int kullaniciId = query.value("KullaniciId").toInt();
    const QString adSoyad = query.value("AdSoyad").toString();
    const QString depolananSifre = query.value("SifreHash").toString();
    const bool aktifMi = query.value("AktifMi").toBool();

    if (!aktifMi)
    {
        sonuc["hata"] = "Bu kullanıcı hesabı pasif durumda.";
        return sonuc;
    }

    // Gecis donemi: eski WPF sisteminden gocen kayitlarda sifre duz metin olarak
    // tasindi (kolon adi SifreHash olsa da icerigi henuz hashlenmemisti). Once
    // hashli esitligi, olmazsa duz metin esitligini kontrol ediyoruz; duz metinle
    // eslesirse kullaniciyi bir daha rahatsiz etmeden sessizce hashli hale
    // yukseltiyoruz (asagidaki UPDATE). Boylece sistem zamanla tamamen hashli
    // sifrelere gecmis olacak.
    const QString girilenSifreHash = sifreyiHashle(sifre);
    bool sifreDogruMu = false;
    bool hashYukseltmesiGerekli = false;

    if (depolananSifre == girilenSifreHash)
    {
        sifreDogruMu = true;
    }
    else if (depolananSifre == sifre)
    {
        sifreDogruMu = true;
        hashYukseltmesiGerekli = true;
    }

    if (!sifreDogruMu)
    {
        sonuc["hata"] = genelHataMesaji;
        return sonuc;
    }

    if (hashYukseltmesiGerekli)
    {
        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.kullanicilar SET SifreHash = :hash WHERE KullaniciId = :id");
        guncelle.bindValue(":hash", girilenSifreHash);
        guncelle.bindValue(":id", kullaniciId);
        if (!guncelle.exec())
            qWarning() << "Sifre hash yukseltmesi basarisiz (giris yine de basarili sayilir):"
                       << guncelle.lastError().text();
    }

    sonuc["basarili"] = true;
    sonuc["kullaniciId"] = kullaniciId;
    sonuc["adSoyad"] = adSoyad;
    sonuc["kullaniciAdi"] = kullaniciAdiTrim;
    sonuc["moduller"] = kullaniciModulleriniGetir(kullaniciId);
    return sonuc;
}

bool Database::yoneticiSifresiDogrula(const QString &sifre)
{
    if (sifre.isEmpty() || !baglantiHazir())
        return false;

    QSqlQuery query(m_db);
    query.prepare(
        "SELECT DISTINCT k.SifreHash "
        "FROM dbo.kullanicilar k "
        "JOIN dbo.kullanici_rolleri kr ON kr.KullaniciId = k.KullaniciId "
        "JOIN dbo.roller r ON r.RolId = kr.RolId "
        "WHERE k.AktifMi = 1 AND r.RolAdi IN (N'Yönetici', N'Göç - Geçici Tam Yetkili')");
    if (!query.exec())
    {
        qWarning() << "yoneticiSifresiDogrula sorgusu basarisiz:" << query.lastError().text();
        return false;
    }

    // girisYap ile ayni kural: hashli ya da (henuz yukseltilmemis) duz metin.
    const QString girilenHash = sifreyiHashle(sifre);
    while (query.next())
    {
        const QString depolanan = query.value(0).toString();
        if (depolanan == girilenHash || depolanan == sifre)
            return true;
    }
    return false;
}

QVariantList Database::kullaniciModulleriniGetir(int kullaniciId)
{
    QVariantList moduller;

    QSqlQuery query(m_db);
    query.prepare(
        "SELECT m.ModulKodu, m.ModulAdi, MAX(CAST(ry.Duzenleyebilir AS INT)) AS Duzenleyebilir "
        "FROM dbo.kullanici_rolleri kr "
        "INNER JOIN dbo.rol_yetkileri ry ON ry.RolId = kr.RolId AND ry.Gorebilir = 1 "
        "INNER JOIN dbo.moduller m ON m.ModulId = ry.ModulId "
        "WHERE kr.KullaniciId = :kullaniciId "
        "GROUP BY m.ModulKodu, m.ModulAdi "
        "ORDER BY m.ModulKodu");
    query.bindValue(":kullaniciId", kullaniciId);

    if (!query.exec())
    {
        qWarning() << "kullaniciModulleriniGetir basarisiz:" << query.lastError().text();
        return moduller;
    }

    while (query.next())
    {
        QVariantMap modul;
        modul["modulKodu"] = query.value("ModulKodu").toString();
        modul["modulAdi"] = query.value("ModulAdi").toString();
        modul["duzenleyebilir"] = query.value("Duzenleyebilir").toBool();
        moduller << modul;
    }

    return moduller;
}

void Database::whereKosullariniOlustur(const QString &arama,
                                        const QString &tarihFiltresi,
                                        const QString &baslangicTarihi,
                                        const QString &bitisTarihi,
                                        const QString &durumFiltresi,
                                        QString &whereClauseOut,
                                        QVariantMap &parametrelerOut) const
{
    QStringList kosullar;

    if (tarihFiltresi == "1 Gün")
        kosullar << "t.OlusturmaTarihi >= DATEADD(day, -1, CAST(GETDATE() AS date))";
    else if (tarihFiltresi == "1 Hafta")
        kosullar << "t.OlusturmaTarihi >= DATEADD(day, -7, CAST(GETDATE() AS date))";
    else if (tarihFiltresi == "15 Gün")
        kosullar << "t.OlusturmaTarihi >= DATEADD(day, -15, CAST(GETDATE() AS date))";
    else if (tarihFiltresi == "30 Gün")
        kosullar << "t.OlusturmaTarihi >= DATEADD(day, -30, CAST(GETDATE() AS date))";
    else if (tarihFiltresi == "Özel Tarih" && !baslangicTarihi.isEmpty() && !bitisTarihi.isEmpty())
    {
        // baslangicTarihi / bitisTarihi QML'den "yyyy-MM-dd" formatinda geliyor.
        kosullar << "CAST(t.OlusturmaTarihi AS date) BETWEEN :baslangic AND :bitis";
        parametrelerOut[":baslangic"] = baslangicTarihi;
        parametrelerOut[":bitis"] = bitisTarihi;
    }

    const QString aramaTrim = arama.trimmed();
    if (!aramaTrim.isEmpty())
    {
        // Numara aramasi, ekranda gorunen Teklif No uzerinden yapilir (TeklifId
        // uzerinden DEGIL): "1203" kok teklifi ve tum revizyonlarini, "1203/Rev.2"
        // (ya da "1203/2", "1203 R2", "1203-Rev2") yalnizca o revizyonu bulur.
        static const QRegularExpression teklifNoDeseni(
            QStringLiteral("^#?(\\d+)(?:\\s*(?:[/-]\\s*(?:rev\\.?|r)?|rev\\.?|r)\\s*(\\d+))?$"),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch noEslesmesi = teklifNoDeseni.match(aramaTrim);
        const bool noEslesiyorMu = noEslesmesi.hasMatch();
        const bool revizyonVarMi = noEslesiyorMu && !noEslesmesi.captured(2).isEmpty();

        QString aramaKosulu = "(";
        if (noEslesiyorMu)
        {
            aramaKosulu += revizyonVarMi
                ? QString("(%1 = :kokTeklifNo AND t.RevizyonNo = :revizyonNo) OR ").arg(teklifNoSql("t"))
                : QString("%1 = :kokTeklifNo OR ").arg(teklifNoSql("t"));
        }

        aramaKosulu +=
            "m.FirmaAdi LIKE :aramaLike OR "
            "p.AdSoyad LIKE :aramaLike OR "
            "EXISTS (SELECT 1 FROM dbo.teklif_kalemleri tk "
            "        INNER JOIN dbo.urunler u ON u.UrunId = tk.UrunId "
            "        WHERE tk.TeklifId = t.TeklifId "
            "          AND (u.UrunAciklamasi LIKE :aramaLike OR u.UrunKodu LIKE :aramaLike))"
            ")";

        kosullar << aramaKosulu;
        parametrelerOut[":aramaLike"] = "%" + aramaTrim + "%";
        if (noEslesiyorMu)
        {
            parametrelerOut[":kokTeklifNo"] = noEslesmesi.captured(1).toInt();
            if (revizyonVarMi)
                parametrelerOut[":revizyonNo"] = noEslesmesi.captured(2).toInt();
        }
    }

    // "Giden Tekliflerim" durumFiltresi'ni bos birakip TUM teklifleri (durumdan
    // bagimsiz) gosterir -- bu sekme WPF'teki gibi bir gecmis/log gibi davraniyor.
    // "Alinan Tekliflerim" / "Biten Tekliflerim" ise burada tek bir Durum degeriyle filtreler.
    if (!durumFiltresi.trimmed().isEmpty())
    {
        kosullar << "t.Durum = :durum";
        parametrelerOut[":durum"] = durumFiltresi.trimmed();
    }

    whereClauseOut = kosullar.isEmpty() ? QString() : ("WHERE " + kosullar.join(" AND "));
}

QVariantMap Database::gecmisTekliflerGetir(const QString &arama,
                                            const QString &tarihFiltresi,
                                            const QString &baslangicTarihi,
                                            const QString &bitisTarihi,
                                            int sayfaNo,
                                            int sayfaBoyutu,
                                            const QString &durumFiltresi)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!baglantiHazir())
    {
        qWarning() << "gecmisTekliflerGetir: veritabani baglantisi yok.";
        return sonuc;
    }

    QString whereClause;
    QVariantMap parametreler;
    whereKosullariniOlustur(arama, tarihFiltresi, baslangicTarihi, bitisTarihi, durumFiltresi, whereClause, parametreler);

    // 1) Toplam kayit sayisi (sayfalama hesabi icin).
    const QString sayimSorgusu = QString(
        "SELECT COUNT(*) "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "%1").arg(whereClause);

    QSqlQuery sayimQuery(m_db);
    sayimQuery.prepare(sayimSorgusu);
    for (auto it = parametreler.constBegin(); it != parametreler.constEnd(); ++it)
        sayimQuery.bindValue(it.key(), it.value());

    if (!sayimQuery.exec())
    {
        qWarning() << "Teklif sayisi sorgusu basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    const int toplamSayfa = std::max(1, static_cast<int>(std::ceil(toplamKayit / static_cast<double>(sayfaBoyutu))));
    sayfaNo = std::clamp(sayfaNo, 1, toplamSayfa);

    // 2) Sayfa verisi.
    // NOT: Yeni semada sevk_bilgileri.TeklifId UNIQUE oldugu icin bir teklifin
    // birden fazla sevk kaydina sahip olmasi artik yapisal olarak imkansiz;
    // yine de OUTER APPLY + TOP 1 korunuyor (ekstra guvenlik, maliyeti yok).
    //
    // KopyaKaynakTeklifId sutunu 07 numarali script ile SONRADAN eklendigi icin
    // sorguya ancak gercekten varsa giriyor -- script'i calistirmamis bir
    // veritabaninda teklif listesi "gecersiz sutun adi" hatasiyla bos kalmasin.
    // Kopya kaynaginin Teklif No'su icin kaynak satirin numarasi/RevizyonNo'su da
    // okunur (kaynak silinmisse NULL gelir, o zaman numara gosterilmez).
    const bool kopyaKolonuVar = kopyaKolonuVarMi();
    const QString kopyaSutunu = kopyaKolonuVar
        ? QString("t.KopyaKaynakTeklifId, %1 AS KopyaKaynakNo, kk.RevizyonNo AS KopyaKaynakRevizyonNo")
              .arg(teklifNoSql("kk"))
        : QStringLiteral("CAST(NULL AS INT) AS KopyaKaynakTeklifId, CAST(NULL AS INT) AS KopyaKaynakNo, "
                         "CAST(NULL AS INT) AS KopyaKaynakRevizyonNo");
    const QString kopyaJoin = kopyaKolonuVar
        ? QStringLiteral("LEFT JOIN dbo.teklifler kk ON kk.TeklifId = t.KopyaKaynakTeklifId ")
        : QString();
    const QString veriSorgusu = QString(
        "SELECT t.TeklifId, m.FirmaAdi, t.OlusturmaTarihi, t.KabulTarihi, "
        "       t.TeslimatTarihi, t.TeslimTarihi, t.UretimPdfTarihi, "
        "       p.KullaniciAdi AS PersonelKullaniciAdi, t.Durum, t.RedSebebi, sb.Aciklamalar, "
        "       t.MusteriNotu, t.UretimNotu, t.AnaTeklifId, t.RevizyonNo, %4 AS TeklifNo, %2, "
        "       son.TeklifId AS GuncelTeklifId, son.RevizyonNo AS GuncelRevizyonNo "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "%3"
        "OUTER APPLY ("
        "    SELECT TOP 1 sbi.Aciklamalar "
        "    FROM dbo.sevk_bilgileri sbi "
        "    WHERE sbi.TeklifId = t.TeklifId "
        "    ORDER BY sbi.SevkBilgileriId DESC"
        ") sb "
        // Bu satirin ait oldugu revizyon zincirinin EN SON kaydi. "Revize Edildi"
        // durumundaki satirlarda "yerine gecen teklif" olarak gosterilir; diger
        // satirlarda (zincirin sonu zaten kendisidir) UI tarafinda kullanilmaz.
        "OUTER APPLY ("
        "    SELECT TOP 1 g.TeklifId, g.RevizyonNo "
        "    FROM dbo.teklifler g "
        "    WHERE g.TeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
        "       OR g.AnaTeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
        "    ORDER BY g.RevizyonNo DESC"
        ") son "
        "%1 "
        "ORDER BY t.OlusturmaTarihi DESC "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY")
        .arg(whereClause, kopyaSutunu, kopyaJoin, teklifNoSql("t"));

    QSqlQuery veriQuery(m_db);
    veriQuery.prepare(veriSorgusu);
    for (auto it = parametreler.constBegin(); it != parametreler.constEnd(); ++it)
        veriQuery.bindValue(it.key(), it.value());
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "Teklif listesi sorgusu basarisiz:" << veriQuery.lastError().text();
        return sonuc;
    }

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        QVariantMap kayit;
        kayit["teklifId"] = veriQuery.value("TeklifId").toInt();
        kayit["firmaAdi"] = veriQuery.value("FirmaAdi").toString();
        kayit["teklifTarihi"] = tarihStr(veriQuery.value("OlusturmaTarihi"));
        kayit["kabulTarihi"] = tarihStr(veriQuery.value("KabulTarihi"));
        kayit["teslimatTarihi"] = tarihStr(veriQuery.value("TeslimatTarihi"));
        kayit["teslimTarihi"] = tarihStr(veriQuery.value("TeslimTarihi"));
        kayit["uretimPdfTarihi"] = tarihSaatStr(veriQuery.value("UretimPdfTarihi"));
        kayit["personelKullaniciAdi"] = veriQuery.value("PersonelKullaniciAdi").toString();
        kayit["durum"] = veriQuery.value("Durum").toString();
        kayit["redSebebi"] = veriQuery.value("RedSebebi").toString();
        kayit["aciklamalar"] = veriQuery.value("Aciklamalar").toString();
        kayit["musteriNotu"] = veriQuery.value("MusteriNotu").toString();
        kayit["uretimNotu"] = veriQuery.value("UretimNotu").toString();
        // Revizyon izleme: AnaTeklifId doluysa bu satir bir revizyondur --
        // Giden Tekliflerim listesinde "Rev N" rozetiyle gosterilir (bkz.
        // GecmisTekliflerPage.qml). anaTeklifId hep KOK teklifin TeklifId'sini
        // tasir (bu satirin kendisi orijinalse anaTeklifId 0'dir).
        kayit["anaTeklifId"] = veriQuery.value("AnaTeklifId").isNull() ? 0 : veriQuery.value("AnaTeklifId").toInt();
        kayit["revizyonNo"] = veriQuery.value("RevizyonNo").toInt();
        // Zincirin en son (gecerli) kaydi: durum "Revize Edildi" ise bu teklifin
        // YERINE GECEN teklif budur ve rozet ipucunda gosterilir.
        kayit["guncelTeklifId"] = veriQuery.value("GuncelTeklifId").toInt();
        kayit["guncelRevizyonNo"] = veriQuery.value("GuncelRevizyonNo").toInt();
        // Kopya izi: bu teklif baska bir teklifin "Kopya" butonuyla olusturulduysa
        // kaynak teklifin id'si. Revizyondan farkli olarak hicbir gecerlilik
        // kurali tasimaz -- yalnizca listede bilgi olarak gosterilir.
        kayit["kopyaKaynakTeklifId"] = veriQuery.value("KopyaKaynakTeklifId").isNull()
            ? 0 : veriQuery.value("KopyaKaynakTeklifId").toInt();

        // Ekranda gosterilen numaralar: hepsi Teklif No bicimindedir (bkz.
        // teklifNoBicimle). teklifId/guncelTeklifId/kopyaKaynakTeklifId yalnizca
        // islem yapmak icin tasinir, kullaniciya gosterilmez.
        // "kokTeklifNo" (int): revizyon eki olmadan numara; liste bunu Rev.N
        // rozetiyle yan yana gosterir.
        const int kokTeklifNo = veriQuery.value("TeklifNo").toInt();
        kayit["kokTeklifNo"] = kokTeklifNo;
        kayit["teklifNo"] = teklifNoBicimle(kokTeklifNo, kayit["revizyonNo"].toInt());
        // Zincirin en son kaydi ayni numarayi tasir, yalnizca revizyonu farklidir.
        kayit["guncelTeklifNo"] = teklifNoBicimle(kokTeklifNo, kayit["guncelRevizyonNo"].toInt());
        kayit["kopyaKaynakTeklifNo"] = veriQuery.value("KopyaKaynakNo").isNull()
            ? QString()
            : teklifNoBicimle(veriQuery.value("KopyaKaynakNo").toInt(),
                              veriQuery.value("KopyaKaynakRevizyonNo").toInt());
        kayitlar << kayit;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

bool Database::teklifSil(int teklifId)
{
    // NOT: WPF tarafindaki sifre onayli silme akisi burada henuz yok;
    // bu ilk asamada sadece mimariyi (QML -> C++ -> SQL Server) dogruluyoruz.
    // Sifre onayi/onay penceresi sonraki adimda eklenecek.
    if (!baglantiHazir())
        return false;

    // Kabul edilmis / tamamlanmis teklif silinemez (bkz. teklifKilitliMi).
    if (teklifKilitliMi(teklifDurumuGetir(teklifId)))
    {
        qWarning() << "teklifSil: kilitli teklif silinemez:" << teklifId;
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.teklifler WHERE TeklifId = :teklifId");
    query.bindValue(":teklifId", teklifId);

    if (!query.exec())
    {
        qWarning() << "Teklif silinemedi:" << query.lastError().text();
        return false;
    }
    return true;
}

void Database::musteriAraBaslat(const QString &arama, int limit)
{
    // Sorgu, UI thread'ini bloke etmemesi icin AramaWorker'in kendi thread'inde
    // calisir; sonuc musteriSonuclariHazir sinyaliyle asenkron olarak doner.
    if (m_aramaWorker)
        QMetaObject::invokeMethod(m_aramaWorker, "musteriAraCalistir", Qt::QueuedConnection,
                                   Q_ARG(QString, arama), Q_ARG(int, limit));
}

void Database::urunAraBaslat(const QString &arama, int limit, const QString &dil)
{
    if (m_aramaWorker)
        QMetaObject::invokeMethod(m_aramaWorker, "urunAraCalistir", Qt::QueuedConnection,
                                   Q_ARG(QString, arama), Q_ARG(int, limit), Q_ARG(QString, dil));
}

QVariantMap Database::teklifKaydet(const QVariantMap &teklif)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["teklifId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const int musteriId = teklif.value("musteriId").toInt();
    const QVariantList kalemler = teklif.value("kalemler").toList();

    if (musteriId <= 0)
    {
        sonuc["hata"] = "Lütfen bir müşteri seçin.";
        return sonuc;
    }
    if (kalemler.isEmpty())
    {
        sonuc["hata"] = "Sepette en az bir ürün olmalı.";
        return sonuc;
    }

    // Tum yazma islemini tek transaction icinde yapiyoruz: teklifler + teklif_kalemleri +
    // teklif_toplamlari ya hep birlikte kaydolur ya da hicbiri (yarim kalmis teklif olusmasin).
    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    // Revizyon baglantisi (bkz. Database.h dokumantasyonu): "anaTeklifId" QML
    // tarafindan sadece Detay -> Teklif Ver -> Kaydet (revizyon) akisinda,
    // >0 olarak gonderilir. Normal "yeni teklif" akisinda bu anahtar 0/bos
    // gelir ve asagidaki blok hic calismaz -- eski davranis AYNEN korunur.
    int anaTeklifId = 0;
    int revizyonNo = 0;
    const int talepEdilenAnaTeklifId = teklif.value("anaTeklifId", 0).toInt();
    if (talepEdilenAnaTeklifId > 0)
    {
        // Secilen teklif zaten bir revizyonsa, KOK teklife baglaniyoruz --
        // boylece revizyon zinciri hep tek bir ana teklif altinda kalir
        // (revizyonun revizyonu diye ayri bir dal olusmaz).
        QSqlQuery kokQuery(m_db);
        kokQuery.prepare("SELECT AnaTeklifId FROM dbo.teklifler WHERE TeklifId = :id");
        kokQuery.bindValue(":id", talepEdilenAnaTeklifId);
        if (kokQuery.exec() && kokQuery.next() && !kokQuery.value(0).isNull())
            anaTeklifId = kokQuery.value(0).toInt();
        else
            anaTeklifId = talepEdilenAnaTeklifId;

        // TAMAMLANMIS IS REVIZE EDILEMEZ: zincirde "Tamamlandı" bir teklif varsa
        // is bitmistir, yeni revizyon acilmaz. Yanlislikla tamamlandiysa kullanici
        // once durumu "Beklemede"ye geri alir (bkz. teklifDurumGuncelle).
        QSqlQuery tamamQuery(m_db);
        tamamQuery.prepare(
            "SELECT COUNT(*) FROM dbo.teklifler "
            "WHERE (TeklifId = :ana OR AnaTeklifId = :ana) AND Durum = :durum");
        tamamQuery.bindValue(":ana", anaTeklifId);
        tamamQuery.bindValue(":durum", QStringLiteral("Tamamlandı"));
        if (!tamamQuery.exec() || !tamamQuery.next() || tamamQuery.value(0).toInt() > 0)
        {
            m_db.rollback();
            sonuc["hata"] = tamamQuery.lastError().isValid()
                ? "Teklif durumu okunamadı: " + tamamQuery.lastError().text()
                : QStringLiteral("Tamamlanmış teklif revize edilemez. Gerekirse önce durumunu "
                                 "\"Beklemede\"ye alın.");
            return sonuc;
        }

        QSqlQuery revQuery(m_db);
        revQuery.prepare(
            "SELECT ISNULL(MAX(RevizyonNo), 0) FROM dbo.teklifler "
            "WHERE TeklifId = :ana OR AnaTeklifId = :ana");
        revQuery.bindValue(":ana", anaTeklifId);
        revizyonNo = (revQuery.exec() && revQuery.next()) ? revQuery.value(0).toInt() + 1 : 1;
    }

    // --- Teklif No ------------------------------------------------------------
    // Revizyon numara harcamaz: kok teklifin numarasini aynen tasir. Yeni
    // (bagimsiz) teklif ise en buyuk numara + 1 alir -- boylece numaralar,
    // TeklifId'nin aksine, revizyonlar yuzunden atlamaz (bkz. db/10_teklif_no.sql).
    // Kolon yoksa (script calistirilmamissa) numara eskisi gibi TeklifId'den
    // turetilir ve burada hicbir sey yazilmaz.
    const bool teklifNoYazilacak = teklifNoKolonuVarMi();
    int teklifNo = 0;
    if (teklifNoYazilacak)
    {
        QString noHatasi;
        teklifNo = anaTeklifId > 0 ? kokTeklifNoGetir(anaTeklifId) : yeniTeklifNoAl(noHatasi);
        if (teklifNo <= 0)
        {
            m_db.rollback();
            sonuc["hata"] = noHatasi.isEmpty() ? QStringLiteral("Teklif numarası alınamadı.") : noHatasi;
            return sonuc;
        }
    }

    QSqlQuery teklifEkle(m_db);
    teklifEkle.prepare(QString(
        "INSERT INTO dbo.teklifler "
        "(MusteriId, KullaniciId, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu, UretimNotu, ParaBirimi, Dil, "
        " IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta, TeslimatSekli, TeslimatYeri, "
        " TeslimatTarihi, SatisSozlesmesiMetni, AnaTeklifId, RevizyonNo%1) "
        "OUTPUT INSERTED.TeklifId "
        "VALUES (:musteriId, :kullaniciId, :indirim, :kdv, N'Beklemede', :not, :uretimNotu, :paraBirimi, :dil, "
        "        :ilgiliKisi, :ilgiliKisiTel, :ilgiliKisiEposta, :teslimatSekli, :teslimatYeri, "
        "        :teslimatTarihi, :sozlesmeMetni, :anaTeklifId, :revizyonNo%2)")
        .arg(teklifNoYazilacak ? QStringLiteral(", TeklifNo") : QString(),
             teklifNoYazilacak ? QStringLiteral(", :teklifNo") : QString()));
    if (teklifNoYazilacak)
        teklifEkle.bindValue(":teklifNo", teklifNo);
    teklifEkle.bindValue(":musteriId", musteriId);
    if (anaTeklifId > 0)
        teklifEkle.bindValue(":anaTeklifId", anaTeklifId);
    else
        teklifEkle.bindValue(":anaTeklifId", QVariant(QMetaType(QMetaType::Int)));
    teklifEkle.bindValue(":revizyonNo", revizyonNo);
    const int kullaniciId = teklif.value("kullaniciId").toInt();
    if (kullaniciId > 0)
        teklifEkle.bindValue(":kullaniciId", kullaniciId);
    else
        teklifEkle.bindValue(":kullaniciId", QVariant(QMetaType(QMetaType::Int)));
    teklifEkle.bindValue(":indirim", teklif.value("genelIndirimOrani", 0).toDouble());
    teklifEkle.bindValue(":kdv", teklif.value("kdvOrani", 0).toDouble());
    teklifEkle.bindValue(":not", teklif.value("musteriNotu").toString());
    teklifEkle.bindValue(":uretimNotu", teklif.value("uretimNotu").toString());
    teklifEkle.bindValue(":paraBirimi", teklif.value("paraBirimi", "TL").toString());
    teklifEkle.bindValue(":dil", teklif.value("dil", "TR").toString());
    teklifEkle.bindValue(":ilgiliKisi", teklif.value("ilgiliKisi").toString());
    teklifEkle.bindValue(":ilgiliKisiTel", teklif.value("ilgiliKisiTelefonu").toString());
    teklifEkle.bindValue(":ilgiliKisiEposta", teklif.value("ilgiliKisiEposta").toString());
    teklifEkle.bindValue(":teslimatSekli", teklif.value("teslimatSekli").toString());
    teklifEkle.bindValue(":teslimatYeri", teklif.value("teslimatYeri").toString());
    teklifEkle.bindValue(":teslimatTarihi", tarihParametresi(teklif.value("teslimatTarihi").toString()));

    // Sozlesme metni: kullanici "Satış Sözleşmesi" penceresinde bir degisiklik
    // yapmadiysa QML bu alani bos gonderir -> NULL kaydedilir ve PDF uretilirken
    // dilin varsayilan metni kullanilir (bkz. TeklifPdfOlusturucu).
    const QString sozlesmeMetni = teklif.value("sozlesmeMetni").toString().trimmed();
    if (sozlesmeMetni.isEmpty())
        teklifEkle.bindValue(":sozlesmeMetni", QVariant(QMetaType(QMetaType::QString)));
    else
        teklifEkle.bindValue(":sozlesmeMetni", sozlesmeMetni);

    if (!teklifEkle.exec() || !teklifEkle.next())
    {
        qWarning() << "teklifKaydet (teklifler) basarisiz:" << teklifEkle.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + teklifEkle.lastError().text();
        return sonuc;
    }

    const int teklifId = teklifEkle.value(0).toInt();

    QString icerikHatasi;
    if (!teklifIceriginiYaz(teklifId, teklif, icerikHatasi))
    {
        m_db.rollback();
        sonuc["hata"] = icerikHatasi;
        return sonuc;
    }

    // --- Kopya izi -----------------------------------------------------------
    // "Kopya" akisi (bkz. TeklifVerPage.kopyalamayaBasla): bu kayit var olan bir
    // teklifin icerigi kopyalanarak olusturuldu. Yazilan tek sey bu iz; kaynak
    // teklife DOKUNULMAZ (revizyonun aksine durumu degismez, zincire baglanmaz),
    // cunku amac ayni anda gecerli olabilen iki bagimsiz teklif.
    //
    // Ayri bir UPDATE olmasinin sebebi: kolon veritabaninda olmayabilir (bkz.
    // kopyaKolonuVarMi). Boylece ana INSERT her durumda ayni kalir ve 07 numarali
    // script calistirilmamis bir kurulumda teklif kaydi yine de sorunsuz olusur.
    const int kopyaKaynakTeklifId = teklif.value("kopyaKaynakTeklifId", 0).toInt();
    if (anaTeklifId <= 0 && kopyaKaynakTeklifId > 0 && kopyaKolonuVarMi())
    {
        QSqlQuery kopyaIzi(m_db);
        kopyaIzi.prepare("UPDATE dbo.teklifler SET KopyaKaynakTeklifId = :kaynak WHERE TeklifId = :id");
        kopyaIzi.bindValue(":kaynak", kopyaKaynakTeklifId);
        kopyaIzi.bindValue(":id", teklifId);
        if (!kopyaIzi.exec())
        {
            // Iz yazilamadiysa teklifin kendisini kaybetmiyoruz: kopya izi
            // yalnizca bilgi amaclidir, teklifin ticari icerigini etkilemez.
            qWarning() << "teklifKaydet (kopya izi) basarisiz:" << kopyaIzi.lastError().text();
        }
    }

    // --- Eski teklifleri "Revize Edildi" olarak isaretle ---------------------
    // Ayni koke bagli ONCEKI kayitlar (kok teklif + eski revizyonlar) artik
    // gecerli degildir: yerlerine bu yeni revizyon gecti. Musteriye ayni teklifin
    // iki surumu de gecerliymis gibi gorunmesin diye bunlari "Revize Edildi"
    // durumuna aliyoruz; boylece listede ayirt edilirler ve PDF'leri yeniden
    // uretilirse ustune uyari bandi basilir (bkz. pdfVerisiniOku).
    //
    // KILITLI teklifler (Kabul Edildi / Tamamlandı) bilincli olarak DISARIDA
    // birakilir: kabul edilmis bir teklif hala yururlukteki bir taahhut olabilir,
    // onun gecersiz sayilmasina sistem degil kullanici karar verir (durum rozeti).
    QVariantList revizeEdilenler;
    if (anaTeklifId > 0)
    {
        QSqlQuery eskiQuery(m_db);
        eskiQuery.prepare(
            "SELECT TeklifId FROM dbo.teklifler "
            "WHERE (TeklifId = :ana OR AnaTeklifId = :ana) "
            "  AND TeklifId <> :yeni AND Durum = N'Beklemede'");
        eskiQuery.bindValue(":ana", anaTeklifId);
        eskiQuery.bindValue(":yeni", teklifId);
        if (eskiQuery.exec())
        {
            while (eskiQuery.next())
                revizeEdilenler << eskiQuery.value(0).toInt();
        }

        if (!revizeEdilenler.isEmpty())
        {
            QSqlQuery isaretle(m_db);
            isaretle.prepare(
                "UPDATE dbo.teklifler SET Durum = :durum "
                "WHERE (TeklifId = :ana OR AnaTeklifId = :ana) "
                "  AND TeklifId <> :yeni AND Durum = N'Beklemede'");
            isaretle.bindValue(":durum", DURUM_REVIZE_EDILDI);
            isaretle.bindValue(":ana", anaTeklifId);
            isaretle.bindValue(":yeni", teklifId);
            if (!isaretle.exec())
            {
                qWarning() << "teklifKaydet (revize isaretleme) basarisiz:" << isaretle.lastError().text();
                m_db.rollback();
                sonuc["hata"] = "Eski teklif revize edilmiş olarak işaretlenemedi: " + isaretle.lastError().text();
                return sonuc;
            }
        }
    }

    if (!m_db.commit())
    {
        qWarning() << "teklifKaydet commit basarisiz:" << m_db.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    // Durum gecmisi loglari bilincli olarak COMMIT SONRASI yazilir: loglama
    // "best effort"tur (tablo yoksa hata verir) ve bunun teklif kaydini goturmesi
    // istenmez (bkz. durumDegisiminiLogla).
    const QString yeniTeklifNoMetni = teklifNoGetir(teklifId);
    // Revizyon sebebi hem eski teklif(ler)in "Revize Edildi" satirina hem de
    // yeni revizyonun ilk satirina yazilir: iki taraftan da Teklif Gecmisi'nde
    // okunur (eski teklif kilitliyse "Revize Edildi" yapilmaz, sebep yine kaybolmaz).
    const QString revizyonSebebi = teklif.value("revizyonSebebi").toString().trimmed();
    const QString sebepEki = revizyonSebebi.isEmpty() ? QString() : " Sebep: " + revizyonSebebi;
    for (const QVariant &eskiId : std::as_const(revizeEdilenler))
        durumDegisiminiLogla(eskiId.toInt(), "Beklemede", DURUM_REVIZE_EDILDI,
                             QString("Teklif %1 olarak revize edildi.%2").arg(yeniTeklifNoMetni, sebepEki).left(500),
                             kullaniciId);
    if (anaTeklifId > 0)
        durumDegisiminiLogla(teklifId, QString(), QStringLiteral("Beklemede"),
                             QString("Teklif %1 revizyonu olarak oluşturuldu.%2")
                                 .arg(teklifNoGetir(talepEdilenAnaTeklifId), sebepEki).left(500),
                             kullaniciId);

    sonuc["basarili"] = true;
    sonuc["teklifId"] = teklifId;
    sonuc["teklifNo"] = yeniTeklifNoMetni;
    // QML kullaniciya "hangi eski teklif(ler) gecersizlesti" bilgisini gosterir.
    sonuc["revizeEdilenTeklifIdler"] = revizeEdilenler;
    return sonuc;
}

bool Database::teklifIceriginiYaz(int teklifId, const QVariantMap &teklif, QString &hataOut)
{
    const QVariantList kalemler = teklif.value("kalemler").toList();

    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap kalem = kalemVar.toMap();

        QSqlQuery kalemEkle(m_db);
        kalemEkle.prepare(
            "INSERT INTO dbo.teklif_kalemleri "
            "(TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati, "
            " UrunAciklamasi, ParaBirimi, Kur, Tamamlandi, UretimNotu) "
            "VALUES (:teklifId, :urunId, :adet, :birimFiyat, :indirimliBirimFiyat, :toplamTutar, "
            "        :maliyetFiyati, :urunAciklamasi, :paraBirimi, :kur, :tamamlandi, :kalemUretimNotu)");
        kalemEkle.bindValue(":teklifId", teklifId);

        // Manuel eklenen kalemlerde (sepete elle yazilan, urunler tablosunda karsiligi
        // olmayan satirlar) UrunId gonderilmez; boyle bir durumda "manuel urun" icin
        // ozel bir yer tutucu urun kaydi kullaniyoruz (asagida garanti ediliyor).
        int urunId = kalem.value("urunId", 0).toInt();
        if (urunId <= 0)
        {
            // Manuel kalem: urunler tablosunda bu teklife ozel, kalici olmayan bir
            // satir olusturup UrunId'sini kullaniyoruz (FOREIGN KEY zorunlulugu var).
            // Kod'u "MANUEL-<teklifId>" seklinde teklife baglayarak izlenebilir
            // kiliyoruz; urunAra/urunListesiGetir bu "MANUEL%" kodlu satirlari
            // ürün kataloğu aramalarindan/listelerinden dislar, boylece bu teklife
            // ozel gecici satirlar normal urun kataloğunu kirletmez.
            QSqlQuery manuelUrun(m_db);
            manuelUrun.prepare(
                "INSERT INTO dbo.urunler (UrunKodu, UrunAciklamasi, BirimFiyat, ParaBirimi) "
                "OUTPUT INSERTED.UrunId "
                "VALUES (:kod, :aciklama, :birimFiyat, :paraBirimi)");
            manuelUrun.bindValue(":kod", QString("MANUEL-%1").arg(teklifId));
            manuelUrun.bindValue(":aciklama", kalem.value("aciklama").toString());
            manuelUrun.bindValue(":birimFiyat", kalem.value("birimFiyat", 0).toDouble());
            manuelUrun.bindValue(":paraBirimi", kalem.value("paraBirimi", "TL").toString());
            if (!manuelUrun.exec() || !manuelUrun.next())
            {
                qWarning() << "teklifIceriginiYaz (manuel urun) basarisiz:" << manuelUrun.lastError().text();
                hataOut = "Manuel ürün kaydedilemedi: " + manuelUrun.lastError().text();
                return false;
            }
            urunId = manuelUrun.value(0).toInt();
        }

        kalemEkle.bindValue(":urunId", urunId);
        kalemEkle.bindValue(":adet", kalem.value("adet", 1).toInt());
        kalemEkle.bindValue(":birimFiyat", kalem.value("birimFiyat", 0).toDouble());
        kalemEkle.bindValue(":indirimliBirimFiyat", kalem.value("indirimliBirimFiyat", 0).toDouble());
        kalemEkle.bindValue(":toplamTutar", kalem.value("toplamTutar", 0).toDouble());
        kalemEkle.bindValue(":maliyetFiyati", kalem.value("maliyetFiyati", 0).toDouble());
        kalemEkle.bindValue(":urunAciklamasi", kalem.value("aciklama").toString());
        kalemEkle.bindValue(":paraBirimi", kalem.value("paraBirimi", "TL").toString());
        kalemEkle.bindValue(":kur", kalem.value("kur", 1).toDouble());

        // Satir bazli uretim takibi. Normal "Teklif Ver" ve "Kopya" akislarinda
        // bu alanlar hic gelmez -> 0 / NULL, yani uretim yeni tekliften temiz
        // baslar. Revizyonda ve duzeltmede ise QML kaynak teklifin degerlerini
        // tasidigi icin "hangi kalem bitmisti" bilgisi korunur.
        kalemEkle.bindValue(":tamamlandi", kalem.value("tamamlandi", false).toBool() ? 1 : 0);
        const QString kalemUretimNotu = kalem.value("uretimNotu").toString().trimmed();
        kalemEkle.bindValue(":kalemUretimNotu", kalemUretimNotu.isEmpty()
            ? QVariant(QMetaType(QMetaType::QString)) : QVariant(kalemUretimNotu));

        if (!kalemEkle.exec())
        {
            qWarning() << "teklifIceriginiYaz (teklif_kalemleri) basarisiz:" << kalemEkle.lastError().text();
            hataOut = "Teklif kalemi kaydedilemedi: " + kalemEkle.lastError().text();
            return false;
        }
    }

    QSqlQuery toplamEkle(m_db);
    toplamEkle.prepare(
        "INSERT INTO dbo.teklif_toplamlari "
        "(TeklifId, IndirimliToplam, KdvTutari, GenelToplam, PaketlemeUcreti, TasimaUcreti) "
        "VALUES (:teklifId, :indirimliToplam, :kdvTutari, :genelToplam, :paketleme, :tasima)");
    toplamEkle.bindValue(":teklifId", teklifId);
    toplamEkle.bindValue(":indirimliToplam", teklif.value("indirimliToplam", 0).toDouble());
    toplamEkle.bindValue(":kdvTutari", teklif.value("kdvTutari", 0).toDouble());
    toplamEkle.bindValue(":genelToplam", teklif.value("genelToplam", 0).toDouble());
    toplamEkle.bindValue(":paketleme", teklif.value("paketlemeUcreti", 0).toDouble());
    toplamEkle.bindValue(":tasima", teklif.value("tasimaUcreti", 0).toDouble());

    if (!toplamEkle.exec())
    {
        qWarning() << "teklifIceriginiYaz (teklif_toplamlari) basarisiz:" << toplamEkle.lastError().text();
        hataOut = "Teklif toplamları kaydedilemedi: " + toplamEkle.lastError().text();
        return false;
    }

    return true;
}

bool Database::duzeltmeKuraliniDenetle(int teklifId, QString &hataOut)
{
    const QString durum = teklifDurumuGetir(teklifId);
    if (durum.isEmpty())
    {
        hataOut = "Teklif bulunamadı.";
        return false;
    }
    // Yalnizca "Beklemede": kabul edilmis/tamamlanmis teklif bir taahhuttur,
    // reddedilmis teklif musteriye gitmis ve cevaplanmistir -- ikisinde de
    // icerik degisikligi ancak yeni bir revizyonla (iz birakarak) yapilir.
    if (durum != "Beklemede")
    {
        hataOut = QString("Teklif \"%1\" durumunda; yalnızca revizyon olarak kaydedilebilir.").arg(durum);
        return false;
    }
    const int yerineGecen = teklifYerineGecenIdGetir(teklifId);
    if (yerineGecen > 0)
    {
        hataOut = QString("Bu teklifin yerine Teklif %1 geçti; düzeltme güncel revizyon üzerinde yapılmalı.")
                      .arg(teklifNoGetir(yerineGecen));
        return false;
    }
    return true;
}

bool Database::teklifDuzeltilebilirMi(int teklifId)
{
    m_sonHataMesaji.clear();
    if (teklifId <= 0 || !baglantiHazir())
        return false;
    QString hata;
    const bool izinli = duzeltmeKuraliniDenetle(teklifId, hata);
    m_sonHataMesaji = hata;
    return izinli;
}

QVariantMap Database::teklifDuzelt(int teklifId, const QVariantMap &teklif, const QString &sebep)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["teklifId"] = teklifId;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const int musteriId = teklif.value("musteriId").toInt();
    const QString temizSebep = sebep.trimmed();
    if (teklifId <= 0)
    {
        sonuc["hata"] = "Düzeltilecek teklif belirtilmedi.";
        return sonuc;
    }
    if (musteriId <= 0)
    {
        sonuc["hata"] = "Lütfen bir müşteri seçin.";
        return sonuc;
    }
    if (teklif.value("kalemler").toList().isEmpty())
    {
        sonuc["hata"] = "Sepette en az bir ürün olmalı.";
        return sonuc;
    }
    if (temizSebep.isEmpty())
    {
        sonuc["hata"] = "Düzeltme sebebi zorunludur.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    // Kural denetimi transaction ICINDE ve satir kilidiyle: kontrol ile yazma
    // arasinda baska bir kullanici teklifi kabul edemesin / revize edemesin.
    {
        QSqlQuery kilit(m_db);
        kilit.prepare("SELECT Durum FROM dbo.teklifler WITH (UPDLOCK, ROWLOCK) WHERE TeklifId = :id");
        kilit.bindValue(":id", teklifId);
        kilit.exec();
    }
    QString kuralHatasi;
    if (!duzeltmeKuraliniDenetle(teklifId, kuralHatasi))
    {
        m_db.rollback();
        sonuc["hata"] = kuralHatasi;
        return sonuc;
    }

    // --- 1) Iz: ustune yazmadan ONCE teklifin tam hali -------------------------
    // Sunucu tarafinda FOR JSON ile uretilir: veritabanindaki degerler (para
    // birimi/kur donusumu yapilmamis, ham haliyle) aynen saklanir. Firma adi da
    // eklenir -- duzeltmelerin en sik sebebi yanlis firma secimidir ve MusteriId
    // tek basina okunakli degildir.
    QSqlQuery iz(m_db);
    iz.prepare(
        "INSERT INTO dbo.teklif_duzeltme_gecmisi (TeklifId, Sebep, OncekiVeri, KullaniciId) "
        "SELECT t.TeklifId, :sebep, "
        "  (SELECT t2.*, "
        "          (SELECT m.FirmaAdi FROM dbo.musteriler m WHERE m.MusteriId = t2.MusteriId) AS FirmaAdi, "
        "          JSON_QUERY((SELECT tk.* FROM dbo.teklif_kalemleri tk "
        "                      WHERE tk.TeklifId = t2.TeklifId ORDER BY tk.TeklifKalemId "
        "                      FOR JSON PATH)) AS Kalemler, "
        "          JSON_QUERY((SELECT tt.* FROM dbo.teklif_toplamlari tt "
        "                      WHERE tt.TeklifId = t2.TeklifId "
        "                      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Toplamlar "
        "   FROM dbo.teklifler t2 WHERE t2.TeklifId = t.TeklifId "
        "   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), "
        "  :kullaniciId "
        "FROM dbo.teklifler t WHERE t.TeklifId = :teklifId");
    iz.bindValue(":sebep", temizSebep.left(500));
    const int kullaniciId = teklif.value("kullaniciId").toInt();
    iz.bindValue(":kullaniciId", kullaniciId > 0 ? QVariant(kullaniciId) : QVariant(QMetaType(QMetaType::Int)));
    iz.bindValue(":teklifId", teklifId);
    if (!iz.exec() || iz.numRowsAffected() != 1)
    {
        qWarning() << "teklifDuzelt (iz) basarisiz:" << iz.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Düzeltme geçmişi yazılamadığı için teklif değiştirilmedi. "
                        "(db/09_teklif_duzeltme_gecmisi.sql çalıştırıldı mı?) "
                        "Değişikliği revizyon olarak kaydedebilirsiniz.";
        return sonuc;
    }

    // --- 2) Baslik: ayni TeklifId yerinde guncellenir ----------------------------
    // Dokunulmayanlar bilincli: KullaniciId (teklifi hazirlayan), OlusturmaTarihi,
    // Durum ve durum tarihleri, AnaTeklifId/RevizyonNo (zincirdeki yeri),
    // KopyaKaynakTeklifId. Duzeltme teklifin kimligini degil icerigini duzeltir.
    QSqlQuery baslik(m_db);
    baslik.prepare(
        "UPDATE dbo.teklifler SET "
        "  MusteriId = :musteriId, GenelIndirimOrani = :indirim, KdvOrani = :kdv, "
        "  MusteriNotu = :not, UretimNotu = :uretimNotu, ParaBirimi = :paraBirimi, Dil = :dil, "
        "  IlgiliKisi = :ilgiliKisi, IlgiliKisiTelefonu = :ilgiliKisiTel, IlgiliKisiEposta = :ilgiliKisiEposta, "
        "  TeslimatSekli = :teslimatSekli, TeslimatYeri = :teslimatYeri, "
        "  TeslimatTarihi = :teslimatTarihi, SatisSozlesmesiMetni = :sozlesmeMetni "
        "WHERE TeklifId = :teklifId AND Durum = N'Beklemede'");
    baslik.bindValue(":musteriId", musteriId);
    baslik.bindValue(":indirim", teklif.value("genelIndirimOrani", 0).toDouble());
    baslik.bindValue(":kdv", teklif.value("kdvOrani", 0).toDouble());
    baslik.bindValue(":not", teklif.value("musteriNotu").toString());
    baslik.bindValue(":uretimNotu", teklif.value("uretimNotu").toString());
    baslik.bindValue(":paraBirimi", teklif.value("paraBirimi", "TL").toString());
    baslik.bindValue(":dil", teklif.value("dil", "TR").toString());
    baslik.bindValue(":ilgiliKisi", teklif.value("ilgiliKisi").toString());
    baslik.bindValue(":ilgiliKisiTel", teklif.value("ilgiliKisiTelefonu").toString());
    baslik.bindValue(":ilgiliKisiEposta", teklif.value("ilgiliKisiEposta").toString());
    baslik.bindValue(":teslimatSekli", teklif.value("teslimatSekli").toString());
    baslik.bindValue(":teslimatYeri", teklif.value("teslimatYeri").toString());
    baslik.bindValue(":teslimatTarihi", tarihParametresi(teklif.value("teslimatTarihi").toString()));
    const QString sozlesmeMetni = teklif.value("sozlesmeMetni").toString().trimmed();
    baslik.bindValue(":sozlesmeMetni", sozlesmeMetni.isEmpty()
        ? QVariant(QMetaType(QMetaType::QString)) : QVariant(sozlesmeMetni));
    baslik.bindValue(":teklifId", teklifId);
    if (!baslik.exec() || baslik.numRowsAffected() != 1)
    {
        qWarning() << "teklifDuzelt (baslik) basarisiz:" << baslik.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif düzeltilemedi: " + baslik.lastError().text();
        return sonuc;
    }

    // --- 3) Kalemler + toplamlar bastan yazilir ----------------------------------
    // Eski kalemler silinir; bu teklife ozel "MANUEL-<id>" urun satirlari da
    // artik hicbir kaleme bagli olmadigi icin temizlenir (yenileri
    // teklifIceriginiYaz'da ayni kodla olusur). Baska bir teklifin kalemine bagli
    // bir satir -- olmamasi gerekir -- NOT EXISTS ile korunur.
    const QStringList temizlikSorgulari = {
        "DELETE FROM dbo.teklif_kalemleri WHERE TeklifId = :teklifId",
        "DELETE FROM dbo.urunler WHERE UrunKodu = :manuelKod "
        "  AND NOT EXISTS (SELECT 1 FROM dbo.teklif_kalemleri tk WHERE tk.UrunId = dbo.urunler.UrunId)",
        "DELETE FROM dbo.teklif_toplamlari WHERE TeklifId = :teklifId",
    };
    for (const QString &sql : temizlikSorgulari)
    {
        QSqlQuery temizlik(m_db);
        temizlik.prepare(sql);
        if (sql.contains(":teklifId"))
            temizlik.bindValue(":teklifId", teklifId);
        if (sql.contains(":manuelKod"))
            temizlik.bindValue(":manuelKod", QString("MANUEL-%1").arg(teklifId));
        if (!temizlik.exec())
        {
            qWarning() << "teklifDuzelt (eski icerik) basarisiz:" << temizlik.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Teklifin eski içeriği güncellenemedi: " + temizlik.lastError().text();
            return sonuc;
        }
    }

    QString icerikHatasi;
    if (!teklifIceriginiYaz(teklifId, teklif, icerikHatasi))
    {
        m_db.rollback();
        sonuc["hata"] = icerikHatasi;
        return sonuc;
    }

    if (!m_db.commit())
    {
        qWarning() << "teklifDuzelt commit basarisiz:" << m_db.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif düzeltilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["teklifNo"] = teklifNoGetir(teklifId);
    return sonuc;
}

QVariantMap Database::teklifDuzenlemeVerisiGetir(int teklifId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    QSqlQuery basQuery(m_db);
    basQuery.prepare(QString(
        "SELECT t.TeklifId, t.MusteriId, m.FirmaAdi, t.GenelIndirimOrani, t.KdvOrani, "
        "       t.ParaBirimi, t.Dil, t.IlgiliKisi, t.IlgiliKisiTelefonu, t.IlgiliKisiEposta, "
        "       t.TeslimatSekli, t.TeslimatYeri, t.SatisSozlesmesiMetni, "
        "       t.AnaTeklifId, t.RevizyonNo, %1 AS TeklifNo, "
        "       t.MusteriNotu, t.UretimNotu, t.TeslimatTarihi, t.Durum, "
        "       tt.PaketlemeUcreti, tt.TasimaUcreti "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "WHERE t.TeklifId = :teklifId").arg(teklifNoSql("t")));
    basQuery.bindValue(":teklifId", teklifId);

    if (!basQuery.exec() || !basQuery.next())
    {
        qWarning() << "teklifDuzenlemeVerisiGetir (baslik) basarisiz:" << basQuery.lastError().text();
        sonuc["hata"] = "Teklif bulunamadı.";
        return sonuc;
    }

    // NOT: kalemQuery'yi baslatmadan ONCE basQuery'nin TUM alanlarini yerel
    // degiskenlere okuyoruz -- ayni baglanti (m_db) uzerinde ikinci bir sorgu
    // calistirmak bazi ODBC surucillerinde ilk sorgunun sonuc kumesini
    // gecersiz kilabiliyor (bkz. teklifPdfOlustur'daki ayni desen).
    const int okunanTeklifId = basQuery.value("TeklifId").toInt();
    const int anaTeklifIdDeger = basQuery.value("AnaTeklifId").isNull()
        ? okunanTeklifId
        : basQuery.value("AnaTeklifId").toInt();
    const int revizyonNoDeger = basQuery.value("RevizyonNo").toInt();
    const int teklifNoDeger = basQuery.value("TeklifNo").toInt();
    const int musteriIdDeger = basQuery.value("MusteriId").toInt();
    const QString firmaAdiDeger = basQuery.value("FirmaAdi").toString();
    const double genelIndirimOraniDeger = basQuery.value("GenelIndirimOrani").toDouble();
    const double kdvOraniDeger = basQuery.value("KdvOrani").toDouble();
    const QString paraBirimi = basQuery.value("ParaBirimi").toString();
    const QString dilDeger = basQuery.value("Dil").toString();
    const QString ilgiliKisiDeger = basQuery.value("IlgiliKisi").toString();
    const QString ilgiliKisiTelefonuDeger = basQuery.value("IlgiliKisiTelefonu").toString();
    const QString ilgiliKisiEpostaDeger = basQuery.value("IlgiliKisiEposta").toString();
    const QString teslimatSekliDeger = basQuery.value("TeslimatSekli").toString();
    const QString teslimatYeriDeger = basQuery.value("TeslimatYeri").toString();
    const QString sozlesmeMetniDeger = basQuery.value("SatisSozlesmesiMetni").toString();
    const double paketlemeUcreti = basQuery.value("PaketlemeUcreti").toDouble();
    const double tasimaUcreti = basQuery.value("TasimaUcreti").toDouble();
    const QString musteriNotuDeger = basQuery.value("MusteriNotu").toString();
    const QString uretimNotuDeger = basQuery.value("UretimNotu").toString();
    const QVariant teslimatTarihiHam = basQuery.value("TeslimatTarihi");
    const QString teslimatTarihiDeger = teslimatTarihiHam.isNull()
        ? QString() : teslimatTarihiHam.toDateTime().date().toString("yyyy-MM-dd");
    const QString durumDeger = basQuery.value("Durum").toString();

    QSqlQuery kalemQuery(m_db);
    kalemQuery.prepare(
        "SELECT tk.TeklifKalemId, tk.UrunId, tk.Adet, tk.BirimFiyat, tk.MaliyetFiyati, tk.Kur, "
        "       tk.Tamamlandi, tk.UretimNotu, "
        "       u.UrunKodu, tk.UrunAciklamasi, "
        "       u.UrunAciklamasi AS KatalogAciklamaTr, u.UrunAciklamasiEn AS KatalogAciklamaEn "
        "FROM dbo.teklif_kalemleri tk "
        "LEFT JOIN dbo.urunler u ON u.UrunId = tk.UrunId "
        "WHERE tk.TeklifId = :teklifId "
        "ORDER BY tk.TeklifKalemId");
    kalemQuery.bindValue(":teklifId", teklifId);
    kalemQuery.exec();

    // Tum kalemler ayni teklifin Kur'unu paylasir (teklifKaydet hepsini ayni
    // anda, secili para birimi/kur ile kaydeder); ilk kalemden okuyup TL'ye geri
    // cevirmek icin kullaniyoruz. Kalem yoksa (teorik olarak olmamali, sepet
    // bos teklif kaydedilemiyor) 1 varsayilir.
    double kur = 1.0;
    bool kurBelirlendi = false;

    QVariantList kalemler;
    while (kalemQuery.next())
    {
        const double kalemKur = kalemQuery.value("Kur").toDouble();
        if (!kurBelirlendi && kalemKur > 0)
        {
            kur = kalemKur;
            kurBelirlendi = true;
        }

        // Manuel eklenen kalemler, teklifKaydet() tarafindan "MANUEL-<teklifId>"
        // kodlu, o teklife ozel gecici bir urunler satirina baglanir (bkz.
        // teklifKaydet). Duzenleme/revizyon icin bunlari tekrar manuel kalem
        // olarak (urunId=0) geri veriyoruz ki kaydedilince YENI teklife ozel
        // taze bir "MANUEL-<yeniTeklifId>" satiri olussun -- eski teklifin
        // gecici urun kaydina baglanip kalmasin.
        const QString urunKodu = kalemQuery.value("UrunKodu").toString();
        const bool manuelMi = urunKodu.startsWith("MANUEL-");

        const double birimFiyat = kalemQuery.value("BirimFiyat").toDouble();
        const double maliyetFiyati = kalemQuery.value("MaliyetFiyati").toDouble();

        QVariantMap kalem;
        kalem["urunId"] = manuelMi ? 0 : kalemQuery.value("UrunId").toInt();
        kalem["urunKodu"] = manuelMi ? QStringLiteral("MANUEL") : urunKodu;
        // Kayitli aciklama teklifin kaydedildigi dildedir; o dilde onu koruyoruz,
        // diger dil icin katalogdaki karsiligini (yoksa kayitli metni) veriyoruz --
        // boylece revizyonda dil degistirilince sepet aciklamalari da degisir.
        const QString kayitliAciklama = kalemQuery.value("UrunAciklamasi").toString();
        const QString katalogTr = kalemQuery.value("KatalogAciklamaTr").toString();
        const QString katalogEn = kalemQuery.value("KatalogAciklamaEn").toString();
        const bool kayitIngilizce = dilDeger.compare("EN", Qt::CaseInsensitive) == 0;
        kalem["aciklama"] = kayitliAciklama;
        kalem["aciklamaTr"] = (kayitIngilizce && !manuelMi && !katalogTr.trimmed().isEmpty())
            ? katalogTr : kayitliAciklama;
        kalem["aciklamaEn"] = kayitIngilizce
            ? kayitliAciklama
            : ((!manuelMi && !katalogEn.trimmed().isEmpty()) ? katalogEn : kayitliAciklama);
        kalem["adet"] = kalemQuery.value("Adet").toInt();
        kalem["birimFiyatTl"] = birimFiyat * kur;
        kalem["maliyet"] = maliyetFiyati * kur;
        // Satir bazli uretim takibi: kalemin kendi id'si (ekrandaki isaret
        // kutusu/not penceresi bununla YERINDE yazar, bkz.
        // teklifKalemTamamlandiGuncelle) ve mevcut degerleri.
        kalem["teklifKalemId"] = kalemQuery.value("TeklifKalemId").toInt();
        kalem["tamamlandi"] = kalemQuery.value("Tamamlandi").toBool();
        kalem["uretimNotu"] = kalemQuery.value("UretimNotu").toString();
        kalemler.append(kalem);
    }

    sonuc["basarili"] = true;
    sonuc["teklifId"] = okunanTeklifId;
    sonuc["anaTeklifId"] = anaTeklifIdDeger;
    sonuc["revizyonNo"] = revizyonNoDeger;
    sonuc["teklifNo"] = teklifNoBicimle(teklifNoDeger, revizyonNoDeger);
    sonuc["musteriId"] = musteriIdDeger;
    sonuc["musteriAdi"] = firmaAdiDeger;
    sonuc["genelIndirimOrani"] = genelIndirimOraniDeger;
    sonuc["kdvOrani"] = kdvOraniDeger;
    sonuc["paraBirimi"] = paraBirimi;
    sonuc["dil"] = dilDeger;
    sonuc["ilgiliKisi"] = ilgiliKisiDeger;
    sonuc["ilgiliKisiTelefonu"] = ilgiliKisiTelefonuDeger;
    sonuc["ilgiliKisiEposta"] = ilgiliKisiEpostaDeger;
    sonuc["teslimatSekli"] = teslimatSekliDeger;
    sonuc["teslimatYeri"] = teslimatYeriDeger;
    // Teklife ozel sozlesme metni yoksa bos doner -- QML tarafi "Satış Sözleşmesi"
    // penceresini acarken bos degeri gorup dilin varsayilan metnini yukler.
    sonuc["sozlesmeMetni"] = sozlesmeMetniDeger;
    sonuc["musteriNotu"] = musteriNotuDeger;
    sonuc["uretimNotu"] = uretimNotuDeger;
    sonuc["teslimatTarihi"] = teslimatTarihiDeger;
    sonuc["durum"] = durumDeger;
    sonuc["paketlemeUcretiTl"] = paketlemeUcreti * kur;
    sonuc["tasimaUcretiTl"] = tasimaUcreti * kur;
    sonuc["kur"] = kur;
    sonuc["kalemler"] = kalemler;
    return sonuc;
}

bool Database::teklifKilitliMi(const QString &durum)
{
    return durum == "Kabul Edildi" || durum == "Tamamlandı";
}

bool Database::kopyaKolonuVarMi()
{
    if (m_kopyaKolonuDurumu >= 0)
        return m_kopyaKolonuDurumu == 1;

    QSqlQuery query(m_db);
    query.prepare(
        "SELECT COUNT(*) FROM sys.columns "
        "WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'KopyaKaynakTeklifId'");
    if (!query.exec() || !query.next())
    {
        // Sorgu calismadiysa (ornegin baglanti o an koptu) onbellege YAZMIYORUZ:
        // bir sonraki cagrida tekrar denenir, yoksa kolon var olsa bile program
        // acik kaldigi surece "yok" sayilirdi.
        qWarning() << "kopyaKolonuVarMi sorgusu basarisiz:" << query.lastError().text();
        return false;
    }

    m_kopyaKolonuDurumu = query.value(0).toInt() > 0 ? 1 : 0;
    if (m_kopyaKolonuDurumu == 0)
        qWarning() << "dbo.teklifler.KopyaKaynakTeklifId sutunu yok; "
                      "kopyalanan tekliflerin kaynak izi tutulmayacak "
                      "(db/07_teklif_kopya_kaynagi.sql calistirilmali).";
    return m_kopyaKolonuDurumu == 1;
}

QString Database::teklifNoGetir(int teklifId)
{
    if (teklifId <= 0 || !baglantiHazir())
        return QString::number(teklifId);

    QSqlQuery query(m_db);
    query.prepare(QString("SELECT %1, t.RevizyonNo FROM dbo.teklifler t WHERE t.TeklifId = :id")
                      .arg(teklifNoSql("t")));
    query.bindValue(":id", teklifId);
    if (!query.exec() || !query.next())
    {
        // Kayit bulunamadi (ornegin silinmis): elde baska bilgi yok.
        return QString::number(teklifId);
    }
    return teklifNoBicimle(query.value(0).toInt(), query.value(1).toInt());
}

int Database::kokTeklifNoGetir(int kokTeklifId)
{
    QSqlQuery query(m_db);
    query.prepare(QString("SELECT %1 FROM dbo.teklifler t WHERE t.TeklifId = :id").arg(teklifNoSql("t")));
    query.bindValue(":id", kokTeklifId);
    if (!query.exec() || !query.next())
    {
        qWarning() << "kokTeklifNoGetir basarisiz:" << kokTeklifId << query.lastError().text();
        return 0;
    }
    return query.value(0).toInt();
}

int Database::yeniTeklifNoAl(QString &hataOut)
{
    // Acik transaction icinde cagrilir. Ayni anda iki bilgisayardan teklif
    // kaydedilirse ikisi ayni "en buyuk + 1"i okuyup ayni numarayi almasin diye
    // numara verme islemi transaction sonuna kadar kilitlenir: ikinci kayit,
    // birincisi bitene kadar bekler ve onun numarasini gorur.
    QSqlQuery kilit(m_db);
    kilit.prepare("EXEC sp_getapplock @Resource = N'LiyaErp_TeklifNo', @LockMode = 'Exclusive', "
                  "@LockOwner = 'Transaction', @LockTimeout = 15000");
    if (!kilit.exec())
    {
        qWarning() << "yeniTeklifNoAl (kilit) basarisiz:" << kilit.lastError().text();
        hataOut = QStringLiteral("Teklif numarası alınamadı: ") + kilit.lastError().text();
        return 0;
    }

    // teklifNoSql, TeklifNo'su bos (eski surum programla kaydedilmis) satirlarin
    // gosterilen numarasini da hesaba katar -- boylece yeni numara hicbir
    // gorunen numarayla cakismaz.
    QSqlQuery query(m_db);
    query.prepare(QString("SELECT ISNULL(MAX(%1), 0) + 1 FROM dbo.teklifler t").arg(teklifNoSql("t")));
    if (!query.exec() || !query.next())
    {
        qWarning() << "yeniTeklifNoAl basarisiz:" << query.lastError().text();
        hataOut = QStringLiteral("Teklif numarası alınamadı: ") + query.lastError().text();
        return 0;
    }
    return query.value(0).toInt();
}

bool Database::teklifNoKolonuVarMi() const
{
    if (m_teklifNoKolonuDurumu >= 0)
        return m_teklifNoKolonuDurumu == 1;

    QSqlQuery query(m_db);
    query.prepare(
        "SELECT COUNT(*) FROM sys.columns "
        "WHERE object_id = OBJECT_ID('dbo.teklifler') AND name = 'TeklifNo'");
    if (!query.exec() || !query.next())
    {
        // Onbellege yazilmaz, bir sonraki cagrida tekrar denenir (bkz. kopyaKolonuVarMi).
        qWarning() << "teklifNoKolonuVarMi sorgusu basarisiz:" << query.lastError().text();
        return false;
    }

    m_teklifNoKolonuDurumu = query.value(0).toInt() > 0 ? 1 : 0;
    if (m_teklifNoKolonuDurumu == 0)
        qWarning() << "dbo.teklifler.TeklifNo sutunu yok; teklif numaralari TeklifId'den "
                      "turetilecek (db/10_teklif_no.sql calistirilmali).";
    return m_teklifNoKolonuDurumu == 1;
}

QString Database::teklifNoSql(const QString &alias) const
{
    // Kolon yoksa eski kural: kok teklifin TeklifId'si. Kolon varsa TeklifNo;
    // bos ise (script sonrasi eski surum programla kaydedilmis satir) yine eski kural.
    const QString eskiKural = QString("ISNULL(%1.AnaTeklifId, %1.TeklifId)").arg(alias);
    return teklifNoKolonuVarMi()
        ? QString("ISNULL(%1.TeklifNo, %2)").arg(alias, eskiKural)
        : eskiKural;
}

int Database::teklifYerineGecenIdGetir(int teklifId)
{
    // Bu teklifin ait oldugu revizyon zincirinde DAHA YENI (RevizyonNo'su buyuk)
    // bir kayit varsa onun TeklifId'sini doner; yoksa 0.
    //
    // "Revize Edildi" durumu icin tek dogru kaynak budur: durum sutunu tek basina
    // yeterli degil, cunku yeni revizyon SILINMIS olabilir -- o zaman eski kayit
    // zincirin yeniden en son (yani gecerli) uyesi olur ve uzerinde tekrar islem
    // yapilabilmesi gerekir (bkz. teklifDurumGuncelle).
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT TOP 1 g.TeklifId "
        "FROM dbo.teklifler g "
        "INNER JOIN dbo.teklifler t ON t.TeklifId = :id "
        "WHERE (g.TeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
        "       OR g.AnaTeklifId = ISNULL(t.AnaTeklifId, t.TeklifId)) "
        "  AND g.RevizyonNo > t.RevizyonNo "
        "ORDER BY g.RevizyonNo DESC");
    query.bindValue(":id", teklifId);
    if (!query.exec())
    {
        qWarning() << "teklifYerineGecenIdGetir basarisiz:" << teklifId << query.lastError().text();
        return 0;
    }
    return query.next() ? query.value(0).toInt() : 0;
}

QString Database::teklifDurumuGetir(int teklifId)
{
    QSqlQuery query(m_db);
    query.prepare("SELECT Durum FROM dbo.teklifler WHERE TeklifId = :id");
    query.bindValue(":id", teklifId);
    if (query.exec() && query.next())
        return query.value(0).toString();
    qWarning() << "teklifDurumuGetir basarisiz:" << teklifId << query.lastError().text();
    return QString();
}

bool Database::teklifTeslimatTarihiGuncelle(int teklifId, const QString &teslimatTarihi)
{
    if (teklifId <= 0 || !baglantiHazir())
        return false;

    // Uretim planlamasi bilgisi: kabul edilmis teklifte de degisebilir, ama
    // tamamlanmis (teslim edilmis) teklifte artik degistirilemez.
    if (teklifDurumuGetir(teklifId) == "Tamamlandı")
    {
        qWarning() << "teklifTeslimatTarihiGuncelle: tamamlanmis teklif degistirilemez:" << teklifId;
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklifler SET TeslimatTarihi = :tarih WHERE TeklifId = :id");
    query.bindValue(":tarih", tarihParametresi(teslimatTarihi));
    query.bindValue(":id", teklifId);

    if (!query.exec())
    {
        qWarning() << "teklifTeslimatTarihiGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

bool Database::teklifMusteriNotuGuncelle(int teklifId, const QString &musteriNotu)
{
    if (teklifId <= 0 || !baglantiHazir())
        return false;

    // Teklif notu teklifin parcasidir: kabul edilmis teklifte degistirilemez.
    if (teklifKilitliMi(teklifDurumuGetir(teklifId)))
    {
        qWarning() << "teklifMusteriNotuGuncelle: kilitli teklif degistirilemez:" << teklifId;
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklifler SET MusteriNotu = :not WHERE TeklifId = :id");
    const QString temiz = musteriNotu.trimmed();
    query.bindValue(":not", temiz.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : QVariant(temiz));
    query.bindValue(":id", teklifId);

    if (!query.exec())
    {
        qWarning() << "teklifMusteriNotuGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

bool Database::teklifUretimNotuGuncelle(int teklifId, const QString &uretimNotu)
{
    if (teklifId <= 0 || !baglantiHazir())
        return false;

    // Planlanan teslim tarihi gibi: kabul edilmis teklifte yazilabilir,
    // tamamlanmis teklifte degistirilemez.
    if (teklifDurumuGetir(teklifId) == "Tamamlandı")
    {
        qWarning() << "teklifUretimNotuGuncelle: tamamlanmis teklif degistirilemez:" << teklifId;
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklifler SET UretimNotu = :not WHERE TeklifId = :id");
    const QString temiz = uretimNotu.trimmed();
    query.bindValue(":not", temiz.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : QVariant(temiz));
    query.bindValue(":id", teklifId);

    if (!query.exec())
    {
        qWarning() << "teklifUretimNotuGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

bool Database::teklifKalemiUretimeAcikMi(int teklifKalemId)
{
    // Kalemin durumu bagli oldugu TEKLIFIN durumudur; kalemin kendi durumu yok.
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT t.Durum FROM dbo.teklif_kalemleri tk "
        "INNER JOIN dbo.teklifler t ON t.TeklifId = tk.TeklifId "
        "WHERE tk.TeklifKalemId = :id");
    query.bindValue(":id", teklifKalemId);

    if (!query.exec() || !query.next())
    {
        qWarning() << "teklifKalemiUretimeAcikMi: kalem bulunamadi:" << teklifKalemId
                   << query.lastError().text();
        return false;
    }

    // Planlanan teslim tarihi / genel uretim notuyla ayni kural: kabul edilmis
    // teklifte yazilabilir, tamamlanmis teklifte kilitlidir.
    if (query.value(0).toString() == "Tamamlandı")
    {
        qWarning() << "teklif kalemi uretim bilgisi degistirilemez (teklif tamamlandi):" << teklifKalemId;
        return false;
    }
    return true;
}

bool Database::teklifKalemTamamlandiGuncelle(int teklifKalemId, bool tamamlandi)
{
    if (teklifKalemId <= 0 || !baglantiHazir())
        return false;

    if (!teklifKalemiUretimeAcikMi(teklifKalemId))
        return false;

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklif_kalemleri SET Tamamlandi = :tamamlandi WHERE TeklifKalemId = :id");
    query.bindValue(":tamamlandi", tamamlandi ? 1 : 0);
    query.bindValue(":id", teklifKalemId);

    if (!query.exec())
    {
        qWarning() << "teklifKalemTamamlandiGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

bool Database::teklifKalemUretimNotuGuncelle(int teklifKalemId, const QString &uretimNotu)
{
    if (teklifKalemId <= 0 || !baglantiHazir())
        return false;

    if (!teklifKalemiUretimeAcikMi(teklifKalemId))
        return false;

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklif_kalemleri SET UretimNotu = :not WHERE TeklifKalemId = :id");
    const QString temiz = uretimNotu.trimmed();
    query.bindValue(":not", temiz.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : QVariant(temiz));
    query.bindValue(":id", teklifKalemId);

    if (!query.exec())
    {
        qWarning() << "teklifKalemUretimNotuGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

QStringList Database::gecerliDurumlar() const
{
    // Sira, QML'deki durum menusunde gorunecek siradir: is akisinin dogal sirasi.
    return { "Beklemede", "Kabul Edildi", "Reddedildi", "Tamamlandı" };
}

bool Database::teklifDurumGuncelle(int teklifId, const QString &durum, const QString &redSebebi, int kullaniciId)
{
    if (!baglantiHazir())
        return false;

    // QML, false donusunde sebebi sonHataMesaji()'ndan okuyor; onceki bir islemden
    // kalan mesaji yanlislikla bu cagriya ait sanmasin diye basta temizliyoruz.
    m_sonHataMesaji.clear();

    // "Revize Edildi" menude yer almaz (kullanici elle secmez) ama gecerli bir
    // durumdur: sistem revizyon kaydederken yazar.
    if (!gecerliDurumlar().contains(durum) && durum != DURUM_REVIZE_EDILDI)
    {
        qWarning() << "teklifDurumGuncelle: gecersiz durum:" << durum;
        return false;
    }

    // Gecmis logu icin degisimden ONCEKI durumu okuyoruz. Ayrica durum zaten
    // istenen degerdeyse gereksiz bir UPDATE + anlamsiz bir log satiri uretmeyelim.
    QString eskiDurum;
    {
        QSqlQuery mevcutQuery(m_db);
        mevcutQuery.prepare("SELECT Durum FROM dbo.teklifler WHERE TeklifId = :teklifId");
        mevcutQuery.bindValue(":teklifId", teklifId);
        if (!mevcutQuery.exec() || !mevcutQuery.next())
        {
            qWarning() << "teklifDurumGuncelle: teklif bulunamadi:" << teklifId
                       << mevcutQuery.lastError().text();
            return false;
        }
        eskiDurum = mevcutQuery.value(0).toString();
    }

    if (eskiDurum == durum)
        return true;

    // --- GECERSIZ KILINMIS REVIZYON UZERINDE ISLEM YAPILAMAZ -----------------
    // Revize edilmis bir teklif artik musteriye verilmis GECERLI teklif degildir;
    // yerine zincirin yeni bir uyesi gecmistir. Bu satirin durumu elle
    // degistirilebilse, teklifin ESKI surumu "Kabul Edildi" olurken YENI surumu
    // "Beklemede" kalabilir ve ayni teklifin iki farkli fiyatli surumu ayni anda
    // "yururlukte" gorunur -- kabul edilen tutarin hangisi oldugu belirsizlesir.
    // "Beklemede"ye cevirmek de ayni kapiyi acar (oradan Kabul Edildi bir adim),
    // bu yuzden geri dondurme dahil TUM elle gecisler engellenir.
    //
    // Kural zincirin GERCEK durumuna bakar, durum sutununa degil: yeni revizyon
    // silinmisse bu kayit tekrar zincirin sonudur ve normal sekilde islenebilir.
    if (eskiDurum == DURUM_REVIZE_EDILDI)
    {
        const int yerineGecen = teklifYerineGecenIdGetir(teklifId);
        if (yerineGecen > 0)
        {
            qWarning() << "teklifDurumGuncelle: revize edilmis teklifin durumu degistirilemez:"
                       << teklifId << "-> yerine gecen:" << yerineGecen;
            m_sonHataMesaji = QString::fromUtf8(
                                  "Teklif %1 revize edildi, durumu değiştirilemez. Güncel teklif: %2")
                                  .arg(teklifNoGetir(teklifId), teklifNoGetir(yerineGecen));
            return false;
        }
    }

    // Durum ileri geri degisebildigi icin, HER gecis tum durum alanlarini yeniden
    // yazar: yeni duruma ait tarih doldurulur, artik gecerli olmayanlar NULL'lanir.
    // Boylece "Reddedildi -> Beklemede" sonrasi ortada eski bir RedTarihi/RedSebebi,
    // "Tamamlandı -> Kabul Edildi" sonrasi eski bir TeslimTarihi kalmaz.
    //
    // KabulTarihi'nin "Tamamlandı"da korunmasinin sebebi: tamamlanmis bir teklif
    // tanim geregi once kabul edilmistir; o tarih raporlamada anlamlidir. Zaten
    // dolu degilse (dogrudan Beklemede -> Tamamlandı gibi bir gecis) simdiki zamanla doldurulur.
    // Ayni sebeple "Tamamlandı -> Kabul Edildi" geri alisinda da musterinin ASIL
    // kabul tarihi korunur (ISNULL); diger durumlardan gelindiginde (goc verisinde
    // eski bir deger kalmis olabilir) her zaman simdiki zaman yazilir.
    //
    // UretimPdfTarihi hicbir gecişte silinmez: uretim PDF'inin teknik ekibe
    // verilmis olmasi, durum sonradan degisse de gecmiste yasanmis bir olaydir.
    QString sql = "UPDATE dbo.teklifler SET Durum = :durum";
    // "Revize Edildi" de "Beklemede" gibi davranir: revize edilmis teklif ne kabul
    // edilmis ne reddedilmistir, dolayisiyla tum durum tarihleri temizlenir.
    if (durum == "Beklemede" || durum == DURUM_REVIZE_EDILDI)
        sql += ", KabulTarihi = NULL, RedTarihi = NULL, RedSebebi = NULL, TeslimTarihi = NULL";
    else if (durum == "Kabul Edildi")
        sql += QString(", KabulTarihi = %1, RedTarihi = NULL, RedSebebi = NULL, TeslimTarihi = NULL")
                   .arg(eskiDurum == "Tamamlandı" ? "ISNULL(KabulTarihi, SYSDATETIME())" : "SYSDATETIME()");
    else if (durum == "Reddedildi")
        sql += ", KabulTarihi = NULL, RedTarihi = SYSDATETIME(), RedSebebi = :redSebebi, TeslimTarihi = NULL";
    else if (durum == "Tamamlandı")
        sql += ", KabulTarihi = ISNULL(KabulTarihi, SYSDATETIME()), RedTarihi = NULL, RedSebebi = NULL,"
               " TeslimTarihi = SYSDATETIME()";
    sql += " WHERE TeklifId = :teklifId";

    QSqlQuery query(m_db);
    query.prepare(sql);
    query.bindValue(":durum", durum);
    query.bindValue(":teklifId", teklifId);
    if (durum == "Reddedildi")
        query.bindValue(":redSebebi", redSebebi.trimmed().isEmpty() ? QVariant(QMetaType(QMetaType::QString))
                                                                    : redSebebi.trimmed());

    if (!query.exec())
    {
        qWarning() << "teklifDurumGuncelle basarisiz:" << query.lastError().text();
        return false;
    }

    // WPF'teki "Tamamla" ile ayni: teklif tamamlaninca tum kalemlerin uretimi de
    // tamamlanmis sayilir (uretim PDF'inde ✓ gorunsun).
    if (durum == "Tamamlandı")
    {
        QSqlQuery kalemler(m_db);
        kalemler.prepare("UPDATE dbo.teklif_kalemleri SET Tamamlandi = 1 WHERE TeklifId = :teklifId");
        kalemler.bindValue(":teklifId", teklifId);
        if (!kalemler.exec())
            qWarning() << "Kalemler tamamlandi olarak isaretlenemedi:" << kalemler.lastError().text();
    }

    durumDegisiminiLogla(teklifId, eskiDurum, durum, redSebebi, kullaniciId);
    return true;
}

void Database::durumDegisiminiLogla(int teklifId, const QString &eskiDurum, const QString &yeniDurum,
                                    const QString &aciklama, int kullaniciId)
{
    // "Best effort": 05_teklif_durum_gecmisi.sql henuz calistirilmadiysa tablo yoktur.
    // Bu durumda durum degisiminin kendisini basarisiz saymak yanlis olur -- sadece
    // uyari basip geciyoruz (log tutulmaz, uygulama calismaya devam eder).
    QSqlQuery logQuery(m_db);
    logQuery.prepare(
        "INSERT INTO dbo.teklif_durum_gecmisi (TeklifId, EskiDurum, YeniDurum, Aciklama, KullaniciId) "
        "VALUES (:teklifId, :eskiDurum, :yeniDurum, :aciklama, :kullaniciId)");
    logQuery.bindValue(":teklifId", teklifId);
    logQuery.bindValue(":eskiDurum", eskiDurum.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : eskiDurum);
    logQuery.bindValue(":yeniDurum", yeniDurum);
    logQuery.bindValue(":aciklama", aciklama.trimmed().isEmpty() ? QVariant(QMetaType(QMetaType::QString))
                                                                 : aciklama.trimmed());
    logQuery.bindValue(":kullaniciId", kullaniciId > 0 ? QVariant(kullaniciId) : QVariant(QMetaType(QMetaType::Int)));

    if (!logQuery.exec())
        qWarning() << "Durum gecmisi yazilamadi (db/05_teklif_durum_gecmisi.sql calistirildi mi?):"
                   << logQuery.lastError().text();
}

QVariantList Database::teklifDurumGecmisiGetir(int teklifId)
{
    QVariantList gecmis;
    if (!baglantiHazir() || teklifId <= 0)
        return gecmis;

    // --- Zincir: kok teklif + tum revizyonlari --------------------------------
    // Gecmis tek bir kayda degil revizyon zincirine aittir; hangi surumden
    // acilirsa acilsin ayni akis gorunur.
    int kokId = teklifId;
    {
        QSqlQuery kokQuery(m_db);
        kokQuery.prepare("SELECT ISNULL(AnaTeklifId, TeklifId) FROM dbo.teklifler WHERE TeklifId = :id");
        kokQuery.bindValue(":id", teklifId);
        if (kokQuery.exec() && kokQuery.next())
            kokId = kokQuery.value(0).toInt();
    }
    const QString zincirSql = QStringLiteral(
        "(SELECT z.TeklifId FROM dbo.teklifler z WHERE z.TeklifId = :kok OR z.AnaTeklifId = :kok)");

    struct Uye
    {
        int id = 0;
        QString no;
        int revizyonNo = 0;
        QDateTime olusturma;
        QVariant olusturmaHam;
        QString personel;
        QString sebep;           // revizyon sebebi (durum gecmisindeki olusturma satirindan)
        QStringList gecersizKilinanlar; // bu revizyon yuzunden "Revize Edildi" olanlar
    };
    QList<Uye> uyeler; // olusturma sirasina gore
    {
        QSqlQuery uyeQuery(m_db);
        uyeQuery.prepare(QString(
            "SELECT t.TeklifId, %1 AS No, t.RevizyonNo, t.OlusturmaTarihi, k.KullaniciAdi "
            "FROM dbo.teklifler t LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = t.KullaniciId "
            "WHERE t.TeklifId IN %2 ORDER BY t.OlusturmaTarihi, t.TeklifId")
            .arg(teklifNoSql("t"), zincirSql));
        uyeQuery.bindValue(":kok", kokId);
        if (!uyeQuery.exec())
            qWarning() << "teklifDurumGecmisiGetir (zincir) basarisiz:" << uyeQuery.lastError().text();
        while (uyeQuery.next())
        {
            Uye u;
            u.id = uyeQuery.value("TeklifId").toInt();
            u.revizyonNo = uyeQuery.value("RevizyonNo").toInt();
            u.no = teklifNoBicimle(uyeQuery.value("No").toInt(), u.revizyonNo);
            u.olusturmaHam = uyeQuery.value("OlusturmaTarihi");
            u.olusturma = u.olusturmaHam.toDateTime();
            u.personel = uyeQuery.value("KullaniciAdi").toString();
            uyeler << u;
        }
    }
    auto uyeBul = [&uyeler](int id) -> Uye * {
        for (Uye &u : uyeler)
            if (u.id == id)
                return &u;
        return nullptr;
    };
    // Revizyon sebebi aciklamanin "Sebep: " sonrasidir (bkz. teklifKaydet).
    auto sebepAyikla = [](const QString &aciklama) {
        const int i = aciklama.indexOf(QStringLiteral("Sebep: "));
        return i < 0 ? QString() : aciklama.mid(i + 7).trimmed();
    };

    auto satirOlustur = [](const QString &tur, const Uye *u, const QString &baslik,
                           const QString &aciklama, const QVariant &tarih, const QString &personel) {
        QVariantMap satir;
        satir["tur"] = tur;
        satir["teklifId"] = u ? u->id : 0;
        satir["teklifNo"] = u ? u->no : QString();
        satir["baslik"] = baslik;
        satir["aciklama"] = aciklama;
        satir["tarih"] = tarihSaatStr(tarih);
        satir["personel"] = personel;
        return satir;
    };

    // Durum ve duzeltme satirlari tek zaman cizelgesinde birlestirilip ham
    // tarihe gore siralanir ("dd.MM.yyyy HH:mm" metni siralamaya uygun degil).
    QList<std::pair<QDateTime, QVariantMap>> satirlar;

    // --- Durum gecmisi ---------------------------------------------------------
    QSqlQuery query(m_db);
    query.prepare(QString(
        "SELECT g.TeklifId, g.EskiDurum, g.YeniDurum, g.Aciklama, g.DegisiklikTarihi, k.KullaniciAdi "
        "FROM dbo.teklif_durum_gecmisi g "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = g.KullaniciId "
        "WHERE g.TeklifId IN %1 "
        "ORDER BY g.DegisiklikTarihi, g.DurumGecmisiId").arg(zincirSql));
    query.bindValue(":kok", kokId);

    // Tablo yoksa sorgu hata verir; kullaniciya eksik gecmis gostermek
    // uygulamayi kirmaktan iyidir (bkz. durumDegisiminiLogla notu).
    if (!query.exec())
        qWarning() << "teklifDurumGecmisiGetir basarisiz:" << query.lastError().text();

    while (query.next())
    {
        Uye *u = uyeBul(query.value("TeklifId").toInt());
        const QString eskiDurum = query.value("EskiDurum").toString();
        const QString yeniDurum = query.value("YeniDurum").toString();
        const QString aciklama = query.value("Aciklama").toString();
        const QDateTime tarih = query.value("DegisiklikTarihi").toDateTime();

        // Olusturma satiri (eski durum yok): ayri satir olmaz, sebebi asagidaki
        // "Revizyon oluşturuldu" satirina tasinir.
        if (eskiDurum.isEmpty() && u)
        {
            if (u->sebep.isEmpty())
                u->sebep = sebepAyikla(aciklama);
            continue;
        }

        // "Revize Edildi" elle secilmez, yalnizca yeni revizyonla olur: ayri satir
        // yerine o revizyonun satirinda "Teklif X → Revize Edildi" olarak gosterilir.
        // Sebep olan revizyon = bu andan once olusturulmus en son uye.
        if (yeniDurum == DURUM_REVIZE_EDILDI && u)
        {
            Uye *neden = nullptr;
            for (Uye &aday : uyeler)
                if (aday.id != u->id && aday.revizyonNo > 0 && aday.olusturma <= tarih)
                    neden = &aday;
            if (neden)
            {
                neden->gecersizKilinanlar << u->no;
                if (neden->sebep.isEmpty())
                    neden->sebep = sebepAyikla(aciklama);
                continue;
            }
        }

        satirlar.append({tarih, satirOlustur(QStringLiteral("durum"), u,
                                             (eskiDurum.isEmpty() ? QStringLiteral("—") : eskiDurum)
                                                 + QStringLiteral("  →  ") + yeniDurum,
                                             aciklama, query.value("DegisiklikTarihi"),
                                             query.value("KullaniciAdi").toString())});
    }

    // --- Duzeltmeler -----------------------------------------------------------
    QSqlQuery duzeltmeQuery(m_db);
    duzeltmeQuery.prepare(QString(
        "SELECT d.TeklifId, d.Sebep, d.DuzeltmeTarihi, k.KullaniciAdi "
        "FROM dbo.teklif_duzeltme_gecmisi d "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = d.KullaniciId "
        "WHERE d.TeklifId IN %1").arg(zincirSql));
    duzeltmeQuery.bindValue(":kok", kokId);
    if (duzeltmeQuery.exec())
    {
        while (duzeltmeQuery.next())
        {
            satirlar.append({duzeltmeQuery.value("DuzeltmeTarihi").toDateTime(),
                             satirOlustur(QStringLiteral("duzeltme"),
                                          uyeBul(duzeltmeQuery.value("TeklifId").toInt()),
                                          QStringLiteral("Düzeltildi (aynı teklif numarasıyla)"),
                                          duzeltmeQuery.value("Sebep").toString(),
                                          duzeltmeQuery.value("DuzeltmeTarihi"),
                                          duzeltmeQuery.value("KullaniciAdi").toString())});
        }
    }
    else
    {
        // 09 numarali script calistirilmamissa tablo yoktur; durum gecmisi yine gosterilir.
        qWarning() << "teklifDurumGecmisiGetir (duzeltmeler) basarisiz:" << duzeltmeQuery.lastError().text();
    }

    // --- Olusturma / revizyon satirlari --------------------------------------
    // Listenin basina eklenir: ayni zaman damgasinda stable_sort sayesinde
    // ayni surumun diger olaylarindan once gelir.
    QList<std::pair<QDateTime, QVariantMap>> olusturmalar;
    for (const Uye &u : std::as_const(uyeler))
    {
        const bool revizyon = u.revizyonNo > 0;
        QString baslik = revizyon ? QStringLiteral("Revizyon oluşturuldu") : QStringLiteral("Teklif oluşturuldu");
        if (!u.gecersizKilinanlar.isEmpty())
            baslik += QStringLiteral("  ·  Teklif ") + u.gecersizKilinanlar.join(QStringLiteral(", "))
                      + QStringLiteral(" → Revize Edildi");
        olusturmalar.append({u.olusturma, satirOlustur(revizyon ? QStringLiteral("revizyon") : QStringLiteral("olusturma"),
                                                      &u, baslik,
                                                      u.sebep.isEmpty() ? QString() : QStringLiteral("Sebep: ") + u.sebep,
                                                      u.olusturmaHam, u.personel)});
    }
    satirlar = olusturmalar + satirlar;

    // Eskiden yeniye: olaylarin akisi yukaridan asagi okunur.
    std::stable_sort(satirlar.begin(), satirlar.end(),
                     [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &satir : std::as_const(satirlar))
        gecmis << satir.second;
    return gecmis;
}

QVariantMap Database::musteriListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!baglantiHazir())
        return sonuc;

    const QString aramaTrim = arama.trimmed();
    QString whereClause;
    if (!aramaTrim.isEmpty())
        whereClause = "WHERE FirmaAdi LIKE :aramaLike OR IlgiliKisi LIKE :aramaLike OR FirmaEposta LIKE :aramaLike";

    QSqlQuery sayimQuery(m_db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.musteriler %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");

    if (!sayimQuery.exec())
    {
        qWarning() << "musteriListesiGetir (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    const int toplamSayfa = std::max(1, static_cast<int>(std::ceil(toplamKayit / static_cast<double>(sayfaBoyutu))));
    sayfaNo = std::clamp(sayfaNo, 1, toplamSayfa);

    QSqlQuery veriQuery(m_db);
    veriQuery.prepare(QString(
        "SELECT MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
        "       VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu "
        "FROM dbo.musteriler %1 "
        "ORDER BY FirmaAdi "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "musteriListesiGetir (veri) basarisiz:" << veriQuery.lastError().text();
        return sonuc;
    }

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        QVariantMap m;
        m["musteriId"] = veriQuery.value("MusteriId").toInt();
        m["firmaAdi"] = veriQuery.value("FirmaAdi").toString();
        m["firmaAdresi"] = veriQuery.value("FirmaAdresi").toString();
        m["firmaTelefonu"] = veriQuery.value("FirmaTelefonu").toString();
        m["firmaEposta"] = veriQuery.value("FirmaEposta").toString();
        m["vergiDairesi"] = veriQuery.value("VergiDairesi").toString();
        m["vergiNumarasi"] = veriQuery.value("VergiNumarasi").toString();
        m["ilgiliKisi"] = veriQuery.value("IlgiliKisi").toString();
        m["ilgiliKisiTelefonu"] = veriQuery.value("IlgiliKisiTelefonu").toString();
        kayitlar << m;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantMap Database::musteriEkle(const QVariantMap &musteri)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["musteriId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString firmaAdi = musteri.value("firmaAdi").toString().trimmed();
    if (firmaAdi.isEmpty())
    {
        sonuc["hata"] = "Firma adı boş olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "INSERT INTO dbo.musteriler "
        "(FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu) "
        "OUTPUT INSERTED.MusteriId "
        "VALUES (:firmaAdi, :firmaAdresi, :firmaTelefonu, :firmaEposta, :vergiDairesi, :vergiNumarasi, :ilgiliKisi, :ilgiliKisiTel)");
    query.bindValue(":firmaAdi", firmaAdi);
    query.bindValue(":firmaAdresi", musteri.value("firmaAdresi").toString());
    query.bindValue(":firmaTelefonu", musteri.value("firmaTelefonu").toString());
    query.bindValue(":firmaEposta", musteri.value("firmaEposta").toString());
    query.bindValue(":vergiDairesi", musteri.value("vergiDairesi").toString());
    query.bindValue(":vergiNumarasi", musteri.value("vergiNumarasi").toString());
    query.bindValue(":ilgiliKisi", musteri.value("ilgiliKisi").toString());
    query.bindValue(":ilgiliKisiTel", musteri.value("ilgiliKisiTelefonu").toString());

    if (!query.exec() || !query.next())
    {
        qWarning() << "musteriEkle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Müşteri kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["musteriId"] = query.value(0).toInt();
    return sonuc;
}

QVariantMap Database::musteriGuncelle(int musteriId, const QVariantMap &musteri)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString firmaAdi = musteri.value("firmaAdi").toString().trimmed();
    if (firmaAdi.isEmpty())
    {
        sonuc["hata"] = "Firma adı boş olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.musteriler SET "
        "FirmaAdi = :firmaAdi, FirmaAdresi = :firmaAdresi, FirmaTelefonu = :firmaTelefonu, "
        "FirmaEposta = :firmaEposta, VergiDairesi = :vergiDairesi, VergiNumarasi = :vergiNumarasi, "
        "IlgiliKisi = :ilgiliKisi, IlgiliKisiTelefonu = :ilgiliKisiTel "
        "WHERE MusteriId = :musteriId");
    query.bindValue(":firmaAdi", firmaAdi);
    query.bindValue(":firmaAdresi", musteri.value("firmaAdresi").toString());
    query.bindValue(":firmaTelefonu", musteri.value("firmaTelefonu").toString());
    query.bindValue(":firmaEposta", musteri.value("firmaEposta").toString());
    query.bindValue(":vergiDairesi", musteri.value("vergiDairesi").toString());
    query.bindValue(":vergiNumarasi", musteri.value("vergiNumarasi").toString());
    query.bindValue(":ilgiliKisi", musteri.value("ilgiliKisi").toString());
    query.bindValue(":ilgiliKisiTel", musteri.value("ilgiliKisiTelefonu").toString());
    query.bindValue(":musteriId", musteriId);

    if (!query.exec())
    {
        qWarning() << "musteriGuncelle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Müşteri güncellenemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::musteriSil(int musteriId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.musteriler WHERE MusteriId = :musteriId");
    query.bindValue(":musteriId", musteriId);

    if (!query.exec())
    {
        // Muhtemel sebep: bu musteriye ait teklif(ler) var (FK kisitlamasi --
        // teklifler.MusteriId icin ON DELETE CASCADE tanimli degil, bilerek:
        // bir musteri yanlislikla silinince tekliflerin de silinmesini istemeyiz).
        qWarning() << "Musteri silinemedi:" << query.lastError().text();
        sonuc["hata"] = "Müşteri silinemedi: bu müşteriye ait teklifler var.";
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::urunListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!baglantiHazir())
        return sonuc;

    const QString aramaTrim = arama.trimmed();
    // "MANUEL-<teklifId>" kodlu satirlar tekliflere ozel gecici kayitlardir,
    // urun kataloğu listesinde gorunmemeli (bkz. urunAra ustundeki not).
    QString whereClause = "WHERE UrunKodu NOT LIKE N'MANUEL%'";
    if (!aramaTrim.isEmpty())
        whereClause += " AND (UrunKodu LIKE :aramaLike OR UrunAciklamasi LIKE :aramaLike OR Kategori LIKE :aramaLike)";

    QSqlQuery sayimQuery(m_db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.urunler %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");

    if (!sayimQuery.exec())
    {
        qWarning() << "urunListesiGetir (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    const int toplamSayfa = std::max(1, static_cast<int>(std::ceil(toplamKayit / static_cast<double>(sayfaBoyutu))));
    sayfaNo = std::clamp(sayfaNo, 1, toplamSayfa);

    QSqlQuery veriQuery(m_db);
    veriQuery.prepare(QString(
        "SELECT UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, GuncelMaliyetTL "
        "FROM dbo.urunler %1 "
        "ORDER BY UrunKodu "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "urunListesiGetir (veri) basarisiz:" << veriQuery.lastError().text();
        return sonuc;
    }

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        QVariantMap u;
        u["urunId"] = veriQuery.value("UrunId").toInt();
        u["urunKodu"] = veriQuery.value("UrunKodu").toString();
        u["kategori"] = veriQuery.value("Kategori").toString();
        u["urunAciklamasi"] = veriQuery.value("UrunAciklamasi").toString();
        u["urunAciklamasiEn"] = veriQuery.value("UrunAciklamasiEn").toString();
        u["birimFiyat"] = veriQuery.value("BirimFiyat").isNull() ? 0.0 : veriQuery.value("BirimFiyat").toDouble();
        u["maliyet"] = veriQuery.value("GuncelMaliyetTL").isNull() ? 0.0 : veriQuery.value("GuncelMaliyetTL").toDouble();
        kayitlar << u;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantMap Database::urunEkle(const QVariantMap &urun)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["urunId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString aciklama = urun.value("urunAciklamasi").toString().trimmed();
    if (aciklama.isEmpty())
    {
        sonuc["hata"] = "Ürün açıklaması boş olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "INSERT INTO dbo.urunler "
        "(UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, ParaBirimi, GuncelMaliyetTL) "
        "OUTPUT INSERTED.UrunId "
        "VALUES (:urunKodu, :kategori, :aciklama, :aciklamaEn, :birimFiyat, N'TL', :maliyet)");
    query.bindValue(":urunKodu", urun.value("urunKodu").toString());
    query.bindValue(":kategori", urun.value("kategori").toString());
    query.bindValue(":aciklama", aciklama);
    query.bindValue(":aciklamaEn", urun.value("urunAciklamasiEn").toString());
    query.bindValue(":birimFiyat", urun.value("birimFiyat", 0).toDouble());
    query.bindValue(":maliyet", urun.value("maliyet", 0).toDouble());

    if (!query.exec() || !query.next())
    {
        qWarning() << "urunEkle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Ürün kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["urunId"] = query.value(0).toInt();
    return sonuc;
}

QVariantMap Database::urunGuncelle(int urunId, const QVariantMap &urun)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString aciklama = urun.value("urunAciklamasi").toString().trimmed();
    if (aciklama.isEmpty())
    {
        sonuc["hata"] = "Ürün açıklaması boş olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.urunler SET "
        "UrunKodu = :urunKodu, Kategori = :kategori, UrunAciklamasi = :aciklama, "
        "UrunAciklamasiEn = :aciklamaEn, BirimFiyat = :birimFiyat, GuncelMaliyetTL = :maliyet "
        "WHERE UrunId = :urunId");
    query.bindValue(":urunKodu", urun.value("urunKodu").toString());
    query.bindValue(":kategori", urun.value("kategori").toString());
    query.bindValue(":aciklama", aciklama);
    query.bindValue(":aciklamaEn", urun.value("urunAciklamasiEn").toString());
    query.bindValue(":birimFiyat", urun.value("birimFiyat", 0).toDouble());
    query.bindValue(":maliyet", urun.value("maliyet", 0).toDouble());
    query.bindValue(":urunId", urunId);

    if (!query.exec())
    {
        qWarning() << "urunGuncelle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Ürün güncellenemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::urunSil(int urunId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.urunler WHERE UrunId = :urunId");
    query.bindValue(":urunId", urunId);

    if (!query.exec())
    {
        // Muhtemel sebep: bu urune ait teklif_kalemleri var (FK kisitlamasi).
        qWarning() << "Urun silinemedi:" << query.lastError().text();
        sonuc["hata"] = "Ürün silinemedi: bu ürünü içeren teklifler var.";
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

bool Database::urunMaliyetiGuncelle(int urunId, double maliyetTl)
{
    m_sonHataMesaji.clear();

    // Manuel kalemlerin katalogda karsiligi yoktur (urunId = 0) -- sessizce gec.
    if (urunId <= 0)
        return false;

    if (!baglantiHazir())
    {
        m_sonHataMesaji = "Veritabanına bağlanılamadı.";
        return false;
    }

    // UrunKodu NULL olabilir; NULL NOT LIKE ... NULL dondugu icin acikca
    // "IS NULL" ile birlikte yaziliyor, aksi halde kodu girilmemis normal bir
    // urunun maliyeti hic guncellenmezdi.
    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.urunler SET GuncelMaliyetTL = :maliyet "
        "WHERE UrunId = :urunId AND (UrunKodu IS NULL OR UrunKodu NOT LIKE N'MANUEL%')");
    query.bindValue(":maliyet", maliyetTl);
    query.bindValue(":urunId", urunId);

    if (!query.exec())
    {
        qWarning() << "urunMaliyetiGuncelle basarisiz:" << query.lastError().text();
        m_sonHataMesaji = "Ürün maliyeti güncellenemedi: " + query.lastError().text();
        return false;
    }

    // Eslesen satir yoksa (urun silinmis veya "MANUEL-..." gecici satir) hata
    // mesaji birakilmaz: cagiran taraf bunu sessizce yok sayar.
    return query.numRowsAffected() > 0;
}

QVariantList Database::rolListesiGetir()
{
    QVariantList sonuc;
    if (!baglantiHazir())
        return sonuc;

    QSqlQuery query(m_db);
    query.prepare("SELECT RolId, RolAdi FROM dbo.roller ORDER BY RolAdi");
    if (!query.exec())
    {
        qWarning() << "rolListesiGetir basarisiz:" << query.lastError().text();
        return sonuc;
    }
    while (query.next())
    {
        QVariantMap r;
        r["rolId"] = query.value("RolId").toInt();
        r["rolAdi"] = query.value("RolAdi").toString();
        sonuc << r;
    }
    return sonuc;
}

QVariantMap Database::personelListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!baglantiHazir())
        return sonuc;

    const QString aramaTrim = arama.trimmed();
    QString whereClause;
    if (!aramaTrim.isEmpty())
        whereClause = "WHERE AdSoyad LIKE :aramaLike OR KullaniciAdi LIKE :aramaLike";

    QSqlQuery sayimQuery(m_db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.kullanicilar %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");

    if (!sayimQuery.exec())
    {
        qWarning() << "personelListesiGetir (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    const int toplamSayfa = std::max(1, static_cast<int>(std::ceil(toplamKayit / static_cast<double>(sayfaBoyutu))));
    sayfaNo = std::clamp(sayfaNo, 1, toplamSayfa);

    QSqlQuery veriQuery(m_db);
    veriQuery.prepare(QString(
        "SELECT KullaniciId, AdSoyad, KullaniciAdi, Telefon, Pozisyon, AktifMi "
        "FROM dbo.kullanicilar %1 "
        "ORDER BY AdSoyad "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", "%" + aramaTrim + "%");
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "personelListesiGetir (veri) basarisiz:" << veriQuery.lastError().text();
        return sonuc;
    }

    // Once sayfadaki personeller tamamen okunur, sonra TEK sorguyla rolleri cekilir.
    // Eskiden her satir icin, veriQuery'nin sonuc kumesi hala acikken ayni baglantida
    // ayri bir rol sorgusu calisiyordu (N+1): hem gereksiz ag gidis-donusu hem de
    // MARS kapali ODBC baglantisinda "connection is busy" riski.
    QList<QVariantMap> personeller;
    QStringList idListesi;
    while (veriQuery.next())
    {
        const int kullaniciId = veriQuery.value("KullaniciId").toInt();
        QVariantMap p;
        p["kullaniciId"] = kullaniciId;
        p["adSoyad"] = veriQuery.value("AdSoyad").toString();
        p["kullaniciAdi"] = veriQuery.value("KullaniciAdi").toString();
        p["telefon"] = veriQuery.value("Telefon").toString();
        p["pozisyon"] = veriQuery.value("Pozisyon").toString();
        p["aktifMi"] = veriQuery.value("AktifMi").toBool();
        personeller << p;
        idListesi << QString::number(kullaniciId);
    }
    veriQuery.finish();

    QHash<int, QVariantList> rolIdleri;
    QHash<int, QStringList> rolAdlari;
    if (!idListesi.isEmpty())
    {
        // IN listesi yalnizca veritabanindan okunmus tamsayilardan olusuyor.
        QSqlQuery rolQuery(m_db);
        if (rolQuery.exec(QString(
                "SELECT kr.KullaniciId, r.RolId, r.RolAdi FROM dbo.kullanici_rolleri kr "
                "INNER JOIN dbo.roller r ON r.RolId = kr.RolId "
                "WHERE kr.KullaniciId IN (%1) ORDER BY r.RolAdi").arg(idListesi.join(','))))
        {
            while (rolQuery.next())
            {
                const int kid = rolQuery.value("KullaniciId").toInt();
                rolIdleri[kid] << rolQuery.value("RolId").toInt();
                rolAdlari[kid] << rolQuery.value("RolAdi").toString();
            }
        }
        else
        {
            qWarning() << "personelListesiGetir (roller) basarisiz:" << rolQuery.lastError().text();
        }
    }

    QVariantList kayitlar;
    for (QVariantMap &p : personeller)
    {
        const int kid = p.value("kullaniciId").toInt();
        p["rolIdListesi"] = rolIdleri.value(kid);
        p["rolAdlari"] = rolAdlari.value(kid).join(", ");
        kayitlar << p;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantMap Database::personelEkle(const QVariantMap &personel)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["kullaniciId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString adSoyad = personel.value("adSoyad").toString().trimmed();
    const QString kullaniciAdi = personel.value("kullaniciAdi").toString().trimmed();
    const QString sifre = personel.value("sifre").toString();

    if (adSoyad.isEmpty() || kullaniciAdi.isEmpty() || sifre.isEmpty())
    {
        sonuc["hata"] = "Ad Soyad, kullanıcı adı ve şifre boş olamaz.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    QSqlQuery ekle(m_db);
    ekle.prepare(
        "INSERT INTO dbo.kullanicilar (AdSoyad, KullaniciAdi, SifreHash, Telefon, Pozisyon, AktifMi) "
        "OUTPUT INSERTED.KullaniciId "
        "VALUES (:adSoyad, :kullaniciAdi, :sifreHash, :telefon, :pozisyon, 1)");
    ekle.bindValue(":adSoyad", adSoyad);
    ekle.bindValue(":kullaniciAdi", kullaniciAdi);
    ekle.bindValue(":sifreHash", sifreyiHashle(sifre));
    ekle.bindValue(":telefon", personel.value("telefon").toString());
    ekle.bindValue(":pozisyon", personel.value("pozisyon").toString());

    if (!ekle.exec() || !ekle.next())
    {
        qWarning() << "personelEkle basarisiz:" << ekle.lastError().text();
        m_db.rollback();
        // UNIQUE ihlali en olasi sebep -- KullaniciAdi zaten var.
        sonuc["hata"] = "Personel kaydedilemedi. Bu kullanıcı adı zaten kullanılıyor olabilir.";
        return sonuc;
    }
    const int kullaniciId = ekle.value(0).toInt();

    const QVariantList rolIdListesi = personel.value("rolIdListesi").toList();
    for (const QVariant &rolIdVar : rolIdListesi)
    {
        QSqlQuery rolEkle(m_db);
        rolEkle.prepare("INSERT INTO dbo.kullanici_rolleri (KullaniciId, RolId) VALUES (:kid, :rid)");
        rolEkle.bindValue(":kid", kullaniciId);
        rolEkle.bindValue(":rid", rolIdVar.toInt());
        if (!rolEkle.exec())
        {
            qWarning() << "personelEkle (rol atama) basarisiz:" << rolEkle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Roller atanamadı: " + rolEkle.lastError().text();
            return sonuc;
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Personel kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["kullaniciId"] = kullaniciId;
    return sonuc;
}

QVariantMap Database::personelGuncelle(int kullaniciId, const QVariantMap &personel)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const QString adSoyad = personel.value("adSoyad").toString().trimmed();
    const QString kullaniciAdi = personel.value("kullaniciAdi").toString().trimmed();
    if (adSoyad.isEmpty() || kullaniciAdi.isEmpty())
    {
        sonuc["hata"] = "Ad Soyad ve kullanıcı adı boş olamaz.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    QString sql = "UPDATE dbo.kullanicilar SET AdSoyad = :adSoyad, KullaniciAdi = :kullaniciAdi, "
                  "Telefon = :telefon, Pozisyon = :pozisyon";
    const QString sifre = personel.value("sifre").toString();
    if (!sifre.isEmpty())
        sql += ", SifreHash = :sifreHash";
    sql += " WHERE KullaniciId = :kullaniciId";

    QSqlQuery guncelle(m_db);
    guncelle.prepare(sql);
    guncelle.bindValue(":adSoyad", adSoyad);
    guncelle.bindValue(":kullaniciAdi", kullaniciAdi);
    guncelle.bindValue(":telefon", personel.value("telefon").toString());
    guncelle.bindValue(":pozisyon", personel.value("pozisyon").toString());
    if (!sifre.isEmpty())
        guncelle.bindValue(":sifreHash", sifreyiHashle(sifre));
    guncelle.bindValue(":kullaniciId", kullaniciId);

    if (!guncelle.exec())
    {
        qWarning() << "personelGuncelle basarisiz:" << guncelle.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Personel güncellenemedi. Bu kullanıcı adı zaten kullanılıyor olabilir.";
        return sonuc;
    }

    // Rolleri sifirla ve yeniden ata (senkron etmenin en basit yolu).
    QSqlQuery rolSil(m_db);
    rolSil.prepare("DELETE FROM dbo.kullanici_rolleri WHERE KullaniciId = :kid");
    rolSil.bindValue(":kid", kullaniciId);
    if (!rolSil.exec())
    {
        m_db.rollback();
        sonuc["hata"] = "Roller güncellenemedi: " + rolSil.lastError().text();
        return sonuc;
    }

    const QVariantList rolIdListesi = personel.value("rolIdListesi").toList();
    for (const QVariant &rolIdVar : rolIdListesi)
    {
        QSqlQuery rolEkle(m_db);
        rolEkle.prepare("INSERT INTO dbo.kullanici_rolleri (KullaniciId, RolId) VALUES (:kid, :rid)");
        rolEkle.bindValue(":kid", kullaniciId);
        rolEkle.bindValue(":rid", rolIdVar.toInt());
        if (!rolEkle.exec())
        {
            m_db.rollback();
            sonuc["hata"] = "Roller atanamadı: " + rolEkle.lastError().text();
            return sonuc;
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Personel güncellenemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

bool Database::personelAktifDurumDegistir(int kullaniciId, bool aktif)
{
    if (!baglantiHazir())
        return false;

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.kullanicilar SET AktifMi = :aktif WHERE KullaniciId = :id");
    query.bindValue(":aktif", aktif);
    query.bindValue(":id", kullaniciId);

    if (!query.exec())
    {
        qWarning() << "personelAktifDurumDegistir basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

bool Database::pdfVerisiniOku(int teklifId, QString &firmaAdiOut, QVariantMap &veriOut, QString &hataOut)
{
    if (!baglantiHazir())
    {
        hataOut = "Veritabanına bağlanılamadı.";
        return false;
    }

    QSqlQuery basQuery(m_db);
    basQuery.prepare(QString(
        "SELECT t.TeklifId, t.OlusturmaTarihi, t.Durum, t.ParaBirimi, t.Dil, "
        "       t.IlgiliKisi, t.IlgiliKisiTelefonu, t.IlgiliKisiEposta, "
        "       t.TeslimatSekli, t.TeslimatYeri, t.GenelIndirimOrani, t.KdvOrani, "
        "       t.SatisSozlesmesiMetni, t.UretimNotu, t.TeslimatTarihi, t.KabulTarihi, "
        "       t.AnaTeklifId, t.RevizyonNo, %1 AS TeklifNo, "
        "       m.FirmaAdi, m.FirmaAdresi, "
        "       k.AdSoyad AS PersonelAdSoyad, k.Telefon AS PersonelTelefon, "
        "       tt.IndirimliToplam, tt.KdvTutari, tt.GenelToplam, tt.PaketlemeUcreti, tt.TasimaUcreti "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = t.KullaniciId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "WHERE t.TeklifId = :teklifId").arg(teklifNoSql("t")));
    basQuery.bindValue(":teklifId", teklifId);

    if (!basQuery.exec() || !basQuery.next())
    {
        qWarning() << "pdfVerisiniOku (baslik) basarisiz:" << basQuery.lastError().text();
        hataOut = "Teklif bulunamadı.";
        return false;
    }

    firmaAdiOut = basQuery.value("FirmaAdi").toString();

    QVariantMap &veri = veriOut;
    veri["firmaAdresi"] = basQuery.value("FirmaAdresi").toString();
    veri["ilgiliKisi"] = basQuery.value("IlgiliKisi").toString();
    veri["ilgiliKisiTelefonu"] = basQuery.value("IlgiliKisiTelefonu").toString();
    veri["ilgiliKisiEposta"] = basQuery.value("IlgiliKisiEposta").toString();
    veri["teslimatSekli"] = basQuery.value("TeslimatSekli").toString();
    veri["teslimatYeri"] = basQuery.value("TeslimatYeri").toString();
    veri["personelAdSoyad"] = basQuery.value("PersonelAdSoyad").toString();
    veri["personelTelefon"] = basQuery.value("PersonelTelefon").toString();
    veri["dil"] = basQuery.value("Dil").toString();
    veri["paraBirimi"] = basQuery.value("ParaBirimi").toString();
    veri["olusturmaTarihi"] = tarihStr(basQuery.value("OlusturmaTarihi"));
    veri["genelIndirimOrani"] = basQuery.value("GenelIndirimOrani").toDouble();
    veri["kdvOrani"] = basQuery.value("KdvOrani").toDouble();
    veri["indirimliToplam"] = basQuery.value("IndirimliToplam").toDouble();
    veri["kdvTutari"] = basQuery.value("KdvTutari").toDouble();
    veri["genelToplam"] = basQuery.value("GenelToplam").toDouble();
    veri["paketlemeUcreti"] = basQuery.value("PaketlemeUcreti").toDouble();
    veri["tasimaUcreti"] = basQuery.value("TasimaUcreti").toDouble();
    // PDF'in son sayfasindaki sozlesme maddeleri. Bos ise TeklifPdfOlusturucu
    // dilin varsayilan metnini kullanir.
    veri["sozlesmeMetni"] = basQuery.value("SatisSozlesmesiMetni").toString();
    // Uretim PDF'ine yalnizca uretim notu basilir. Teklif notu (MusteriNotu)
    // uretimciye gitmemesi icin burada bilincli olarak OKUNMAZ.
    veri["uretimNotu"] = basQuery.value("UretimNotu").toString();
    // Planlanan teslim tarihi (bos olabilir) ve kabul tarihi: teklif PDF'inde
    // teslimat blogunda, uretim PDF'inde bilgi blogunda gosterilir.
    veri["teslimatTarihi"] = tarihStr(basQuery.value("TeslimatTarihi"));
    veri["kabulTarihi"] = tarihStr(basQuery.value("KabulTarihi"));
    veri["durum"] = basQuery.value("Durum").toString();

    // --- PDF'teki teklif numarasi ve revizyon uyarisi ------------------------
    // Bir revizyon, veritabaninda yeni bir TeklifId ile durur; ama PDF'te KOK
    // teklifin Teklif No'su "1203/Rev.2" seklinde basilir. Aksi halde musteri ayni
    // teklifin revizyonunu bagimsiz, ikinci bir teklif sanirdi.
    // kokTeklifId zincirin ic anahtaridir (asagidaki sorgu icin), kokTeklifNo
    // ise belgeye basilan numaradir.
    const int kokTeklifId = basQuery.value("AnaTeklifId").isNull()
        ? teklifId
        : basQuery.value("AnaTeklifId").toInt();
    veri["kokTeklifNo"] = basQuery.value("TeklifNo").toInt();
    veri["revizyonNo"] = basQuery.value("RevizyonNo").toInt();

    // Bu teklif revize edilmisse (yerine yeni bir revizyon gecmisse), PDF'in
    // ustune "gecerli degildir" bandi basilir; bandda gecerli olan revizyonun
    // numarasi da yazsin diye zincirin EN SON kaydini okuyoruz.
    if (veri["durum"].toString() == DURUM_REVIZE_EDILDI)
    {
        QSqlQuery sonQuery(m_db);
        sonQuery.prepare(
            "SELECT TOP 1 RevizyonNo FROM dbo.teklifler "
            "WHERE TeklifId = :kok OR AnaTeklifId = :kok "
            "ORDER BY RevizyonNo DESC");
        sonQuery.bindValue(":kok", kokTeklifId);
        if (sonQuery.exec() && sonQuery.next())
            veri["guncelRevizyonNo"] = sonQuery.value(0).toInt();
    }

    QSqlQuery kalemQuery(m_db);
    kalemQuery.prepare(
        "SELECT tk.Adet, tk.BirimFiyat, tk.IndirimliBirimFiyat, tk.ToplamTutar, "
        "       tk.Tamamlandi, tk.UretimNotu, "
        "       u.UrunKodu, tk.UrunAciklamasi, u.UrunAciklamasi AS KatalogAciklamaTr "
        "FROM dbo.teklif_kalemleri tk "
        "LEFT JOIN dbo.urunler u ON u.UrunId = tk.UrunId "
        "WHERE tk.TeklifId = :teklifId "
        "ORDER BY tk.TeklifKalemId");
    kalemQuery.bindValue(":teklifId", teklifId);
    kalemQuery.exec();

    // Basliklar Dil alanina (TR/EN) gore secilir; kalemlerdeki UrunAciklamasi zaten
    // kaydedilirken secili dile gore yazilmisti (bkz. urunAra), burada ayrica
    // cevrilmesine gerek yok. Parasal alanlarda hep "TL" yazmak yerine teklifin
    // gercek ParaBirimi'ni kullaniyoruz (teklifKaydet artik tum kalem/toplam
    // tutarlarini kaydedilecegi para birimine cevirip kaydediyor).
    QVariantList kalemler;
    while (kalemQuery.next())
    {
        QVariantMap kalem;
        kalem["adet"] = kalemQuery.value("Adet").toInt();
        kalem["birimFiyat"] = kalemQuery.value("BirimFiyat").toDouble();
        kalem["indirimliBirimFiyat"] = kalemQuery.value("IndirimliBirimFiyat").toDouble();
        kalem["toplamTutar"] = kalemQuery.value("ToplamTutar").toDouble();
        kalem["urunKodu"] = kalemQuery.value("UrunKodu").toString();
        kalem["urunAciklamasi"] = kalemQuery.value("UrunAciklamasi").toString();
        // Uretim PDF'i teknik ekip icin HER ZAMAN Turkce basilir; teklif EN
        // kaydedildiyse katalogdaki TR aciklamayi kullanabilsin diye tasinir.
        // Manuel kalemlerde ("MANUEL-...") katalog satiri teklife ozeldir ve
        // zaten kayitli aciklamanin aynisidir.
        kalem["urunAciklamasiTr"] = kalemQuery.value("KatalogAciklamaTr").toString();
        // Satir bazli uretim takibi: yalnizca URETIM PDF'i kullanir (musteriye
        // giden teklif PDF'i bu alanlari gormezden gelir -- ic bilgidir).
        kalem["tamamlandi"] = kalemQuery.value("Tamamlandi").toBool();
        kalem["uretimNotu"] = kalemQuery.value("UretimNotu").toString();
        kalemler.append(kalem);
    }
    veri["kalemler"] = kalemler;
    return true;
}

QVariantMap Database::teklifPdfOlustur(int teklifId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    QString firmaAdi;
    QVariantMap veri;
    QString hata;
    if (!pdfVerisiniOku(teklifId, firmaAdi, veri, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    // NOT: Eskiden burada UretimPdfTarihi de guncelleniyordu; bu yanlisti --
    // musteriye giden teklif PDF'i uretim emri degildir. O alan artik yalnizca
    // uretim PDF'i indirilince (pdfKaydet) yazilir.
    sonuc = m_pdfOlusturucu.teklifPdfUret(teklifId, firmaAdi, veri);
    sonuc["tur"] = QStringLiteral("teklif");
    sonuc["teklifId"] = teklifId;
    return sonuc;
}

QVariantMap Database::uretimPdfOlustur(int teklifId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    QString firmaAdi;
    QVariantMap veri;
    QString hata;
    if (!pdfVerisiniOku(teklifId, firmaAdi, veri, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    sonuc = m_pdfOlusturucu.uretimPdfUret(teklifId, firmaAdi, veri);
    sonuc["tur"] = QStringLiteral("uretim");
    sonuc["teklifId"] = teklifId;
    return sonuc;
}

QVariantMap Database::pdfKaydet(const QVariantMap &pdf)
{
    QVariantMap sonuc = TeklifPdfOlusturucu::onizlemeyiKaydet(pdf.value("dosyaYolu").toString(),
                                                              pdf.value("dosyaAdi").toString());
    if (!sonuc.value("basarili").toBool())
        return sonuc;

    // "Üretim PDF" sutunu, uretim PDF'inin teknik ekibe verildigi ani gosterir;
    // sadece onizlemek bunu doldurmaz, indirmek doldurur. PDF zaten diske
    // yazildigi icin bu guncelleme basarisiz olsa bile islem basarili sayilir.
    const int teklifId = pdf.value("teklifId").toInt();
    if (pdf.value("tur").toString() == QLatin1String("uretim") && teklifId > 0)
    {
        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.teklifler SET UretimPdfTarihi = SYSDATETIME() WHERE TeklifId = :id");
        guncelle.bindValue(":id", teklifId);
        if (!guncelle.exec())
            qWarning() << "UretimPdfTarihi guncellenemedi:" << guncelle.lastError().text();
    }
    return sonuc;
}

void Database::pdfOnizlemesiniSil(const QString &onizlemeYolu)
{
    TeklifPdfOlusturucu::onizlemeyiSil(onizlemeYolu);
}

QVariantMap Database::satisSozlesmesiOlustur(const QVariantMap &teklif)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    // Bu ekran, teklif HENUZ KAYDEDILMEMISKEN de calisabilmeli (kullanici
    // "Teklifi Kaydet"e basmadan once sozlesmeyi gormek isteyebilir). Bu yuzden
    // veritabanindan degil, dogrudan QML'den gelen "teklif" haritasindan uretir.
    QString firmaAdi = teklif.value("musteriAdi").toString().trimmed();
    const int musteriId = teklif.value("musteriId").toInt();
    QString firmaAdresi;

    if (musteriId > 0 && baglantiHazir())
    {
        QSqlQuery musteriQuery(m_db);
        musteriQuery.prepare("SELECT FirmaAdi, FirmaAdresi FROM dbo.musteriler WHERE MusteriId = :id");
        musteriQuery.bindValue(":id", musteriId);
        if (musteriQuery.exec() && musteriQuery.next())
        {
            firmaAdi = musteriQuery.value("FirmaAdi").toString();
            firmaAdresi = musteriQuery.value("FirmaAdresi").toString();
        }
    }

    if (firmaAdi.trimmed().isEmpty())
    {
        sonuc["hata"] = "Sözleşme için müşteri bilgisi bulunamadı.";
        return sonuc;
    }

    if (teklif.value("kalemler").toList().isEmpty())
    {
        sonuc["hata"] = "Sözleşme için sepette en az bir ürün olmalı.";
        return sonuc;
    }

    QVariantMap veri = teklif;
    veri["firmaAdi"] = firmaAdi;
    veri["firmaAdresi"] = firmaAdresi;

    return m_pdfOlusturucu.satisSozlesmesiUret(veri);
}

QString Database::varsayilanSozlesmeMetni(const QString &dil) const
{
    return TeklifPdfOlusturucu::varsayilanSozlesmeMetni(dil.compare("EN", Qt::CaseInsensitive) == 0);
}

QVariantList Database::sozlesmeSatirlari(const QString &metin, const QVariantMap &teklif) const
{
    const bool ingilizce = teklif.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
    const QDate bugun = QDate::currentDate();
    const auto uygula = [&](const QString &s) {
        return TeklifPdfOlusturucu::sozlesmeDegiskenleriniUygula(s, teklif, ingilizce, bugun);
    };

    static const QRegularExpression etiketDeseni(QStringLiteral("^\\[([A-Z_]+)\\]\\s*"));
    QVariantList satirlar;
    for (const QString &hamSatir : metin.split(QRegularExpression("\r\n|\n|\r")))
    {
        QString icerik = hamSatir.trimmed();
        if (icerik.isEmpty())
            continue;

        const bool alt = icerik.startsWith(QStringLiteral("- ")) || icerik.startsWith(QStringLiteral("• "));
        if (alt)
            icerik = icerik.mid(2).trimmed();

        // Satir basi kosul etiketlerini ayir. Bir etiketin gercekten kosul olup
        // olmadigini PDF'in kendi fonksiyonuna sorariz: taninan etiket "[X] x"
        // metnini degistirir ("x" veya bos), taninmayan ("[NOT]") dokunmaz.
        QString etiketler;
        forever
        {
            const QRegularExpressionMatch m = etiketDeseni.match(icerik);
            if (!m.hasMatch())
                break;
            const QString deneme = QStringLiteral("[%1] x").arg(m.captured(1));
            if (uygula(deneme) == deneme)
                break;
            etiketler += QStringLiteral("[%1] ").arg(m.captured(1));
            icerik = icerik.mid(m.capturedEnd());
        }

        const bool gorunur = etiketler.isEmpty() || !uygula(etiketler + QStringLiteral("x")).isEmpty();
        const QString gorunen = uygula(icerik);
        satirlar << QVariantMap{
            { "etiketler", etiketler },
            { "hamIcerik", icerik },
            { "orijinalGorunen", gorunen },
            { "gorunen", gorunen },
            { "alt", alt },
            { "gorunur", gorunur },
        };
    }
    return satirlar;
}

QString Database::sozlesmeSatirlarindanMetin(const QVariantList &satirlar, const QVariantMap &teklif) const
{
    const bool ingilizce = teklif.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
    const QDate bugun = QDate::currentDate();
    static const QRegularExpression degiskenDeseni(QStringLiteral("\\{\\{[^{}]+\\}\\}"));

    QStringList cikti;
    for (const QVariant &v : satirlar)
    {
        const QVariantMap s = v.toMap();
        const QString ham = s.value("hamIcerik").toString();
        QString icerik = s.value("gorunen").toString();

        if (!s.value("gorunur").toBool() || icerik == s.value("orijinalGorunen").toString())
        {
            icerik = ham;
        }
        else
        {
            // Ham icerikteki her {{DEGISKEN}}'in doldurulmus degeri yeni metinde
            // hala varsa, o deger tekrar yer tutucuya cevrilir. Uzun degerler once
            // aranir ki ör. "20" (KDV_ORANI) "%20 KDV dahildir"in icinden kapilmasin.
            QList<QPair<QString, QString>> eslesmeler; // doldurulmus deger -> yer tutucu
            auto it = degiskenDeseni.globalMatch(ham);
            while (it.hasNext())
            {
                const QString yerTutucu = it.next().captured(0);
                const QString deger = TeklifPdfOlusturucu::sozlesmeDegiskenleriniUygula(yerTutucu, teklif, ingilizce, bugun);
                if (!deger.isEmpty() && deger != yerTutucu)
                    eslesmeler.append({ deger, yerTutucu });
            }
            std::stable_sort(eslesmeler.begin(), eslesmeler.end(),
                             [](const auto &a, const auto &b) { return a.first.size() > b.first.size(); });

            // Once gecici isaretlerle degistir: geri konan bir yer tutucunun
            // icinde baska bir deger aranmasin.
            QStringList geriKonanlar;
            for (const auto &[deger, yerTutucu] : std::as_const(eslesmeler))
            {
                const qsizetype konum = icerik.indexOf(deger);
                if (konum < 0)
                    continue;
                icerik.replace(konum, deger.size(), QStringLiteral("\u0001%1\u0002").arg(geriKonanlar.size()));
                geriKonanlar << yerTutucu;
            }
            for (qsizetype i = 0; i < geriKonanlar.size(); ++i)
                icerik.replace(QStringLiteral("\u0001%1\u0002").arg(i), geriKonanlar.at(i));
        }

        // Yapistirilan cok satirli metin: her satir ayri madde olur (ilk satir bu maddenin).
        const QStringList parcalar = icerik.split(QRegularExpression("\r\n|\n|\r"), Qt::SkipEmptyParts);
        for (qsizetype i = 0; i < parcalar.size(); ++i)
        {
            const QString parca = parcalar.at(i).trimmed();
            if (parca.isEmpty())
                continue;
            if (i == 0)
                cikti << (s.value("alt").toBool() ? QStringLiteral("- ") : QString())
                             + s.value("etiketler").toString() + parca;
            else
                cikti << parca;
        }
    }
    return cikti.join(QLatin1Char('\n'));
}

QString Database::teklifSozlesmeMetniGetir(int teklifId, const QString &dil)
{
    if (teklifId > 0 && baglantiHazir())
    {
        QSqlQuery query(m_db);
        query.prepare("SELECT SatisSozlesmesiMetni FROM dbo.teklifler WHERE TeklifId = :id");
        query.bindValue(":id", teklifId);
        if (query.exec() && query.next())
        {
            const QString metin = query.value(0).toString();
            if (!metin.trimmed().isEmpty())
                return metin;
        }
        else
        {
            qWarning() << "teklifSozlesmeMetniGetir basarisiz:" << query.lastError().text();
        }
    }

    // Teklif henuz kaydedilmemis veya kendine ozel bir metni yok: pencere
    // fabrika varsayilaniyla acilir.
    return varsayilanSozlesmeMetni(dil);
}

bool Database::teklifSozlesmeMetniKaydet(int teklifId, const QString &metin)
{
    if (teklifId <= 0 || !baglantiHazir())
        return false;

    if (teklifKilitliMi(teklifDurumuGetir(teklifId)))
    {
        qWarning() << "teklifSozlesmeMetniKaydet: kilitli teklif degistirilemez:" << teklifId;
        return false;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklifler SET SatisSozlesmesiMetni = :metin WHERE TeklifId = :id");
    query.bindValue(":id", teklifId);
    // Bos metin -> NULL: teklif tekrar dilin varsayilan metnine doner.
    if (metin.trimmed().isEmpty())
        query.bindValue(":metin", QVariant(QMetaType(QMetaType::QString)));
    else
        query.bindValue(":metin", metin);

    if (!query.exec())
    {
        qWarning() << "teklifSozlesmeMetniKaydet basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

namespace
{
    // dbo.sevk_bilgileri'nin METIN sutunlari: {SQL sutun adi, QML anahtari}.
    // Alan sayisi cok oldugu icin SELECT / INSERT / UPDATE uclusu bu tek
    // listeden uretilir -- ileride yeni bir alan gerektiginde buraya bir satir
    // eklemek (ve QML'de bir satir gostermek) yeterli olur.
    //
    // SiparisTarihi (DATE) bu listede YOKTUR: string degil tarih oldugu ve
    // "yyyy-MM-dd" <-> DATE cevrimi gerektirdigi icin ayrica islenir.
    struct SevkAlani
    {
        const char *sutun;
        const char *anahtar;
    };

    const SevkAlani SEVK_METIN_ALANLARI[] = {
        { "FaturaBasligi",        "faturaBasligi" },
        { "FaturaAdresi",         "faturaAdresi" },
        { "FaturaVergiDairesi",   "faturaVergiDairesi" },
        { "FaturaVergiNo",        "faturaVergiNo" },
        { "FaturaYetkili",        "faturaYetkili" },
        { "FaturaTelefon",        "faturaTelefon" },
        { "FaturaFax",            "faturaFax" },
        { "FaturaEposta",         "faturaEposta" },
        { "IrsaliyeBasligi",      "irsaliyeBasligi" },
        { "IrsaliyeAdresi",       "irsaliyeAdresi" },
        { "IrsaliyeVergiDairesi", "irsaliyeVergiDairesi" },
        { "IrsaliyeVergiNo",      "irsaliyeVergiNo" },
        { "IrsaliyeYetkili",      "irsaliyeYetkili" },
        { "IrsaliyeTelefon",      "irsaliyeTelefon" },
        { "IrsaliyeEposta",       "irsaliyeEposta" },
        { "SiparisKdv",           "siparisKdv" },
        { "FaturaSekli",          "faturaSekli" },
        { "Garanti",              "garanti" },
        { "Teslimat",             "teslimat" },
        { "Odeme",                "odeme" },
        { "Nakliye",              "nakliye" },
        { "Kalibrasyon",          "kalibrasyon" },
        { "Egitim",               "egitim" },
        { "ReferansNumarasi",     "referansNumarasi" },
        { "EkFaturaNotu",         "ekFaturaNotu" },
        { "Aciklamalar",          "aciklamalar" }
    };

    // Bos birakilan alanlar bos string olarak degil NULL olarak saklanir --
    // boylece "doldurulmamis" ile "bos birakilmis" ayrimi veritabaninda kalmaz
    // ve listedeki AÇIKLAMALAR sutunu bos satirlarda gercekten bos gorunur.
    QVariant sevkMetinParametresi(const QString &deger)
    {
        const QString temiz = deger.trimmed();
        return temiz.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : QVariant(temiz);
    }
}

QVariantMap Database::sevkBilgileriGetir(int teklifId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();
    sonuc["kayitVarMi"] = false;
    // Pencere her alani bulmayi bekler; kayit yoksa da haritayi bos degerlerle
    // eksiksiz dolduruyoruz (QML tarafinda "undefined" kontrolu gerekmesin).
    for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
        sonuc[alan.anahtar] = QString();
    sonuc["siparisTarihi"] = QString();

    if (teklifId <= 0)
    {
        sonuc["hata"] = "Geçersiz teklif.";
        return sonuc;
    }
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    QStringList sutunlar;
    for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
        sutunlar << QString::fromLatin1(alan.sutun);
    sutunlar << "SiparisTarihi";

    QSqlQuery query(m_db);
    query.prepare("SELECT " + sutunlar.join(", ") + " FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId");
    query.bindValue(":teklifId", teklifId);

    if (!query.exec())
    {
        qWarning() << "sevkBilgileriGetir basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Sevk bilgileri okunamadı: " + query.lastError().text();
        return sonuc;
    }

    if (query.next())
    {
        sonuc["kayitVarMi"] = true;
        for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
            sonuc[alan.anahtar] = query.value(QString::fromLatin1(alan.sutun)).toString();
        const QVariant siparisTarihiHam = query.value("SiparisTarihi");
        sonuc["siparisTarihi"] = siparisTarihiHam.isNull()
            ? QString()
            : siparisTarihiHam.toDateTime().date().toString("yyyy-MM-dd");
    }

    // ON DOLDURMA (WPF'teki ApplyDefaultBillingInformation ile ayni fikir):
    // fatura bilgileri neredeyse her zaman musterinin kendi bilgileridir, yetkili
    // ve iletisim ise teklifteki ilgili kisidir. Kullanici farkli bir fatura
    // basligi/adresi isterse ustune yazar; bu degerler ancak "Kaydet"e basilinca
    // veritabanina gider.
    QSqlQuery onQuery(m_db);
    onQuery.prepare(
        "SELECT m.FirmaAdi, m.FirmaAdresi, m.VergiDairesi, m.VergiNumarasi, "
        "       t.IlgiliKisi, t.IlgiliKisiTelefonu, t.IlgiliKisiEposta, t.KdvOrani "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "WHERE t.TeklifId = :teklifId");
    onQuery.bindValue(":teklifId", teklifId);

    if (onQuery.exec() && onQuery.next())
    {
        auto bosAlaniDoldur = [&sonuc](const char *anahtar, const QString &varsayilan) {
            if (!sonuc.value(anahtar).toString().trimmed().isEmpty())
                return;
            if (varsayilan.trimmed().isEmpty())
                return;
            sonuc[anahtar] = varsayilan.trimmed();
        };

        bosAlaniDoldur("faturaBasligi", onQuery.value("FirmaAdi").toString());
        bosAlaniDoldur("faturaAdresi", onQuery.value("FirmaAdresi").toString());
        bosAlaniDoldur("faturaVergiDairesi", onQuery.value("VergiDairesi").toString());
        bosAlaniDoldur("faturaVergiNo", onQuery.value("VergiNumarasi").toString());
        bosAlaniDoldur("faturaYetkili", onQuery.value("IlgiliKisi").toString());
        bosAlaniDoldur("faturaTelefon", onQuery.value("IlgiliKisiTelefonu").toString());
        bosAlaniDoldur("faturaEposta", onQuery.value("IlgiliKisiEposta").toString());

        // KDV teklifte zaten secilidir; irsaliye formunda "%20" gibi gorunur.
        const double kdvOrani = onQuery.value("KdvOrani").toDouble();
        if (kdvOrani > 0)
            bosAlaniDoldur("siparisKdv", "%" + QString::number(kdvOrani, 'g', 4));
    }
    else
    {
        // On doldurma yapilamamasi (ornegin teklif silinmis) kayit okumayi
        // gecersiz kilmaz; form bos/kayitli haliyle acilir.
        qWarning() << "sevkBilgileriGetir on doldurma basarisiz:" << teklifId << onQuery.lastError().text();
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::sevkBilgileriKaydet(int teklifId, const QVariantMap &sevk)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (teklifId <= 0)
    {
        sonuc["hata"] = "Geçersiz teklif.";
        return sonuc;
    }
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    // Kilit kurali: teslim edilmis (Tamamlandı) teklifin sevk/irsaliye bilgileri
    // artik degistirilemez -- pencere o teklifte zaten salt okunur acilir, bu
    // kontrol kuralin veritabani tarafindaki karsiligidir.
    if (teklifDurumuGetir(teklifId) == "Tamamlandı")
    {
        sonuc["hata"] = "Tamamlanmış teklifin sevk bilgileri değiştirilemez.";
        return sonuc;
    }

    QSqlQuery varMiQuery(m_db);
    varMiQuery.prepare("SELECT SevkBilgileriId FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId");
    varMiQuery.bindValue(":teklifId", teklifId);
    if (!varMiQuery.exec())
    {
        qWarning() << "sevkBilgileriKaydet (kayit kontrolu) basarisiz:" << varMiQuery.lastError().text();
        sonuc["hata"] = "Sevk bilgileri okunamadı: " + varMiQuery.lastError().text();
        return sonuc;
    }
    const bool kayitVar = varMiQuery.next();

    QStringList atamalar;
    QStringList sutunlar;
    QStringList yerTutucular;
    for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
    {
        const QString sutun = QString::fromLatin1(alan.sutun);
        const QString yerTutucu = ":" + QString::fromLatin1(alan.anahtar);
        atamalar << sutun + " = " + yerTutucu;
        sutunlar << sutun;
        yerTutucular << yerTutucu;
    }

    QSqlQuery query(m_db);
    if (kayitVar)
    {
        query.prepare("UPDATE dbo.sevk_bilgileri SET " + atamalar.join(", ")
                      + ", SiparisTarihi = :siparisTarihi WHERE TeklifId = :teklifId");
    }
    else
    {
        query.prepare("INSERT INTO dbo.sevk_bilgileri (TeklifId, " + sutunlar.join(", ")
                      + ", SiparisTarihi) VALUES (:teklifId, " + yerTutucular.join(", ")
                      + ", :siparisTarihi)");
    }

    for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
    {
        query.bindValue(":" + QString::fromLatin1(alan.anahtar),
                        sevkMetinParametresi(sevk.value(alan.anahtar).toString()));
    }
    query.bindValue(":siparisTarihi", tarihParametresi(sevk.value("siparisTarihi").toString()));
    query.bindValue(":teklifId", teklifId);

    if (!query.exec())
    {
        qWarning() << "sevkBilgileriKaydet basarisiz:" << teklifId << query.lastError().text();
        sonuc["hata"] = "Sevk bilgileri kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}
