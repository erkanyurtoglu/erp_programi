#include "AramaSorgulari.h"
#include "SqlYardimcilari.h"
// teklifListesiSorgusu, Teklif No'yu PDF'tekiyle AYNI bicimde uretir.
#include "TeklifPdfOlusturucu.h"

#include <QSqlDatabase>
#include <QDateTime>
#include <QElapsedTimer>
#include <QRegularExpression>
#include <utility>
#include <QSqlQuery>
#include <QSqlError>
#include <QStringList>
#include <QHash>
#include <QVariantMap>
#include <QDebug>
#include <algorithm>
#include <cmath>

namespace
{
    // Arsivlenmis (AktifMi = 0) kayitlari disarida brakan WHERE parcasi.
    // Sutun semada yoksa (db/13_musteri_urun_arsiv.sql calistirilmamissa) bos
    // doner: program eski semayla da calismaya devam eder, yalnizca arsivleme
    // ozelligi devre disi kalir.
    QString arsivKosulu(QSqlDatabase &db, const QString &tablo, const QString &takmaAd,
                        bool arsivliDahil)
    {
        if (arsivliDahil || !semaKolonuVarMi(db, tablo, QStringLiteral("AktifMi")))
            return QString();
        const QString onek = takmaAd.isEmpty() ? QString() : takmaAd + QLatin1Char('.');
        return onek + QStringLiteral("AktifMi = 1");
    }

    // AktifMi sutunu yoksa kayit her zaman "aktif" sayilir -- ekranda her
    // seyin pasif gorunmesi yerine eski (arsivsiz) davranis korunur.
    bool aktifMiOku(const QSqlQuery &query, bool kolonVarMi)
    {
        return kolonVarMi ? query.value("AktifMi").toBool() : true;
    }

    // Verilen kosullari "WHERE a AND b" haline getirir (bos olanlari atar).
    QString whereBirlestir(const QStringList &kosullar)
    {
        QStringList dolu;
        for (const QString &k : kosullar)
            if (!k.trimmed().isEmpty())
                dolu << QLatin1Char('(') + k + QLatin1Char(')');
        if (dolu.isEmpty())
            return QString();
        return QStringLiteral("WHERE ") + dolu.join(QStringLiteral(" AND "));
    }

    // COUNT sonucundan sayfa sayisini hesaplar ve istenen sayfayi sinirlar.
    int sayfayiSinirla(int toplamKayit, int sayfaBoyutu, int sayfaNo, int &toplamSayfaOut)
    {
        toplamSayfaOut = std::max(
            1, static_cast<int>(std::ceil(toplamKayit / static_cast<double>(std::max(1, sayfaBoyutu)))));
        return std::clamp(sayfaNo, 1, toplamSayfaOut);
    }

    QVariantMap bosListeSonucu()
    {
        QVariantMap sonuc;
        sonuc["kayitlar"] = QVariantList();
        sonuc["toplamKayit"] = 0;
        sonuc["toplamSayfa"] = 1;
        sonuc["mevcutSayfa"] = 1;
        return sonuc;
    }
}

QVariantList musteriAraSorgusu(QSqlDatabase &db, const QString &arama, int limit)
{
    QVariantList sonuc;
    const QString aramaTrim = arama.trimmed();
    // Arsivlenmis musteriler yeni tekliflerde secilemez (gecmis teklifler
    // etkilenmez -- satir yerinde durur, bkz. db/13_musteri_urun_arsiv.sql).
    const QString arsiv = arsivKosulu(db, QStringLiteral("dbo.musteriler"), QString(), false);

    QSqlQuery query(db);
    if (aramaTrim.isEmpty())
    {
        // Arama kutusu bosken listeyi bomboş gostermemek icin en son eklenen
        // musterileri getiriyoruz (kullanici genelde en yeni firmalarla calisir).
        query.prepare(QString(
            "SELECT TOP (%1) MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
            "       IlgiliKisi, IlgiliKisiTelefonu "
            "FROM dbo.musteriler %2 ORDER BY MusteriId DESC")
            .arg(limit).arg(whereBirlestir({arsiv})));
    }
    else
    {
        // LIKE deseni ESCAPE ile baglanir: kullanici "%" veya "_" yazdiginda
        // bunlar joker degil, duz karakter olarak aranir.
        query.prepare(QString(
            "SELECT TOP (%1) MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
            "       IlgiliKisi, IlgiliKisiTelefonu "
            "FROM dbo.musteriler %2 "
            "ORDER BY FirmaAdi")
            .arg(limit)
            .arg(whereBirlestir({arsiv,
                                 "FirmaAdi LIKE :aramaLike ESCAPE N'\\' "
                                 "OR IlgiliKisi LIKE :aramaLike ESCAPE N'\\'"})));
        query.bindValue(":aramaLike", likeDeseni(aramaTrim));
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

QVariantList urunAraSorgusu(QSqlDatabase &db, const QString &arama, int limit, const QString &dil)
{
    QVariantList sonuc;

    const QString aramaTrim = arama.trimmed();
    const bool ingilizce = dil.compare("EN", Qt::CaseInsensitive) == 0;

    // "MANUEL-<teklifId>" kodlu satirlar, sepete manuel eklenen kalemler icin
    // FOREIGN KEY zorunlulugu yuzunden urunler tablosuna yazilan, teklife ozel
    // gecici satirlardir -- normal urun katalogu arama/listelemesinde gorunmemeli.
    const QString manuelHaric = "UrunKodu IS NULL OR UrunKodu NOT LIKE N'MANUEL%'";
    const QString arsiv = arsivKosulu(db, QStringLiteral("dbo.urunler"), QString(), false);

    QSqlQuery query(db);
    if (aramaTrim.isEmpty())
    {
        query.prepare(QString(
            "SELECT TOP (%1) UrunId, UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, "
            "       BirimFiyat, ParaBirimi, GuncelMaliyetTL "
            "FROM dbo.urunler %2 ORDER BY UrunId DESC")
            .arg(limit).arg(whereBirlestir({manuelHaric, arsiv})));
    }
    else
    {
        // "ORDER BY UrunKodu" ile nvarchar(MAX) sutunlari ayni SELECT'te
        // toplamak tablonun tamamini LOB'larla birlikte siralatiyor (bkz.
        // urunListesiSorgusu'ndaki ayrintili not). Once anahtarlari
        // siralayip sinirliyoruz, genis sutunlari sonra okuyoruz.
        query.prepare(QString(
            "SELECT u.UrunId, u.UrunKodu, u.Kategori, u.UrunAciklamasi, u.UrunAciklamasiEn, "
            "       u.BirimFiyat, u.ParaBirimi, u.GuncelMaliyetTL "
            "FROM dbo.urunler AS u "
            "INNER JOIN ("
            "    SELECT TOP (%1) UrunId FROM dbo.urunler %2 "
            "    ORDER BY UrunKodu"
            ") AS secim ON secim.UrunId = u.UrunId "
            "ORDER BY u.UrunKodu")
            .arg(limit)
            .arg(whereBirlestir({manuelHaric, arsiv,
                                 "UrunKodu LIKE :aramaLike ESCAPE N'\\' "
                                 "OR UrunAciklamasi LIKE :aramaLike ESCAPE N'\\' "
                                 "OR UrunAciklamasiEn LIKE :aramaLike ESCAPE N'\\'"})));
        query.bindValue(":aramaLike", likeDeseni(aramaTrim));
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
        // Sepete eklenen kalem her iki dili de tasir; teklif dili sonradan
        // degistirilse bile sepetteki aciklama secili dile gore gosterilir.
        u["urunAciklamasiTr"] = aciklamaTr;
        u["urunAciklamasiEn"] = aciklamaEn;
        u["birimFiyat"] = query.value("BirimFiyat").toDouble();
        u["paraBirimi"] = query.value("ParaBirimi").toString();
        u["maliyet"] = query.value("GuncelMaliyetTL").isNull() ? 0.0 : query.value("GuncelMaliyetTL").toDouble();
        sonuc << u;
    }
    return sonuc;
}

QVariantMap musteriListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                   int sayfaNo, int sayfaBoyutu, bool arsivliDahil)
{
    QVariantMap sonuc = bosListeSonucu();

    const QString aramaTrim = arama.trimmed();
    const bool arsivKolonu = semaKolonuVarMi(db, QStringLiteral("dbo.musteriler"),
                                             QStringLiteral("AktifMi"));
    const QString arsiv = arsivKosulu(db, QStringLiteral("dbo.musteriler"), QString(), arsivliDahil);

    // Arama artik telefon ve vergi numarasini da kapsiyor: kullanicilar bir
    // firmayi siklikla elindeki telefon ya da fatura bilgisiyle ariyor.
    QString aramaKosulu;
    if (!aramaTrim.isEmpty())
    {
        aramaKosulu = "FirmaAdi LIKE :aramaLike ESCAPE N'\\' "
                      "OR IlgiliKisi LIKE :aramaLike ESCAPE N'\\' "
                      "OR FirmaEposta LIKE :aramaLike ESCAPE N'\\' "
                      "OR FirmaTelefonu LIKE :aramaLike ESCAPE N'\\' "
                      "OR IlgiliKisiTelefonu LIKE :aramaLike ESCAPE N'\\' "
                      "OR VergiNumarasi LIKE :aramaLike ESCAPE N'\\'";
    }
    const QString whereClause = whereBirlestir({arsiv, aramaKosulu});

    QSqlQuery sayimQuery(db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.musteriler %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));

    if (!sayimQuery.exec())
    {
        qWarning() << "musteriListesiSorgusu (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    int toplamSayfa = 1;
    sayfaNo = sayfayiSinirla(toplamKayit, sayfaBoyutu, sayfaNo, toplamSayfa);

    QSqlQuery veriQuery(db);
    veriQuery.prepare(QString(
        "SELECT MusteriId, FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, "
        "       VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu%1 "
        "FROM dbo.musteriler %2 "
        "ORDER BY FirmaAdi "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY")
        .arg(arsivKolonu ? QStringLiteral(", AktifMi") : QString())
        .arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "musteriListesiSorgusu (veri) basarisiz:" << veriQuery.lastError().text();
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
        m["aktifMi"] = aktifMiOku(veriQuery, arsivKolonu);
        kayitlar << m;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantMap urunListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                int sayfaNo, int sayfaBoyutu, bool arsivliDahil)
{
    QVariantMap sonuc = bosListeSonucu();

    const QString aramaTrim = arama.trimmed();
    const bool arsivKolonu = semaKolonuVarMi(db, QStringLiteral("dbo.urunler"),
                                             QStringLiteral("AktifMi"));

    // "MANUEL-<teklifId>" kodlu satirlar tekliflere ozel gecici kayitlardir,
    // urun katalogu listesinde gorunmemeli (bkz. urunAraSorgusu ustundeki not).
    // "IS NULL OR": NULL NOT LIKE ... NULL doner; aksi halde kodu girilmemis
    // (ör. eski programdan gocen) urunler listede hic gorunmezdi.
    const QString manuelHaric = "UrunKodu IS NULL OR UrunKodu NOT LIKE N'MANUEL%'";
    const QString arsiv = arsivKosulu(db, QStringLiteral("dbo.urunler"), QString(), arsivliDahil);

    QString aramaKosulu;
    if (!aramaTrim.isEmpty())
    {
        aramaKosulu = "UrunKodu LIKE :aramaLike ESCAPE N'\\' "
                      "OR UrunAciklamasi LIKE :aramaLike ESCAPE N'\\' "
                      "OR UrunAciklamasiEn LIKE :aramaLike ESCAPE N'\\' "
                      "OR Kategori LIKE :aramaLike ESCAPE N'\\'";
    }
    const QString whereClause = whereBirlestir({manuelHaric, arsiv, aramaKosulu});

    QSqlQuery sayimQuery(db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.urunler %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));

    if (!sayimQuery.exec())
    {
        qWarning() << "urunListesiSorgusu (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    int toplamSayfa = 1;
    sayfaNo = sayfayiSinirla(toplamKayit, sayfaBoyutu, sayfaNo, toplamSayfa);

    // ONEMLI (performans): UrunAciklamasi ve UrunAciklamasiEn nvarchar(MAX)'tir.
    // "ORDER BY UrunKodu ... OFFSET/FETCH" bu sutunlarla ayni SELECT'te olursa
    // SQL Server tablonun TAMAMINI (LOB icerikleriyle birlikte) siralamak zorunda
    // kaliyor -- olculen sure: 25 saniye. Bu sure boyunca UI thread'i tamamen
    // blokeli kaliyordu ("Yanit Vermiyor").
    //
    // Cozum "ertelenmis join" (deferred join): once SADECE anahtar sutunu
    // siralayip sayfayi seciyoruz (LOB tasinmaz, ~12 ms), sonra secilen 50 satirin
    // genis sutunlarini anahtar uzerinden okuyoruz. Olculen sure: ~42 ms.
    QSqlQuery veriQuery(db);
    veriQuery.prepare(QString(
        "SELECT u.UrunId, u.UrunKodu, u.Kategori, u.UrunAciklamasi, u.UrunAciklamasiEn, "
        "       u.BirimFiyat, u.GuncelMaliyetTL%1 "
        "FROM dbo.urunler AS u "
        "INNER JOIN ("
        "    SELECT UrunId FROM dbo.urunler %2 "
        "    ORDER BY UrunKodu "
        "    OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY"
        ") AS sayfa ON sayfa.UrunId = u.UrunId "
        "ORDER BY u.UrunKodu")
        .arg(arsivKolonu ? QStringLiteral(", u.AktifMi") : QString())
        .arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "urunListesiSorgusu (veri) basarisiz:" << veriQuery.lastError().text();
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
        u["aktifMi"] = aktifMiOku(veriQuery, arsivKolonu);
        kayitlar << u;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantMap personelListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                    int sayfaNo, int sayfaBoyutu, bool pasifDahil)
{
    QVariantMap sonuc = bosListeSonucu();

    const QString aramaTrim = arama.trimmed();

    // Personelde AktifMi sutunu bastan beri var (kalici silme yerine kullanilir).
    const QString pasifHaric = pasifDahil ? QString() : QStringLiteral("AktifMi = 1");

    // Arama pozisyon ve telefonu da kapsiyor ("Üretim" yazip o birimdeki
    // personeli bulmak en sik ihtiyac).
    QString aramaKosulu;
    if (!aramaTrim.isEmpty())
    {
        aramaKosulu = "AdSoyad LIKE :aramaLike ESCAPE N'\\' "
                      "OR KullaniciAdi LIKE :aramaLike ESCAPE N'\\' "
                      "OR Pozisyon LIKE :aramaLike ESCAPE N'\\' "
                      "OR Telefon LIKE :aramaLike ESCAPE N'\\'";
    }
    const QString whereClause = whereBirlestir({pasifHaric, aramaKosulu});

    QSqlQuery sayimQuery(db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.kullanicilar %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));

    if (!sayimQuery.exec())
    {
        qWarning() << "personelListesiSorgusu (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    int toplamSayfa = 1;
    sayfaNo = sayfayiSinirla(toplamKayit, sayfaBoyutu, sayfaNo, toplamSayfa);

    QSqlQuery veriQuery(db);
    veriQuery.prepare(QString(
        "SELECT KullaniciId, AdSoyad, KullaniciAdi, Telefon, Pozisyon, AktifMi "
        "FROM dbo.kullanicilar %1 "
        "ORDER BY AdSoyad "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "personelListesiSorgusu (veri) basarisiz:" << veriQuery.lastError().text();
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
        QSqlQuery rolQuery(db);
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
            qWarning() << "personelListesiSorgusu (roller) basarisiz:" << rolQuery.lastError().text();
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

QVariantMap tedarikciListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                    int sayfaNo, int sayfaBoyutu, bool arsivliDahil)
{
    QVariantMap sonuc = bosListeSonucu();

    const QString aramaTrim = arama.trimmed();
    const bool arsivKolonu = semaKolonuVarMi(db, QStringLiteral("dbo.tedarikciler"),
                                              QStringLiteral("AktifMi"));
    // db/15_tedarikci.sql calistirilmamissa liste yine de acilir; ilgili kisi
    // telefonu bos gorunur.
    const bool ilgiliTelKolonu = semaKolonuVarMi(db, QStringLiteral("dbo.tedarikciler"),
                                                  QStringLiteral("IlgiliKisiTelefonu"));
    const QString arsiv = arsivKosulu(db, QStringLiteral("dbo.tedarikciler"), QString(), arsivliDahil);

    QString aramaKosulu;
    if (!aramaTrim.isEmpty())
    {
        aramaKosulu = "FirmaAdi LIKE :aramaLike ESCAPE N'\\' "
                      "OR IlgiliKisi LIKE :aramaLike ESCAPE N'\\' "
                      "OR Eposta LIKE :aramaLike ESCAPE N'\\' "
                      "OR Telefon LIKE :aramaLike ESCAPE N'\\' "
                      "OR VergiNumarasi LIKE :aramaLike ESCAPE N'\\'";
    }
    const QString whereClause = whereBirlestir({arsiv, aramaKosulu});

    QSqlQuery sayimQuery(db);
    sayimQuery.prepare(QString("SELECT COUNT(*) FROM dbo.tedarikciler %1").arg(whereClause));
    if (!aramaTrim.isEmpty())
        sayimQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));

    if (!sayimQuery.exec())
    {
        qWarning() << "tedarikciListesiSorgusu (sayim) basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    int toplamSayfa = 1;
    sayfaNo = sayfayiSinirla(toplamKayit, sayfaBoyutu, sayfaNo, toplamSayfa);

    QSqlQuery veriQuery(db);
    veriQuery.prepare(QString(
        "SELECT TedarikciId, FirmaAdi, Adres, Telefon, Eposta, VergiDairesi, VergiNumarasi, IlgiliKisi, "
        "       %1 AS IlgiliKisiTelefonu%2 "
        "FROM dbo.tedarikciler %3 "
        "ORDER BY FirmaAdi "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY")
        .arg(ilgiliTelKolonu ? QStringLiteral("IlgiliKisiTelefonu") : QStringLiteral("CAST(NULL AS NVARCHAR(50))"))
        .arg(arsivKolonu ? QStringLiteral(", AktifMi") : QString())
        .arg(whereClause));
    if (!aramaTrim.isEmpty())
        veriQuery.bindValue(":aramaLike", likeDeseni(aramaTrim));
    veriQuery.bindValue(":offset", (sayfaNo - 1) * sayfaBoyutu);
    veriQuery.bindValue(":sayfaBoyutu", sayfaBoyutu);

    if (!veriQuery.exec())
    {
        qWarning() << "tedarikciListesiSorgusu (veri) basarisiz:" << veriQuery.lastError().text();
        return sonuc;
    }

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        QVariantMap m;
        m["tedarikciId"] = veriQuery.value("TedarikciId").toInt();
        m["firmaAdi"] = veriQuery.value("FirmaAdi").toString();
        m["firmaAdresi"] = veriQuery.value("Adres").toString();
        m["firmaTelefonu"] = veriQuery.value("Telefon").toString();
        m["firmaEposta"] = veriQuery.value("Eposta").toString();
        m["vergiDairesi"] = veriQuery.value("VergiDairesi").toString();
        m["vergiNumarasi"] = veriQuery.value("VergiNumarasi").toString();
        m["ilgiliKisi"] = veriQuery.value("IlgiliKisi").toString();
        m["ilgiliKisiTelefonu"] = veriQuery.value("IlgiliKisiTelefonu").toString();
        m["aktifMi"] = aktifMiOku(veriQuery, arsivKolonu);
        kayitlar << m;
    }

    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

QVariantList rolListesiSorgusu(QSqlDatabase &db)
{
    QVariantList sonuc;
    QSqlQuery query(db);
    query.prepare("SELECT RolId, RolAdi FROM dbo.roller ORDER BY RolAdi");
    if (!query.exec())
    {
        qWarning() << "rolListesiSorgusu basarisiz:" << query.lastError().text();
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

// ----------------------------------------------------------------------
// Gecmis Teklifler listesi. Eskiden Database icinde, ANA baglanti uzerinden
// ve UI thread'inde calisiyordu: 3000+ kayitli listede arama yapildiginda
// (teklif_kalemleri uzerindeki EXISTS + LIKE yuzunden) pencere "Yanit
// Vermiyor" durumuna dusuyordu. Artik diger sayfali listelerle ayni worker
// thread'i + ayri ODBC baglantisi uzerinde calisir.
// ----------------------------------------------------------------------
namespace
{
    QString teklifTarihStr(const QVariant &v)
    {
        if (v.isNull())
            return QString();
        return v.toDateTime().date().toString("dd.MM.yyyy");
    }

    QString teklifTarihSaatStr(const QVariant &v)
    {
        if (v.isNull())
            return QString();
        return v.toDateTime().toString("dd.MM.yyyy HH:mm");
    }

    // Kullanicinin gordugu tek numara ("1203", "1203/Rev.2"); bicim PDF'tekiyle ayni.
    QString teklifNoMetniBicimle(int teklifNo, int revizyonNo)
    {
        QVariantMap veri;
        veri["kokTeklifNo"] = teklifNo;
        veri["revizyonNo"] = revizyonNo;
        return TeklifPdfOlusturucu::teklifNoMetni(teklifNo, veri);
    }

    // dbo.teklifler.TeklifNo sutunu yoksa (db/10 calistirilmamissa) numara
    // eskisi gibi kok TeklifId'den turetilir -- bkz. Database::teklifNoSql.
    QString teklifNoSqlIfadesi(QSqlDatabase &db, const QString &alias)
    {
        const QString eskiKural = QString("ISNULL(%1.AnaTeklifId, %1.TeklifId)").arg(alias);
        return semaKolonuVarMi(db, QStringLiteral("teklifler"), QStringLiteral("TeklifNo"))
            ? QString("ISNULL(%1.TeklifNo, %2)").arg(alias, eskiKural)
            : eskiKural;
    }

    // Tarih + arama + durum filtresi; COUNT, veri ve toplam sorgularinda AYNI
    // sekilde kullanilir (eski Database::whereKosullariniOlustur).
    void teklifWhereKosullari(QSqlDatabase &db,
                              const QString &arama,
                              const QString &tarihFiltresi,
                              const QString &baslangicTarihi,
                              const QString &bitisTarihi,
                              const QString &durumFiltresi,
                              QString &whereClauseOut,
                              QVariantMap &parametrelerOut)
    {
        QStringList kosullar;

        // "N Gun" = bugun dahil son N takvim gunu ("1 Gun" yalnizca bugun).
        static const QHash<QString, int> gunFiltreleri = {
            { QString::fromUtf8("1 GÃ¼n"), 1 }, { QString::fromUtf8("1 Hafta"), 7 },
            { QString::fromUtf8("15 GÃ¼n"), 15 }, { QString::fromUtf8("30 GÃ¼n"), 30 },
        };
        if (gunFiltreleri.contains(tarihFiltresi))
        {
            kosullar << QString("t.OlusturmaTarihi >= DATEADD(day, -%1, CAST(GETDATE() AS date))")
                            .arg(gunFiltreleri.value(tarihFiltresi) - 1);
        }
        else if (tarihFiltresi == QString::fromUtf8("Ã–zel Tarih")
                 && !baslangicTarihi.isEmpty() && !bitisTarihi.isEmpty())
        {
            // Ters secilmisse (baslangic > bitis) yer degistirilir.
            QString bas = baslangicTarihi;
            QString bit = bitisTarihi;
            if (bas > bit)
                std::swap(bas, bit);
            kosullar << "CAST(t.OlusturmaTarihi AS date) BETWEEN :baslangic AND :bitis";
            parametrelerOut[":baslangic"] = bas;
            parametrelerOut[":bitis"] = bit;
        }
        else if (tarihFiltresi == QString::fromUtf8("Ã–zel Tarih") && !baslangicTarihi.isEmpty())
        {
            kosullar << "CAST(t.OlusturmaTarihi AS date) >= :baslangic";
            parametrelerOut[":baslangic"] = baslangicTarihi;
        }
        else if (tarihFiltresi == QString::fromUtf8("Ã–zel Tarih") && !bitisTarihi.isEmpty())
        {
            kosullar << "CAST(t.OlusturmaTarihi AS date) <= :bitis";
            parametrelerOut[":bitis"] = bitisTarihi;
        }

        const QString aramaTrim = arama.trimmed();
        if (!aramaTrim.isEmpty())
        {
            // Numara aramasi ekranda gorunen Teklif No uzerinden yapilir.
            static const QRegularExpression teklifNoDeseni(
                QStringLiteral("^#?(\\d+)(?:\\s*(?:[/-]\\s*(?:rev\\.?|r)?|rev\\.?|r)\\s*(\\d+))?$"),
                QRegularExpression::CaseInsensitiveOption);
            const QRegularExpressionMatch noEslesmesi = teklifNoDeseni.match(aramaTrim);
            const bool noEslesiyorMu = noEslesmesi.hasMatch();
            const bool revizyonVarMi = noEslesiyorMu && !noEslesmesi.captured(2).isEmpty();

            const QString noSql = teklifNoSqlIfadesi(db, QStringLiteral("t"));
            QString aramaKosulu = "(";
            if (noEslesiyorMu)
            {
                aramaKosulu += revizyonVarMi
                    ? QString("(%1 = :kokTeklifNo AND t.RevizyonNo = :revizyonNo) OR ").arg(noSql)
                    : QString("%1 = :kokTeklifNo OR ").arg(noSql);
            }

            aramaKosulu +=
                "m.FirmaAdi LIKE :aramaLike OR "
                "p.AdSoyad LIKE :aramaLike OR "
                "EXISTS (SELECT 1 FROM dbo.teklif_kalemleri tk "
                "        INNER JOIN dbo.urunler u ON u.UrunId = tk.UrunId "
                "        WHERE tk.TeklifId = t.TeklifId "
                "          AND (tk.UrunAciklamasi LIKE :aramaLike OR u.UrunAciklamasi LIKE :aramaLike "
                "               OR u.UrunAciklamasiEn LIKE :aramaLike OR u.UrunKodu LIKE :aramaLike))"
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

        if (!durumFiltresi.trimmed().isEmpty())
        {
            kosullar << "t.Durum = :durum";
            parametrelerOut[":durum"] = durumFiltresi.trimmed();
        }

        whereClauseOut = kosullar.isEmpty() ? QString() : ("WHERE " + kosullar.join(" AND "));
    }
}

QVariantMap teklifListesiSorgusu(QSqlDatabase &db, const QString &arama,
                                 const QString &tarihFiltresi,
                                 const QString &baslangicTarihi,
                                 const QString &bitisTarihi,
                                 int sayfaNo, int sayfaBoyutu,
                                 const QString &durumFiltresi)
{
    QVariantMap sonuc = bosListeSonucu();
    sonuc["paraBirimiToplamlari"] = QVariantList();

    // Sorgu UC parcadan olusuyor (sayim / veri / para birimi toplami). Hangisinin
    // yavasladigi gunlukten dogrudan okunabilsin diye her biri ayri olculur.
    QElapsedTimer olcum;
    olcum.start();
    qint64 sayimMs = 0, veriMs = 0, toplamMs = 0;

    QString whereClause;
    QVariantMap parametreler;
    teklifWhereKosullari(db, arama, tarihFiltresi, baslangicTarihi, bitisTarihi,
                         durumFiltresi, whereClause, parametreler);

    // 1) Toplam kayit sayisi (sayfalama hesabi icin).
    const QString sayimSorgusu = QString(
        "SELECT COUNT(*) "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "%1").arg(whereClause);

    QSqlQuery sayimQuery(db);
    sayimQuery.prepare(sayimSorgusu);
    for (auto it = parametreler.constBegin(); it != parametreler.constEnd(); ++it)
        sayimQuery.bindValue(it.key(), it.value());

    if (!sayimQuery.exec())
    {
        qWarning() << "Teklif sayisi sorgusu basarisiz:" << sayimQuery.lastError().text();
        return sonuc;
    }
    sayimMs = olcum.restart();

    int toplamKayit = 0;
    if (sayimQuery.next())
        toplamKayit = sayimQuery.value(0).toInt();

    int toplamSayfa = 1;
    sayfaNo = sayfayiSinirla(toplamKayit, sayfaBoyutu, sayfaNo, toplamSayfa);

    // 2) Sayfa verisi. KopyaKaynakTeklifId sutunu 07 numarali script ile SONRADAN
    // eklendigi icin sorguya ancak gercekten varsa giriyor.
    const bool kopyaKolonuVar = semaKolonuVarMi(db, QStringLiteral("teklifler"),
                                                QStringLiteral("KopyaKaynakTeklifId"));
    const QString kopyaSutunu = kopyaKolonuVar
        ? QString("t.KopyaKaynakTeklifId, %1 AS KopyaKaynakNo, kk.RevizyonNo AS KopyaKaynakRevizyonNo")
              .arg(teklifNoSqlIfadesi(db, QStringLiteral("kk")))
        : QStringLiteral("CAST(NULL AS INT) AS KopyaKaynakTeklifId, CAST(NULL AS INT) AS KopyaKaynakNo, "
                         "CAST(NULL AS INT) AS KopyaKaynakRevizyonNo");
    const QString kopyaJoin = kopyaKolonuVar
        ? QStringLiteral("LEFT JOIN dbo.teklifler kk ON kk.TeklifId = t.KopyaKaynakTeklifId ")
        : QString();
    // ONCE SAYFALA, SONRA ZENGINLESTIR.
    //
    // Eskiden tek bir sorguda hem filtreleme hem de iki OUTER APPLY birlikte
    // vardi. Ozellikle "son" APPLY'i (revizyon zincirinin en son kaydi) OR'lu
    // kosulu yuzunden index kullanamiyor ve FILTREYE UYAN HER SATIR icin
    // teklifler tablosunu bastan tariyordu: "Biten Tekliflerim" (667 kayit)
    // icin bu, 3297 satirlik tablonun yuz binlerce kez taranmasi demekti ve
    // sorgu 36 SANIYE suruyordu (bkz. gunlukteki [olcum] kayitlari) -- ustelik
    // ekranda yalnizca 50 satir gosterilecekken.
    //
    // Artik once SADECE id'ler sayfalanir (ucuz: filtre + siralama + OFFSET),
    // pahali APPLY/JOIN'ler ise yalnizca o 50 satir icin calisir.
    const QString sayfaIdleri = QString(
        "SELECT t.TeklifId, t.OlusturmaTarihi "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "%1 "
        "ORDER BY t.OlusturmaTarihi DESC "
        "OFFSET :offset ROWS FETCH NEXT :sayfaBoyutu ROWS ONLY").arg(whereClause);

    // Govde once doldurulur, CTE SONRA basa eklenir: boylece filtre metni
    // (whereClause) arg() tarafindan hic yorumlanmaz.
    const QString veriGovdesi = QString(
        "SELECT t.TeklifId, m.FirmaAdi, t.OlusturmaTarihi, t.KabulTarihi, "
        "       t.TeslimatTarihi, t.TeslimTarihi, t.UretimPdfTarihi, "
        "       p.KullaniciAdi AS PersonelKullaniciAdi, p.AdSoyad AS PersonelAdSoyad, "
        "       t.Durum, t.RedSebebi, sb.Aciklamalar, "
        // DIKKAT: yer tutucu numaralari asagidaki .arg() cagrisinin SIRASIYLA
        // eslesmelidir. QString'in cok argumanli arg()'i, en kucuk numarali
        // yer tutucudan baslayarak sirayla doldurur -- yani numaralari atlamak
        // (ör. %1'siz birakmak) tum argumanlari kaydirir ve sorguyu bozar.
        "       t.MusteriNotu, t.UretimNotu, t.AnaTeklifId, t.RevizyonNo, %3 AS TeklifNo, %1, "
        "       son.TeklifId AS GuncelTeklifId, son.RevizyonNo AS GuncelRevizyonNo, "
        "       t.ParaBirimi, tt.GenelToplam "
        "FROM sayfa s "
        "INNER JOIN dbo.teklifler t ON t.TeklifId = s.TeklifId "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "%2"
        "OUTER APPLY ("
        "    SELECT TOP 1 sbi.Aciklamalar "
        "    FROM dbo.sevk_bilgileri sbi "
        "    WHERE sbi.TeklifId = t.TeklifId "
        "    ORDER BY sbi.SevkBilgileriId DESC"
        ") sb "
        // Bu satirin ait oldugu revizyon zincirinin EN SON kaydi.
        "OUTER APPLY ("
        "    SELECT TOP 1 g.TeklifId, g.RevizyonNo "
        "    FROM dbo.teklifler g "
        "    WHERE g.TeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
        "       OR g.AnaTeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
        "    ORDER BY g.RevizyonNo DESC"
        ") son "
        // Filtre (ve sayfalama) zaten "sayfa" icinde uygulandi; burada yalnizca
        // satirlarin sirasi korunur.
        "ORDER BY t.OlusturmaTarihi DESC")
        // %1 = kopya sutunlari, %2 = kopya JOIN'i, %3 = Teklif No ifadesi.
        // (Filtre artik burada degil, asagidaki "sayfa" CTE'sinin icinde.)
        .arg(kopyaSutunu, kopyaJoin, teklifNoSqlIfadesi(db, QStringLiteral("t")));

    const QString veriSorgusu =
        QStringLiteral("WITH sayfa AS (") + sayfaIdleri + QStringLiteral(") ") + veriGovdesi;

    QSqlQuery veriQuery(db);
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
    veriMs = olcum.restart();

    QVariantList kayitlar;
    while (veriQuery.next())
    {
        QVariantMap kayit;
        kayit["teklifId"] = veriQuery.value("TeklifId").toInt();
        kayit["firmaAdi"] = veriQuery.value("FirmaAdi").toString();
        kayit["teklifTarihi"] = teklifTarihStr(veriQuery.value("OlusturmaTarihi"));
        kayit["kabulTarihi"] = teklifTarihStr(veriQuery.value("KabulTarihi"));
        kayit["teslimatTarihi"] = teklifTarihStr(veriQuery.value("TeslimatTarihi"));
        kayit["teslimTarihi"] = teklifTarihStr(veriQuery.value("TeslimTarihi"));
        kayit["uretimPdfTarihi"] = teklifTarihSaatStr(veriQuery.value("UretimPdfTarihi"));
        kayit["personelKullaniciAdi"] = veriQuery.value("PersonelKullaniciAdi").toString();
        // Listede kisa kullanici adi gorunur; tam ad satirin ipucunda gosterilir.
        kayit["personelAdSoyad"] = veriQuery.value("PersonelAdSoyad").toString();
        kayit["durum"] = veriQuery.value("Durum").toString();
        kayit["redSebebi"] = veriQuery.value("RedSebebi").toString();
        kayit["aciklamalar"] = veriQuery.value("Aciklamalar").toString();
        kayit["musteriNotu"] = veriQuery.value("MusteriNotu").toString();
        kayit["uretimNotu"] = veriQuery.value("UretimNotu").toString();
        kayit["anaTeklifId"] = veriQuery.value("AnaTeklifId").isNull()
            ? 0 : veriQuery.value("AnaTeklifId").toInt();
        kayit["revizyonNo"] = veriQuery.value("RevizyonNo").toInt();
        kayit["guncelTeklifId"] = veriQuery.value("GuncelTeklifId").toInt();
        kayit["guncelRevizyonNo"] = veriQuery.value("GuncelRevizyonNo").toInt();
        kayit["kopyaKaynakTeklifId"] = veriQuery.value("KopyaKaynakTeklifId").isNull()
            ? 0 : veriQuery.value("KopyaKaynakTeklifId").toInt();

        const int kokTeklifNo = veriQuery.value("TeklifNo").toInt();
        kayit["kokTeklifNo"] = kokTeklifNo;
        kayit["teklifNo"] = teklifNoMetniBicimle(kokTeklifNo, kayit["revizyonNo"].toInt());
        kayit["guncelTeklifNo"] = teklifNoMetniBicimle(kokTeklifNo, kayit["guncelRevizyonNo"].toInt());
        kayit["kopyaKaynakTeklifNo"] = veriQuery.value("KopyaKaynakNo").isNull()
            ? QString()
            : teklifNoMetniBicimle(veriQuery.value("KopyaKaynakNo").toInt(),
                                   veriQuery.value("KopyaKaynakRevizyonNo").toInt());
        const QString pb = veriQuery.value("ParaBirimi").toString().trimmed();
        kayit["paraBirimi"] = pb.isEmpty() ? QStringLiteral("TL") : pb;
        kayit["genelToplam"] = veriQuery.value("GenelToplam").toDouble();
        kayitlar << kayit;
    }

    // Sekme toplami (Alinan/Biten Tekliflerim): filtreye uyan TUM kayitlarin
    // genel toplami, para birimi bazinda. Giden Tekliflerim'de (durum filtresi
    // yok) revize/red surumler de listede oldugu icin toplam anlamsizdir.
    QVariantList paraBirimiToplamlari;
    if (!durumFiltresi.trimmed().isEmpty())
    {
        QSqlQuery toplamQuery(db);
        toplamQuery.prepare(QString(
            "SELECT ISNULL(NULLIF(LTRIM(RTRIM(t.ParaBirimi)), ''), 'TL') AS PB, "
            "       SUM(ISNULL(tt.GenelToplam, 0)) AS Toplam "
            "FROM dbo.teklifler t "
            "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
            "LEFT JOIN dbo.kullanicilar p ON p.KullaniciId = t.KullaniciId "
            "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
            "%1 "
            "GROUP BY ISNULL(NULLIF(LTRIM(RTRIM(t.ParaBirimi)), ''), 'TL') "
            "ORDER BY PB DESC").arg(whereClause));
        for (auto it = parametreler.constBegin(); it != parametreler.constEnd(); ++it)
            toplamQuery.bindValue(it.key(), it.value());
        if (toplamQuery.exec())
        {
            while (toplamQuery.next())
            {
                QVariantMap satir;
                satir["paraBirimi"] = toplamQuery.value("PB").toString();
                satir["toplam"] = toplamQuery.value("Toplam").toDouble();
                paraBirimiToplamlari << satir;
            }
        }
        else
        {
            qWarning() << "Teklif toplam sorgusu basarisiz:" << toplamQuery.lastError().text();
        }
        toplamMs = olcum.restart();
    }

    qInfo().nospace() << "[olcum] teklif listesi parcalari -- sayim: " << sayimMs
                      << " ms, veri: " << veriMs << " ms, para birimi toplami: " << toplamMs
                      << " ms (durum=" << durumFiltresi << ", kayit=" << toplamKayit << ")";

    sonuc["paraBirimiToplamlari"] = paraBirimiToplamlari;
    sonuc["kayitlar"] = kayitlar;
    sonuc["toplamKayit"] = toplamKayit;
    sonuc["toplamSayfa"] = toplamSayfa;
    sonuc["mevcutSayfa"] = sayfaNo;
    return sonuc;
}

