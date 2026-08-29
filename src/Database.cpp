#include "Database.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>
#include <QDateTime>
#include <QDebug>
#include <QCryptographicHash>
#include <QTextDocument>
#include <QPrinter>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QDesktopServices>
#include <QUrl>
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

    if (!m_baglantiHazir)
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
    const QString veriSorgusu = QString(
        "SELECT t.TeklifId, m.FirmaAdi, t.OlusturmaTarihi, t.KabulTarihi, "
        "       t.TeslimatTarihi, t.TeslimTarihi, t.UretimPdfTarihi, "
        "       p.KullaniciAdi AS PersonelKullaniciAdi, t.Durum, t.RedSebebi, sb.Aciklamalar "
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
        kayit["redSebebi"] = veriQuery.value("RedSebebi").toString();
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

QVariantList Database::musteriAra(const QString &arama, int limit)
{
    QVariantList sonuc;
    if (!m_baglantiHazir)
        return sonuc;

    const QString aramaTrim = arama.trimmed();

    QSqlQuery query(m_db);
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

QVariantList Database::urunAra(const QString &arama, int limit, const QString &dil)
{
    QVariantList sonuc;
    if (!m_baglantiHazir)
        return sonuc;

    const QString aramaTrim = arama.trimmed();
    const bool ingilizce = dil.compare("EN", Qt::CaseInsensitive) == 0;

    QSqlQuery query(m_db);
    if (aramaTrim.isEmpty())
    {
        query.prepare(QString(
            "SELECT TOP (%1) UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, "
            "       BirimFiyat, ParaBirimi, GuncelMaliyetTL "
            "FROM dbo.urunler ORDER BY UrunId DESC").arg(limit));
    }
    else
    {
        query.prepare(QString(
            "SELECT TOP (%1) UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, "
            "       BirimFiyat, ParaBirimi, GuncelMaliyetTL "
            "FROM dbo.urunler "
            "WHERE UrunKodu LIKE :aramaLike OR UrunAciklamasi LIKE :aramaLike "
            "   OR UrunAciklamasiEn LIKE :aramaLike "
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

QVariantMap Database::teklifKaydet(const QVariantMap &teklif)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["teklifId"] = 0;
    sonuc["hata"] = QString();

    if (!m_baglantiHazir)
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

    QSqlQuery teklifEkle(m_db);
    teklifEkle.prepare(
        "INSERT INTO dbo.teklifler "
        "(MusteriId, KullaniciId, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu, ParaBirimi, Dil, "
        " IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta, TeslimatSekli, TeslimatYeri) "
        "OUTPUT INSERTED.TeklifId "
        "VALUES (:musteriId, :kullaniciId, :indirim, :kdv, N'Beklemede', :not, :paraBirimi, :dil, "
        "        :ilgiliKisi, :ilgiliKisiTel, :ilgiliKisiEposta, :teslimatSekli, :teslimatYeri)");
    teklifEkle.bindValue(":musteriId", musteriId);
    const int kullaniciId = teklif.value("kullaniciId").toInt();
    if (kullaniciId > 0)
        teklifEkle.bindValue(":kullaniciId", kullaniciId);
    else
        teklifEkle.bindValue(":kullaniciId", QVariant(QMetaType(QMetaType::Int)));
    teklifEkle.bindValue(":indirim", teklif.value("genelIndirimOrani", 0).toDouble());
    teklifEkle.bindValue(":kdv", teklif.value("kdvOrani", 0).toDouble());
    teklifEkle.bindValue(":not", teklif.value("musteriNotu").toString());
    teklifEkle.bindValue(":paraBirimi", teklif.value("paraBirimi", "TL").toString());
    teklifEkle.bindValue(":dil", teklif.value("dil", "TR").toString());
    teklifEkle.bindValue(":ilgiliKisi", teklif.value("ilgiliKisi").toString());
    teklifEkle.bindValue(":ilgiliKisiTel", teklif.value("ilgiliKisiTelefonu").toString());
    teklifEkle.bindValue(":ilgiliKisiEposta", teklif.value("ilgiliKisiEposta").toString());
    teklifEkle.bindValue(":teslimatSekli", teklif.value("teslimatSekli").toString());
    teklifEkle.bindValue(":teslimatYeri", teklif.value("teslimatYeri").toString());

    if (!teklifEkle.exec() || !teklifEkle.next())
    {
        qWarning() << "teklifKaydet (teklifler) basarisiz:" << teklifEkle.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + teklifEkle.lastError().text();
        return sonuc;
    }

    const int teklifId = teklifEkle.value(0).toInt();

    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap kalem = kalemVar.toMap();

        QSqlQuery kalemEkle(m_db);
        kalemEkle.prepare(
            "INSERT INTO dbo.teklif_kalemleri "
            "(TeklifId, UrunId, Adet, BirimFiyat, IndirimliBirimFiyat, ToplamTutar, MaliyetFiyati, "
            " UrunAciklamasi, ParaBirimi, Kur) "
            "VALUES (:teklifId, :urunId, :adet, :birimFiyat, :indirimliBirimFiyat, :toplamTutar, "
            "        :maliyetFiyati, :urunAciklamasi, :paraBirimi, :kur)");
        kalemEkle.bindValue(":teklifId", teklifId);

        // Manuel eklenen kalemlerde (sepete elle yazilan, urunler tablosunda karsiligi
        // olmayan satirlar) UrunId gonderilmez; boyle bir durumda "manuel urun" icin
        // ozel bir yer tutucu urun kaydi kullaniyoruz (asagida garanti ediliyor).
        int urunId = kalem.value("urunId", 0).toInt();
        if (urunId <= 0)
        {
            // Manuel kalem: urunler tablosunda bu teklife ozel, kalici olmayan bir
            // satir olusturup UrunId'sini kullaniyoruz (FOREIGN KEY zorunlulugu var).
            QSqlQuery manuelUrun(m_db);
            manuelUrun.prepare(
                "INSERT INTO dbo.urunler (UrunKodu, UrunAciklamasi, BirimFiyat, ParaBirimi) "
                "OUTPUT INSERTED.UrunId "
                "VALUES (:kod, :aciklama, :birimFiyat, :paraBirimi)");
            manuelUrun.bindValue(":kod", kalem.value("urunKodu", "MANUEL").toString());
            manuelUrun.bindValue(":aciklama", kalem.value("aciklama").toString());
            manuelUrun.bindValue(":birimFiyat", kalem.value("birimFiyat", 0).toDouble());
            manuelUrun.bindValue(":paraBirimi", kalem.value("paraBirimi", "TL").toString());
            if (!manuelUrun.exec() || !manuelUrun.next())
            {
                qWarning() << "teklifKaydet (manuel urun) basarisiz:" << manuelUrun.lastError().text();
                m_db.rollback();
                sonuc["hata"] = "Manuel ürün kaydedilemedi: " + manuelUrun.lastError().text();
                return sonuc;
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

        if (!kalemEkle.exec())
        {
            qWarning() << "teklifKaydet (teklif_kalemleri) basarisiz:" << kalemEkle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Teklif kalemi kaydedilemedi: " + kalemEkle.lastError().text();
            return sonuc;
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
        qWarning() << "teklifKaydet (teklif_toplamlari) basarisiz:" << toplamEkle.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif toplamları kaydedilemedi: " + toplamEkle.lastError().text();
        return sonuc;
    }

    if (!m_db.commit())
    {
        qWarning() << "teklifKaydet commit basarisiz:" << m_db.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["teklifId"] = teklifId;
    return sonuc;
}

bool Database::teklifDurumGuncelle(int teklifId, const QString &durum, const QString &redSebebi)
{
    if (!m_baglantiHazir)
        return false;

    QString sql = "UPDATE dbo.teklifler SET Durum = :durum";
    if (durum == "Kabul Edildi")
        sql += ", KabulTarihi = SYSDATETIME()";
    else if (durum == "Reddedildi")
        sql += ", RedTarihi = SYSDATETIME(), RedSebebi = :redSebebi";
    else if (durum == "Tamamlandı")
        sql += ", TeslimTarihi = SYSDATETIME()";
    sql += " WHERE TeklifId = :teklifId";

    QSqlQuery query(m_db);
    query.prepare(sql);
    query.bindValue(":durum", durum);
    query.bindValue(":teklifId", teklifId);
    if (durum == "Reddedildi")
        query.bindValue(":redSebebi", redSebebi.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : redSebebi);

    if (!query.exec())
    {
        qWarning() << "teklifDurumGuncelle basarisiz:" << query.lastError().text();
        return false;
    }
    return true;
}

QVariantMap Database::musteriListesiGetir(const QString &arama, int sayfaNo, int sayfaBoyutu)
{
    QVariantMap sonuc;
    sonuc["kayitlar"] = QVariantList();
    sonuc["toplamKayit"] = 0;
    sonuc["toplamSayfa"] = 1;
    sonuc["mevcutSayfa"] = 1;

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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
        sonuc["hata"] = "Bu müşteri silinemedi. Muhtemelen bu müşteriye ait kayıtlı teklifler var; "
                        "önce o teklifleri silmeniz veya başka bir müşteriye taşımanız gerekir.";
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

    if (!m_baglantiHazir)
        return sonuc;

    const QString aramaTrim = arama.trimmed();
    QString whereClause;
    if (!aramaTrim.isEmpty())
        whereClause = "WHERE UrunKodu LIKE :aramaLike OR UrunAciklamasi LIKE :aramaLike OR Kategori LIKE :aramaLike";

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

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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
        sonuc["hata"] = "Bu ürün silinemedi. Muhtemelen bu ürünü içeren kayıtlı teklifler var.";
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantList Database::rolListesiGetir()
{
    QVariantList sonuc;
    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        const int kullaniciId = veriQuery.value("KullaniciId").toInt();

        // Kucuk personel sayisi (tipik olarak birkac düzine) icin N+1 sorgu
        // performans acisindan sorun degil; gecmisTekliflerGetir'deki gibi tek
        // sorguya sikistirmaya gerek yok.
        QSqlQuery rolQuery(m_db);
        rolQuery.prepare(
            "SELECT r.RolId, r.RolAdi FROM dbo.kullanici_rolleri kr "
            "INNER JOIN dbo.roller r ON r.RolId = kr.RolId "
            "WHERE kr.KullaniciId = :id ORDER BY r.RolAdi");
        rolQuery.bindValue(":id", kullaniciId);
        rolQuery.exec();

        QVariantList rolIdListesi;
        QStringList rolAdlari;
        while (rolQuery.next())
        {
            rolIdListesi << rolQuery.value("RolId").toInt();
            rolAdlari << rolQuery.value("RolAdi").toString();
        }

        QVariantMap p;
        p["kullaniciId"] = kullaniciId;
        p["adSoyad"] = veriQuery.value("AdSoyad").toString();
        p["kullaniciAdi"] = veriQuery.value("KullaniciAdi").toString();
        p["telefon"] = veriQuery.value("Telefon").toString();
        p["pozisyon"] = veriQuery.value("Pozisyon").toString();
        p["aktifMi"] = veriQuery.value("AktifMi").toBool();
        p["rolIdListesi"] = rolIdListesi;
        p["rolAdlari"] = rolAdlari.join(", ");
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

    if (!m_baglantiHazir)
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

    if (!m_baglantiHazir)
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
    if (!m_baglantiHazir)
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

QVariantMap Database::teklifPdfOlustur(int teklifId)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["dosyaYolu"] = QString();
    sonuc["hata"] = QString();

    if (!m_baglantiHazir)
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    QSqlQuery basQuery(m_db);
    basQuery.prepare(
        "SELECT t.TeklifId, t.OlusturmaTarihi, t.Durum, t.ParaBirimi, t.Dil, "
        "       t.IlgiliKisi, t.IlgiliKisiTelefonu, t.IlgiliKisiEposta, "
        "       t.TeslimatSekli, t.TeslimatYeri, t.GenelIndirimOrani, t.KdvOrani, "
        "       m.FirmaAdi, m.FirmaAdresi, "
        "       k.AdSoyad AS PersonelAdSoyad, "
        "       tt.IndirimliToplam, tt.KdvTutari, tt.GenelToplam, tt.PaketlemeUcreti, tt.TasimaUcreti "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = t.KullaniciId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "WHERE t.TeklifId = :teklifId");
    basQuery.bindValue(":teklifId", teklifId);

    if (!basQuery.exec() || !basQuery.next())
    {
        qWarning() << "teklifPdfOlustur (baslik) basarisiz:" << basQuery.lastError().text();
        sonuc["hata"] = "Teklif bulunamadı.";
        return sonuc;
    }

    const QString firmaAdi = basQuery.value("FirmaAdi").toString();
    const QString firmaAdresi = basQuery.value("FirmaAdresi").toString();
    const QString ilgiliKisi = basQuery.value("IlgiliKisi").toString();
    const QString ilgiliKisiTel = basQuery.value("IlgiliKisiTelefonu").toString();
    const QString ilgiliKisiEposta = basQuery.value("IlgiliKisiEposta").toString();
    const QString teslimatSekli = basQuery.value("TeslimatSekli").toString();
    const QString teslimatYeri = basQuery.value("TeslimatYeri").toString();
    const QString personelAdSoyad = basQuery.value("PersonelAdSoyad").toString();
    const QString paraBirimi = basQuery.value("ParaBirimi").toString();
    const QString olusturmaTarihi = tarihStr(basQuery.value("OlusturmaTarihi"));
    const double genelIndirimOrani = basQuery.value("GenelIndirimOrani").toDouble();
    const double kdvOrani = basQuery.value("KdvOrani").toDouble();
    const double indirimliToplam = basQuery.value("IndirimliToplam").toDouble();
    const double kdvTutari = basQuery.value("KdvTutari").toDouble();
    const double genelToplam = basQuery.value("GenelToplam").toDouble();
    const double paketlemeUcreti = basQuery.value("PaketlemeUcreti").toDouble();
    const double tasimaUcreti = basQuery.value("TasimaUcreti").toDouble();

    QSqlQuery kalemQuery(m_db);
    kalemQuery.prepare(
        "SELECT tk.Adet, tk.BirimFiyat, tk.IndirimliBirimFiyat, tk.ToplamTutar, "
        "       u.UrunKodu, tk.UrunAciklamasi "
        "FROM dbo.teklif_kalemleri tk "
        "LEFT JOIN dbo.urunler u ON u.UrunId = tk.UrunId "
        "WHERE tk.TeklifId = :teklifId "
        "ORDER BY tk.TeklifKalemId");
    kalemQuery.bindValue(":teklifId", teklifId);
    kalemQuery.exec();

    QString kalemSatirlariHtml;
    while (kalemQuery.next())
    {
        kalemSatirlariHtml += QString(
            "<tr>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;'>%1</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;'>%2</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:center;'>%3</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:right;'>%4</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:right;'>%5</td>"
            "</tr>")
            .arg(kalemQuery.value("UrunKodu").toString().toHtmlEscaped())
            .arg(kalemQuery.value("UrunAciklamasi").toString().toHtmlEscaped())
            .arg(kalemQuery.value("Adet").toInt())
            .arg(QString::number(kalemQuery.value("IndirimliBirimFiyat").toDouble(), 'f', 2))
            .arg(QString::number(kalemQuery.value("ToplamTutar").toDouble(), 'f', 2));
    }

    const QString html = QString(
        "<html><body style='font-family:Segoe UI, Arial; font-size:12px; color:#111;'>"
        "<h2 style='margin-bottom:0;'>LİYA LABORATUVAR CİHAZLARI</h2>"
        "<div style='color:#555;margin-bottom:16px;'>Teklif No: <b>#%1</b> &nbsp;&nbsp; Tarih: <b>%2</b></div>"
        "<table style='width:100%;margin-bottom:16px;'>"
        "<tr><td style='width:50%;vertical-align:top;'>"
        "<b>Firma:</b> %3<br/>%4<br/>"
        "<b>İlgili Kişi:</b> %5 %6<br/>%7"
        "</td>"
        "<td style='width:50%;vertical-align:top;'>"
        "<b>Teklifi Yapan:</b> %8<br/>"
        "<b>Teslimat Şekli:</b> %9<br/>"
        "<b>Teslimat Yeri:</b> %10<br/>"
        "<b>Para Birimi:</b> %11"
        "</td></tr></table>"
        "<table style='width:100%;border-collapse:collapse;margin-bottom:16px;'>"
        "<tr style='background:#f0f0f0;'>"
        "<th style='padding:6px 8px;text-align:left;'>Ürün Kodu</th>"
        "<th style='padding:6px 8px;text-align:left;'>Açıklama</th>"
        "<th style='padding:6px 8px;'>Adet</th>"
        "<th style='padding:6px 8px;text-align:right;'>Birim Fiyat (İndirimli)</th>"
        "<th style='padding:6px 8px;text-align:right;'>Toplam</th>"
        "</tr>%12</table>"
        "<table style='margin-left:auto;width:320px;'>"
        "<tr><td>İndirim Oranı</td><td style='text-align:right;'>%13%</td></tr>"
        "<tr><td>İndirimli Toplam</td><td style='text-align:right;'>%14 TL</td></tr>"
        "<tr><td>KDV (%15%)</td><td style='text-align:right;'>%16 TL</td></tr>"
        "<tr><td>Paketleme Ücreti</td><td style='text-align:right;'>%17 TL</td></tr>"
        "<tr><td>Taşıma Ücreti</td><td style='text-align:right;'>%18 TL</td></tr>"
        "<tr style='font-weight:bold;font-size:14px;'><td>GENEL TOPLAM</td><td style='text-align:right;'>%19 TL</td></tr>"
        "</table>"
        "</body></html>")
        .arg(teklifId)
        .arg(olusturmaTarihi)
        .arg(firmaAdi.toHtmlEscaped())
        .arg(firmaAdresi.toHtmlEscaped())
        .arg(ilgiliKisi.toHtmlEscaped())
        .arg(ilgiliKisiTel.toHtmlEscaped())
        .arg(ilgiliKisiEposta.toHtmlEscaped())
        .arg(personelAdSoyad.toHtmlEscaped())
        .arg(teslimatSekli.toHtmlEscaped())
        .arg(teslimatYeri.toHtmlEscaped())
        .arg(paraBirimi)
        .arg(kalemSatirlariHtml)
        .arg(QString::number(genelIndirimOrani, 'f', 1))
        .arg(QString::number(indirimliToplam, 'f', 2))
        .arg(QString::number(kdvOrani, 'f', 1))
        .arg(QString::number(kdvTutari, 'f', 2))
        .arg(QString::number(paketlemeUcreti, 'f', 2))
        .arg(QString::number(tasimaUcreti, 'f', 2))
        .arg(QString::number(genelToplam, 'f', 2));

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/Liya ERP Teklifler";
    QDir().mkpath(klasor);

    QString firmaAdiTemiz = firmaAdi;
    firmaAdiTemiz.replace(QRegularExpression("[\\\\/:*?\"<>|]"), "_");
    const QString dosyaYolu = QString("%1/Teklif_%2_%3.pdf").arg(klasor).arg(teklifId).arg(firmaAdiTemiz);

    QTextDocument belge;
    belge.setHtml(html);

    QPrinter yazici(QPrinter::HighResolution);
    yazici.setOutputFormat(QPrinter::PdfFormat);
    yazici.setOutputFileName(dosyaYolu);
    belge.print(&yazici);

    // Uretim tarihini kaydet (Gecmis Teklifler ekraninda "Üretim Pdf Tarihi" sütunu bunu gösteriyor).
    QSqlQuery guncelle(m_db);
    guncelle.prepare("UPDATE dbo.teklifler SET UretimPdfTarihi = SYSDATETIME() WHERE TeklifId = :id");
    guncelle.bindValue(":id", teklifId);
    guncelle.exec();

    sonuc["basarili"] = true;
    sonuc["dosyaYolu"] = dosyaYolu;
    return sonuc;
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

    if (m_baglantiHazir && musteriId > 0)
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

    const QVariantList kalemler = teklif.value("kalemler").toList();
    if (kalemler.isEmpty())
    {
        sonuc["hata"] = "Sözleşme için sepette en az bir ürün olmalı.";
        return sonuc;
    }

    QString kalemSatirlariHtml;
    for (const QVariant &kalemVar : kalemler)
    {
        const QVariantMap k = kalemVar.toMap();
        kalemSatirlariHtml += QString(
            "<tr>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;'>%1</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:center;'>%2</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:right;'>%3</td>"
            "<td style='padding:6px 8px;border-bottom:1px solid #ddd;text-align:right;'>%4</td>"
            "</tr>")
            .arg(k.value("aciklama").toString().toHtmlEscaped())
            .arg(k.value("adet").toInt())
            .arg(QString::number(k.value("indirimliBirimFiyat").toDouble(), 'f', 2))
            .arg(QString::number(k.value("toplamTutar").toDouble(), 'f', 2));
    }

    const QString bugununTarihi = QDateTime::currentDateTime().toString("dd.MM.yyyy");
    const QString paraBirimi = teklif.value("paraBirimi").toString();
    const QString ilgiliKisi = teklif.value("ilgiliKisi").toString();
    const QString teslimatSekli = teklif.value("teslimatSekli").toString();
    const QString teslimatYeri = teklif.value("teslimatYeri").toString();
    const double genelToplam = teklif.value("genelToplam").toDouble();

    const QString html = QString(
        "<html><body style='font-family:Segoe UI, Arial; font-size:12px; color:#111;'>"
        "<h2 style='margin-bottom:0;'>SATIŞ SÖZLEŞMESİ</h2>"
        "<div style='color:#555;margin-bottom:16px;'>Tarih: <b>%1</b></div>"
        "<p><b>Satıcı:</b> Liya Laboratuvar Cihazları<br/>"
        "<b>Alıcı:</b> %2<br/>%3"
        "<b>İlgili Kişi:</b> %4</p>"
        "<p>Aşağıda belirtilen ürün/hizmetler, taraflar arasında mutabık kalınan"
        " şartlarla satışa konu edilmiştir:</p>"
        "<table style='width:100%;border-collapse:collapse;margin-bottom:16px;'>"
        "<tr style='background:#f0f0f0;'>"
        "<th style='padding:6px 8px;text-align:left;'>Açıklama</th>"
        "<th style='padding:6px 8px;'>Adet</th>"
        "<th style='padding:6px 8px;text-align:right;'>Birim Fiyat</th>"
        "<th style='padding:6px 8px;text-align:right;'>Toplam</th>"
        "</tr>%5</table>"
        "<p><b>Teslimat Şekli:</b> %6<br/>"
        "<b>Teslimat Yeri:</b> %7<br/>"
        "<b>Para Birimi:</b> %8</p>"
        "<table style='margin-left:auto;width:260px;'>"
        "<tr style='font-weight:bold;font-size:14px;'><td>GENEL TOPLAM</td><td style='text-align:right;'>%9 %8</td></tr>"
        "</table>"
        "<p style='margin-top:32px;'>Taraflar işbu sözleşme şartlarını kabul ve taahhüt eder.</p>"
        "<table style='width:100%;margin-top:24px;'>"
        "<tr><td style='width:50%;'>Satıcı<br/><br/>__________________</td>"
        "<td style='width:50%;'>Alıcı<br/><br/>__________________</td></tr>"
        "</table>"
        "</body></html>")
        .arg(bugununTarihi)
        .arg(firmaAdi.toHtmlEscaped())
        .arg(firmaAdresi.isEmpty() ? QString() : (firmaAdresi.toHtmlEscaped() + "<br/>"))
        .arg(ilgiliKisi.toHtmlEscaped())
        .arg(kalemSatirlariHtml)
        .arg(teslimatSekli.toHtmlEscaped())
        .arg(teslimatYeri.toHtmlEscaped())
        .arg(paraBirimi)
        .arg(QString::number(genelToplam, 'f', 2));

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation) + "/Liya ERP Teklifler";
    QDir().mkpath(klasor);

    QString firmaAdiTemiz = firmaAdi;
    firmaAdiTemiz.replace(QRegularExpression("[\\\\/:*?\"<>|]"), "_");
    const QString dosyaYolu = QString("%1/Satis_Sozlesmesi_%2_%3.pdf")
        .arg(klasor)
        .arg(firmaAdiTemiz)
        .arg(QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss"));

    QTextDocument belge;
    belge.setHtml(html);

    QPrinter yazici(QPrinter::HighResolution);
    yazici.setOutputFormat(QPrinter::PdfFormat);
    yazici.setOutputFileName(dosyaYolu);
    belge.print(&yazici);

    sonuc["basarili"] = true;
    sonuc["dosyaYolu"] = dosyaYolu;
    return sonuc;
}
