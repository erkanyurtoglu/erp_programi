#include "Database.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>
#include <QDateTime>
#include <QDebug>
#include <QCryptographicHash>
#include <cmath>
#include <algorithm>

namespace
{
    // Yeni ERP semasi: ayni SQL Server ornegi (EXCALIBUR\SQLEXPRESS) uzerinde,
    // eski LiyaTeklifVeriTabani'nden bagimsiz, yeniden tasarlanmis veritabani.
    const QString SUNUCU = R"(EXCALIBUR\SQLEXPRESS)";
    const QString VERITABANI = "LiyaErpVeriTabani";

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
}

Database::~Database()
{
    if (m_db.isOpen())
        m_db.close();
}

bool Database::baglan()
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
        m_db = QSqlDatabase::addDatabase("QODBC", "erp_baglantisi");

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

        m_db.setDatabaseName(baglantiDizesi);

        if (m_db.open())
        {
            qInfo() << "Veritabanina baglanildi. Surucu:" << surucu << "Veritabani:" << VERITABANI;
            return true;
        }

        m_sonHataMesaji = m_db.lastError().text();

        // m_db'yi once bosaltip baglantiyi kapatiyoruz ki removeDatabase() cagrisi
        // "connection is still in use" uyarisi vermesin (m_db hala o baglantiya
        // referans tutan tek nesne, ustteki QSqlDatabase::addDatabase donusunden).
        m_db.close();
        m_db = QSqlDatabase();
        QSqlDatabase::removeDatabase("erp_baglantisi");
    }

    qWarning() << "Veritabanina baglanilamadi:" << m_sonHataMesaji;
    return false;
}

QVariantMap Database::girisYap(const QString &kullaniciAdi, const QString &sifre)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!m_baglantiHazir)
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
        bool idEslesiyorMu = false;
        const int teklifIdArama = aramaTrim.toInt(&idEslesiyorMu);

        QString aramaKosulu = "(";
        if (idEslesiyorMu)
            aramaKosulu += "t.TeklifId = :teklifId OR ";

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
        if (idEslesiyorMu)
            parametrelerOut[":teklifId"] = teklifIdArama;
    }

    whereClauseOut = kosullar.isEmpty() ? QString() : ("WHERE " + kosullar.join(" AND "));
}

QVariantMap Database::gecmisTekliflerGetir(const QString &arama,
                                            const QString &tarihFiltresi,
                                            const QString &baslangicTarihi,
                                            const QString &bitisTarihi,
                                            int sayfaNo,
                                            int sayfaBoyutu)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!m_baglantiHazir)
    {
        qWarning() << "gecmisTekliflerGetir: veritabani baglantisi yok.";
        return sonuc;
    }

    QString whereClause;
    QVariantMap parametreler;
    whereKosullariniOlustur(arama, tarihFiltresi, baslangicTarihi, bitisTarihi, whereClause, parametreler);

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
    const QString veriSorgusu = QString(
        "SELECT t.TeklifId, m.FirmaAdi, t.OlusturmaTarihi, t.KabulTarihi, "
        "       t.TeslimatTarihi, t.TeslimTarihi, t.UretimPdfTarihi, "
        "       p.KullaniciAdi AS PersonelKullaniciAdi, t.Durum, sb.Aciklamalar "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "OUTER APPLY ("
        "    SELECT TOP 1 sbi.Aciklamalar "
        "    FROM dbo.sevk_bilgileri sbi "
        "    WHERE sbi.TeklifId = t.TeklifId "
        "    ORDER BY sbi.SevkBilgileriId DESC"
        ") sb "
        "%1 "
        "ORDER BY t.OlusturmaTarihi DESC "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause);

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
        kayit["aciklamalar"] = veriQuery.value("Aciklamalar").toString();
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
    if (!m_baglantiHazir)
        return false;

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
