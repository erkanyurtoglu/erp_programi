#include "Database.h"
#include "AramaWorker.h"
#include "AramaSorgulari.h"
#include "SqlYardimcilari.h"
#include "Tanilama.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QSqlRecord>
#include <QVariant>
#include <QDateTime>
#include <QDebug>
#include <QCryptographicHash>
#include <QHash>
#include <QSet>
#include <QVector>
#include <QRegularExpression>
#include <QUuid>
#include <QLocale>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QClipboard>
#include <QFile>
#include <cmath>
#include <algorithm>
#include <utility>

namespace
{
    // Yeni ERP semasi: ayni SQL Server ornegi (EXCALIBUR\SQLEXPRESS) uzerinde,
    // eski LiyaTeklifVeriTabani'nden bagimsiz, yeniden tasarlanmis veritabani.
    // Baska bir sunucuda calistirmak icin exe'nin yanina baglanti.ini konur:
    //     [Veritabani]
    //     Sunucu=BASKA-PC\SQLEXPRESS
    //     Ad=LiyaErpVeriTabani
    // Dosya ya da anahtar yoksa asagidaki varsayilanlar kullanilir.
    struct BaglantiAyari
    {
        QString sunucu;
        QString veritabani;
    };

    const BaglantiAyari &baglantiAyari()
    {
        static const BaglantiAyari ayar = [] {
            const QString yol = QCoreApplication::applicationDirPath() + QStringLiteral("/baglanti.ini");
            BaglantiAyari a;
            // QSettings kullanilmiyor: INI bicimindeki "\" kacis karakteri sayilir
            // ve "PC\SQLEXPRESS" -> "PCQLEXPRESS" okunur. Satirlar elle ayrilir.
            QFile dosya(yol);
            if (dosya.open(QIODevice::ReadOnly | QIODevice::Text))
            {
                const QStringList satirlar = QString::fromUtf8(dosya.readAll()).split(QLatin1Char('\n'));
                for (const QString &satir : satirlar)
                {
                    const int esittir = satir.indexOf(QLatin1Char('='));
                    if (esittir <= 0)
                        continue;
                    const QString anahtar = satir.left(esittir).trimmed();
                    const QString deger = satir.mid(esittir + 1).trimmed();
                    if (anahtar.compare(QLatin1String("Sunucu"), Qt::CaseInsensitive) == 0)
                        a.sunucu = deger;
                    else if (anahtar.compare(QLatin1String("Ad"), Qt::CaseInsensitive) == 0)
                        a.veritabani = deger;
                }
            }
            if (a.sunucu.isEmpty())
                a.sunucu = QStringLiteral(R"(EXCALIBUR\SQLEXPRESS)");
            if (a.veritabani.isEmpty())
                a.veritabani = QStringLiteral("LiyaErpVeriTabani");
            qInfo() << "Baglanti ayari:" << a.sunucu << "/" << a.veritabani
                    << (QFile::exists(yol) ? "(baglanti.ini)" : "(varsayilan)");
            return a;
        }();
        return ayar;
    }

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

    // teklifKaydet / teklifDuzelt'in ortak sayisal denetimi. Arayuz de sinirliyor,
    // ama veritabanina anlamsiz (negatif toplamli, %150 indirimli) ya da sutuna
    // sigmayan (DECIMAL(5,2) -> 999,99'dan buyuk oran) bir teklif hic yazilmasin.
    bool teklifVerisiniDenetle(const QVariantMap &teklif, QString &hataOut)
    {
        const double indirim = teklif.value("genelIndirimOrani", 0).toDouble();
        const double kdv = teklif.value("kdvOrani", 0).toDouble();
        if (indirim < 0 || indirim > 100)
        {
            hataOut = QStringLiteral("İndirim oranı 0 ile 100 arasında olmalı.");
            return false;
        }
        if (kdv < 0 || kdv > 100)
        {
            hataOut = QStringLiteral("KDV oranı 0 ile 100 arasında olmalı.");
            return false;
        }
        const double paketleme = teklif.value("paketlemeUcreti", 0).toDouble();
        const double tasima = teklif.value("tasimaUcreti", 0).toDouble();
        if (paketleme < 0 || tasima < 0)
        {
            hataOut = QStringLiteral("Paketleme/taşıma ücreti negatif olamaz.");
            return false;
        }

        // Fiyatlar teklifin kendi para birimindedir; kur yalnizca TL tutulan
        // maliyetin karsiligidir. Dovizli teklif kursuz da kaydedilebilir: bu
        // durumda Kur=1 yazilir ve MaliyetFiyati TL'dir (gocten gelen kayitlarla
        // ayni kural, bkz. teklifDuzenlemeVerisiGetir "kurBilinmiyor").

        // TUTARLAR SUNUCUDA YENIDEN HESAPLANIR: ekrandan gelen satir/toplam
        // degerleri ayni kurallarla (bkz. TeklifVerPage.hesap) dogrulanir. Arayuzde
        // bir hata ya da eski bir surum tutarsiz bir teklif gonderirse (ör. satir
        // toplamlari genel toplamla tutmuyorsa) kayit yapilmaz -- musteriye celiskili
        // bir PDF gitmesin. Her adim kurusa yuvarlandigi icin 1 kurusluk tolerans var.
        const double tolerans = 0.011;
        const auto yuvarla = [](double x) { return std::round(x * 100.0) / 100.0; };
        double indirimliToplamHesap = 0.0;
        for (const QVariant &kalemVar : teklif.value("kalemler").toList())
        {
            const QVariantMap kalem = kalemVar.toMap();
            const int adet = kalem.value("adet", 0).toInt();
            if (adet < 1)
            {
                hataOut = QStringLiteral("Kalem adedi en az 1 olmalı.");
                return false;
            }
            const double birimFiyat = kalem.value("birimFiyat", 0).toDouble();
            if (birimFiyat < 0 || kalem.value("maliyetFiyati", 0).toDouble() < 0)
            {
                hataOut = QStringLiteral("Birim fiyat ve maliyet negatif olamaz.");
                return false;
            }
            const double kur = kalem.value("kur", 1).toDouble();
            if (!std::isfinite(kur) || kur <= 0)
            {
                hataOut = QStringLiteral("Kalem kuru geçersiz; teklif kaydedilmedi.");
                return false;
            }
            const double indirimliBirim = kalem.value("indirimliBirimFiyat", 0).toDouble();
            const double toplamTutar = kalem.value("toplamTutar", 0).toDouble();
            if (std::abs(indirimliBirim - yuvarla(birimFiyat * (1.0 - indirim / 100.0))) > tolerans
                || std::abs(toplamTutar - yuvarla(indirimliBirim * adet)) > tolerans)
            {
                hataOut = QStringLiteral("Kalem tutarları tutarsız (indirimli fiyat × adet); teklif kaydedilmedi.");
                return false;
            }
            indirimliToplamHesap += toplamTutar;
        }

        const double indirimliToplam = teklif.value("indirimliToplam", 0).toDouble();
        const double kdvTutari = teklif.value("kdvTutari", 0).toDouble();
        const double genelToplam = teklif.value("genelToplam", 0).toDouble();
        const double kdvMatrahi = yuvarla(indirimliToplam + paketleme + tasima);
        if (std::abs(indirimliToplam - yuvarla(indirimliToplamHesap)) > tolerans
            || std::abs(kdvTutari - yuvarla(kdvMatrahi * kdv / 100.0)) > tolerans
            || std::abs(genelToplam - yuvarla(kdvMatrahi + kdvTutari)) > tolerans)
        {
            hataOut = QStringLiteral("Teklif toplamları kalemlerle tutmuyor (ara toplam / KDV / genel toplam); "
                                     "teklif kaydedilmedi.");
            return false;
        }
        return true;
    }

    // FATURALANMIS TEKLIF DONDURULUR: fatura kesildikten sonra teklifin icerigi,
    // durumu (Beklemede/Reddedildi'ye donus) ya da varligi degisirse fatura ile
    // teklif celisir. Revizyon ise fatura bilgisini tasimadigi icin yeni surumu
    // Muhasebe'de yeniden "Faturalanacak" gosterir -- ayni is iki kez faturalanir.
    // Degisiklik gerekiyorsa once fatura bilgisi (Muhasebe) kaldirilir.
    //
    // zincir=true: teklifin tum revizyon zincirine bakar (revizyon icin; eski
    // bir surumde kalmis fatura da sayilir). Fatura no bulunursa faturaNoOut'a
    // yazilir. db/30 kurulu degilse fatura yoktur. Sorgu hatasinda false doner;
    // cagiran yazmayi reddeder.
    bool faturaNoBul(const QSqlDatabase &db, int teklifId, bool zincir, QString &faturaNoOut)
    {
        faturaNoOut.clear();
        if (!semaKolonuVarMi(db, QStringLiteral("dbo.sevk_bilgileri"), QStringLiteral("FaturaNo")))
            return true;

        QSqlQuery query(db);
        query.prepare(zincir
            ? QStringLiteral(
                  "SELECT TOP 1 sb.FaturaNo FROM dbo.sevk_bilgileri sb "
                  "INNER JOIN dbo.teklifler g ON g.TeklifId = sb.TeklifId "
                  "INNER JOIN dbo.teklifler t ON t.TeklifId = :id "
                  "WHERE (g.TeklifId = ISNULL(t.AnaTeklifId, t.TeklifId) "
                  "       OR g.AnaTeklifId = ISNULL(t.AnaTeklifId, t.TeklifId)) "
                  "  AND NULLIF(LTRIM(RTRIM(sb.FaturaNo)), N'') IS NOT NULL "
                  "ORDER BY g.RevizyonNo DESC")
            : QStringLiteral(
                  "SELECT FaturaNo FROM dbo.sevk_bilgileri "
                  "WHERE TeklifId = :id AND NULLIF(LTRIM(RTRIM(FaturaNo)), N'') IS NOT NULL"));
        query.bindValue(":id", teklifId);
        if (!query.exec())
        {
            qWarning() << "faturaNoBul basarisiz:" << teklifId << query.lastError().text();
            return false;
        }
        if (query.next())
            faturaNoOut = query.value(0).toString().trimmed();
        return true;
    }

    // ------------------------------------------------------------------
    // Sifre saklama
    //
    // Sifreler kullanici basina rastgele bir TUZ (salt) ile hashlenir:
    // SHA-256(tuz + sifre). Tuzsuz duz SHA-256'da ayni sifreyi kullanan iki
    // personelin hash'i birebir ayni cikiyordu -- veritabanini goren biri
    // kimlerin ayni sifreyi kullandigini anlar, ustelik yaygin sifreler hazir
    // "rainbow table" ile dogrudan cozulebilirdi.
    //
    // Tuz bos verilirse ESKI (tuzsuz) hash uretilir. Bu bilincli bir geriye
    // donuk uyumluluk yolu: SifreSalt sutunu henuz doldurulmamis kayitlar
    // eskisi gibi dogrulanir, girisYap onlari sessizce tuzlu hale yukseltir
    // (bkz. db/12_personel_sifre_salt.sql).
    // ------------------------------------------------------------------
    QString sifreyiHashle(const QString &sifre, const QString &tuz = QString())
    {
        const QByteArray girdi = tuz.isEmpty() ? sifre.toUtf8()
                                               : (tuz.toUtf8() + sifre.toUtf8());
        return QString::fromLatin1(
            QCryptographicHash::hash(girdi, QCryptographicHash::Sha256).toHex());
    }

    // Saklanan deger bir SHA-256 hex ozeti mi (64 hex karakter)? Duz metin
    // geri donus yolu (gocten gelen hashlenmemis sifreler) YALNIZCA hash'e
    // benzemeyen kayitlarda denenir; aksi halde veritabanindaki hash'i goren
    // biri o hash'i sifre kutusuna yazarak giris yapabilirdi.
    bool sha256OzetiMi(const QString &deger)
    {
        static const QRegularExpression ozet(QStringLiteral("^[0-9a-fA-F]{64}$"));
        return ozet.match(deger).hasMatch();
    }

    // Duz metin (hashlenmemis, gocten gelen) kayitla eslesme.
    bool duzMetinSifreEslesir(const QString &depolanan, const QString &sifre)
    {
        return !sha256OzetiMi(depolanan) && depolanan == sifre;
    }

    QString yeniTuzUret()
    {
        return QString::fromLatin1(QUuid::createUuid().toRfc4122().toHex());
    }

    // ------------------------------------------------------------------
    // Sifrenin geri acilabilir kopyasi (bkz. db/29_personel_sifre_gorunur.sql)
    //
    // Yonetici unutulan sifreyi bakip personele soyleyebilsin diye istendi.
    // Giris yine tuzlu hash ile dogrulanir; bu kopya yalnizca
    // personelSifresiGetir ile, tek yetkili kullanici ve PIN ile okunur. Sifreleme
    // SQL Server'da yapilir (ENCRYPTBYPASSPHRASE); anahtar her iki yonde de
    // NVARCHAR'a cevrilir, yoksa VARCHAR/NVARCHAR farki farkli anahtar uretir.
    // Anahtar degistirilirse mevcut kopyalar acilamaz (personel tekrar giris
    // yapinca yenisi yazilir).
    // ------------------------------------------------------------------
    const char *const SIFRE_GORUNTULEME_ANAHTARI = "I0wwtFey3B7WPmdCa7a1QFFjLN0lPjTSYGbPFRU4ITc";
    const char *const SIFRELI_KOPYA_IFADESI =
        "ENCRYPTBYPASSPHRASE(CAST(:sifreAnahtari AS NVARCHAR(128)), CAST(:sifreAcik AS NVARCHAR(256)))";

    // Personel sifrelerini gorebilen TEK kullanici ve ondan istenen PIN'in
    // SHA-256 ozeti (PIN kodda acik yazilmaz).
    const char *const SIFRE_GORUNTULEYEN_KULLANICI = "ErkanYurtoglu";
    const char *const SIFRE_GORUNTULEME_PIN_OZETI =
        "2c6499976963e9832529bc8d9dff516d16c13d372d852d1500f5892e46a25507";
    const int SIFRE_PIN_AZAMI_HATA = 5;

    bool sifreliKopyaKolonuVarMi(QSqlDatabase &db)
    {
        return semaKolonuVarMi(db, QStringLiteral("dbo.kullanicilar"), QStringLiteral("SifreSifreli"));
    }

    void sifreliKopyaParametreleriniBagla(QSqlQuery &query, const QString &sifre)
    {
        query.bindValue(":sifreAnahtari", QString::fromLatin1(SIFRE_GORUNTULEME_ANAHTARI));
        query.bindValue(":sifreAcik", sifre);
    }

    // Yazma islemlerinin sunucu tarafi yetki denetimi (bkz. modulDuzenleyebilirMi).
    // Arayuz butonlari gizlemekle yetinmez; Satinalma tarafindaki kuralin aynisi.
    const char *const SATIS_YETKI_YOK = "Bu işlem için Satış modülünde düzenleme yetkiniz yok.";
    const char *const YONETIM_YETKI_YOK = "Bu işlem için Yönetim modülünde düzenleme yetkiniz yok.";

    // ------------------------------------------------------------------
    // Form alanlari: ortak temizleme / dogrulama yardimcilari
    //
    // Musterilerim / Urunlerim / Personellerim formlarindan gelen her metin
    // alani bunlardan gecer. Eskiden yalnizca ZORUNLU alanlar (FirmaAdi,
    // UrunAciklamasi) trim ediliyordu; telefon, e-posta, kategori, urun kodu
    // ham haliyle yazildigi icin " ABC " gibi kayitlar hem ORDER BY
    // siralamasini hem de LIKE aramasini sessizce bozuyordu.
    // ------------------------------------------------------------------

    // Haritadaki metin alanini bosluklardan arindirip doner.
    QString alan(const QVariantMap &harita, const QString &anahtar)
    {
        return harita.value(anahtar).toString().trimmed();
    }

    // OPSIYONEL metin sutunlari icin parametre: bos deger '' yerine NULL
    // baglanir. Aksi halde ayni "bos" iki farkli sekilde saklanir ve
    // PDF/rapor tarafindaki IS NULL / COALESCE kontrolleri tutarsiz davranir.
    QVariant metinParametresi(const QString &deger)
    {
        const QString t = deger.trimmed();
        if (t.isEmpty())
            return QVariant(QMetaType(QMetaType::QString));
        return t;
    }

    // NOT: likeIcinKacir / likeDeseni / manuelKoduMu / semaKolonuVarMi,
    // AramaSorgulari ile paylasildigi icin SqlYardimcilari.h'de duruyor.

    // SQL Server yabanci anahtar (FOREIGN KEY) ihlali mi? Silme hatalarinda
    // dogru mesaji gosterebilmek icin: eskiden HER hata (baglanti kopmasi,
    // zaman asimi, yetki eksikligi) kullaniciya "bu kayda ait teklifler var"
    // diye gosteriliyor, yani yanlis yone yonlendiriyordu.
    bool fkIhlaliMi(const QSqlError &hata)
    {
        return hata.nativeErrorCode() == QStringLiteral("547");
    }

    // Tekil indeks (2601) veya UNIQUE kisit (2627) ihlali mi?
    bool tekillikIhlaliMi(const QSqlError &hata)
    {
        const QString kod = hata.nativeErrorCode();
        return kod == QStringLiteral("2601") || kod == QStringLiteral("2627");
    }

    // Cok basit bir e-posta bicim kontrolu ("a@b.co"). Amac gecerliligi
    // kanitlamak degil, "ahmet" / "ahmet@" gibi acik yazim hatalarini
    // veritabanina yazmadan yakalamak. Alan opsiyonel: bos deger gecerlidir.
    bool epostaGecerliMi(const QString &eposta)
    {
        const QString t = eposta.trimmed();
        if (t.isEmpty())
            return true;
        static const QRegularExpression desen(QStringLiteral(R"(^[^\s@]+@[^\s@]+\.[^\s@]{2,}$)"));
        return desen.match(t).hasMatch();
    }

    // Vergi numarasi: 10 hane (kurumlar) veya 11 hane (TCKN/sahis sirketi).
    // Rakam arasindaki bosluk/tire/nokta serbest, harf kabul edilmez.
    // Alan opsiyonel: bos deger gecerlidir.
    bool vergiNoGecerliMi(const QString &vergiNo)
    {
        const QString t = vergiNo.trimmed();
        if (t.isEmpty())
            return true;
        int rakam = 0;
        for (const QChar &c : t)
        {
            if (c.isDigit())
                ++rakam;
            else if (c != ' ' && c != '-' && c != '.' && c != '/')
                return false;
        }
        return rakam == 10 || rakam == 11;
    }

    // Telefon: en az 7 rakam; '+', bosluk, '-', '/', parantez serbest.
    // Alan opsiyonel: bos deger gecerlidir.
    bool telefonGecerliMi(const QString &telefon)
    {
        const QString t = telefon.trimmed();
        if (t.isEmpty())
            return true;
        static const QRegularExpression desen(QStringLiteral(R"(^[0-9+\s()\-/]{7,25}$)"));
        if (!desen.match(t).hasMatch())
            return false;
        int rakam = 0;
        for (const QChar &c : t)
            if (c.isDigit())
                ++rakam;
        return rakam >= 7;
    }

}

Database::Database(QObject *parent) : QObject(parent)
{
    m_baglantiHazir = baglan();

    // UC AYRI WORKER, UC AYRI THREAD, UC AYRI ODBC BAGLANTISI.
    //
    // Eskiden hepsi TEK worker uzerindeydi ve bu, yavas tek bir sorgunun
    // programin TUM listelerini kilitlemesine yol aciyordu: sorgular tek bir
    // olay kuyrugunda sirayla calistigi icin, one giren agir bir teklif
    // sorgusu (ya da kopmus bir baglantinin zaman asimi) arkasindaki
    // musteri/urun/personel isteklerini de bekletiyor, kullanici butun
    // ekranlari ayni anda "Yükleniyor…" halinde goruyordu.
    //
    // Ayrim, islerin birbirini bekletmemesi icin kullanim sekline gore:
    //   * canli arama  -> kullanici YAZARKEN tetiklenir, her zaman akici olmali
    //   * sayfali listeler -> Musterilerim / Urunlerim / Personellerim / Tedarikcilerim
    //   * teklif listesi   -> en agir sorgu (teklif_kalemleri uzerinde EXISTS + LIKE)
    m_aramaWorker = workerBaslat(m_aramaThread, QStringLiteral("erp_arama_baglantisi"));
    connect(m_aramaWorker, &AramaWorker::musteriSonucHazir, this, &Database::musteriSonuclariHazir);
    connect(m_aramaWorker, &AramaWorker::urunSonucHazir, this, &Database::urunSonuclariHazir);

    m_listeWorker = workerBaslat(m_listeThread, QStringLiteral("erp_liste_baglantisi"));
    connect(m_listeWorker, &AramaWorker::musteriListesiHazir, this, &Database::musteriListesiHazir);
    connect(m_listeWorker, &AramaWorker::urunListesiHazir, this, &Database::urunListesiHazir);
    connect(m_listeWorker, &AramaWorker::personelListesiHazir, this, &Database::personelListesiHazir);
    connect(m_listeWorker, &AramaWorker::tedarikciListesiHazir, this, &Database::tedarikciListesiHazir);
    connect(m_listeWorker, &AramaWorker::rolListesiHazir, this, &Database::rolListesiHazir);
    connect(m_listeWorker, &AramaWorker::rolYetkiListesiHazir, this, &Database::rolYetkiListesiHazir);
    connect(m_listeWorker, &AramaWorker::ayarListesiHazir, this, &Database::ayarListesiHazir);
    // Fiyat bilgisi yetkiye gore ayiklanip oyle yayinlanir (bkz. cihazListesiAyikla).
    connect(m_listeWorker, &AramaWorker::cihazListesiHazir, this, &Database::cihazListesiAyikla);

    m_teklifWorker = workerBaslat(m_teklifThread, QStringLiteral("erp_teklif_baglantisi"));
    connect(m_teklifWorker, &AramaWorker::teklifListesiHazir, this, &Database::teklifListesiHazir);
    connect(m_teklifWorker, &AramaWorker::panoOzetiHazir, this, &Database::panoOzetiHazir);
    connect(m_teklifWorker, &AramaWorker::islemGecmisiHazir, this, &Database::islemGecmisiHazir);
    connect(m_teklifWorker, &AramaWorker::muhasebeListesiHazir, this, &Database::muhasebeListesiHazir);

    // Arka plan kaydi: "Teklifi Kaydet" SQL Server'i beklerken arayuz donmasin.
    // Baglanti (erp_kayit_baglantisi) ilk kayitta, kayit thread'inin icinde
    // acilir (bkz. baglantiHazir) ve thread biterken yine orada kapatilir.
    m_kayitBaglami = new QObject;
    m_kayitBaglami->moveToThread(&m_kayitThread);
    connect(&m_kayitThread, &QThread::finished, m_kayitBaglami, [this] {
        if (m_kayitDb.isValid())
            m_kayitDb.close();
        m_kayitDb = QSqlDatabase();
        QSqlDatabase::removeDatabase(QStringLiteral("erp_kayit_baglantisi"));
    }, Qt::DirectConnection);
    connect(&m_kayitThread, &QThread::finished, m_kayitBaglami, &QObject::deleteLater);
    m_kayitThread.start();
}

int Database::teklifKaydetBaslat(const QVariantMap &teklif)
{
    const int istekNo = ++m_kayitIstekSayaci;
    QMetaObject::invokeMethod(m_kayitBaglami, [this, istekNo, teklif] {
        emit teklifKayitHazir(istekNo, teklifKaydet(teklif));
    }, Qt::QueuedConnection);
    return istekNo;
}

int Database::teklifDuzeltBaslat(int teklifId, const QVariantMap &teklif, const QString &sebep)
{
    const int istekNo = ++m_kayitIstekSayaci;
    QMetaObject::invokeMethod(m_kayitBaglami, [this, istekNo, teklifId, teklif, sebep] {
        emit teklifKayitHazir(istekNo, teklifDuzelt(teklifId, teklif, sebep));
    }, Qt::QueuedConnection);
    return istekNo;
}

AramaWorker *Database::workerBaslat(QThread &thread, const QString &baglantiAdi)
{
    // Worker kendi thread'ine tasinir; baglantisini ANCAK thread fiilen
    // baslayinca (kendi icinde) acar -- bkz. AramaWorker::baglantiyiAc().
    auto *worker = new AramaWorker(baglantiAdi);
    worker->moveToThread(&thread);
    connect(&thread, &QThread::started, worker, &AramaWorker::baglantiyiAc);
    connect(&thread, &QThread::finished, worker, &QObject::deleteLater);
    thread.start();
    return worker;
}

Database::~Database()
{
    // Thread o an bir sorgunun ICINDEYSE quit() hemen etkili olmaz: olay dongusu
    // ancak sorgu donunce devam edebilir. Bu yuzden once yeterince beklenir --
    // ODBC istek zaman asimi (ISTEK_ZAMAN_ASIMI_SN) + pay kadar.
    //
    // Sure yine de yetmezse thread SONLANDIRILIR. Hos bir cozum degildir, ama
    // alternatifi kesin bir cokmedir: QThread yikicisi, thread hala calisirken
    // cagrilirsa uygulamayi abort eder ("QThread: Destroyed while thread is
    // still running") -- programi kapatan kullanici bunu "program cokerek
    // kapandi" diye gorur. Kapanis anindayiz; yarim kalan SELECT'in veri
    // butunlugu acisindan bir sonucu yok. Kayit thread'inde yarim kalan bir
    // teklif kaydi tek transaction'dir: baglanti kopunca SQL Server onu geri alir.
    const int bekleMs = (ISTEK_ZAMAN_ASIMI_SN + 5) * 1000;
    for (QThread *thread : { &m_aramaThread, &m_listeThread, &m_teklifThread, &m_kayitThread })
    {
        thread->quit();
        if (thread->wait(bekleMs))
            continue;

        qWarning() << "Worker thread" << bekleMs << "ms icinde kapanmadi; sonlandiriliyor.";
        thread->terminate();
        thread->wait(2000);
    }

    if (m_db.isOpen())
        m_db.close();
}

QString Database::sunucuAdi() const
{
    return baglantiAyari().sunucu;
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

    const QString &SUNUCU = baglantiAyari().sunucu;
    const QString &VERITABANI = baglantiAyari().veritabani;

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
    // Bu cagri UI thread'indedir (Database, main()'de olusturulur): suresi
    // dogrudan "program acilirken ne kadar donuyor" demektir. Ilk cagri ayni
    // zamanda Qt'nin QODBC eklentisini de yukler.
    QElapsedTimer olcum;
    olcum.start();
    const bool basarili = baglantiAc(m_db, "erp_baglantisi", m_sonHataMesaji);
    qInfo() << "[olcum] ana baglanti (eklenti yuklemesi dahil):" << olcum.elapsed() << "ms";
    m_sonBaglantiDenemesi.start();
    if (basarili)
        m_sonKullanim.start();
    return basarili;
}

bool Database::baglantiHazir()
{
    if (QThread::currentThread() == &m_kayitThread)
        return baglantiyiHazirla(m_kayitDb, "erp_kayit_baglantisi", m_kayitSonKullanim,
                                 m_kayitSonBaglantiDenemesi, m_kayitHataMesaji);

    m_baglantiHazir = baglantiyiHazirla(m_db, "erp_baglantisi", m_sonKullanim,
                                        m_sonBaglantiDenemesi, m_sonHataMesaji);
    return m_baglantiHazir;
}

QSqlDatabase Database::aktifDb() const
{
    return QThread::currentThread() == &m_kayitThread ? m_kayitDb : m_db;
}

QVariantMap Database::girisYap(const QString &kullaniciAdi, const QString &sifre)
{
    ERP_IZ("girisYap");
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

    // SifreSalt sutunu db/12_personel_sifre_salt.sql ile eklenir; script henuz
    // calistirilmamissa sutun yoktur ve giris eski (tuzsuz) yolla isler.
    const bool tuzKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.kullanicilar"),
                                           QStringLiteral("SifreSalt"));

    QSqlQuery query(m_db);
    query.prepare(QString("SELECT KullaniciId, AdSoyad, KullaniciAdi, SifreHash, AktifMi%1 "
                          "FROM dbo.kullanicilar WHERE KullaniciAdi = :kullaniciAdi")
                      .arg(tuzKolonu ? QStringLiteral(", SifreSalt") : QString()));
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

    // Sifre dogrulamasinda UC surum birlikte destekleniyor; hepsi ayni gecis
    // mantiginin halkalari:
    //   1) TUZLU hash  -- hedef bicim (SifreSalt dolu).
    //   2) TUZSUZ hash -- db/12 oncesi kaydedilmis sifreler.
    //   3) DUZ METIN   -- eski WPF sisteminden gocen kayitlar (kolon adi
    //                     SifreHash olsa da icerigi hashlenmemisti).
    // 2 veya 3 ile eslesirse kullaniciyi hic rahatsiz etmeden sessizce TUZLU
    // hale yukseltiyoruz (asagidaki UPDATE). Boylece sistem zamanla tamamen
    // tuzlu hash'e gecer ve kimsenin sifresini sifirlamak gerekmez.
    const QString depolananTuz = tuzKolonu ? query.value("SifreSalt").toString() : QString();

    bool sifreDogruMu = false;
    bool yukseltmeGerekli = false;

    // SifreHash'e SSMS'ten elle duz sifre yazilabiliyor; o satirda eski tuz
    // dolu kalsa da deger hash degilse duz metin olarak karsilastirilir.
    if (duzMetinSifreEslesir(depolananSifre, sifre))
    {
        sifreDogruMu = true;
        yukseltmeGerekli = true;
    }
    else if (!depolananTuz.isEmpty())
    {
        sifreDogruMu = (depolananSifre == sifreyiHashle(sifre, depolananTuz));
    }
    else if (depolananSifre == sifreyiHashle(sifre))
    {
        sifreDogruMu = true;
        yukseltmeGerekli = true;
    }

    if (!sifreDogruMu)
    {
        sonuc["hata"] = genelHataMesaji;
        return sonuc;
    }

    // Yukseltme ancak tuz sutunu varsa yapilabilir; yoksa kayit oldugu gibi
    // kalir ve giris yine basarili sayilir (script calistirilinca yukseltilir).
    if (yukseltmeGerekli && tuzKolonu)
    {
        const QString yeniTuz = yeniTuzUret();
        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.kullanicilar SET SifreHash = :hash, SifreSalt = :tuz "
                         "WHERE KullaniciId = :id");
        guncelle.bindValue(":hash", sifreyiHashle(sifre, yeniTuz));
        guncelle.bindValue(":tuz", yeniTuz);
        guncelle.bindValue(":id", kullaniciId);
        if (!guncelle.exec())
            qWarning() << "Sifre tuzlu hale yukseltilemedi (giris yine de basarili sayilir):"
                       << guncelle.lastError().text();
    }

    // Sifrenin geri acilabilir kopyasi yoksa (db/29 oncesi kayit) simdi yazilir:
    // hash'ten geri cevrilemedigi icin acik sifrenin bilindigi tek an giristir.
    // Duz metinden yukseltilen kayitta kopya eski bir sifreye ait olabilir
    // (sifre elle degistirilmis); o zaman da yenilenir.
    if (sifreliKopyaKolonuVarMi(m_db))
    {
        QSqlQuery kopya(m_db);
        kopya.prepare(QString("UPDATE dbo.kullanicilar SET SifreSifreli = %1 "
                              "WHERE KullaniciId = :id%2")
                          .arg(QString::fromLatin1(SIFRELI_KOPYA_IFADESI),
                               yukseltmeGerekli ? QString() : QStringLiteral(" AND SifreSifreli IS NULL")));
        sifreliKopyaParametreleriniBagla(kopya, sifre);
        kopya.bindValue(":id", kullaniciId);
        if (!kopya.exec())
            qWarning() << "Sifre kopyasi yazilamadi (giris yine de basarili sayilir):"
                       << kopya.lastError().text();
    }

    // Is kurallarinin SUNUCUDA bilmesi gereken oturum bilgisi (bkz.
    // aktifKullaniciId): QML'den gelen bir id'ye guvenmek yerine burada tutulur.
    m_aktifKullaniciId = kullaniciId;

    sonuc["basarili"] = true;
    sonuc["kullaniciId"] = kullaniciId;
    sonuc["adSoyad"] = adSoyad;
    sonuc["kullaniciAdi"] = kullaniciAdiTrim;
    sonuc["moduller"] = kullaniciModulleriniGetir(kullaniciId);
    return sonuc;
}

bool Database::yoneticiSifresiDogrula(const QString &sifre)
{
    ERP_IZ("yoneticiSifresiDogrula");
    if (sifre.isEmpty() || !baglantiHazir())
        return false;

    const bool tuzKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.kullanicilar"),
                                           QStringLiteral("SifreSalt"));

    QSqlQuery query(m_db);
    query.prepare(QString(
        "SELECT DISTINCT k.SifreHash%1 "
        "FROM dbo.kullanicilar k "
        "JOIN dbo.kullanici_rolleri kr ON kr.KullaniciId = k.KullaniciId "
        "JOIN dbo.roller r ON r.RolId = kr.RolId "
        "WHERE k.AktifMi = 1 AND r.RolAdi IN (N'Yönetici', N'Göç - Geçici Tam Yetkili')")
        .arg(tuzKolonu ? QStringLiteral(", k.SifreSalt") : QString()));
    if (!query.exec())
    {
        qWarning() << "yoneticiSifresiDogrula sorgusu basarisiz:" << query.lastError().text();
        return false;
    }

    // girisYap ile ayni uc surum: tuzlu hash, tuzsuz hash veya (henuz
    // yukseltilmemis) duz metin. Yukseltme burada YAPILMAZ -- bu metot sadece
    // dogrulama yapar; yukseltme kullanici kendi girisini yaptiginda olur.
    while (query.next())
    {
        const QString depolanan = query.value(0).toString();
        const QString tuz = tuzKolonu ? query.value(1).toString() : QString();

        // Elle yazilmis duz sifre tuz dolu olsa da kabul edilir (bkz. girisYap).
        if (duzMetinSifreEslesir(depolanan, sifre))
            return true;
        if (!tuz.isEmpty())
        {
            if (depolanan == sifreyiHashle(sifre, tuz))
                return true;
        }
        else if (depolanan == sifreyiHashle(sifre))
        {
            return true;
        }
    }
    return false;
}

QVariantList Database::kullaniciModulleriniGetir(int kullaniciId)
{
    QVariantList moduller;

    QSqlQuery query(aktifDb());
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

QVariantMap Database::gecmisTekliflerGetir(const QString &arama,
                                            const QString &tarihFiltresi,
                                            const QString &baslangicTarihi,
                                            const QString &bitisTarihi,
                                            int sayfaNo,
                                            int sayfaBoyutu,
                                            const QString &durumFiltresi)
{
    ERP_IZ("gecmisTekliflerGetir");
    // SENKRON yol -- yalnizca geriye donuk uyumluluk icin durur. Ekranlar
    // gecmisTekliflerGetirBaslat'i kullanmalidir: bu cagri, sorgu suresince
    // UI thread'ini bloke eder (bkz. Database.h'deki asenkron yol notu).
    if (!baglantiHazir())
    {
        qWarning() << "gecmisTekliflerGetir: veritabani baglantisi yok.";
        QVariantMap bos;
        bos["kayitlar"] = QVariantList();
        bos["toplamKayit"] = 0;
        bos["toplamSayfa"] = 1;
        bos["mevcutSayfa"] = 1;
        bos["paraBirimiToplamlari"] = QVariantList();
        return bos;
    }
    return teklifListesiSorgusu(m_db, arama, tarihFiltresi, baslangicTarihi, bitisTarihi,
                                sayfaNo, sayfaBoyutu, durumFiltresi);
}

int Database::gecmisTekliflerGetirBaslat(const QString &arama,
                                          const QString &tarihFiltresi,
                                          const QString &baslangicTarihi,
                                          const QString &bitisTarihi,
                                          int sayfaNo,
                                          int sayfaBoyutu,
                                          const QString &durumFiltresi)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_teklifWorker)
    {
        // Worker yoksa (olmamasi gereken durum) cagiran taraf asili kalmasin.
        emit teklifListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_teklifWorker, "teklifListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama),
                              Q_ARG(QString, tarihFiltresi), Q_ARG(QString, baslangicTarihi),
                              Q_ARG(QString, bitisTarihi), Q_ARG(int, sayfaNo),
                              Q_ARG(int, sayfaBoyutu), Q_ARG(QString, durumFiltresi));
    return istekNo;
}

bool Database::teklifSil(int teklifId)
{
    ERP_IZ("teklifSil");
    // Yonetici sifresi onayi QML tarafinda (SifreOnayDialog) istenir.
    m_sonHataMesaji.clear();
    if (teklifId <= 0 || !baglantiHazir())
    {
        m_sonHataMesaji = QStringLiteral("Veritabanına bağlanılamadı.");
        return false;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

    // Kabul edilmis / tamamlanmis teklif silinemez (bkz. teklifKilitliMi).
    const QString durum = teklifDurumuGetir(teklifId);
    if (teklifKilitliMi(durum))
    {
        m_sonHataMesaji = QString("Teklif %1 \"%2\" durumunda; silinemez.").arg(teklifNoGetir(teklifId), durum);
        return false;
    }
    {
        QString faturaNo;
        if (!faturaNoBul(m_db, teklifId, false, faturaNo))
        {
            m_sonHataMesaji = QStringLiteral("Teklifin fatura bilgisi okunamadı; lütfen tekrar deneyin.");
            return false;
        }
        if (!faturaNo.isEmpty())
        {
            m_sonHataMesaji = QString("Teklif %1 faturalandı (Fatura No: %2); silinemez. "
                                      "Önce Muhasebe'den fatura bilgisi kaldırılmalı.")
                                  .arg(teklifNoGetir(teklifId), faturaNo);
            return false;
        }
    }

    // Revizyonlari olan kok teklif silinemez: revizyonlar AnaTeklifId ile ona
    // baglidir (FK). Kullaniciya sebebi acikca soylenir.
    {
        QSqlQuery revSayisi(m_db);
        revSayisi.prepare("SELECT COUNT(*) FROM dbo.teklifler WHERE AnaTeklifId = :id");
        revSayisi.bindValue(":id", teklifId);
        if (revSayisi.exec() && revSayisi.next() && revSayisi.value(0).toInt() > 0)
        {
            m_sonHataMesaji = QString("Teklif %1'in %2 revizyonu var; önce revizyonlar silinmeli.")
                                  .arg(teklifNoGetir(teklifId)).arg(revSayisi.value(0).toInt());
            return false;
        }
    }

    // Zincirin bilgisi SILMEDEN ONCE okunur: silinen kayit zincirin en son
    // uyesiyse, yeniden zincirin sonu olacak onceki surum asagida onarilir.
    const int yerineGecen = teklifYerineGecenIdGetir(teklifId);
    if (yerineGecen < 0)
    {
        m_sonHataMesaji = QStringLiteral("Teklifin revizyon zinciri okunamadı; lütfen tekrar deneyin.");
        return false;
    }
    const bool sonSurumMu = yerineGecen == 0;
    int kokId = teklifId;
    {
        QSqlQuery kokQuery(m_db);
        kokQuery.prepare("SELECT ISNULL(AnaTeklifId, TeklifId) FROM dbo.teklifler WHERE TeklifId = :id");
        kokQuery.bindValue(":id", teklifId);
        if (kokQuery.exec() && kokQuery.next())
            kokId = kokQuery.value(0).toInt();
    }

    // SILME IZI ZORUNLUDUR (db/28): kalemler, toplamlar, sevk ve gecmis
    // tablolari CASCADE ile gittigi icin iz yazilamazsa silme yapilmaz.
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.teklif_silme_gecmisi"), QStringLiteral("SilinenVeri")))
    {
        m_sonHataMesaji = QStringLiteral("Teklif silme izi tutulamadığı için silme yapılmadı. "
                                         "db/28_teklif_silme_gecmisi.sql betiği çalıştırılmalı.");
        return false;
    }
    // Transaction'dan ONCE: teklifNoGetir baglantiyi yoklayabilir.
    const QString silinenTeklifNo = teklifNoGetir(teklifId);
    // Gecmis tablolari (05, 09) kurulu degilse JSON'a eklenmez.
    const bool durumGecmisiVar = semaKolonuVarMi(m_db, QStringLiteral("dbo.teklif_durum_gecmisi"),
                                                 QStringLiteral("YeniDurum"));
    const bool duzeltmeGecmisiVar = semaKolonuVarMi(m_db, QStringLiteral("dbo.teklif_duzeltme_gecmisi"),
                                                    QStringLiteral("OncekiVeri"));

    if (!m_db.transaction())
    {
        m_sonHataMesaji = "İşlem başlatılamadı: " + m_db.lastError().text();
        return false;
    }

    {
        QSqlQuery iz(m_db);
        iz.prepare(QString(
            "INSERT INTO dbo.teklif_silme_gecmisi (TeklifId, TeklifNo, FirmaAdi, Durum, SilinenVeri, KullaniciId) "
            "SELECT t.TeklifId, :teklifNo, m.FirmaAdi, t.Durum, "
            "  (SELECT t2.*, "
            "          JSON_QUERY((SELECT tk.* FROM dbo.teklif_kalemleri tk "
            "                      WHERE tk.TeklifId = t2.TeklifId ORDER BY tk.TeklifKalemId "
            "                      FOR JSON PATH)) AS Kalemler, "
            "          JSON_QUERY((SELECT tt.* FROM dbo.teklif_toplamlari tt "
            "                      WHERE tt.TeklifId = t2.TeklifId "
            "                      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Toplamlar, "
            "          JSON_QUERY((SELECT sb.* FROM dbo.sevk_bilgileri sb "
            "                      WHERE sb.TeklifId = t2.TeklifId "
            "                      FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS SevkBilgileri%1%2 "
            "   FROM dbo.teklifler t2 WHERE t2.TeklifId = t.TeklifId "
            "   FOR JSON PATH, WITHOUT_ARRAY_WRAPPER), "
            "  :kullaniciId "
            "FROM dbo.teklifler t "
            "LEFT JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
            "WHERE t.TeklifId = :teklifId")
            .arg(durumGecmisiVar
                     ? QStringLiteral(", JSON_QUERY((SELECT dg.* FROM dbo.teklif_durum_gecmisi dg "
                                      "WHERE dg.TeklifId = t2.TeklifId FOR JSON PATH)) AS DurumGecmisi")
                     : QString(),
                 duzeltmeGecmisiVar
                     ? QStringLiteral(", JSON_QUERY((SELECT zg.* FROM dbo.teklif_duzeltme_gecmisi zg "
                                      "WHERE zg.TeklifId = t2.TeklifId FOR JSON PATH)) AS DuzeltmeGecmisi")
                     : QString()));
        iz.bindValue(":teklifNo", silinenTeklifNo.left(30));
        iz.bindValue(":kullaniciId", m_aktifKullaniciId > 0 ? QVariant(m_aktifKullaniciId)
                                                            : QVariant(QMetaType(QMetaType::Int)));
        iz.bindValue(":teklifId", teklifId);
        if (!iz.exec() || iz.numRowsAffected() != 1)
        {
            qWarning() << "teklifSil (silme izi) basarisiz:" << iz.lastError().text();
            m_db.rollback();
            m_sonHataMesaji = "Silme izi yazılamadığı için teklif silinmedi: " + iz.lastError().text();
            return false;
        }
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.teklifler WHERE TeklifId = :teklifId");
    query.bindValue(":teklifId", teklifId);
    if (!query.exec())
    {
        qWarning() << "Teklif silinemedi:" << query.lastError().text();
        m_db.rollback();
        m_sonHataMesaji = "Teklif silinemedi: " + query.lastError().text();
        return false;
    }

    // Teklife ozel "MANUEL-<teklifId>" urun satirlari artik hicbir kaleme bagli
    // degil (kalemler CASCADE ile silindi); katalogda yetim kalmasinlar.
    QSqlQuery manuelSil(m_db);
    manuelSil.prepare("DELETE FROM dbo.urunler WHERE UrunKodu = :kod "
                      "AND NOT EXISTS (SELECT 1 FROM dbo.teklif_kalemleri tk WHERE tk.UrunId = dbo.urunler.UrunId)");
    manuelSil.bindValue(":kod", QString("MANUEL-%1").arg(teklifId));
    if (!manuelSil.exec())
        qWarning() << "teklifSil (manuel urun temizligi) basarisiz:" << manuelSil.lastError().text();

    // Silinen kayit zincirin en son revizyonuysa onceki surum yeniden gecerlidir:
    // "Revize Edildi" olarak kalirsa listede/PDF'te hala gecersiz gorunurdu.
    int yenidenGecerliId = 0;
    if (sonSurumMu && kokId != teklifId)
    {
        QSqlQuery sonQuery(m_db);
        sonQuery.prepare("SELECT TOP 1 TeklifId, Durum FROM dbo.teklifler "
                         "WHERE TeklifId = :kok OR AnaTeklifId = :kok ORDER BY RevizyonNo DESC");
        sonQuery.bindValue(":kok", kokId);
        if (sonQuery.exec() && sonQuery.next() && sonQuery.value(1).toString() == DURUM_REVIZE_EDILDI)
        {
            yenidenGecerliId = sonQuery.value(0).toInt();
            QSqlQuery geriAl(m_db);
            geriAl.prepare("UPDATE dbo.teklifler SET Durum = N'Beklemede' WHERE TeklifId = :id");
            geriAl.bindValue(":id", yenidenGecerliId);
            if (!geriAl.exec())
            {
                m_db.rollback();
                m_sonHataMesaji = "Önceki sürüm yeniden geçerli yapılamadı: " + geriAl.lastError().text();
                return false;
            }
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        m_sonHataMesaji = "Teklif silinemedi: " + m_db.lastError().text();
        return false;
    }

    if (yenidenGecerliId > 0)
        durumDegisiminiLogla(yenidenGecerliId, DURUM_REVIZE_EDILDI, QStringLiteral("Beklemede"),
                             QStringLiteral("Yerine geçen revizyon silindiği için yeniden geçerli."), 0);
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
    qInfo() << "[olcum] urunAraBaslat istegi kuyruga alindi, arama=" << arama << "dil=" << dil;
    if (m_aramaWorker)
        QMetaObject::invokeMethod(m_aramaWorker, "urunAraCalistir", Qt::QueuedConnection,
                                   Q_ARG(QString, arama), Q_ARG(int, limit), Q_ARG(QString, dil));
}

QVariantMap Database::teklifKaydet(const QVariantMap &teklif)
{
    ERP_IZ("teklifKaydet");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["teklifId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
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
    QString denetimHatasi;
    if (!teklifVerisiniDenetle(teklif, denetimHatasi))
    {
        sonuc["hata"] = denetimHatasi;
        return sonuc;
    }

    // Teklifin ICINE yazilacak ayar degerleri transaction'dan ONCE okunur
    // (ayar okuma baglantiyi yoklayabilir; yazma isleminin ortasinda olmasin).
    //   * Sozlesme metni: QML bos gonderdiyse (pencere acilmadi/degismedi)
    //     yeni teklif / kopya -> dilin o anki varsayilan metni; revizyon ->
    //     fabrika metni. Bos gelmesi, revize edilen teklifin de metninin bos
    //     (NULL) oldugu anlamina gelir; NULL'lar bu kuraldan once kaydedilmis
    //     tekliflerdir ve fabrika metniyle basilirlar. Revizyon ayni sozlesmeyi tasir.
    //   * Gecerlilik gunu (db/25): o anki ayar; revizyon da yeni bir belge
    //     oldugu icin guncel sureyi alir.
    const QString teklifDili = teklif.value("dil", "TR").toString();
    QString sozlesmeMetni = teklif.value("sozlesmeMetni").toString().trimmed();
    if (sozlesmeMetni.isEmpty())
    {
        sozlesmeMetni = teklif.value("anaTeklifId", 0).toInt() > 0
            ? TeklifPdfOlusturucu::varsayilanSozlesmeMetni(teklifDili.compare("EN", Qt::CaseInsensitive) == 0)
            : varsayilanSozlesmeMetni(teklifDili);
    }
    const bool gecerlilikSutunu = semaKolonuVarMi(aktifDb(), QStringLiteral("dbo.teklifler"),
                                                  QStringLiteral("GecerlilikGunu"));
    const int gecerlilikGunu = qBound(1, qRound(ayarSayiGetir(QStringLiteral("TEKLIF_GECERLILIK_GUNU"))), 365);

    // Tum yazma islemini tek transaction icinde yapiyoruz: teklifler + teklif_kalemleri +
    // teklif_toplamlari ya hep birlikte kaydolur ya da hicbiri (yarim kalmis teklif olusmasin).
    if (!aktifDb().transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + aktifDb().lastError().text();
        return sonuc;
    }

    // Teklif No ve RevizyonNo "en buyuk + 1" ile verilir; ayni anda iki kayit
    // ayni numarayi almasin diye numara verme transaction sonuna kadar kilitlenir.
    {
        QString kilitHatasi;
        if (!numaraKilidiAl(kilitHatasi))
        {
            aktifDb().rollback();
            sonuc["hata"] = kilitHatasi;
            return sonuc;
        }
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
        // REVIZYON YALNIZCA GUNCEL SURUMDEN: yerine zaten yeni bir revizyon gecmis
        // bir tekliften revizyon alinirsa, guncel surum ESKI icerikten uretilmis
        // bir kayitla sessizce gecersiz kilinirdi.
        const int yerineGecen = teklifYerineGecenIdGetir(talepEdilenAnaTeklifId);
        if (yerineGecen != 0)
        {
            aktifDb().rollback();
            sonuc["hata"] = yerineGecen < 0
                ? QString("Teklifin revizyon zinciri okunamadı; lütfen tekrar deneyin.")
                : QString("Teklif %1'in yerine Teklif %2 geçti; revizyon güncel sürümden yapılmalı.")
                      .arg(teklifNoGetir(talepEdilenAnaTeklifId), teklifNoGetir(yerineGecen));
            return sonuc;
        }

        // Secilen teklif zaten bir revizyonsa, KOK teklife baglaniyoruz --
        // boylece revizyon zinciri hep tek bir ana teklif altinda kalir
        // (revizyonun revizyonu diye ayri bir dal olusmaz).
        QSqlQuery kokQuery(aktifDb());
        kokQuery.prepare("SELECT AnaTeklifId FROM dbo.teklifler WHERE TeklifId = :id");
        kokQuery.bindValue(":id", talepEdilenAnaTeklifId);
        if (kokQuery.exec() && kokQuery.next() && !kokQuery.value(0).isNull())
            anaTeklifId = kokQuery.value(0).toInt();
        else
            anaTeklifId = talepEdilenAnaTeklifId;

        // TAMAMLANMIS IS REVIZE EDILEMEZ: zincirde "Tamamlandı" bir teklif varsa
        // is bitmistir, yeni revizyon acilmaz. Yanlislikla tamamlandiysa kullanici
        // once durumu "Beklemede"ye geri alir (bkz. teklifDurumGuncelle).
        QSqlQuery tamamQuery(aktifDb());
        tamamQuery.prepare(
            "SELECT COUNT(*) FROM dbo.teklifler "
            "WHERE (TeklifId = :ana OR AnaTeklifId = :ana) AND Durum = :durum");
        tamamQuery.bindValue(":ana", anaTeklifId);
        tamamQuery.bindValue(":durum", QStringLiteral("Tamamlandı"));
        if (!tamamQuery.exec() || !tamamQuery.next() || tamamQuery.value(0).toInt() > 0)
        {
            aktifDb().rollback();
            sonuc["hata"] = tamamQuery.lastError().isValid()
                ? "Teklif durumu okunamadı: " + tamamQuery.lastError().text()
                : QStringLiteral("Tamamlanmış teklif revize edilemez. Gerekirse önce durumunu "
                                 "\"Beklemede\"ye alın.");
            return sonuc;
        }

        QSqlQuery revQuery(aktifDb());
        revQuery.prepare(
            "SELECT ISNULL(MAX(RevizyonNo), 0) FROM dbo.teklifler "
            "WHERE TeklifId = :ana OR AnaTeklifId = :ana");
        revQuery.bindValue(":ana", anaTeklifId);
        if (!revQuery.exec() || !revQuery.next())
        {
            // Eskiden basarisizlikta sessizce 1 varsayiliyordu -- var olan bir
            // Rev.1 ile cakisan numara uretebilirdi.
            aktifDb().rollback();
            sonuc["hata"] = "Revizyon numarası alınamadı: " + revQuery.lastError().text();
            return sonuc;
        }
        revizyonNo = revQuery.value(0).toInt() + 1;

        // FATURALANMIS TEKLIF REVIZE EDILEMEZ (bkz. faturaNoBul): fatura yeni
        // revizyona gecmez ve ayni is Muhasebe'de yeniden faturalanacak gorunur.
        QString faturaNo;
        if (!faturaNoBul(aktifDb(), anaTeklifId, true, faturaNo) || !faturaNo.isEmpty())
        {
            aktifDb().rollback();
            sonuc["hata"] = faturaNo.isEmpty()
                ? QStringLiteral("Teklifin fatura bilgisi okunamadı; lütfen tekrar deneyin.")
                : QString("Teklif faturalandı (Fatura No: %1); revize edilemez. "
                          "Önce Muhasebe'den fatura bilgisi kaldırılmalı.").arg(faturaNo);
            return sonuc;
        }
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
            aktifDb().rollback();
            sonuc["hata"] = noHatasi.isEmpty() ? QStringLiteral("Teklif numarası alınamadı.") : noHatasi;
            return sonuc;
        }
    }

    QSqlQuery teklifEkle(aktifDb());
    teklifEkle.prepare(QString(
        "INSERT INTO dbo.teklifler "
        "(MusteriId, KullaniciId, GenelIndirimOrani, KdvOrani, Durum, MusteriNotu, UretimNotu, ParaBirimi, Dil, "
        " IlgiliKisi, IlgiliKisiTelefonu, IlgiliKisiEposta, TeslimatSekli, TeslimatYeri, "
        " TeslimatTarihi, SatisSozlesmesiMetni, AnaTeklifId, RevizyonNo%1%3) "
        "OUTPUT INSERTED.TeklifId "
        "VALUES (:musteriId, :kullaniciId, :indirim, :kdv, N'Beklemede', :not, :uretimNotu, :paraBirimi, :dil, "
        "        :ilgiliKisi, :ilgiliKisiTel, :ilgiliKisiEposta, :teslimatSekli, :teslimatYeri, "
        "        :teslimatTarihi, :sozlesmeMetni, :anaTeklifId, :revizyonNo%2%4)")
        .arg(teklifNoYazilacak ? QStringLiteral(", TeklifNo") : QString(),
             teklifNoYazilacak ? QStringLiteral(", :teklifNo") : QString(),
             gecerlilikSutunu ? QStringLiteral(", GecerlilikGunu") : QString(),
             gecerlilikSutunu ? QStringLiteral(", :gecerlilikGunu") : QString()));
    if (teklifNoYazilacak)
        teklifEkle.bindValue(":teklifNo", teklifNo);
    teklifEkle.bindValue(":musteriId", musteriId);
    if (anaTeklifId > 0)
        teklifEkle.bindValue(":anaTeklifId", anaTeklifId);
    else
        teklifEkle.bindValue(":anaTeklifId", QVariant(QMetaType(QMetaType::Int)));
    teklifEkle.bindValue(":revizyonNo", revizyonNo);
    // Kaydi yapan kisi oturumdan alinir; QML'in gonderdigi "kullaniciId"
    // yok sayilir (bkz. aktifKullaniciId).
    const int kullaniciId = m_aktifKullaniciId;
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

    // Sozlesme metni HER ZAMAN teklifin icine yazilir: varsayilan metin
    // (Yonetim / Sistem Ayarlari) sonradan degisse de bu teklif kaydedildigi
    // metinle basilir (metnin nasil secildigi: transaction'in ustu).
    teklifEkle.bindValue(":sozlesmeMetni", sozlesmeMetni);
    if (gecerlilikSutunu)
        teklifEkle.bindValue(":gecerlilikGunu", gecerlilikGunu);

    if (!teklifEkle.exec() || !teklifEkle.next())
    {
        qWarning() << "teklifKaydet (teklifler) basarisiz:" << teklifEkle.lastError().text();
        aktifDb().rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + teklifEkle.lastError().text();
        return sonuc;
    }

    const int teklifId = teklifEkle.value(0).toInt();

    QString icerikHatasi;
    if (!teklifIceriginiYaz(teklifId, teklif, icerikHatasi))
    {
        aktifDb().rollback();
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
        QSqlQuery kopyaIzi(aktifDb());
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
    // Beklemede'nin yaninda KABUL EDILMIS ve REDDEDILMIS eski surumler de
    // isaretlenir. Eskiden yalnizca Beklemede'ler isaretleniyordu: kabul edilmis
    // bir teklif revize edilince eski surum "Kabul Edildi" kalip yeni revizyon da
    // kabul edilebiliyordu -- ayni teklifin iki fiyatli surumu birden Alınan
    // Tekliflerim'de, ikisi de uretime gidebilir halde duruyordu. Kabul edilmis
    // bir teklifin revizyonu, musteriyle yeniden mutabakat demektir: yeni
    // revizyon ayrica kabul edilmelidir. (Tamamlandı zaten revize edilemez.)
    // Durum tarihleri, teklifDurumGuncelle'deki "Revize Edildi" gecisiyle ayni
    // sekilde temizlenir; eski degerler durum gecmisinde kalir.
    QVariantList revizeEdilenler;
    QHash<int, QString> revizeEdilenEskiDurum;
    if (anaTeklifId > 0)
    {
        const QString gecersizKilinacaklar = QStringLiteral(
            "WHERE (TeklifId = :ana OR AnaTeklifId = :ana) "
            "  AND TeklifId <> :yeni "
            "  AND Durum IN (N'Beklemede', N'Kabul Edildi', N'Reddedildi')");
        QSqlQuery eskiQuery(aktifDb());
        eskiQuery.prepare("SELECT TeklifId, Durum FROM dbo.teklifler " + gecersizKilinacaklar);
        eskiQuery.bindValue(":ana", anaTeklifId);
        eskiQuery.bindValue(":yeni", teklifId);
        if (!eskiQuery.exec())
        {
            aktifDb().rollback();
            sonuc["hata"] = "Eski teklif sürümleri okunamadı: " + eskiQuery.lastError().text();
            return sonuc;
        }
        while (eskiQuery.next())
        {
            const int eskiId = eskiQuery.value(0).toInt();
            revizeEdilenler << eskiId;
            revizeEdilenEskiDurum.insert(eskiId, eskiQuery.value(1).toString());
        }

        if (!revizeEdilenler.isEmpty())
        {
            QSqlQuery isaretle(aktifDb());
            isaretle.prepare(
                "UPDATE dbo.teklifler SET Durum = :durum, "
                "  KabulTarihi = NULL, RedTarihi = NULL, RedSebebi = NULL, TeslimTarihi = NULL "
                + gecersizKilinacaklar);
            isaretle.bindValue(":durum", DURUM_REVIZE_EDILDI);
            isaretle.bindValue(":ana", anaTeklifId);
            isaretle.bindValue(":yeni", teklifId);
            if (!isaretle.exec())
            {
                qWarning() << "teklifKaydet (revize isaretleme) basarisiz:" << isaretle.lastError().text();
                aktifDb().rollback();
                sonuc["hata"] = "Eski teklif revize edilmiş olarak işaretlenemedi: " + isaretle.lastError().text();
                return sonuc;
            }
        }

        // Sevk/irsaliye bilgileri (fatura basligi, siparis sartlari...) siparisin
        // bilgisidir, teklifin belirli bir surumunun degil: eskiden eski surumde
        // kaliyor, yeni revizyonda "İrsaliye" penceresi bos aciliyordu. Zincirde
        // kaydi olan en guncel surumden yeni revizyona KOPYALANIR (eski surumdeki
        // kayit gecmis olarak yerinde kalir).
        QString sevkHatasi;
        if (!sevkBilgileriniRevizyonaKopyala(anaTeklifId, teklifId, sevkHatasi))
        {
            aktifDb().rollback();
            sonuc["hata"] = sevkHatasi;
            return sonuc;
        }
    }

    if (!aktifDb().commit())
    {
        qWarning() << "teklifKaydet commit basarisiz:" << aktifDb().lastError().text();
        aktifDb().rollback();
        sonuc["hata"] = "Teklif kaydedilemedi: " + aktifDb().lastError().text();
        return sonuc;
    }

    // Durum gecmisi loglari bilincli olarak COMMIT SONRASI yazilir: loglama
    // "best effort"tur (tablo yoksa hata verir) ve bunun teklif kaydini goturmesi
    // istenmez (bkz. durumDegisiminiLogla).
    const QString yeniTeklifNoMetni = teklifNoGetir(teklifId);
    // Revizyon sebebi hem eski teklif(ler)in "Revize Edildi" satirina hem de
    // yeni revizyonun ilk satirina yazilir: iki taraftan da Teklif Gecmisi'nde
    // okunur.
    const QString revizyonSebebi = teklif.value("revizyonSebebi").toString().trimmed();
    const QString sebepEki = revizyonSebebi.isEmpty() ? QString() : " Sebep: " + revizyonSebebi;
    for (const QVariant &eskiId : std::as_const(revizeEdilenler))
        durumDegisiminiLogla(eskiId.toInt(), revizeEdilenEskiDurum.value(eskiId.toInt()), DURUM_REVIZE_EDILDI,
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

        QSqlQuery kalemEkle(aktifDb());
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
            QSqlQuery manuelUrun(aktifDb());
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

    QSqlQuery toplamEkle(aktifDb());
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
    // Beklemede'ye donus faturali teklifte engelli; bu, ondan onceki kayitlar icin.
    QString faturaNo;
    if (!faturaNoBul(aktifDb(), teklifId, false, faturaNo))
    {
        hataOut = QStringLiteral("Teklifin fatura bilgisi okunamadı; lütfen tekrar deneyin.");
        return false;
    }
    if (!faturaNo.isEmpty())
    {
        hataOut = QString("Teklif faturalandı (Fatura No: %1); düzeltilemez. "
                          "Önce Muhasebe'den fatura bilgisi kaldırılmalı.").arg(faturaNo);
        return false;
    }
    const int yerineGecen = teklifYerineGecenIdGetir(teklifId);
    if (yerineGecen != 0)
    {
        hataOut = yerineGecen < 0
            ? QString("Teklifin revizyon zinciri okunamadı; lütfen tekrar deneyin.")
            : QString("Bu teklifin yerine Teklif %1 geçti; düzeltme güncel revizyon üzerinde yapılmalı.")
                  .arg(teklifNoGetir(yerineGecen));
        return false;
    }
    return true;
}

bool Database::teklifDuzeltilebilirMi(int teklifId)
{
    ERP_IZ("teklifDuzeltilebilirMi");
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
    ERP_IZ("teklifDuzelt");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["teklifId"] = teklifId;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
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
    QString denetimHatasi;
    if (!teklifVerisiniDenetle(teklif, denetimHatasi))
    {
        sonuc["hata"] = denetimHatasi;
        return sonuc;
    }

    if (!aktifDb().transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + aktifDb().lastError().text();
        return sonuc;
    }

    // Kural denetimi transaction ICINDE ve satir kilidiyle: kontrol ile yazma
    // arasinda baska bir kullanici teklifi kabul edemesin / revize edemesin.
    {
        QSqlQuery kilit(aktifDb());
        kilit.prepare("SELECT Durum FROM dbo.teklifler WITH (UPDLOCK, ROWLOCK) WHERE TeklifId = :id");
        kilit.bindValue(":id", teklifId);
        kilit.exec();
    }
    QString kuralHatasi;
    if (!duzeltmeKuraliniDenetle(teklifId, kuralHatasi))
    {
        aktifDb().rollback();
        sonuc["hata"] = kuralHatasi;
        return sonuc;
    }

    // --- 1) Iz: ustune yazmadan ONCE teklifin tam hali -------------------------
    // Sunucu tarafinda FOR JSON ile uretilir: veritabanindaki degerler (para
    // birimi/kur donusumu yapilmamis, ham haliyle) aynen saklanir. Firma adi da
    // eklenir -- duzeltmelerin en sik sebebi yanlis firma secimidir ve MusteriId
    // tek basina okunakli degildir.
    QSqlQuery iz(aktifDb());
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
    const int kullaniciId = m_aktifKullaniciId;
    iz.bindValue(":kullaniciId", kullaniciId > 0 ? QVariant(kullaniciId) : QVariant(QMetaType(QMetaType::Int)));
    iz.bindValue(":teklifId", teklifId);
    if (!iz.exec() || iz.numRowsAffected() != 1)
    {
        qWarning() << "teklifDuzelt (iz) basarisiz:" << iz.lastError().text();
        aktifDb().rollback();
        sonuc["hata"] = "Düzeltme geçmişi yazılamadığı için teklif değiştirilmedi. "
                        "(db/09_teklif_duzeltme_gecmisi.sql çalıştırıldı mı?) "
                        "Değişikliği revizyon olarak kaydedebilirsiniz.";
        return sonuc;
    }

    // --- 2) Baslik: ayni TeklifId yerinde guncellenir ----------------------------
    // Dokunulmayanlar bilincli: KullaniciId (teklifi hazirlayan), OlusturmaTarihi,
    // Durum ve durum tarihleri, AnaTeklifId/RevizyonNo (zincirdeki yeri),
    // KopyaKaynakTeklifId. Duzeltme teklifin kimligini degil icerigini duzeltir.
    QSqlQuery baslik(aktifDb());
    baslik.prepare(
        "UPDATE dbo.teklifler SET "
        "  MusteriId = :musteriId, GenelIndirimOrani = :indirim, KdvOrani = :kdv, "
        "  MusteriNotu = :not, UretimNotu = :uretimNotu, ParaBirimi = :paraBirimi, Dil = :dil, "
        "  IlgiliKisi = :ilgiliKisi, IlgiliKisiTelefonu = :ilgiliKisiTel, IlgiliKisiEposta = :ilgiliKisiEposta, "
        "  TeslimatSekli = :teslimatSekli, TeslimatYeri = :teslimatYeri, "
        "  TeslimatTarihi = :teslimatTarihi, "
        "  SatisSozlesmesiMetni = COALESCE(:sozlesmeMetni, SatisSozlesmesiMetni) "
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
    // Bos = sozlesmeye dokunulmadi: kayitli metin (NULL ise NULL) aynen kalir.
    const QString sozlesmeMetni = teklif.value("sozlesmeMetni").toString().trimmed();
    baslik.bindValue(":sozlesmeMetni", sozlesmeMetni.isEmpty()
        ? QVariant(QMetaType(QMetaType::QString)) : QVariant(sozlesmeMetni));
    baslik.bindValue(":teklifId", teklifId);
    if (!baslik.exec() || baslik.numRowsAffected() != 1)
    {
        qWarning() << "teklifDuzelt (baslik) basarisiz:" << baslik.lastError().text();
        aktifDb().rollback();
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
        QSqlQuery temizlik(aktifDb());
        temizlik.prepare(sql);
        if (sql.contains(":teklifId"))
            temizlik.bindValue(":teklifId", teklifId);
        if (sql.contains(":manuelKod"))
            temizlik.bindValue(":manuelKod", QString("MANUEL-%1").arg(teklifId));
        if (!temizlik.exec())
        {
            qWarning() << "teklifDuzelt (eski icerik) basarisiz:" << temizlik.lastError().text();
            aktifDb().rollback();
            sonuc["hata"] = "Teklifin eski içeriği güncellenemedi: " + temizlik.lastError().text();
            return sonuc;
        }
    }

    QString icerikHatasi;
    if (!teklifIceriginiYaz(teklifId, teklif, icerikHatasi))
    {
        aktifDb().rollback();
        sonuc["hata"] = icerikHatasi;
        return sonuc;
    }

    if (!aktifDb().commit())
    {
        qWarning() << "teklifDuzelt commit basarisiz:" << aktifDb().lastError().text();
        aktifDb().rollback();
        sonuc["hata"] = "Teklif düzeltilemedi: " + aktifDb().lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["teklifNo"] = teklifNoGetir(teklifId);
    return sonuc;
}

QVariantMap Database::teklifDuzenlemeVerisiGetir(int teklifId)
{
    ERP_IZ("teklifDuzenlemeVerisiGetir");
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
        "       t.MusteriNotu, t.UretimNotu, t.TeslimatTarihi, t.Durum, t.OlusturmaTarihi, %2 AS GecerlilikGunu, "
        "       tt.PaketlemeUcreti, tt.TasimaUcreti, "
        "       tt.IndirimliToplam, tt.KdvTutari, tt.GenelToplam "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "WHERE t.TeklifId = :teklifId").arg(teklifNoSql("t"),
            semaKolonuVarMi(m_db, QStringLiteral("dbo.teklifler"), QStringLiteral("GecerlilikGunu"))
                ? QStringLiteral("t.GecerlilikGunu") : QStringLiteral("CAST(NULL AS INT)")));
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
    const bool toplamKaydiVar = !basQuery.value("GenelToplam").isNull();
    const double kayitliIndirimliToplam = basQuery.value("IndirimliToplam").toDouble();
    const double kayitliKdvTutari = basQuery.value("KdvTutari").toDouble();
    const double kayitliGenelToplam = basQuery.value("GenelToplam").toDouble();
    const QString musteriNotuDeger = basQuery.value("MusteriNotu").toString();
    const QString uretimNotuDeger = basQuery.value("UretimNotu").toString();
    const QVariant teslimatTarihiHam = basQuery.value("TeslimatTarihi");
    const QString teslimatTarihiDeger = teslimatTarihiHam.isNull()
        ? QString() : teslimatTarihiHam.toDateTime().date().toString("yyyy-MM-dd");
    const QString durumDeger = basQuery.value("Durum").toString();
    const QString olusturmaTarihiDeger = basQuery.value("OlusturmaTarihi").toDateTime().date().toString("yyyy-MM-dd");

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
        // Birim fiyat teklifin para birimindedir; maliyet katalog gibi TL'dir.
        // Kur bilinmeyen dovizli teklifte Kur=1 ve MaliyetFiyati zaten TL'dir.
        kalem["birimFiyat"] = birimFiyat;
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
    // Teklifin gecerlilik gunu; saklanmamissa (eski teklif) PDF ile ayni sabit.
    sonuc["gecerlilikGunu"] = basQuery.value("GecerlilikGunu").toInt() > 0
        ? basQuery.value("GecerlilikGunu").toInt() : TeklifPdfOlusturucu::kVarsayilanGecerlilikGunu;
    sonuc["musteriNotu"] = musteriNotuDeger;
    sonuc["uretimNotu"] = uretimNotuDeger;
    sonuc["teslimatTarihi"] = teslimatTarihiDeger;
    sonuc["durum"] = durumDeger;
    // Sozlesme penceresindeki {{GECERLILIK_TARIHI}} onizlemesi PDF ile ayni
    // tarihten hesaplansin diye (bkz. sozlesmeSatirlari).
    sonuc["olusturmaTarihi"] = olusturmaTarihiDeger;
    sonuc["paketlemeUcreti"] = paketlemeUcreti;
    sonuc["tasimaUcreti"] = tasimaUcreti;
    // Veritabanindaki (PDF'e basilan) toplamlar, teklifin para biriminde. Eski
    // kurallarla (ör. KDV yalnizca urun toplamindan) kaydedilmis tekliflerde
    // ekranin yeniden hesabi bunlardan farkli olabilir; ekran farki gosterir.
    sonuc["kayitliToplamVar"] = toplamKaydiVar;
    sonuc["kayitliIndirimliToplam"] = kayitliIndirimliToplam;
    sonuc["kayitliKdvTutari"] = kayitliKdvTutari;
    sonuc["kayitliGenelToplam"] = kayitliGenelToplam;
    sonuc["kur"] = kur;
    // Dovizli teklifte gercek bir kur 1'den buyuktur. Eski programdan gocen
    // tekliflerde Kur sutununa 1 yazilmistir (bkz. db/02_veri_gocu.sql) ama
    // BirimFiyat dovizdir -- bu kurla "TL" hesaplamak 54 USD'yi 54 TL yapar.
    const QString pb = paraBirimi.trimmed().toUpper();
    const bool dovizli = pb == QLatin1String("USD") || pb == QLatin1String("EUR");
    sonuc["kurBilinmiyor"] = dovizli && kur <= 1.0001;
    sonuc["kalemler"] = kalemler;

    // Yerine yeni revizyon gecmis teklif yalnizca goruntulenir (bkz. teklifKaydet:
    // revizyon yalnizca guncel surumden alinir).
    const int yerineGecen = teklifYerineGecenIdGetir(okunanTeklifId);
    sonuc["guncelSurum"] = yerineGecen == 0;
    sonuc["guncelTeklifNo"] = yerineGecen > 0 ? teklifNoGetir(yerineGecen) : sonuc["teklifNo"].toString();
    // Faturalanmis zincir revize edilemez (bkz. teklifKaydet); ekran revizyonu
    // bastan kapatir. Okunamazsa kayit sirasindaki denetim yine engeller.
    QString faturaNo;
    faturaNoBul(m_db, okunanTeklifId, true, faturaNo);
    sonuc["faturaNo"] = faturaNo;
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

    QSqlQuery query(aktifDb());
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
    ERP_IZ("teklifNoGetir");
    if (teklifId <= 0 || !baglantiHazir())
        return QString::number(teklifId);

    QSqlQuery query(aktifDb());
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
    QSqlQuery query(aktifDb());
    query.prepare(QString("SELECT %1 FROM dbo.teklifler t WHERE t.TeklifId = :id").arg(teklifNoSql("t")));
    query.bindValue(":id", kokTeklifId);
    if (!query.exec() || !query.next())
    {
        qWarning() << "kokTeklifNoGetir basarisiz:" << kokTeklifId << query.lastError().text();
        return 0;
    }
    return query.value(0).toInt();
}

bool Database::numaraKilidiAl(QString &hataOut)
{
    // Acik transaction icinde cagrilir. Ayni anda iki bilgisayardan teklif (ya
    // da ayni teklifin revizyonu) kaydedilirse ikisi ayni "en buyuk + 1"i okuyup
    // ayni numarayi almasin diye numara verme transaction sonuna kadar
    // kilitlenir: ikinci kayit, birincisi bitene kadar bekler ve onun numarasini gorur.
    //
    // sp_getapplock zaman asiminda HATA FIRLATMAZ, negatif donus kodu verir;
    // bu yuzden kod okunup denetlenir (eskiden yalnizca exec() sonucuna
    // bakiliyordu ve kilit alinamasa da devam ediliyordu).
    QSqlQuery kilit(aktifDb());
    kilit.prepare("SET NOCOUNT ON; DECLARE @sonuc INT; "
                  "EXEC @sonuc = sp_getapplock @Resource = N'LiyaErp_TeklifNo', @LockMode = 'Exclusive', "
                  "@LockOwner = 'Transaction', @LockTimeout = 15000; "
                  "SELECT @sonuc;");
    if (!kilit.exec() || !kilit.next())
    {
        qWarning() << "numaraKilidiAl basarisiz:" << kilit.lastError().text();
        hataOut = QStringLiteral("Teklif numarası alınamadı: ") + kilit.lastError().text();
        return false;
    }
    if (kilit.value(0).toInt() < 0)
    {
        hataOut = QStringLiteral("Teklif numarası alınamadı: başka bir kayıt sürüyor, lütfen tekrar deneyin.");
        return false;
    }
    return true;
}

int Database::yeniTeklifNoAl(QString &hataOut)
{
    // teklifNoSql, TeklifNo'su bos (eski surum programla kaydedilmis) satirlarin
    // gosterilen numarasini da hesaba katar -- boylece yeni numara hicbir
    // gorunen numarayla cakismaz.
    QSqlQuery query(aktifDb());
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

    QSqlQuery query(aktifDb());
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
    QSqlQuery query(aktifDb());
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
        // -1 = bilinmiyor. Eskiden 0 ("guncel surum") donuyordu ve baglanti
        // hatasinda revize edilmis teklif uzerinde islem yapilabiliyordu.
        // Yazmayi koruyan cagiranlar "!= 0" ile denetler: hata = reddet.
        qWarning() << "teklifYerineGecenIdGetir basarisiz:" << teklifId << query.lastError().text();
        return -1;
    }
    return query.next() ? query.value(0).toInt() : 0;
}

QString Database::teklifDurumuGetir(int teklifId)
{
    QSqlQuery query(aktifDb());
    query.prepare("SELECT Durum FROM dbo.teklifler WHERE TeklifId = :id");
    query.bindValue(":id", teklifId);
    if (query.exec() && query.next())
        return query.value(0).toString();
    qWarning() << "teklifDurumuGetir basarisiz:" << teklifId << query.lastError().text();
    return QString();
}

bool Database::teklifTeslimatTarihiGuncelle(int teklifId, const QString &teslimatTarihi)
{
    ERP_IZ("teklifTeslimatTarihiGuncelle");
    if (teklifId <= 0 || !baglantiHazir())
        return false;
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

    // Uretim planlamasi bilgisi: kabul edilmis teklifte de degisebilir, ama
    // tamamlanmis (teslim edilmis) teklifte artik degistirilemez.
    // Yerine yeni revizyon gecmis teklifin uretim planlamasi da yapilmaz.
    const QString durum = teklifDurumuGetir(teklifId);
    if (durum == "Tamamlandı" || teklifYerineGecenIdGetir(teklifId) != 0)
    {
        qWarning() << "teklifTeslimatTarihiGuncelle: tamamlanmis/revize edilmis teklif degistirilemez:" << teklifId;
        m_sonHataMesaji = QString::fromUtf8("Tamamlanmış ya da revize edilmiş teklifin teslim tarihi değiştirilemez.");
        return false;
    }

    // Tarih musteri PDF'ine basilir ama duzeltme/revizyon olmadan yerinde
    // degisir: eski deger durum gecmisine yazilsin diye once okunur.
    QString eskiTarih;
    {
        QSqlQuery eskiQuery(m_db);
        eskiQuery.prepare("SELECT TeslimatTarihi FROM dbo.teklifler WHERE TeklifId = :id");
        eskiQuery.bindValue(":id", teklifId);
        if (eskiQuery.exec() && eskiQuery.next() && !eskiQuery.value(0).isNull())
            eskiTarih = eskiQuery.value(0).toDateTime().date().toString("yyyy-MM-dd");
    }
    // Gecersiz metin tarihParametresi'nde NULL yazilir; karsilastirma da oyle.
    const QDate yeniTarihDeger = QDate::fromString(teslimatTarihi.trimmed(), "yyyy-MM-dd");
    const QString yeniTarih = yeniTarihDeger.isValid() ? yeniTarihDeger.toString("yyyy-MM-dd") : QString();
    if (eskiTarih == yeniTarih)
        return true;

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.teklifler SET TeslimatTarihi = :tarih WHERE TeklifId = :id");
    query.bindValue(":tarih", tarihParametresi(teslimatTarihi));
    query.bindValue(":id", teklifId);

    if (!query.exec())
    {
        qWarning() << "teklifTeslimatTarihiGuncelle basarisiz:" << query.lastError().text();
        m_sonHataMesaji = "Planlanan teslim tarihi kaydedilemedi: " + query.lastError().text();
        return false;
    }

    // EskiDurum = YeniDurum: durum degismedi, gecmis ekranlari bu satiri
    // "Planlanan teslim tarihi değişti" olarak gosterir.
    const auto tarihMetni = [](const QString &yyyyAaGg) {
        const QDate tarih = QDate::fromString(yyyyAaGg, "yyyy-MM-dd");
        return tarih.isValid() ? tarih.toString("dd.MM.yyyy") : QStringLiteral("—");
    };
    durumDegisiminiLogla(teklifId, durum, durum,
                         tarihMetni(eskiTarih) + QStringLiteral("  →  ") + tarihMetni(yeniTarih),
                         m_aktifKullaniciId);
    return true;
}

bool Database::teklifMusteriNotuGuncelle(int teklifId, const QString &musteriNotu)
{
    ERP_IZ("teklifMusteriNotuGuncelle");
    if (teklifId <= 0 || !baglantiHazir())
        return false;
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

    // Teklif notu teklifin parcasidir: kabul edilmis teklifte degistirilemez.
    // Yerine yeni revizyon gecmis (gecersiz) surumun notu da degismez.
    if (teklifKilitliMi(teklifDurumuGetir(teklifId)) || teklifYerineGecenIdGetir(teklifId) != 0)
    {
        qWarning() << "teklifMusteriNotuGuncelle: kilitli/revize edilmis teklif degistirilemez:" << teklifId;
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
    ERP_IZ("teklifUretimNotuGuncelle");
    if (teklifId <= 0 || !baglantiHazir())
        return false;
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

    // Planlanan teslim tarihi gibi: kabul edilmis teklifte yazilabilir,
    // tamamlanmis teklifte degistirilemez.
    if (teklifDurumuGetir(teklifId) == "Tamamlandı" || teklifYerineGecenIdGetir(teklifId) != 0)
    {
        qWarning() << "teklifUretimNotuGuncelle: tamamlanmis/revize edilmis teklif degistirilemez:" << teklifId;
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
        "SELECT t.Durum, t.TeklifId FROM dbo.teklif_kalemleri tk "
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
    const QString durum = query.value(0).toString();
    const int teklifId = query.value(1).toInt();
    if (durum == "Tamamlandı")
    {
        qWarning() << "teklif kalemi uretim bilgisi degistirilemez (teklif tamamlandi):" << teklifKalemId;
        return false;
    }
    // Yerine yeni revizyon gecmis teklifin kalemleri uretimde takip edilmez.
    if (teklifYerineGecenIdGetir(teklifId) != 0)
    {
        qWarning() << "teklif kalemi uretim bilgisi degistirilemez (teklif revize edildi):" << teklifKalemId;
        return false;
    }
    return true;
}

bool Database::teklifKalemTamamlandiGuncelle(int teklifKalemId, bool tamamlandi)
{
    ERP_IZ("teklifKalemTamamlandiGuncelle");
    if (teklifKalemId <= 0 || !baglantiHazir())
        return false;
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

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
    ERP_IZ("teklifKalemUretimNotuGuncelle");
    if (teklifKalemId <= 0 || !baglantiHazir())
        return false;
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

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
    ERP_IZ("teklifDurumGuncelle");
    if (!baglantiHazir())
        return false;

    // QML, false donusunde sebebi sonHataMesaji()'ndan okuyor; onceki bir islemden
    // kalan mesaji yanlislikla bu cagriya ait sanmasin diye basta temizliyoruz.
    m_sonHataMesaji.clear();

    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
        return false;
    }

    // "Revize Edildi" elle verilemez: yalnizca teklifKaydet bir revizyon
    // olustururken (kendi UPDATE'iyle) yazar. Bu metot QML'e acik oldugu icin
    // yalnizca menudeki durumlari kabul eder.
    if (!gecerliDurumlar().contains(durum))
    {
        qWarning() << "teklifDurumGuncelle: gecersiz durum:" << durum;
        m_sonHataMesaji = QString::fromUtf8("Geçersiz durum: \"%1\".").arg(durum);
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
    // Durum sutunu ne olursa olsun uygulanir -- eskiden yalnizca "Revize Edildi"
    // satirlarda bakiliyordu ve yerine yeni revizyon gecmis "Reddedildi" (ya da
    // eski surum programla kalmis "Kabul Edildi") bir surum hala kabul edilebiliyordu.
    {
        const int yerineGecen = teklifYerineGecenIdGetir(teklifId);
        if (yerineGecen < 0)
        {
            m_sonHataMesaji = QString::fromUtf8("Teklifin revizyon zinciri okunamadı; lütfen tekrar deneyin.");
            return false;
        }
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

    // TAMAMLANDI YALNIZCA KABULDEN SONRA: "Beklemede"/"Reddedildi" bir teklif
    // dogrudan "Tamamlandı" yapilirsa, musterinin hic kabul etmedigi teklife
    // KabulTarihi olarak o an yazilir ve Alınan Tekliflerim/uretim asamasi
    // atlanmis olurdu. Once "Kabul Edildi" yapilmalidir.
    if (durum == "Tamamlandı" && eskiDurum != "Kabul Edildi")
    {
        m_sonHataMesaji = QString::fromUtf8("Teklif %1 \"%2\" durumunda; \"Tamamlandı\" yapılmadan önce "
                                            "\"Kabul Edildi\" olmalı.")
                              .arg(teklifNoGetir(teklifId), eskiDurum);
        return false;
    }

    // FATURALANMIS TEKLIF SIPARIS OLMAKTAN CIKAMAZ (bkz. faturaNoBul):
    // Beklemede'den sonra duzeltilip silinebilirdi. Kabul Edildi <-> Tamamlandı serbest.
    if (durum == "Beklemede" || durum == "Reddedildi")
    {
        QString faturaNo;
        if (!faturaNoBul(m_db, teklifId, false, faturaNo))
        {
            m_sonHataMesaji = QString::fromUtf8("Teklifin fatura bilgisi okunamadı; lütfen tekrar deneyin.");
            return false;
        }
        if (!faturaNo.isEmpty())
        {
            m_sonHataMesaji = QString::fromUtf8("Teklif %1 faturalandı (Fatura No: %2); \"%3\" yapılamaz. "
                                                "Önce Muhasebe'den fatura bilgisi kaldırılmalı.")
                                  .arg(teklifNoGetir(teklifId), faturaNo, durum);
            return false;
        }
    }

    // KABULDE PLANLANAN TESLIM TARIHI ZORUNLU: secilmesi unutuluyordu. Arayuz
    // onay penceresinde tarihi alip once teklifTeslimatTarihiGuncelle ile yazar.
    if (durum == "Kabul Edildi")
    {
        QSqlQuery tarihQuery(m_db);
        tarihQuery.prepare("SELECT TeslimatTarihi FROM dbo.teklifler WHERE TeklifId = :id");
        tarihQuery.bindValue(":id", teklifId);
        if (!tarihQuery.exec() || !tarihQuery.next() || tarihQuery.value(0).isNull())
        {
            m_sonHataMesaji = QString::fromUtf8("Teklif %1 kabul edilmeden önce planlanan teslim tarihi seçilmeli.")
                                  .arg(teklifNoGetir(teklifId));
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
    // dolu degilse (yalnizca goc verisinde olabilir; Tamamlandı'ya artik yalnizca
    // Kabul Edildi'den gecilir, bkz. yukaridaki kural) simdiki zamanla doldurulur.
    // Ayni sebeple "Tamamlandı -> Kabul Edildi" geri alisinda da musterinin ASIL
    // kabul tarihi korunur (ISNULL); diger durumlardan gelindiginde (goc verisinde
    // eski bir deger kalmis olabilir) her zaman simdiki zaman yazilir.
    //
    // UretimPdfTarihi hicbir gecişte silinmez: uretim PDF'inin teknik ekibe
    // verilmis olmasi, durum sonradan degisse de gecmiste yasanmis bir olaydir.
    QString sql = "UPDATE dbo.teklifler SET Durum = :durum";
    if (durum == "Beklemede")
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
    // RedSebebi sutunu 500 karakter: uzun bir metin "truncated" hatasiyla tum
    // durum degisikligini dusurmesin.
    const QString temizRedSebebi = redSebebi.trimmed().left(500);
    if (durum == "Reddedildi")
        query.bindValue(":redSebebi", temizRedSebebi.isEmpty() ? QVariant(QMetaType(QMetaType::QString))
                                                               : QVariant(temizRedSebebi));

    if (!query.exec())
    {
        qWarning() << "teklifDurumGuncelle basarisiz:" << query.lastError().text();
        m_sonHataMesaji = "Durum güncellenemedi: " + query.lastError().text();
        return false;
    }

    // NOT: Eskiden "Tamamlandı"da tum kalemlerin Tamamlandi bayragi 1 yapiliyordu;
    // tamamlanma geri alininca hangi kalemin GERCEKTEN bittigi kayboluyordu.
    // Artik kalemlere yazilmaz: tamamlanmis teklifte tum kalemler ekranda ve
    // uretim PDF'inde bitmis gosterilir (bkz. TeklifPdfOlusturucu::uretimPdfUret).

    // Degisikligi yapan kisi oturumdan alinir; parametre yalnizca eski
    // QML cagrilariyla uyum icin durur.
    Q_UNUSED(kullaniciId);
    durumDegisiminiLogla(teklifId, eskiDurum, durum, temizRedSebebi, m_aktifKullaniciId);
    return true;
}

void Database::durumDegisiminiLogla(int teklifId, const QString &eskiDurum, const QString &yeniDurum,
                                    const QString &aciklama, int kullaniciId)
{
    // "Best effort": 05_teklif_durum_gecmisi.sql henuz calistirilmadiysa tablo yoktur.
    // Bu durumda durum degisiminin kendisini basarisiz saymak yanlis olur -- sadece
    // uyari basip geciyoruz (log tutulmaz, uygulama calismaya devam eder).
    QSqlQuery logQuery(aktifDb());
    logQuery.prepare(
        "INSERT INTO dbo.teklif_durum_gecmisi (TeklifId, EskiDurum, YeniDurum, Aciklama, KullaniciId) "
        "VALUES (:teklifId, :eskiDurum, :yeniDurum, :aciklama, :kullaniciId)");
    logQuery.bindValue(":teklifId", teklifId);
    logQuery.bindValue(":eskiDurum", eskiDurum.isEmpty() ? QVariant(QMetaType(QMetaType::QString)) : eskiDurum);
    logQuery.bindValue(":yeniDurum", yeniDurum);
    logQuery.bindValue(":aciklama", aciklama.trimmed().isEmpty() ? QVariant(QMetaType(QMetaType::QString))
                                                                 : QVariant(aciklama.trimmed().left(500)));
    logQuery.bindValue(":kullaniciId", kullaniciId > 0 ? QVariant(kullaniciId) : QVariant(QMetaType(QMetaType::Int)));

    if (!logQuery.exec())
        qWarning() << "Durum gecmisi yazilamadi (db/05_teklif_durum_gecmisi.sql calistirildi mi?):"
                   << logQuery.lastError().text();
}

QVariantList Database::teklifDurumGecmisiGetir(int teklifId)
{
    ERP_IZ("teklifDurumGecmisiGetir");
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

        // Durum degismeden yazilan satir: planlanan teslim tarihi degisikligi
        // (bkz. teklifTeslimatTarihiGuncelle).
        satirlar.append({tarih, satirOlustur(QStringLiteral("durum"), u,
                                             eskiDurum == yeniDurum
                                                 ? QStringLiteral("Planlanan teslim tarihi değişti")
                                                 : (eskiDurum.isEmpty() ? QStringLiteral("—") : eskiDurum)
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

// ----------------------------------------------------------------------
// Sayfali listeler. Sorgu SQL'i AramaSorgulari'nda durur ve ayni dosya
// AramaWorker tarafindan da kullanilir (bkz. *ListesiGetirBaslat) -- boylece
// senkron ve asenkron yol birbirinden sapmaz.
// ----------------------------------------------------------------------
QVariantMap Database::musteriListesiGetir(const QString &arama, int sayfaNo,
                                           int sayfaBoyutu, bool arsivliDahil)
{
    ERP_IZ("musteriListesiGetir");
    if (!baglantiHazir())
        return QVariantMap();
    return musteriListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, arsivliDahil);
}

int Database::musteriListesiGetirBaslat(const QString &arama, int sayfaNo,
                                         int sayfaBoyutu, bool arsivliDahil)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_listeWorker)
    {
        // Worker yoksa (olmamasi gereken durum) cagiran taraf asili kalmasin.
        emit musteriListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_listeWorker, "musteriListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama), Q_ARG(int, sayfaNo),
                              Q_ARG(int, sayfaBoyutu), Q_ARG(bool, arsivliDahil));
    return istekNo;
}

int Database::urunListesiGetirBaslat(const QString &arama, int sayfaNo,
                                      int sayfaBoyutu, bool arsivliDahil)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_listeWorker)
    {
        emit urunListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_listeWorker, "urunListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama), Q_ARG(int, sayfaNo),
                              Q_ARG(int, sayfaBoyutu), Q_ARG(bool, arsivliDahil));
    return istekNo;
}

int Database::personelListesiGetirBaslat(const QString &arama, int sayfaNo,
                                          int sayfaBoyutu, bool pasifDahil)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_listeWorker)
    {
        emit personelListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_listeWorker, "personelListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama), Q_ARG(int, sayfaNo),
                              Q_ARG(int, sayfaBoyutu), Q_ARG(bool, pasifDahil));
    return istekNo;
}

QVariantMap Database::iliskiliKayitSonucu(const QString &mesaj)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = mesaj;
    // Ekran bu bayragi gorunce kullaniciya kalici silme yerine ARSIVLEMEYI onerir.
    sonuc["iliskiliKayitVar"] = true;
    return sonuc;
}

namespace
{
    // musteriEkle / musteriGuncelle'nin ortak alan denetimi. Hatali bir sey
    // varsa hataOut doldurulur ve false doner.
    bool musteriAlanlariniDenetle(const QVariantMap &musteri, QString &hataOut)
    {
        if (alan(musteri, "firmaAdi").isEmpty())
        {
            hataOut = "Firma adı boş olamaz.";
            return false;
        }
        if (!epostaGecerliMi(alan(musteri, "firmaEposta")))
        {
            hataOut = "E-posta adresi geçerli görünmüyor (örnek: ad@firma.com).";
            return false;
        }
        if (!telefonGecerliMi(alan(musteri, "firmaTelefonu")))
        {
            hataOut = "Telefon numarası geçerli görünmüyor (en az 7 rakam olmalı).";
            return false;
        }
        if (!telefonGecerliMi(alan(musteri, "ilgiliKisiTelefonu")))
        {
            hataOut = "İlgili kişi telefonu geçerli görünmüyor (en az 7 rakam olmalı).";
            return false;
        }
        if (!vergiNoGecerliMi(alan(musteri, "vergiNumarasi")))
        {
            hataOut = "Vergi numarası 10 haneli (şirket) veya 11 haneli (şahıs) olmalıdır.";
            return false;
        }
        return true;
    }

    // Musteri parametrelerini sorguya baglar. Zorunlu olan FirmaAdi haric tum
    // alanlar OPSIYONEL: bos birakilanlar '' yerine NULL kaydedilir.
    void musteriParametreleriniBagla(QSqlQuery &query, const QVariantMap &musteri)
    {
        query.bindValue(":firmaAdi", alan(musteri, "firmaAdi"));
        query.bindValue(":firmaAdresi", metinParametresi(alan(musteri, "firmaAdresi")));
        query.bindValue(":firmaTelefonu", metinParametresi(alan(musteri, "firmaTelefonu")));
        query.bindValue(":firmaEposta", metinParametresi(alan(musteri, "firmaEposta")));
        query.bindValue(":vergiDairesi", metinParametresi(alan(musteri, "vergiDairesi")));
        query.bindValue(":vergiNumarasi", metinParametresi(alan(musteri, "vergiNumarasi")));
        query.bindValue(":ilgiliKisi", metinParametresi(alan(musteri, "ilgiliKisi")));
        query.bindValue(":ilgiliKisiTel", metinParametresi(alan(musteri, "ilgiliKisiTelefonu")));
    }
}

QVariantMap Database::musteriEkle(const QVariantMap &musteri)
{
    ERP_IZ("musteriEkle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["musteriId"] = 0;
    sonuc["hata"] = QString();
    sonuc["mukerrer"] = false;
    sonuc["mukerrerAd"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    if (!musteriAlanlariniDenetle(musteri, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    const QString firmaAdi = alan(musteri, "firmaAdi");

    // MUKERRER FIRMA UYARISI: ayni isim iki kez eklenince teklif gecmisi iki
    // kayda bolunuyor ve hangisinin dogru oldugu anlasilmiyordu. Sert bir
    // UNIQUE kisiti koymuyoruz (ayni ismi tasiyan farkli sube/tuzel kisiler
    // gercek bir ihtiyac), bunun yerine kullaniciya soruyoruz: onay
    // "mukerrerOnayi" ile geri gelirse kayit yapilir.
    if (!musteri.value("mukerrerOnayi", false).toBool())
    {
        QSqlQuery kontrol(m_db);
        kontrol.prepare("SELECT TOP (1) FirmaAdi FROM dbo.musteriler "
                        "WHERE LTRIM(RTRIM(FirmaAdi)) = :firmaAdi");
        kontrol.bindValue(":firmaAdi", firmaAdi);
        if (kontrol.exec() && kontrol.next())
        {
            sonuc["mukerrer"] = true;
            sonuc["mukerrerAd"] = kontrol.value(0).toString();
            sonuc["hata"] = "\"" + kontrol.value(0).toString()
                            + "\" adlı müşteri zaten kayıtlı.";
            return sonuc;
        }
    }

    QSqlQuery query(m_db);
    query.prepare(
        "INSERT INTO dbo.musteriler "
        "(FirmaAdi, FirmaAdresi, FirmaTelefonu, FirmaEposta, VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu) "
        "OUTPUT INSERTED.MusteriId "
        "VALUES (:firmaAdi, :firmaAdresi, :firmaTelefonu, :firmaEposta, :vergiDairesi, :vergiNumarasi, :ilgiliKisi, :ilgiliKisiTel)");
    musteriParametreleriniBagla(query, musteri);

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
    ERP_IZ("musteriGuncelle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    if (!musteriAlanlariniDenetle(musteri, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.musteriler SET "
        "FirmaAdi = :firmaAdi, FirmaAdresi = :firmaAdresi, FirmaTelefonu = :firmaTelefonu, "
        "FirmaEposta = :firmaEposta, VergiDairesi = :vergiDairesi, VergiNumarasi = :vergiNumarasi, "
        "IlgiliKisi = :ilgiliKisi, IlgiliKisiTelefonu = :ilgiliKisiTel "
        "WHERE MusteriId = :musteriId");
    musteriParametreleriniBagla(query, musteri);
    query.bindValue(":musteriId", musteriId);

    if (!query.exec())
    {
        qWarning() << "musteriGuncelle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Müşteri güncellenemedi: " + query.lastError().text();
        return sonuc;
    }

    // Kayit bulunamadiysa (baska biri silmis olabilir) sessizce "basarili"
    // demek yerine kullaniciya soyluyoruz -- aksi halde form kapanir ve
    // degisikligin kaydedildigi sanilirdi.
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Müşteri bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::musteriSil(int musteriId)
{
    ERP_IZ("musteriSil");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();
    sonuc["iliskiliKayitVar"] = false;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.musteriler WHERE MusteriId = :musteriId");
    query.bindValue(":musteriId", musteriId);

    if (!query.exec())
    {
        const QSqlError hata = query.lastError();
        qWarning() << "Musteri silinemedi:" << hata.text();

        // teklifler.MusteriId icin ON DELETE CASCADE tanimli DEGIL (bilerek:
        // bir musteri yanlislikla silinince tekliflerin de silinmesini
        // istemeyiz). Bu yuzden teklifi olan musteri kalici silinemez --
        // ekran bu durumda arsivlemeyi onerir.
        //
        // ONEMLI: eskiden buradaki HER hata (baglanti kopmasi, zaman asimi,
        // yetki eksikligi) "bu musteriye ait teklifler var" diye gosteriliyor,
        // yani kullaniciyi yanlis yone yonlendiriyordu.
        if (fkIhlaliMi(hata))
            return iliskiliKayitSonucu(
                "Bu müşteriye ait teklifler olduğu için kalıcı olarak silinemez.");

        sonuc["hata"] = "Müşteri silinemedi: " + hata.text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Müşteri bulunamadı; kayıt zaten silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::musteriArsivDurumDegistir(int musteriId, bool aktif)
{
    ERP_IZ("musteriArsivDurumDegistir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.musteriler"), QStringLiteral("AktifMi")))
    {
        sonuc["hata"] = "Arşivleme için db/13_musteri_urun_arsiv.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.musteriler SET AktifMi = :aktif WHERE MusteriId = :id");
    query.bindValue(":aktif", aktif);
    query.bindValue(":id", musteriId);

    if (!query.exec())
    {
        qWarning() << "musteriArsivDurumDegistir basarisiz:" << query.lastError().text();
        sonuc["hata"] = (aktif ? QString("Müşteri arşivden çıkarılamadı: ")
                               : QString("Müşteri arşivlenemedi: ")) + query.lastError().text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Müşteri bulunamadı; kayıt silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::urunListesiGetir(const QString &arama, int sayfaNo,
                                        int sayfaBoyutu, bool arsivliDahil)
{
    ERP_IZ("urunListesiGetir");
    if (!baglantiHazir())
        return QVariantMap();
    return urunListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, arsivliDahil);
}

namespace
{
    // urunEkle / urunGuncelle'nin ortak alan denetimi.
    bool urunAlanlariniDenetle(const QVariantMap &urun, QString &hataOut)
    {
        if (alan(urun, "urunAciklamasi").isEmpty())
        {
            hataOut = "Ürün açıklaması boş olamaz.";
            return false;
        }

        // "MANUEL" oneki REZERVEDIR: bu kodla kaydedilen urun, manuel teklif
        // kalemleri icin olusturulan gecici satirlarla birlikte urun katalogu
        // listelerinden filtrelenir -- yani veritabanina yazilir ama hicbir
        // ekranda gorunmez, dolayisiyla duzenlenemez ve silinemez olurdu.
        if (manuelKoduMu(alan(urun, "urunKodu")))
        {
            hataOut = "Ürün kodu \"MANUEL\" ile başlayamaz; bu ön ek sistem tarafından "
                      "teklife özel manuel kalemler için kullanılır.";
            return false;
        }

        if (urun.value("birimFiyat", 0).toDouble() < 0 || urun.value("maliyet", 0).toDouble() < 0
            || urun.value("fiyatUSD", 0).toDouble() < 0 || urun.value("fiyatEUR", 0).toDouble() < 0)
        {
            hataOut = "Fiyatlar ve maliyet negatif olamaz.";
            return false;
        }
        return true;
    }

    // USD / EUR liste fiyati: 0 ya da bos -> NULL ("bu para biriminde fiyat
    // girilmemis"; teklifte kalem 0 gelir ve elle girilir -- kurdan hesaplanmaz).
    QVariant dovizFiyatParametresi(const QVariantMap &urun, const char *anahtar)
    {
        const double deger = urun.value(QLatin1String(anahtar), 0).toDouble();
        return deger > 0.0 ? QVariant(deger) : QVariant(QMetaType(QMetaType::Double));
    }

    void urunParametreleriniBagla(QSqlQuery &query, const QVariantMap &urun)
    {
        // Urun kodu, kategori ve EN aciklamasi OPSIYONEL: bos birakilanlar
        // '' yerine NULL kaydedilir -- boylece "kodu girilmemis urun" tek bir
        // sekilde ('' degil NULL) temsil edilir ve kod kontrolu
        // (urunKoduKullanimdaMi) bos kodlari dogru sekilde kapsam disi tutar.
        query.bindValue(":urunKodu", metinParametresi(alan(urun, "urunKodu")));
        query.bindValue(":kategori", metinParametresi(alan(urun, "kategori")));
        query.bindValue(":aciklama", alan(urun, "urunAciklamasi"));
        query.bindValue(":aciklamaEn", metinParametresi(alan(urun, "urunAciklamasiEn")));
        query.bindValue(":birimFiyat", urun.value("birimFiyat", 0).toDouble());
        query.bindValue(":maliyet", urun.value("maliyet", 0).toDouble());
    }
}

// Girilen urun kodu baska bir urunde kullanilmis mi? (haricUrunId > 0 ise o
// kayit disarida birakilir -- guncellemede urunun kendi kodu catisma saymaz.)
// Kod bos ise kontrol yapilmaz: kod opsiyoneldir ve kodsuz urunler tekillik
// kapsaminda degildir.
//
// Urun kodu tekilliginin TEK bekcisi budur -- veritabaninda destekleyici bir
// tekil indeks yoktur ve kurulamaz (gerekce: db/14_urun_kodu_tekil.sql).
// "MANUEL" onekli kodlar buraya hic gelmez: urunAlanlariniDenetle onlari
// daha once reddeder.
bool Database::urunKoduKullanimdaMi(const QString &urunKodu, int haricUrunId, QString &sahipOut)
{
    const QString kod = urunKodu.trimmed();
    if (kod.isEmpty())
        return false;

    QSqlQuery query(m_db);
    query.prepare("SELECT TOP (1) UrunId, UrunAciklamasi FROM dbo.urunler "
                  "WHERE LTRIM(RTRIM(UrunKodu)) = :kod AND UrunId <> :haric");
    query.bindValue(":kod", kod);
    query.bindValue(":haric", haricUrunId);

    if (!query.exec())
    {
        // Kontrol calismadiysa (baglanti/zaman asimi) kaydi engellemiyoruz:
        // kullanicinin isini bir tekillik SUPHESI yuzunden durdurmak,
        // mukerrer kod riskinden daha kotu. Asil INSERT/UPDATE zaten hemen
        // ardindan deneniyor; o da basarisiz olursa kullanici hatayi gorur.
        qWarning() << "urunKoduKullanimdaMi basarisiz:" << query.lastError().text();
        return false;
    }

    if (!query.next())
        return false;

    sahipOut = query.value("UrunAciklamasi").toString().trimmed();
    return true;
}

QVariantMap Database::urunEkle(const QVariantMap &urun)
{
    ERP_IZ("urunEkle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["urunId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    if (!urunAlanlariniDenetle(urun, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    // MUKERRER URUN KODU: ayni kodla iki urun varsa Teklif Ver ekranindaki
    // aramada hangisinin secildigi belirsiz kaliyor, maliyet guncellemesi
    // (urunMaliyetiGuncelle) yanlis satira gidebiliyordu.
    QString sahip;
    if (urunKoduKullanimdaMi(alan(urun, "urunKodu"), 0, sahip))
    {
        sonuc["hata"] = "\"" + alan(urun, "urunKodu") + "\" kodu başka bir üründe kullanılıyor"
                        + (sahip.isEmpty() ? QString() : " (" + sahip + ")") + ".";
        return sonuc;
    }

    // USD / EUR liste fiyatlari db/26 ile eklendi; sutun yoksa yazilmaz.
    const bool dovizSutunlari = semaKolonuVarMi(m_db, QStringLiteral("dbo.urunler"), QStringLiteral("FiyatUSD"));
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "INSERT INTO dbo.urunler "
        "(UrunKodu, Kategori, UrunAciklamasi, UrunAciklamasiEn, BirimFiyat, ParaBirimi, GuncelMaliyetTL%1) "
        "OUTPUT INSERTED.UrunId "
        "VALUES (:urunKodu, :kategori, :aciklama, :aciklamaEn, :birimFiyat, N'TL', :maliyet%2)")
        .arg(dovizSutunlari ? QStringLiteral(", FiyatUSD, FiyatEUR") : QString(),
             dovizSutunlari ? QStringLiteral(", :fiyatUSD, :fiyatEUR") : QString()));
    urunParametreleriniBagla(query, urun);
    if (dovizSutunlari)
    {
        query.bindValue(":fiyatUSD", dovizFiyatParametresi(urun, "fiyatUSD"));
        query.bindValue(":fiyatEUR", dovizFiyatParametresi(urun, "fiyatEUR"));
    }

    if (!query.exec() || !query.next())
    {
        const QSqlError sqlHata = query.lastError();
        qWarning() << "urunEkle basarisiz:" << sqlHata.text();
        sonuc["hata"] = tekillikIhlaliMi(sqlHata)
            ? QString("Bu ürün kodu başka bir üründe kullanılıyor.")
            : "Ürün kaydedilemedi: " + sqlHata.text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["urunId"] = query.value(0).toInt();
    return sonuc;
}

QVariantMap Database::urunGuncelle(int urunId, const QVariantMap &urun)
{
    ERP_IZ("urunGuncelle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    if (!urunAlanlariniDenetle(urun, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    QString sahip;
    if (urunKoduKullanimdaMi(alan(urun, "urunKodu"), urunId, sahip))
    {
        sonuc["hata"] = "\"" + alan(urun, "urunKodu") + "\" kodu başka bir üründe kullanılıyor"
                        + (sahip.isEmpty() ? QString() : " (" + sahip + ")") + ".";
        return sonuc;
    }

    const bool dovizSutunlari = semaKolonuVarMi(m_db, QStringLiteral("dbo.urunler"), QStringLiteral("FiyatUSD"));
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE dbo.urunler SET "
        "UrunKodu = :urunKodu, Kategori = :kategori, UrunAciklamasi = :aciklama, "
        "UrunAciklamasiEn = :aciklamaEn, BirimFiyat = :birimFiyat, GuncelMaliyetTL = :maliyet%1 "
        "WHERE UrunId = :urunId")
        .arg(dovizSutunlari ? QStringLiteral(", FiyatUSD = :fiyatUSD, FiyatEUR = :fiyatEUR") : QString()));
    urunParametreleriniBagla(query, urun);
    if (dovizSutunlari)
    {
        query.bindValue(":fiyatUSD", dovizFiyatParametresi(urun, "fiyatUSD"));
        query.bindValue(":fiyatEUR", dovizFiyatParametresi(urun, "fiyatEUR"));
    }
    query.bindValue(":urunId", urunId);

    if (!query.exec())
    {
        const QSqlError sqlHata = query.lastError();
        qWarning() << "urunGuncelle basarisiz:" << sqlHata.text();
        sonuc["hata"] = tekillikIhlaliMi(sqlHata)
            ? QString("Bu ürün kodu başka bir üründe kullanılıyor.")
            : "Ürün güncellenemedi: " + sqlHata.text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Ürün bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::urunSil(int urunId)
{
    ERP_IZ("urunSil");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();
    sonuc["iliskiliKayitVar"] = false;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.urunler WHERE UrunId = :urunId");
    query.bindValue(":urunId", urunId);

    if (!query.exec())
    {
        const QSqlError hata = query.lastError();
        qWarning() << "Urun silinemedi:" << hata.text();

        // musteriSil ile ayni kural (oradaki ayrintili nota bakin): teklif
        // kaleminde kullanilmis urun kalici silinemez, ekran arsivlemeyi onerir.
        if (fkIhlaliMi(hata))
            return iliskiliKayitSonucu(
                "Bu ürünü içeren teklifler olduğu için kalıcı olarak silinemez.");

        sonuc["hata"] = "Ürün silinemedi: " + hata.text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Ürün bulunamadı; kayıt zaten silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::urunArsivDurumDegistir(int urunId, bool aktif)
{
    ERP_IZ("urunArsivDurumDegistir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        sonuc["hata"] = QString::fromUtf8(SATIS_YETKI_YOK);
        return sonuc;
    }

    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.urunler"), QStringLiteral("AktifMi")))
    {
        sonuc["hata"] = "Arşivleme için db/13_musteri_urun_arsiv.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.urunler SET AktifMi = :aktif WHERE UrunId = :id");
    query.bindValue(":aktif", aktif);
    query.bindValue(":id", urunId);

    if (!query.exec())
    {
        qWarning() << "urunArsivDurumDegistir basarisiz:" << query.lastError().text();
        sonuc["hata"] = (aktif ? QString("Ürün arşivden çıkarılamadı: ")
                               : QString("Ürün arşivlenemedi: ")) + query.lastError().text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Ürün bulunamadı; kayıt silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

bool Database::urunMaliyetiGuncelle(int urunId, double maliyetTl)
{
    ERP_IZ("urunMaliyetiGuncelle");
    m_sonHataMesaji.clear();

    // Manuel kalemlerin katalogda karsiligi yoktur (urunId = 0) -- sessizce gec.
    if (urunId <= 0)
        return false;

    if (!baglantiHazir())
    {
        m_sonHataMesaji = "Veritabanına bağlanılamadı.";
        return false;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")))
    {
        m_sonHataMesaji = QString::fromUtf8(SATIS_YETKI_YOK);
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

void Database::rolListesiGetirBaslat()
{
    if (!m_listeWorker)
    {
        emit rolListesiHazir(QVariantList());
        return;
    }
    QMetaObject::invokeMethod(m_listeWorker, "rolListesiCalistir", Qt::QueuedConnection);
}

QVariantMap Database::personelListesiGetir(const QString &arama, int sayfaNo,
                                            int sayfaBoyutu, bool pasifDahil)
{
    ERP_IZ("personelListesiGetir");
    if (!baglantiHazir())
        return QVariantMap();
    return personelListesiSorgusu(m_db, arama, sayfaNo, sayfaBoyutu, pasifDahil);
}

int Database::aktifYoneticiSayisi(int haricKullaniciId)
{
    // yoneticiSifresiDogrula ile AYNI rol kumesi: yonetici sifresiyle korunan
    // islemleri acabilen herkes. Bu iki yer birbirinden saparsa, "yonetici
    // kaldi" denip aslinda hicbir yonetici kalmamis olabilir.
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT COUNT(DISTINCT k.KullaniciId) "
        "FROM dbo.kullanicilar k "
        "JOIN dbo.kullanici_rolleri kr ON kr.KullaniciId = k.KullaniciId "
        "JOIN dbo.roller r ON r.RolId = kr.RolId "
        "WHERE k.AktifMi = 1 AND k.KullaniciId <> :haric "
        "  AND r.RolAdi IN (N'Yönetici', N'Göç - Geçici Tam Yetkili')");
    query.bindValue(":haric", haricKullaniciId);

    if (!query.exec() || !query.next())
    {
        qWarning() << "aktifYoneticiSayisi basarisiz:" << query.lastError().text();
        return -1;   // bilinmiyor
    }
    return query.value(0).toInt();
}

namespace
{
    // personelEkle / personelGuncelle'nin ortak alan denetimi. sifreZorunlu
    // false ise (guncelleme) bos sifre "degistirme" anlamina gelir ve
    // uzunluk kontrolu yalnizca DOLU sifreye uygulanir.
    bool personelAlanlariniDenetle(const QVariantMap &personel, bool sifreZorunlu, QString &hataOut)
    {
        if (alan(personel, "adSoyad").isEmpty() || alan(personel, "kullaniciAdi").isEmpty())
        {
            hataOut = "Ad Soyad ve kullanıcı adı boş olamaz.";
            return false;
        }

        // Kullanici adi girise yazilan bir anahtardir: ici bosluklu bir ad
        // ("ahmet y") giris ekraninda fark edilmeyen hatalara yol acar.
        if (alan(personel, "kullaniciAdi").contains(QLatin1Char(' ')))
        {
            hataOut = "Kullanıcı adı boşluk içeremez.";
            return false;
        }

        const QString sifre = personel.value("sifre").toString();
        if (sifreZorunlu && sifre.isEmpty())
        {
            hataOut = "Şifre boş olamaz.";
            return false;
        }

        if (!telefonGecerliMi(alan(personel, "telefon")))
        {
            hataOut = "Telefon numarası geçerli görünmüyor (en az 7 rakam olmalı).";
            return false;
        }

        // EN AZ BIR ROL: rolsuz kullanici giris yapabiliyor ama hicbir modul
        // goremiyordu (kullaniciModulleriniGetir bos doner) -- kullanici
        // acisindan sebebi anlasilmaz bir "bos program" durumu olusuyordu.
        if (personel.value("rolIdListesi").toList().isEmpty())
        {
            hataOut = "En az bir rol seçilmelidir; rolsüz personel giriş yapsa bile "
                      "hiçbir modülü göremez.";
            return false;
        }
        return true;
    }

    // Personelin rollerini sifirlar ve verilen listeyi yeniden atar. Acik bir
    // transaction icinde cagrilmalidir. Ekleme yolunda da ayni fonksiyon
    // kullanilir (orada silinecek rol yoktur, DELETE bos gecer).
    bool personelRolleriniYaz(QSqlDatabase &db, int kullaniciId,
                               const QVariantList &rolIdListesi, QString &hataOut)
    {
        QSqlQuery rolSil(db);
        rolSil.prepare("DELETE FROM dbo.kullanici_rolleri WHERE KullaniciId = :kid");
        rolSil.bindValue(":kid", kullaniciId);
        if (!rolSil.exec())
        {
            hataOut = "Roller güncellenemedi: " + rolSil.lastError().text();
            return false;
        }

        for (const QVariant &rolIdVar : rolIdListesi)
        {
            QSqlQuery rolEkle(db);
            rolEkle.prepare("INSERT INTO dbo.kullanici_rolleri (KullaniciId, RolId) VALUES (:kid, :rid)");
            rolEkle.bindValue(":kid", kullaniciId);
            rolEkle.bindValue(":rid", rolIdVar.toInt());
            if (!rolEkle.exec())
            {
                qWarning() << "personel rol atama basarisiz:" << rolEkle.lastError().text();
                hataOut = "Roller atanamadı: " + rolEkle.lastError().text();
                return false;
            }
        }
        return true;
    }
}

QVariantMap Database::personelEkle(const QVariantMap &personel)
{
    ERP_IZ("personelEkle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["kullaniciId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = QString::fromUtf8(YONETIM_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    if (!personelAlanlariniDenetle(personel, /*sifreZorunlu*/ true, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    // Tuzlu hash (bkz. sifreyiHashle ustundeki not). Tuz sutunu yoksa
    // (db/12 calistirilmamissa) eski tuzsuz bicimde kaydediyoruz, boylece
    // program eski semayla da calismaya devam eder.
    const bool tuzKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.kullanicilar"),
                                           QStringLiteral("SifreSalt"));
    const QString tuz = tuzKolonu ? yeniTuzUret() : QString();
    const QString sifre = personel.value("sifre").toString();
    const bool kopyaKolonu = sifreliKopyaKolonuVarMi(m_db);

    QSqlQuery ekle(m_db);
    ekle.prepare(QString(
        "INSERT INTO dbo.kullanicilar (AdSoyad, KullaniciAdi, SifreHash, Telefon, Pozisyon, AktifMi%1%3) "
        "OUTPUT INSERTED.KullaniciId "
        "VALUES (:adSoyad, :kullaniciAdi, :sifreHash, :telefon, :pozisyon, 1%2%4)")
        .arg(tuzKolonu ? QStringLiteral(", SifreSalt") : QString())
        .arg(tuzKolonu ? QStringLiteral(", :sifreTuz") : QString())
        .arg(kopyaKolonu ? QStringLiteral(", SifreSifreli") : QString())
        .arg(kopyaKolonu ? QStringLiteral(", ") + QString::fromLatin1(SIFRELI_KOPYA_IFADESI) : QString()));
    if (kopyaKolonu)
        sifreliKopyaParametreleriniBagla(ekle, sifre);
    ekle.bindValue(":adSoyad", alan(personel, "adSoyad"));
    ekle.bindValue(":kullaniciAdi", alan(personel, "kullaniciAdi"));
    ekle.bindValue(":sifreHash", sifreyiHashle(sifre, tuz));
    // Telefon ve pozisyon opsiyonel: bos birakilanlar NULL kaydedilir.
    ekle.bindValue(":telefon", metinParametresi(alan(personel, "telefon")));
    ekle.bindValue(":pozisyon", metinParametresi(alan(personel, "pozisyon")));
    if (tuzKolonu)
        ekle.bindValue(":sifreTuz", tuz);

    if (!ekle.exec() || !ekle.next())
    {
        const QSqlError sqlHata = ekle.lastError();
        qWarning() << "personelEkle basarisiz:" << sqlHata.text();
        m_db.rollback();
        sonuc["hata"] = tekillikIhlaliMi(sqlHata)
            ? QString("\"") + alan(personel, "kullaniciAdi") + "\" kullanıcı adı zaten kullanılıyor."
            : "Personel kaydedilemedi: " + sqlHata.text();
        return sonuc;
    }
    const int kullaniciId = ekle.value(0).toInt();

    if (!personelRolleriniYaz(m_db, kullaniciId, personel.value("rolIdListesi").toList(), hata))
    {
        m_db.rollback();
        sonuc["hata"] = hata;
        return sonuc;
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
    ERP_IZ("personelGuncelle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = QString::fromUtf8(YONETIM_YETKI_YOK);
        return sonuc;
    }

    QString hata;
    // Guncellemede sifre OPSIYONEL: bos birakilirsa mevcut sifre korunur.
    if (!personelAlanlariniDenetle(personel, /*sifreZorunlu*/ false, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    const QVariantList rolIdListesi = personel.value("rolIdListesi").toList();

    // SON YONETICIYI YETKISIZ BIRAKMA KORUMASI: personelAktifDurumDegistir'deki
    // kurallin ayni gerekcesi -- yonetici rolunu kendinden/son yoneticiden
    // ALMAK da sistemi kilitler: yonetici sifresi isteyen hicbir islem (teklif
    // silme, personel kaydi, musteri duzenleme) bir daha yapilamaz.
    {
        QSqlQuery yoneticiRolleri(m_db);
        yoneticiRolleri.prepare("SELECT RolId FROM dbo.roller "
                                "WHERE RolAdi IN (N'Yönetici', N'Göç - Geçici Tam Yetkili')");
        // Sorgu calismazsa koruma ATLANMAZ: aktifYoneticiSayisi'ndaki "bilinmiyor =
        // riskli" kuraliyla ayni sekilde islem reddedilir.
        if (!yoneticiRolleri.exec())
        {
            qWarning() << "personelGuncelle: yonetici rolleri okunamadi:" << yoneticiRolleri.lastError().text();
            sonuc["hata"] = "Yönetici rolleri doğrulanamadı; işlem güvenli olmadığı için yapılmadı. "
                            "Bağlantıyı kontrol edip tekrar deneyin.";
            return sonuc;
        }
        {
            QList<int> yoneticiRolIdleri;
            while (yoneticiRolleri.next())
                yoneticiRolIdleri << yoneticiRolleri.value(0).toInt();

            bool yoneticiKalacak = false;
            for (const QVariant &rolIdVar : rolIdListesi)
                if (yoneticiRolIdleri.contains(rolIdVar.toInt()))
                    yoneticiKalacak = true;

            if (!yoneticiKalacak)
            {
                const int digerYoneticiler = aktifYoneticiSayisi(kullaniciId);
                if (digerYoneticiler == 0)
                {
                    sonuc["hata"] = "Bu personel sistemdeki tek yönetici; yönetici rolü "
                                    "kaldırılamaz. Önce başka bir personele yönetici rolü verin.";
                    return sonuc;
                }
                if (digerYoneticiler < 0)
                {
                    sonuc["hata"] = "Yönetici sayısı doğrulanamadı; işlem güvenli olmadığı "
                                    "için yapılmadı. Bağlantıyı kontrol edip tekrar deneyin.";
                    return sonuc;
                }
            }
        }
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    const QString sifre = personel.value("sifre").toString();
    const bool sifreDegisiyor = !sifre.isEmpty();
    const bool tuzKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.kullanicilar"),
                                           QStringLiteral("SifreSalt"));
    const QString tuz = (sifreDegisiyor && tuzKolonu) ? yeniTuzUret() : QString();
    const bool kopyaKolonu = sifreDegisiyor && sifreliKopyaKolonuVarMi(m_db);

    QString sql = "UPDATE dbo.kullanicilar SET AdSoyad = :adSoyad, KullaniciAdi = :kullaniciAdi, "
                  "Telefon = :telefon, Pozisyon = :pozisyon";
    if (sifreDegisiyor)
    {
        sql += ", SifreHash = :sifreHash";
        // Sifre her degistiginde YENI tuz uretilir; eski tuzla kalmasi
        // hash'in yeni sifreyle uyusmamasina yol acardi.
        if (tuzKolonu)
            sql += ", SifreSalt = :sifreTuz";
        if (kopyaKolonu)
            sql += QStringLiteral(", SifreSifreli = ") + QString::fromLatin1(SIFRELI_KOPYA_IFADESI);
    }
    sql += " WHERE KullaniciId = :kullaniciId";

    QSqlQuery guncelle(m_db);
    guncelle.prepare(sql);
    guncelle.bindValue(":adSoyad", alan(personel, "adSoyad"));
    guncelle.bindValue(":kullaniciAdi", alan(personel, "kullaniciAdi"));
    guncelle.bindValue(":telefon", metinParametresi(alan(personel, "telefon")));
    guncelle.bindValue(":pozisyon", metinParametresi(alan(personel, "pozisyon")));
    if (sifreDegisiyor)
    {
        guncelle.bindValue(":sifreHash", sifreyiHashle(sifre, tuz));
        if (tuzKolonu)
            guncelle.bindValue(":sifreTuz", tuz);
        if (kopyaKolonu)
            sifreliKopyaParametreleriniBagla(guncelle, sifre);
    }
    guncelle.bindValue(":kullaniciId", kullaniciId);

    if (!guncelle.exec())
    {
        const QSqlError sqlHata = guncelle.lastError();
        qWarning() << "personelGuncelle basarisiz:" << sqlHata.text();
        m_db.rollback();
        sonuc["hata"] = tekillikIhlaliMi(sqlHata)
            ? QString("\"") + alan(personel, "kullaniciAdi") + "\" kullanıcı adı zaten kullanılıyor."
            : "Personel güncellenemedi: " + sqlHata.text();
        return sonuc;
    }

    if (guncelle.numRowsAffected() == 0)
    {
        m_db.rollback();
        sonuc["hata"] = "Personel bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }

    // Rolleri sifirla ve yeniden ata (senkron etmenin en basit yolu).
    if (!personelRolleriniYaz(m_db, kullaniciId, rolIdListesi, hata))
    {
        m_db.rollback();
        sonuc["hata"] = hata;
        return sonuc;
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

bool Database::sifreGoruntuleyebilirMi()
{
    ERP_IZ("sifreGoruntuleyebilirMi");
    if (m_aktifKullaniciId <= 0 || !baglantiHazir())
        return false;

    QSqlQuery query(m_db);
    query.prepare("SELECT KullaniciAdi FROM dbo.kullanicilar WHERE KullaniciId = :id AND AktifMi = 1");
    query.bindValue(":id", m_aktifKullaniciId);
    if (!query.exec() || !query.next())
        return false;
    return query.value(0).toString().compare(QString::fromLatin1(SIFRE_GORUNTULEYEN_KULLANICI),
                                             Qt::CaseInsensitive) == 0;
}

QVariantMap Database::personelSifresiGetir(int kullaniciId, const QString &pin)
{
    ERP_IZ("personelSifresiGetir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["sifre"] = QString();
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!sifreGoruntuleyebilirMi())
    {
        sonuc["hata"] = "Personel şifrelerini görme yetkiniz yok.";
        return sonuc;
    }
    if (m_sifrePinHataSayisi >= SIFRE_PIN_AZAMI_HATA)
    {
        sonuc["hata"] = "Çok fazla yanlış PIN girildi; programı yeniden açıp tekrar deneyin.";
        return sonuc;
    }
    if (QString::fromLatin1(QCryptographicHash::hash(pin.toUtf8(), QCryptographicHash::Sha256).toHex())
        != QString::fromLatin1(SIFRE_GORUNTULEME_PIN_OZETI))
    {
        ++m_sifrePinHataSayisi;
        qWarning() << "personelSifresiGetir: yanlis PIN, kullaniciId" << m_aktifKullaniciId;
        sonuc["hata"] = "PIN yanlış.";
        return sonuc;
    }
    m_sifrePinHataSayisi = 0;

    if (!sifreliKopyaKolonuVarMi(m_db))
    {
        sonuc["hata"] = "Şifre görüntüleme için db/29_personel_sifre_gorunur.sql çalıştırılmalı.";
        return sonuc;
    }

    const bool tuzKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.kullanicilar"),
                                           QStringLiteral("SifreSalt"));
    QSqlQuery query(m_db);
    query.prepare(QString(
        "SELECT CAST(DECRYPTBYPASSPHRASE(CAST(:sifreAnahtari AS NVARCHAR(128)), SifreSifreli) "
        "AS NVARCHAR(256)), SifreHash%1 FROM dbo.kullanicilar WHERE KullaniciId = :id")
        .arg(tuzKolonu ? QStringLiteral(", SifreSalt") : QString()));
    query.bindValue(":sifreAnahtari", QString::fromLatin1(SIFRE_GORUNTULEME_ANAHTARI));
    query.bindValue(":id", kullaniciId);
    if (!query.exec() || !query.next())
    {
        qWarning() << "personelSifresiGetir basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Şifre okunamadı.";
        return sonuc;
    }

    QString sifre = query.value(0).toString();
    // Gocten gelip henuz hashlenmemis ya da SSMS'ten elle yazilmis kayitta
    // sifre SifreHash'te duz metin durur; giris de onu kabul ettigi icin
    // (bkz. girisYap) gecerli sifre odur, eski kopya degil.
    const QString depolanan = query.value(1).toString();
    if (!depolanan.isEmpty() && !sha256OzetiMi(depolanan))
        sifre = depolanan;

    if (sifre.isEmpty())
    {
        sonuc["hata"] = "Şifre henüz kayıtlı değil; personel bir sonraki girişinde görünür. "
                        "Hemen gerekiyorsa yeni şifre verin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["sifre"] = sifre;
    return sonuc;
}

QVariantMap Database::personelAktifDurumDegistir(int kullaniciId, bool aktif)
{
    ERP_IZ("personelAktifDurumDegistir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = QString::fromUtf8(YONETIM_YETKI_YOK);
        return sonuc;
    }

    // ---- Pasife almanin iki koruması ----
    // Ikisinin de onledigi sonuc ayni: programdan GERI DONUSU OLMAYAN bir
    // kilitlenme. Bu yuzden kontroller istemci tarafinda degil burada.
    if (!aktif)
    {
        // 1) Kullanici kendi hesabini pasife alamaz: pasife aldigi anda kendi
        //    oturumu gecersizlesir, bir daha giris yapamaz ve -- tek yoneticiyse
        //    -- hesabini geri acabilecek kimse kalmaz.
        if (kullaniciId > 0 && kullaniciId == m_aktifKullaniciId)
        {
            sonuc["hata"] = "Kendi hesabınızı pasife alamazsınız.";
            return sonuc;
        }

        // 2) Sistemde aktif yonetici KALMAYACAKSA islem reddedilir. Aksi halde
        //    yonetici sifresi isteyen hicbir islem (teklif silme, personel
        //    kaydi, musteri/urun duzenleme) bir daha yapilamazdi -- ve bu
        //    durumu duzeltmek de yonetici sifresi gerektirdigi icin program
        //    kalici olarak kilitli kalirdi.
        const int kalanYoneticiler = aktifYoneticiSayisi(kullaniciId);
        if (kalanYoneticiler == 0)
        {
            sonuc["hata"] = "Bu personel sistemdeki tek yönetici; pasife alınamaz. "
                            "Önce başka bir personele yönetici rolü verin.";
            return sonuc;
        }
        if (kalanYoneticiler < 0)
        {
            sonuc["hata"] = "Yönetici sayısı doğrulanamadı; işlem güvenli olmadığı için "
                            "yapılmadı. Bağlantıyı kontrol edip tekrar deneyin.";
            return sonuc;
        }
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.kullanicilar SET AktifMi = :aktif WHERE KullaniciId = :id");
    query.bindValue(":aktif", aktif);
    query.bindValue(":id", kullaniciId);

    if (!query.exec())
    {
        qWarning() << "personelAktifDurumDegistir basarisiz:" << query.lastError().text();
        sonuc["hata"] = (aktif ? QString("Personel aktif edilemedi: ")
                               : QString("Personel pasife alınamadı: ")) + query.lastError().text();
        return sonuc;
    }

    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Personel bulunamadı; kayıt silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
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
        "       t.AnaTeklifId, t.RevizyonNo, %1 AS TeklifNo, %2 AS GecerlilikGunu, "
        "       m.FirmaAdi, m.FirmaAdresi, "
        "       k.AdSoyad AS PersonelAdSoyad, k.Telefon AS PersonelTelefon, "
        "       tt.IndirimliToplam, tt.KdvTutari, tt.GenelToplam, tt.PaketlemeUcreti, tt.TasimaUcreti "
        "FROM dbo.teklifler t "
        "INNER JOIN dbo.musteriler m ON m.MusteriId = t.MusteriId "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = t.KullaniciId "
        "LEFT JOIN dbo.teklif_toplamlari tt ON tt.TeklifId = t.TeklifId "
        "WHERE t.TeklifId = :teklifId").arg(teklifNoSql("t"),
            semaKolonuVarMi(m_db, QStringLiteral("dbo.teklifler"), QStringLiteral("GecerlilikGunu"))
                ? QStringLiteral("t.GecerlilikGunu") : QStringLiteral("CAST(NULL AS INT)")));
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
    // Sozlesmedeki gecerlilik tarihi bundan hesaplanir (PDF'in basildigi gunden degil).
    veri["teklifTarihi"] = basQuery.value("OlusturmaTarihi").toDateTime().date();
    // {{GECERLILIK_TARIHI}} icin teklifin kendi gunu (db/25); NULL ise (eski
    // teklif) 0 kalir ve TeklifPdfOlusturucu eski sabiti kullanir.
    veri["gecerlilikGunu"] = basQuery.value("GecerlilikGunu").toInt();
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
    // numarasi da yazsin diye zincirin EN SON kaydini okuyoruz. Durum sutununa
    // degil zincirin gercek haline bakilir: yeni revizyon silinmis bir kayit
    // gecerlidir ve bandda kendi numarasini "gecerli teklif" diye gostermez.
    veri["gecersiz"] = teklifYerineGecenIdGetir(teklifId) > 0;
    if (veri["gecersiz"].toBool())
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
    ERP_IZ("teklifPdfOlustur");
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
    ERP_IZ("uretimPdfOlustur");
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
    ERP_IZ("pdfKaydet");
    QVariantMap sonuc = TeklifPdfOlusturucu::onizlemeyiKaydet(pdf.value("dosyaYolu").toString(),
                                                              pdf.value("dosyaAdi").toString());
    if (!sonuc.value("basarili").toBool())
        return sonuc;

    // "Üretim PDF" sutunu, uretim PDF'inin teknik ekibe verildigi ani gosterir;
    // sadece onizlemek bunu doldurmaz, indirmek doldurur. PDF zaten diske
    // yazildigi icin bu guncelleme basarisiz olsa bile islem basarili sayilir.
    const int teklifId = pdf.value("teklifId").toInt();
    if (pdf.value("tur").toString() == QLatin1String("uretim") && teklifId > 0 && baglantiHazir())
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
    ERP_IZ("pdfOnizlemesiniSil");
    TeklifPdfOlusturucu::onizlemeyiSil(onizlemeYolu);
}

QString Database::varsayilanSozlesmeMetni(const QString &dil)
{
    ERP_IZ("varsayilanSozlesmeMetni");
    // Yonetim / Sistem Ayarlari'nda kaydedilmis metin; yoksa fabrika metni.
    return ayarMetniGetir(sozlesmeAyarAnahtari(dil));
}

namespace
{
    // Sozlesme degiskenlerinin hesaplanacagi tarih: kayitli teklifte teklifin
    // tarihi ("teklifTarihi", yyyy-MM-dd), yeni formda bugun -- PDF ile ayni kural.
    QDate sozlesmeTarihi(const QVariantMap &teklif)
    {
        const QDate tarih = QDate::fromString(teklif.value("teklifTarihi").toString(), "yyyy-MM-dd");
        return tarih.isValid() ? tarih : QDate::currentDate();
    }

    // "varsayilanModu" (Yonetim / Sistem Ayarlari'nda varsayilan sozlesme
    // duzenlenirken) gercek bir teklif yoktur. Her satir, KENDI kosul
    // etiketlerini saglayan ORNEK bir teklifle doldurulur: [DOVIZ] satiri USD,
    // [TL] satiri TL teklifiyle... Boylece alternatif maddelerin hepsi
    // gorunur ve {{DEGISKEN}}'ler PDF'teki gibi okunur; geri cevirirken ayni
    // ornek kullanildigi icin degerler tekrar degiskene doner. Teslimat
    // alanlari bos birakilmaz: bos deger geri cevrilemez ve duzenlenen
    // satirdan {{TESLIMAT_*}} kaybolurdu.
    QVariantMap sozlesmeSatirTeklifi(const QVariantMap &teklif, const QString &etiketler)
    {
        if (!teklif.value("varsayilanModu").toBool())
            return teklif;

        const bool ingilizce = teklif.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
        QVariantMap ornek = teklif;
        ornek["paraBirimi"] = etiketler.contains(QStringLiteral("[TL]")) ? QStringLiteral("TL") : QStringLiteral("USD");
        ornek["kdvOrani"] = etiketler.contains(QStringLiteral("[KDV_HARIC]")) ? 0.0 : 20.0;
        ornek["tasimaUcreti"] = etiketler.contains(QStringLiteral("[NAKLIYE_DAHIL]")) ? 1.0 : 0.0;
        ornek["teslimatSekli"] = ingilizce ? QStringLiteral("Ex-Works") : QStringLiteral("Fabrika Teslim");
        ornek["teslimatYeri"] = QStringLiteral("Ankara");
        ornek.remove(QStringLiteral("teklifTarihi"));   // bugun
        return ornek;
    }
}

QVariantList Database::sozlesmeSatirlari(const QString &metin, const QVariantMap &teklif) const
{
    ERP_IZ("sozlesmeSatirlari");
    const bool ingilizce = teklif.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
    const bool varsayilanModu = teklif.value("varsayilanModu").toBool();
    const QDate bugun = sozlesmeTarihi(teklif);
    const auto uygula = [&](const QString &s, const QVariantMap &veri) {
        return TeklifPdfOlusturucu::sozlesmeDegiskenleriniUygula(s, veri, ingilizce, bugun);
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
            if (uygula(deneme, teklif) == deneme)
                break;
            etiketler += QStringLiteral("[%1] ").arg(m.captured(1));
            icerik = icerik.mid(m.capturedEnd());
        }

        // Varsayilan metin duzenlenirken hicbir satir gizlenmez (bkz.
        // sozlesmeSatirTeklifi).
        const QVariantMap satirTeklifi = sozlesmeSatirTeklifi(teklif, etiketler);
        const bool gorunur = varsayilanModu || etiketler.isEmpty()
                             || !uygula(etiketler + QStringLiteral("x"), satirTeklifi).isEmpty();
        const QString gorunen = uygula(icerik, satirTeklifi);
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
    ERP_IZ("sozlesmeSatirlarindanMetin");
    const bool ingilizce = teklif.value("dil").toString().compare("EN", Qt::CaseInsensitive) == 0;
    const QDate bugun = sozlesmeTarihi(teklif);
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
            // Satir, sozlesmeSatirlari'nda hangi veriyle doldurulduysa onunla.
            const QVariantMap satirTeklifi = sozlesmeSatirTeklifi(teklif, s.value("etiketler").toString());
            QList<QPair<QString, QString>> eslesmeler; // doldurulmus deger -> yer tutucu
            auto it = degiskenDeseni.globalMatch(ham);
            while (it.hasNext())
            {
                const QString yerTutucu = it.next().captured(0);
                const QString deger = TeklifPdfOlusturucu::sozlesmeDegiskenleriniUygula(yerTutucu, satirTeklifi, ingilizce, bugun);
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
    ERP_IZ("teklifSozlesmeMetniGetir");
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
            // Kayitli teklifin metni bos (NULL): sozlesme metni teklife
            // yazilmadan once kaydedilmis bir teklif. PDF'i fabrika metniyle
            // basildigi icin pencere de onu gosterir (ayardaki metni degil).
            return TeklifPdfOlusturucu::varsayilanSozlesmeMetni(
                dil.compare("EN", Qt::CaseInsensitive) == 0);
        }
        else
        {
            qWarning() << "teklifSozlesmeMetniGetir basarisiz:" << query.lastError().text();
        }
    }

    // Teklif henuz kaydedilmemis: pencere o anki varsayilan metinle acilir.
    return varsayilanSozlesmeMetni(dil);
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

bool Database::sevkBilgileriniRevizyonaKopyala(int kokTeklifId, int yeniTeklifId, QString &hataOut)
{
    QStringList sutunlar;
    for (const SevkAlani &alan : SEVK_METIN_ALANLARI)
        sutunlar << QString::fromLatin1(alan.sutun);
    sutunlar << QStringLiteral("SiparisTarihi");
    const QString sutunListesi = sutunlar.join(", ");

    QSqlQuery kopyala(aktifDb());
    kopyala.prepare(QString(
        "INSERT INTO dbo.sevk_bilgileri (TeklifId, %1) "
        "SELECT TOP 1 :yeni, %2 "
        "FROM dbo.sevk_bilgileri sb "
        "INNER JOIN dbo.teklifler t ON t.TeklifId = sb.TeklifId "
        "WHERE (t.TeklifId = :kok OR t.AnaTeklifId = :kok) AND t.TeklifId <> :yeni "
        "  AND NOT EXISTS (SELECT 1 FROM dbo.sevk_bilgileri x WHERE x.TeklifId = :yeni) "
        "ORDER BY t.RevizyonNo DESC")
        .arg(sutunListesi, "sb." + sutunlar.join(", sb.")));
    kopyala.bindValue(":yeni", yeniTeklifId);
    kopyala.bindValue(":kok", kokTeklifId);
    if (!kopyala.exec())
    {
        qWarning() << "sevkBilgileriniRevizyonaKopyala basarisiz:" << kopyala.lastError().text();
        hataOut = "Sevk/irsaliye bilgileri yeni revizyona taşınamadı: " + kopyala.lastError().text();
        return false;
    }
    return true;
}

QVariantMap Database::sevkBilgileriGetir(int teklifId)
{
    ERP_IZ("sevkBilgileriGetir");
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

    // Faturalanmis teklifte yalnizca KAYITLI (dolu) kimlik alanlari kilitlenir
    // (bkz. sevkBilgileriKaydet); asagidaki on doldurma bunu ayirt edilemez
    // hale getirdigi icin liste on doldurmadan once cikarilir.
    QVariantList kayitliKimlikAlanlari;
    for (const char *anahtar : { "faturaBasligi", "faturaAdresi", "faturaVergiDairesi", "faturaVergiNo" })
        if (!sonuc.value(anahtar).toString().trimmed().isEmpty())
            kayitliKimlikAlanlari << QString::fromLatin1(anahtar);
    sonuc["kayitliKimlikAlanlari"] = kayitliKimlikAlanlari;

    // Fatura takibi (db/30) ayri okunur: betik calistirilmamissa pencere bu
    // bolumu gizler, geri kalan her sey eskisi gibi calisir.
    const bool faturaAlanlariVar = semaKolonuVarMi(m_db, QStringLiteral("dbo.sevk_bilgileri"),
                                                   QStringLiteral("FaturaNo"));
    sonuc["faturaAlanlariVar"] = faturaAlanlariVar;
    sonuc["irsaliyeNo"] = QString();
    sonuc["faturaNo"] = QString();
    sonuc["faturaTarihi"] = QString();
    if (faturaAlanlariVar && sonuc.value("kayitVarMi").toBool())
    {
        QSqlQuery faturaQuery(m_db);
        faturaQuery.prepare("SELECT IrsaliyeNo, FaturaNo, FaturaTarihi FROM dbo.sevk_bilgileri "
                            "WHERE TeklifId = :teklifId");
        faturaQuery.bindValue(":teklifId", teklifId);
        if (faturaQuery.exec() && faturaQuery.next())
        {
            sonuc["irsaliyeNo"] = faturaQuery.value(0).toString();
            sonuc["faturaNo"] = faturaQuery.value(1).toString();
            sonuc["faturaTarihi"] = faturaQuery.value(2).isNull()
                ? QString() : faturaQuery.value(2).toDate().toString("yyyy-MM-dd");
        }
        else
        {
            qWarning() << "sevkBilgileriGetir (fatura) basarisiz:" << faturaQuery.lastError().text();
        }
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
    ERP_IZ("sevkBilgileriKaydet");
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
    // Irsaliye bilgilerini muhasebe de duzeltebilir (Muhasebe karti).
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")) && !modulDuzenleyebilirMi(QStringLiteral("MUHASEBE")))
    {
        sonuc["hata"] = "Bu işlem için Satış ya da Muhasebe modülünde düzenleme yetkiniz yok.";
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

    const bool faturaAlanlariVar = semaKolonuVarMi(m_db, QStringLiteral("dbo.sevk_bilgileri"),
                                                   QStringLiteral("FaturaNo"));
    QSqlQuery varMiQuery(m_db);
    varMiQuery.prepare(faturaAlanlariVar
        ? "SELECT SevkBilgileriId, FaturaNo, FaturaBasligi, FaturaAdresi, FaturaVergiDairesi, FaturaVergiNo "
          "FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId"
        : "SELECT SevkBilgileriId FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId");
    varMiQuery.bindValue(":teklifId", teklifId);
    if (!varMiQuery.exec())
    {
        qWarning() << "sevkBilgileriKaydet (kayit kontrolu) basarisiz:" << varMiQuery.lastError().text();
        sonuc["hata"] = "Sevk bilgileri okunamadı: " + varMiQuery.lastError().text();
        return sonuc;
    }
    const bool kayitVar = varMiQuery.next();

    // FATURALANMIS TEKLIFIN FATURA KIMLIGI DONDURULUR (bkz. faturaNoBul): kesilen
    // faturadaki baslik/adres/vergi bilgisi sistemdekiyle celismesin. Bos alan
    // doldurulabilir (eski kayitta girilmemis olabilir); dolu alan degismez.
    if (kayitVar && faturaAlanlariVar)
    {
        const QString faturaNo = varMiQuery.value("FaturaNo").toString().trimmed();
        if (!faturaNo.isEmpty())
        {
            static const SevkAlani KIMLIK_ALANLARI[] = {
                { "FaturaBasligi",      "faturaBasligi" },
                { "FaturaAdresi",       "faturaAdresi" },
                { "FaturaVergiDairesi", "faturaVergiDairesi" },
                { "FaturaVergiNo",      "faturaVergiNo" }
            };
            for (const SevkAlani &alan : KIMLIK_ALANLARI)
            {
                const QString eski = varMiQuery.value(QString::fromLatin1(alan.sutun)).toString().trimmed();
                const QString yeni = sevk.value(alan.anahtar).toString().trimmed();
                if (!eski.isEmpty() && yeni != eski)
                {
                    sonuc["hata"] = QString("Teklif faturalandı (Fatura No: %1); fatura başlığı, adresi, vergi dairesi "
                                            "ve vergi no değiştirilemez. Önce fatura no kaldırılmalı.").arg(faturaNo);
                    return sonuc;
                }
            }
        }
    }

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

QVariantMap Database::faturaBilgisiKaydet(int teklifId, const QVariantMap &fatura)
{
    ERP_IZ("faturaBilgisiKaydet");
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
    // Fatura no'yu duruma gore satis da muhasebe de yazar.
    if (!modulDuzenleyebilirMi(QStringLiteral("SATIS")) && !modulDuzenleyebilirMi(QStringLiteral("MUHASEBE")))
    {
        sonuc["hata"] = "Bu işlem için Satış ya da Muhasebe modülünde düzenleme yetkiniz yok.";
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.sevk_bilgileri"), QStringLiteral("FaturaNo")))
    {
        sonuc["hata"] = "Fatura bilgisi kaydedilemedi: db/30_fatura_takibi.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    // Yalnizca siparise donusmus tekliflerin faturasi olur.
    const QString durum = teklifDurumuGetir(teklifId);
    if (!teklifKilitliMi(durum))
    {
        sonuc["hata"] = QString("Teklif \"%1\" durumunda; fatura bilgisi yalnızca kabul edilmiş "
                                "ya da tamamlanmış teklife yazılır.").arg(durum);
        return sonuc;
    }

    // Yalnizca gonderilen anahtarlar yazilir; gonderilmeyen kayittaki degerini
    // korur. Boylece ekran yalnizca degistirdigini gonderir ve baska birinin
    // ayni anda girdigi irsaliye/fatura no eski degerle ezilmez.
    QString irsaliyeNo;
    QString faturaNo;
    QString faturaTarihi;
    {
        QSqlQuery eskiQuery(m_db);
        eskiQuery.prepare("SELECT IrsaliyeNo, FaturaNo, FaturaTarihi FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId");
        eskiQuery.bindValue(":teklifId", teklifId);
        if (!eskiQuery.exec())
        {
            qWarning() << "faturaBilgisiKaydet (okuma) basarisiz:" << teklifId << eskiQuery.lastError().text();
            sonuc["hata"] = "Fatura bilgisi okunamadı: " + eskiQuery.lastError().text();
            return sonuc;
        }
        if (eskiQuery.next())
        {
            irsaliyeNo = eskiQuery.value(0).toString();
            faturaNo = eskiQuery.value(1).toString();
            faturaTarihi = eskiQuery.value(2).isNull() ? QString() : eskiQuery.value(2).toDate().toString("yyyy-MM-dd");
        }
    }
    if (fatura.contains("irsaliyeNo"))
        irsaliyeNo = fatura.value("irsaliyeNo").toString();
    if (fatura.contains("faturaNo"))
        faturaNo = fatura.value("faturaNo").toString();
    if (fatura.contains("faturaTarihi"))
        faturaTarihi = fatura.value("faturaTarihi").toString();

    // Tarih kurali her giriste ayni (Muhasebe karti ve irsaliye penceresi):
    // fatura no'suz tarih olmaz (fatura geri alindi); tarihsiz fatura bugundur.
    if (faturaNo.trimmed().isEmpty())
        faturaTarihi.clear();
    else if (!QDate::fromString(faturaTarihi.trimmed(), "yyyy-MM-dd").isValid())
        faturaTarihi = QDate::currentDate().toString("yyyy-MM-dd");

    // Kayit yoksa once yalnizca TeklifId ile olusturulur; ardindan tek UPDATE.
    QSqlQuery query(m_db);
    query.prepare(
        "IF NOT EXISTS (SELECT 1 FROM dbo.sevk_bilgileri WHERE TeklifId = :teklifId1) "
        "    INSERT INTO dbo.sevk_bilgileri (TeklifId) VALUES (:teklifId2); "
        "UPDATE dbo.sevk_bilgileri SET IrsaliyeNo = :irsaliyeNo, FaturaNo = :faturaNo, "
        "    FaturaTarihi = :faturaTarihi, FaturaGuncelleyenId = :kullaniciId, "
        "    FaturaGuncellemeTarihi = SYSDATETIME() "
        "WHERE TeklifId = :teklifId3");
    query.bindValue(":teklifId1", teklifId);
    query.bindValue(":teklifId2", teklifId);
    query.bindValue(":irsaliyeNo", sevkMetinParametresi(irsaliyeNo.left(50)));
    query.bindValue(":faturaNo", sevkMetinParametresi(faturaNo.left(50)));
    query.bindValue(":faturaTarihi", tarihParametresi(faturaTarihi));
    query.bindValue(":kullaniciId", m_aktifKullaniciId > 0 ? QVariant(m_aktifKullaniciId)
                                                         : QVariant(QMetaType(QMetaType::Int)));
    query.bindValue(":teklifId3", teklifId);
    if (!query.exec())
    {
        qWarning() << "faturaBilgisiKaydet basarisiz:" << teklifId << query.lastError().text();
        sonuc["hata"] = "Fatura bilgisi kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}


// ===========================================================================
// YONETIM: Roller ve Yetkiler
// ===========================================================================
void Database::rolYetkiListesiGetirBaslat()
{
    if (!m_listeWorker)
    {
        emit rolYetkiListesiHazir(QVariantMap());
        return;
    }
    QMetaObject::invokeMethod(m_listeWorker, "rolYetkiListesiCalistir", Qt::QueuedConnection);
}

QVariantMap Database::rolKaydet(int rolId, const QVariantMap &rol)
{
    ERP_IZ("rolKaydet");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["rolId"] = 0;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = "Rolleri düzenleme yetkiniz yok.";
        return sonuc;
    }

    const QString rolAdi = alan(rol, "rolAdi");
    if (rolAdi.isEmpty())
    {
        sonuc["hata"] = "Rol adı boş olamaz.";
        return sonuc;
    }
    if (rolAdi.length() > 50)
    {
        sonuc["hata"] = "Rol adı en fazla 50 karakter olabilir.";
        return sonuc;
    }

    // Sistem rolleri yonetici korumalarinin dayanagi (bkz. sistemRoluMu):
    // yetkileri daraltilirsa ya da adi degisirse "yonetici" tanimi sessizce
    // bozulur. Baska bir rolun adini sistem rolu adina cevirmek de ayni
    // sebeple yasak.
    if (rolId > 0)
    {
        QSqlQuery mevcut(m_db);
        mevcut.prepare("SELECT RolAdi FROM dbo.roller WHERE RolId = :id");
        mevcut.bindValue(":id", rolId);
        if (!mevcut.exec())
        {
            sonuc["hata"] = "Rol okunamadı: " + mevcut.lastError().text();
            return sonuc;
        }
        if (!mevcut.next())
        {
            sonuc["hata"] = "Rol bulunamadı; silinmiş olabilir. Listeyi yenileyin.";
            return sonuc;
        }
        if (sistemRoluMu(mevcut.value(0).toString()))
        {
            sonuc["hata"] = "Sistem rolleri değiştirilemez.";
            return sonuc;
        }
    }
    if (sistemRoluMu(rolAdi))
    {
        sonuc["hata"] = "\"" + rolAdi + "\" adı sistem rolüne ayrılmıştır.";
        return sonuc;
    }

    QSet<int> gecerliModuller;
    {
        QSqlQuery modulSorgusu(m_db);
        if (!modulSorgusu.exec("SELECT ModulId FROM dbo.moduller"))
        {
            sonuc["hata"] = "Modüller okunamadı: " + modulSorgusu.lastError().text();
            return sonuc;
        }
        while (modulSorgusu.next())
            gecerliModuller.insert(modulSorgusu.value(0).toInt());
    }

    // modulId -> duzenleyebilir; yalnizca GOREBILIR olanlar yazilir.
    // Duzenleyebilir isaretliyse gorebilir de sayilir: gorulmeyen modulde
    // duzenleme yetkisi anlamsizdir (kullaniciModulleriniGetir onu hic donmez).
    QMap<int, bool> yazilacak;
    const QVariantList yetkiler = rol.value("yetkiler").toList();
    for (const QVariant &v : yetkiler)
    {
        const QVariantMap y = v.toMap();
        const int modulId = y.value("modulId").toInt();
        if (!gecerliModuller.contains(modulId))
        {
            sonuc["hata"] = "Geçersiz modül; listeyi yenileyip tekrar deneyin.";
            return sonuc;
        }
        const bool duzenleyebilir = y.value("duzenleyebilir").toBool();
        if (y.value("gorebilir").toBool() || duzenleyebilir)
            yazilacak[modulId] = duzenleyebilir;
    }
    if (yazilacak.isEmpty())
    {
        sonuc["hata"] = "En az bir modülde görme yetkisi verilmelidir; aksi halde bu "
                        "roldeki personel hiçbir modülü göremez.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    int kayitRolId = rolId;
    {
        QSqlQuery yaz(m_db);
        if (rolId > 0)
        {
            yaz.prepare("UPDATE dbo.roller SET RolAdi = :ad WHERE RolId = :id");
            yaz.bindValue(":id", rolId);
        }
        else
        {
            yaz.prepare("INSERT INTO dbo.roller (RolAdi) OUTPUT INSERTED.RolId VALUES (:ad)");
        }
        yaz.bindValue(":ad", rolAdi);

        if (!yaz.exec())
        {
            const QSqlError sqlHata = yaz.lastError();
            qWarning() << "rolKaydet basarisiz:" << sqlHata.text();
            m_db.rollback();
            sonuc["hata"] = tekillikIhlaliMi(sqlHata)
                ? "\"" + rolAdi + "\" adında bir rol zaten var."
                : "Rol kaydedilemedi: " + sqlHata.text();
            return sonuc;
        }
        if (rolId > 0 && yaz.numRowsAffected() == 0)
        {
            m_db.rollback();
            sonuc["hata"] = "Rol bulunamadı; silinmiş olabilir. Listeyi yenileyin.";
            return sonuc;
        }
        if (rolId <= 0)
        {
            if (!yaz.next())
            {
                m_db.rollback();
                sonuc["hata"] = "Rol kaydedilemedi: yeni rolün numarası alınamadı.";
                return sonuc;
            }
            kayitRolId = yaz.value(0).toInt();
        }
    }

    // Yetkileri sifirla ve yeniden yaz (personelRolleriniYaz ile ayni yol).
    QSqlQuery yetkiSil(m_db);
    yetkiSil.prepare("DELETE FROM dbo.rol_yetkileri WHERE RolId = :id");
    yetkiSil.bindValue(":id", kayitRolId);
    if (!yetkiSil.exec())
    {
        m_db.rollback();
        sonuc["hata"] = "Yetkiler güncellenemedi: " + yetkiSil.lastError().text();
        return sonuc;
    }

    for (auto it = yazilacak.cbegin(); it != yazilacak.cend(); ++it)
    {
        QSqlQuery yetkiEkle(m_db);
        yetkiEkle.prepare("INSERT INTO dbo.rol_yetkileri (RolId, ModulId, Gorebilir, Duzenleyebilir) "
                          "VALUES (:rid, :mid, 1, :duz)");
        yetkiEkle.bindValue(":rid", kayitRolId);
        yetkiEkle.bindValue(":mid", it.key());
        yetkiEkle.bindValue(":duz", it.value());
        if (!yetkiEkle.exec())
        {
            qWarning() << "rol yetkisi yazilamadi:" << yetkiEkle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Yetkiler kaydedilemedi: " + yetkiEkle.lastError().text();
            return sonuc;
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Rol kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["rolId"] = kayitRolId;
    return sonuc;
}

QVariantMap Database::rolSil(int rolId)
{
    ERP_IZ("rolSil");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = "Rolleri düzenleme yetkiniz yok.";
        return sonuc;
    }

    QSqlQuery mevcut(m_db);
    mevcut.prepare("SELECT r.RolAdi, "
                   "  (SELECT COUNT(*) FROM dbo.kullanici_rolleri kr WHERE kr.RolId = r.RolId) "
                   "FROM dbo.roller r WHERE r.RolId = :id");
    mevcut.bindValue(":id", rolId);
    if (!mevcut.exec())
    {
        sonuc["hata"] = "Rol okunamadı: " + mevcut.lastError().text();
        return sonuc;
    }
    if (!mevcut.next())
    {
        sonuc["hata"] = "Rol bulunamadı; zaten silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }
    if (mevcut.value(0).toString() == QStringLiteral("Yönetici"))
    {
        sonuc["hata"] = "\"Yönetici\" rolü silinemez.";
        return sonuc;
    }
    const int kisiSayisi = mevcut.value(1).toInt();
    if (kisiSayisi > 0)
    {
        sonuc["hata"] = QString("Bu rol %1 personele atanmış (pasifler dahil). Silmek için "
                                "önce bu personelin rollerini değiştirin.").arg(kisiSayisi);
        return sonuc;
    }

    // Kontrol ile DELETE arasinda rol birine atanmis olabilir: kosul
    // DELETE'in kendisinde de tekrarlanir.
    QSqlQuery sil(m_db);
    sil.prepare("DELETE FROM dbo.roller WHERE RolId = :id "
                "AND NOT EXISTS (SELECT 1 FROM dbo.kullanici_rolleri WHERE RolId = :id2)");
    sil.bindValue(":id", rolId);
    sil.bindValue(":id2", rolId);
    if (!sil.exec())
    {
        qWarning() << "rolSil basarisiz:" << sil.lastError().text();
        sonuc["hata"] = "Rol silinemedi: " + sil.lastError().text();
        return sonuc;
    }
    if (sil.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Rol bu sırada bir personele atanmış; silinmedi. Listeyi yenileyin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

// ===========================================================================
// YONETIM: Sistem Ayarlari
// ===========================================================================
void Database::ayarListesiGetirBaslat()
{
    if (!m_listeWorker)
    {
        emit ayarListesiHazir(QVariantMap());
        return;
    }
    QMetaObject::invokeMethod(m_listeWorker, "ayarListesiCalistir", Qt::QueuedConnection);
}

double Database::ayarSayiGetir(const QString &anahtar)
{
    const AyarTanimi *tanim = ayarTanimiBul(anahtar);
    const double varsayilan = tanim ? tanim->varsayilan : 0.0;

    if (!baglantiHazir())
        return varsayilan;
    if (!semaKolonuVarMi(aktifDb(), QStringLiteral("dbo.ayarlar"), QStringLiteral("Anahtar")))
        return varsayilan;

    QSqlQuery query(aktifDb());
    query.prepare("SELECT Deger FROM dbo.ayarlar WHERE Anahtar = :anahtar");
    query.bindValue(":anahtar", anahtar);
    if (!query.exec() || !query.next())
        return varsayilan;

    bool cevrildi = false;
    const double deger = query.value(0).toString().trimmed().toDouble(&cevrildi);
    if (!cevrildi)
        return varsayilan;
    // Tabloya elle sinir disi bir deger yazilmissa varsayilana donulur.
    if (tanim && (deger < tanim->enAz || deger > tanim->enFazla))
        return varsayilan;
    return deger;
}

// ===========================================================================
// YONETIM: Ozet (pano)
// ===========================================================================
int Database::panoOzetiGetirBaslat(const QString &donem, const QString &ozelBaslangic,
                                   const QString &ozelBitis)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_teklifWorker)
    {
        emit panoOzetiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    // Teklif tablosunu tarayan sorgu: teklif listeleriyle ayni worker'da.
    QMetaObject::invokeMethod(m_teklifWorker, "panoOzetiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, donem),
                              Q_ARG(QString, ozelBaslangic), Q_ARG(QString, ozelBitis));
    return istekNo;
}

// ===========================================================================
// YONETIM: Islem Gecmisi
// ===========================================================================
int Database::islemGecmisiGetirBaslat(const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_teklifWorker)
    {
        emit islemGecmisiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_teklifWorker, "islemGecmisiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QVariantMap, suzgec),
                              Q_ARG(int, sayfaNo), Q_ARG(int, sayfaBoyutu));
    return istekNo;
}

// ===========================================================================
// MUHASEBE: fatura kesilecek teklifler (bkz. db/31_muhasebe_modulu.sql)
// ===========================================================================
int Database::muhasebeListesiGetirBaslat(const QVariantMap &suzgec, int sayfaNo, int sayfaBoyutu)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_teklifWorker)
    {
        emit muhasebeListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_teklifWorker, "muhasebeListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QVariantMap, suzgec),
                              Q_ARG(int, sayfaNo), Q_ARG(int, sayfaBoyutu));
    return istekNo;
}

QVariantMap Database::muhasebeTeklifVerisiGetir(int teklifId)
{
    ERP_IZ("muhasebeTeklifVerisiGetir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    // PDF'e basilan veriyle birebir ayni kaynak: muhasebe faturaya teklifte
    // ne yaziyorsa onu aktarsin.
    QString firmaAdi;
    QVariantMap veri;
    QString hata;
    if (!pdfVerisiniOku(teklifId, firmaAdi, veri, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    QVariantList kalemler;
    for (const QVariant &v : veri.value("kalemler").toList())
    {
        const QVariantMap k = v.toMap();
        const QString kod = k.value("urunKodu").toString();
        kalemler << QVariantMap{
            // Teklife ozel manuel satirlarin kodu ic anahtardir; faturaya gitmez.
            { "urunKodu", kod.startsWith(QStringLiteral("MANUEL-")) ? QString() : kod },
            { "aciklama", k.value("urunAciklamasi").toString() },
            { "adet", k.value("adet") },
            { "birimFiyat", k.value("birimFiyat") },
            { "indirimliBirimFiyat", k.value("indirimliBirimFiyat") },
            { "toplamTutar", k.value("toplamTutar") },
        };
    }

    sonuc["teklifNo"] = teklifNoGetir(teklifId);
    sonuc["firmaAdi"] = firmaAdi;
    for (const char *anahtar : { "paraBirimi", "durum", "kabulTarihi", "teslimatTarihi", "personelAdSoyad",
                                 "genelIndirimOrani", "kdvOrani", "indirimliToplam", "kdvTutari",
                                 "genelToplam", "paketlemeUcreti", "tasimaUcreti" })
        sonuc[anahtar] = veri.value(anahtar);
    sonuc["kalemler"] = kalemler;
    sonuc["basarili"] = true;
    return sonuc;
}

void Database::panoyaKopyala(const QString &metin)
{
    if (QClipboard *pano = QGuiApplication::clipboard())
        pano->setText(metin);
}

QString Database::ayarMetniGetir(const QString &anahtar)
{
    const AyarTanimi *tanim = ayarTanimiBul(anahtar);
    const QString varsayilan = tanim ? tanim->varsayilanMetin : QString();

    if (!baglantiHazir())
        return varsayilan;
    if (!semaKolonuVarMi(aktifDb(), QStringLiteral("dbo.ayarlar"), QStringLiteral("Anahtar")))
        return varsayilan;

    QSqlQuery query(aktifDb());
    query.prepare("SELECT Deger FROM dbo.ayarlar WHERE Anahtar = :anahtar");
    query.bindValue(":anahtar", anahtar);
    if (!query.exec() || !query.next())
        return varsayilan;

    const QString metin = query.value(0).toString().trimmed();
    return metin.isEmpty() ? varsayilan : metin;
}

QVariantMap Database::ayarlariKaydet(const QVariantMap &degerler)
{
    ERP_IZ("ayarlariKaydet");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = "Sistem ayarlarını düzenleme yetkiniz yok.";
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.ayarlar"), QStringLiteral("Anahtar")))
    {
        sonuc["hata"] = "Ayar tablosu bulunamadı; db/17 betiği çalıştırılmamış.";
        return sonuc;
    }

    // Once hepsi denetlenir: biri gecersizse hicbiri yazilmaz. Yazilacak
    // deger metin olarak hazirlanir; NULL QVariant = "satir varsayilana donsun".
    QList<QPair<const AyarTanimi *, QVariant>> yazilacak;
    bool uzunMetinVar = false;
    for (auto it = degerler.cbegin(); it != degerler.cend(); ++it)
    {
        const AyarTanimi *tanim = ayarTanimiBul(it.key());
        if (!tanim)
        {
            sonuc["hata"] = "Tanımsız ayar: " + it.key();
            return sonuc;
        }

        if (tanim->tur == QStringLiteral("metin"))
        {
            // Bos veya fabrika metniyle ayni metin saklanmaz: satir NULL
            // kalir ve koddaki fabrika metni kullanilir.
            const QString metin = it.value().toString().trimmed();
            if (metin.isEmpty() || metin == tanim->varsayilanMetin.trimmed())
            {
                yazilacak << qMakePair(tanim, QVariant(QMetaType(QMetaType::QString)));
            }
            else
            {
                uzunMetinVar = uzunMetinVar || metin.length() > 500;
                yazilacak << qMakePair(tanim, QVariant(metin));
            }
            continue;
        }

        bool cevrildi = false;
        const double deger = it.value().toDouble(&cevrildi);
        if (!cevrildi || !std::isfinite(deger))
        {
            sonuc["hata"] = "\"" + tanim->baslik + "\" için geçerli bir sayı girin.";
            return sonuc;
        }
        if (deger < tanim->enAz || deger > tanim->enFazla)
        {
            sonuc["hata"] = QString("\"%1\" %2 ile %3 arasında olmalıdır.")
                                .arg(tanim->baslik)
                                .arg(QLocale(QLocale::Turkish).toString(tanim->enAz, 'f', 0))
                                .arg(QLocale(QLocale::Turkish).toString(tanim->enFazla, 'f', 0));
            return sonuc;
        }
        // Deger metin sutununda nokta ondalikla saklanir ("50000", "18.5");
        // okuyan taraf (ayarSayiGetir, satinalmaOnayEsigiGetir) QString::toDouble kullanir.
        const double carpan = std::pow(10.0, tanim->ondalik);
        yazilacak << qMakePair(tanim, QVariant(QString::number(std::round(deger * carpan) / carpan, 'g', 15)));
    }
    if (yazilacak.isEmpty())
    {
        sonuc["basarili"] = true;
        return sonuc;
    }

    // Deger sutunu db/17'de NVARCHAR(500) acildi; sozlesme metni sigmaz.
    // Sessizce kesilmesin (ya da SQL'in anlasilmaz "truncated" hatasi
    // cikmasin) diye once sutunun genisletilip genisletilmedigine bakilir.
    if (uzunMetinVar)
    {
        QSqlQuery sutun(m_db);
        sutun.prepare("SELECT max_length FROM sys.columns "
                      "WHERE object_id = OBJECT_ID('dbo.ayarlar') AND name = 'Deger'");
        if (!sutun.exec() || !sutun.next() || sutun.value(0).toInt() != -1)
        {
            sonuc["hata"] = "Sözleşme metni ayar tablosuna sığmıyor; önce "
                            "db/23_ayar_degeri_uzun_metin.sql betiği çalıştırılmalı.";
            return sonuc;
        }
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    for (const auto &kayit : yazilacak)
    {
        const QVariant &sade = kayit.second;

        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.ayarlar SET Deger = :deger, GuncellemeTarihi = SYSDATETIME() "
                         "WHERE Anahtar = :anahtar");
        guncelle.bindValue(":deger", sade);
        guncelle.bindValue(":anahtar", kayit.first->anahtar);
        if (!guncelle.exec())
        {
            qWarning() << "ayarlariKaydet basarisiz:" << guncelle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Ayarlar kaydedilemedi: " + guncelle.lastError().text();
            return sonuc;
        }
        // Varsayilana donen (NULL) ayarin satiri yoksa eklemeye gerek yok.
        if (guncelle.numRowsAffected() > 0 || sade.isNull())
            continue;

        QSqlQuery ekle(m_db);
        ekle.prepare("INSERT INTO dbo.ayarlar (Anahtar, Deger, Aciklama) VALUES (:anahtar, :deger, :aciklama)");
        ekle.bindValue(":anahtar", kayit.first->anahtar);
        ekle.bindValue(":deger", sade);
        ekle.bindValue(":aciklama", kayit.first->baslik);
        if (!ekle.exec())
        {
            qWarning() << "ayarlariKaydet (ekleme) basarisiz:" << ekle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Ayarlar kaydedilemedi: " + ekle.lastError().text();
            return sonuc;
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Ayarlar kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

// ===========================================================================
// SATINALMA: Tedarikcilerim
// ===========================================================================
bool Database::modulDuzenleyebilirMi(const QString &modulKodu)
{
    if (m_aktifKullaniciId <= 0)
        return false;

    const QVariantList moduller = kullaniciModulleriniGetir(m_aktifKullaniciId);
    for (const QVariant &v : moduller)
    {
        const QVariantMap m = v.toMap();
        if (m.value("modulKodu").toString() == modulKodu)
            return m.value("duzenleyebilir").toBool();
    }
    return false;
}

int Database::tedarikciListesiGetirBaslat(const QString &arama, int sayfaNo,
                                           int sayfaBoyutu, bool arsivliDahil)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_listeWorker)
    {
        emit tedarikciListesiHazir(istekNo, QVariantMap());
        return istekNo;
    }
    QMetaObject::invokeMethod(m_listeWorker, "tedarikciListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama), Q_ARG(int, sayfaNo),
                              Q_ARG(int, sayfaBoyutu), Q_ARG(bool, arsivliDahil));
    return istekNo;
}

namespace
{
    const char *const TEDARIKCI_YETKI_YOK = "Bu işlem için Satınalma modülünde düzenleme yetkiniz yok.";
}

QVariantMap Database::tedarikciEkle(const QVariantMap &tedarikci)
{
    ERP_IZ("tedarikciEkle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["tedarikciId"] = 0;
    sonuc["hata"] = QString();
    sonuc["mukerrer"] = false;
    sonuc["mukerrerAd"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.tedarikciler"), QStringLiteral("IlgiliKisiTelefonu")))
    {
        sonuc["hata"] = "Tedarikçi kaydı için db/15_tedarikci.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    QString hata;
    if (!musteriAlanlariniDenetle(tedarikci, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    const QString firmaAdi = alan(tedarikci, "firmaAdi");

    // Mukerrer firma adi bir HATA degil bir soru (musteriyle ayni mantik):
    // kullanici "yine de ekle" derse mukerrerOnayi ile tekrar gelir.
    if (!tedarikci.value("mukerrerOnayi", false).toBool())
    {
        QSqlQuery kontrol(m_db);
        kontrol.prepare("SELECT TOP (1) FirmaAdi FROM dbo.tedarikciler "
                        "WHERE LTRIM(RTRIM(FirmaAdi)) = :firmaAdi");
        kontrol.bindValue(":firmaAdi", firmaAdi);
        if (kontrol.exec() && kontrol.next())
        {
            sonuc["mukerrer"] = true;
            sonuc["mukerrerAd"] = kontrol.value(0).toString();
            sonuc["hata"] = "\"" + kontrol.value(0).toString() + "\" adlı tedarikçi zaten kayıtlı.";
            return sonuc;
        }
    }

    QSqlQuery query(m_db);
    query.prepare(
        "INSERT INTO dbo.tedarikciler "
        "(FirmaAdi, Adres, Telefon, Eposta, VergiDairesi, VergiNumarasi, IlgiliKisi, IlgiliKisiTelefonu) "
        "OUTPUT INSERTED.TedarikciId "
        "VALUES (:firmaAdi, :firmaAdresi, :firmaTelefonu, :firmaEposta, :vergiDairesi, :vergiNumarasi, "
        "        :ilgiliKisi, :ilgiliKisiTel)");
    musteriParametreleriniBagla(query, tedarikci);

    if (!query.exec() || !query.next())
    {
        qWarning() << "tedarikciEkle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Tedarikçi kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["tedarikciId"] = query.value(0).toInt();
    return sonuc;
}

QVariantMap Database::tedarikciGuncelle(int tedarikciId, const QVariantMap &tedarikci)
{
    ERP_IZ("tedarikciGuncelle");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.tedarikciler"), QStringLiteral("IlgiliKisiTelefonu")))
    {
        sonuc["hata"] = "Tedarikçi kaydı için db/15_tedarikci.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    QString hata;
    if (!musteriAlanlariniDenetle(tedarikci, hata))
    {
        sonuc["hata"] = hata;
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.tedarikciler SET "
        "FirmaAdi = :firmaAdi, Adres = :firmaAdresi, Telefon = :firmaTelefonu, "
        "Eposta = :firmaEposta, VergiDairesi = :vergiDairesi, VergiNumarasi = :vergiNumarasi, "
        "IlgiliKisi = :ilgiliKisi, IlgiliKisiTelefonu = :ilgiliKisiTel "
        "WHERE TedarikciId = :tedarikciId");
    musteriParametreleriniBagla(query, tedarikci);
    query.bindValue(":tedarikciId", tedarikciId);

    if (!query.exec())
    {
        qWarning() << "tedarikciGuncelle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Tedarikçi güncellenemedi: " + query.lastError().text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Tedarikçi bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::tedarikciSil(int tedarikciId)
{
    ERP_IZ("tedarikciSil");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();
    sonuc["iliskiliKayitVar"] = false;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("DELETE FROM dbo.tedarikciler WHERE TedarikciId = :id");
    query.bindValue(":id", tedarikciId);

    if (!query.exec())
    {
        const QSqlError hata = query.lastError();
        qWarning() << "Tedarikci silinemedi:" << hata.text();
        // satinalmalar.TedarikciId icin ON DELETE CASCADE yok (bilerek): satinalma
        // gecmisi olan tedarikci kalici silinemez, ekran arsivlemeyi onerir.
        if (fkIhlaliMi(hata))
            return iliskiliKayitSonucu(
                "Bu tedarikçiye ait satınalma kayıtları olduğu için kalıcı olarak silinemez.");

        sonuc["hata"] = "Tedarikçi silinemedi: " + hata.text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Tedarikçi bulunamadı; kayıt zaten silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::tedarikciArsivDurumDegistir(int tedarikciId, bool aktif)
{
    ERP_IZ("tedarikciArsivDurumDegistir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["hata"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.tedarikciler"), QStringLiteral("AktifMi")))
    {
        sonuc["hata"] = "Arşivleme için db/15_tedarikci.sql betiği çalıştırılmalı.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare("UPDATE dbo.tedarikciler SET AktifMi = :aktif WHERE TedarikciId = :id");
    query.bindValue(":aktif", aktif);
    query.bindValue(":id", tedarikciId);

    if (!query.exec())
    {
        qWarning() << "tedarikciArsivDurumDegistir basarisiz:" << query.lastError().text();
        sonuc["hata"] = (aktif ? QString("Tedarikçi arşivden çıkarılamadı: ")
                               : QString("Tedarikçi arşivlenemedi: ")) + query.lastError().text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Tedarikçi bulunamadı; kayıt silinmiş olabilir.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

// ============================================================================
// SATINALMA
//
// Akis: TALEP -> TEKLIF KARSILASTIRMA -> SIPARIS(LER) -> TESLIM -> FATURA
// (bkz. Database.h'deki not ve db/20_satinalma_talep_teklif_siparis.sql).
// ============================================================================

namespace
{
    const char *const SATINALMA_SEMA_YOK =
        "Satınalma ekranları için db/20_satinalma_talep_teklif_siparis.sql ve "
        "db/21_satinalma_arastirma_ve_site_siparis.sql betikleri çalıştırılmalı.";

    // Para alanlari kurus hassasiyetinde saklanir; ara carpimlarin kuyruk
    // basamaklari toplami kaydirmasin diye her satirda yuvarlanir.
    double kurusaYuvarla(double deger)
    {
        return std::round(deger * 100.0) / 100.0;
    }

    // Bos para birimi TL sayilir; gecersizse bos doner.
    QString paraBirimiDuzelt(const QString &ham)
    {
        const QString pb = ham.trimmed().toUpper();
        if (pb.isEmpty() || pb == QStringLiteral("TL") || pb == QStringLiteral("TRY"))
            return QStringLiteral("TL");
        if (pb == QStringLiteral("USD") || pb == QStringLiteral("EUR"))
            return pb;
        return QString();
    }

    // Teslimat sekilleri. Kargo firmasi / takip no yalnizca ilk ikisinde
    // anlamlidir; digerlerinde bu alanlar hic gosterilmez ve NULL yazilir.
    bool gecerliTeslimatSekliMi(const QString &sekil)
    {
        return sekil == QStringLiteral("Kargo")
            || sekil == QStringLiteral("Ambar / Nakliye")
            || sekil == QStringLiteral("Tedarikçi getirecek")
            || sekil == QStringLiteral("Biz alacağız");
    }

    bool kargoluTeslimatMi(const QString &sekil)
    {
        return sekil == QStringLiteral("Kargo") || sekil == QStringLiteral("Ambar / Nakliye");
    }

    // "Aktif" siparis: iptal / red edilmemis. Talep kaleminin siparise donusup
    // donusmedigi buna gore hesaplanir -- iptal edilen siparisin kalemleri
    // talepte yeniden acik sayilir.
    const char *const AKTIF_SIPARIS_KOSULU = "s.Durum NOT IN (N'İptal', N'Reddedildi')";

    // Siparis "acik" (henuz kapanmamis) sayilan durumlar. Kismi teslim de
    // aciktir: kalanini beklemeye devam ediyoruz.
    const char *const ACIK_SIPARIS_KOSULU =
        "s.Durum NOT IN (N'Teslim Alındı', N'İptal', N'Reddedildi')";

    // Gecikme: beklenen teslim tarihi GECMIS ve siparis hala acik.
    const char *const GECIKME_GUNU_SQL =
        "CASE WHEN s.BeklenenTeslimTarihi IS NULL THEN 0 "
        "     ELSE DATEDIFF(day, s.BeklenenTeslimTarihi, CAST(SYSDATETIME() AS DATE)) END";

    // Talebin, aktif bir siparise donusmus kalemlerinin listesi (alt sorgu).
    const char *const SIPARISLI_TALEP_KALEMLERI_SQL =
        "SELECT DISTINCT sk.TalepKalemId FROM dbo.satinalma_kalemleri sk "
        "JOIN dbo.satinalmalar s ON s.SatinalmaId = sk.SatinalmaId "
        "WHERE sk.TalepKalemId IS NOT NULL AND s.Durum NOT IN (N'İptal', N'Reddedildi')";

    // Talep durumu saklanmaz, kalemlerden hesaplanir.
    const char *const TALEP_DURUM_SQL =
        "CASE WHEN t.IptalMi = 1 THEN N'İptal' "
        "     WHEN ISNULL(ks.SiparisliKalem, 0) = 0 THEN N'Teklif Toplanıyor' "
        "     WHEN ks.SiparisliKalem >= ks.KalemSayisi THEN N'Siparişe Dönüştü' "
        "     ELSE N'Kısmen Siparişte' END";

    // Durum degistirme ekrandan gelir; gecerli kume burada tutulur ki QML'den
    // serbest metin gelip veritabanina bilinmeyen bir durum yazilmasin.
    bool elleAyarlanabilirDurumMu(const QString &durum)
    {
        return durum == QStringLiteral("Sipariş Verildi")
            || durum == QStringLiteral("Kargoda")
            || durum == QStringLiteral("İptal")
            || durum == QStringLiteral("Reddedildi");
    }

    QVariant intParametresi(int deger)
    {
        return deger > 0 ? QVariant(deger) : QVariant(QMetaType(QMetaType::Int));
    }

    // Aramadaki belge numarasi: ekranda gorunen "SA-0012" / "TLP-0012" aynen
    // yazilsa da bulunsun. On ek yoksa onekOut bos doner; numara degilse 0.
    int belgeNoAyikla(const QString &arama, QString &onekOut)
    {
        static const QRegularExpression desen(
            QStringLiteral("^\\s*(?:(SA|TLP)\\s*-?\\s*)?(\\d+)\\s*$"),
            QRegularExpression::CaseInsensitiveOption);
        const QRegularExpressionMatch m = desen.match(arama);
        onekOut = m.hasMatch() ? m.captured(1).toUpper() : QString();
        return m.hasMatch() ? m.captured(2).toInt() : 0;
    }

    QVariantMap basarisizSonuc()
    {
        QVariantMap sonuc;
        sonuc["basarili"] = false;
        sonuc["hata"]     = QString();
        return sonuc;
    }
}

bool Database::satinalmaSemasiHazirMi()
{
    // Eskiden tablo m_db.record() ile yoklaniyordu: QODBC bunu her cagrida
    // sunucudaki sp_columns'a sorar ve SQL Server plan onbellegini bosalttikca
    // ~250-400 ms surer. Her satinalma islemi (liste, kaydet, getir) bunu
    // UI thread'inde odediginden semaKolonuVarMi'nin onbellekli yoklamasi kullanilir.
    return semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalma_talepleri"), QStringLiteral("TalepId"))
        && semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("TeslimatSekli"))
        && semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("SiteSiparisNo"));
}

bool Database::satinalmaKilidiAl(const QString &kaynak, QString &hataOut)
{
    // Acik transaction icinde cagrilir; kilit transaction bitince kalkar.
    // sp_getapplock zaman asiminda hata firlatmaz, negatif kod doner.
    // kaynak yalnizca bu dosyadaki sabitlerden gelir.
    QSqlQuery kilit(m_db);
    kilit.prepare(QStringLiteral(
        "SET NOCOUNT ON; DECLARE @sonuc INT; "
        "EXEC @sonuc = sp_getapplock @Resource = N'LiyaErp_%1', @LockMode = 'Exclusive', "
        "@LockOwner = 'Transaction', @LockTimeout = 15000; "
        "SELECT @sonuc;").arg(kaynak));
    if (!kilit.exec() || !kilit.next())
    {
        qWarning() << "satinalmaKilidiAl basarisiz:" << kaynak << kilit.lastError().text();
        hataOut = QStringLiteral("İşlem kilidi alınamadı: ") + kilit.lastError().text();
        return false;
    }
    if (kilit.value(0).toInt() < 0)
    {
        hataOut = QStringLiteral("Başka bir kayıt sürüyor, lütfen tekrar deneyin.");
        return false;
    }
    return true;
}

int Database::satinalmaNoAl(const QString &tablo, const QString &kolon, QString &hataOut)
{
    // Acik transaction icinde cagrilir. Iki bilgisayar ayni anda kaydederse
    // ayni "en buyuk + 1"i okumasinlar diye numara verme transaction sonuna
    // kadar kilitlenir (teklif numarasindaki desenin aynisi, bkz.
    // numaraKilidiAl). tablo/kolon yalnizca bu dosyadaki sabitlerden gelir.
    if (!satinalmaKilidiAl(kolon, hataOut))
        return 0;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral("SELECT ISNULL(MAX(%1), 0) + 1 FROM %2").arg(kolon, tablo))
        || !query.next())
    {
        qWarning() << "satinalmaNoAl basarisiz:" << query.lastError().text();
        hataOut = QStringLiteral("Numara alınamadı: ") + query.lastError().text();
        return 0;
    }
    return query.value(0).toInt();
}

QVariantList Database::tedarikciSecenekleriGetir()
{
    ERP_IZ("tedarikciSecenekleriGetir");
    QVariantList liste;
    if (!baglantiHazir())
        return liste;

    // AktifMi kolonu 15_tedarikci.sql ile geldi; betik calistirilmamissa
    // arsiv kavrami yoktur ve hepsi listelenir.
    const bool arsivKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.tedarikciler"),
                                             QStringLiteral("AktifMi"));
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral("SELECT TedarikciId, FirmaAdi FROM dbo.tedarikciler %1 "
                                 "ORDER BY FirmaAdi")
                      .arg(arsivKolonu ? QStringLiteral("WHERE AktifMi = 1") : QString()));
    if (!query.exec())
    {
        qWarning() << "tedarikciSecenekleriGetir basarisiz:" << query.lastError().text();
        return liste;
    }

    while (query.next())
    {
        QVariantMap satir;
        satir["tedarikciId"] = query.value(0).toInt();
        satir["firmaAdi"]    = query.value(1).toString();
        liste.append(satir);
    }
    return liste;
}

double Database::satinalmaOnayEsigiGetir()
{
    // Satir yoksa / deger bozuksa 0 (onay istenmez): bozuk bir ayar yuzunden
    // TUM siparislerin onayda takilmasi, onay istenmemesinden daha zararlidir.
    // Varsayilan ve sinirlar ayarTanimlari()'nda (SqlYardimcilari.cpp).
    return ayarSayiGetir(QStringLiteral("SATINALMA_PATRON_ONAY_ESIGI_TL"));
}

QVariantList Database::satinalmaKalemOnerileri(const QString &arama, int enFazla)
{
    QVariantList liste;
    if (!baglantiHazir())
        return liste;
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalma_kalemleri"), QStringLiteral("KalemAdi")))
        return liste;

    const QString desen = likeDeseni(arama);
    if (desen.isEmpty())
        return liste;

    // Ayni ad defalarca gecer (her alimda bir satir); bizi ilgilendiren, her
    // ad icin EN SON alim. ROW_NUMBER ile ad basina tek satir birakiliyor.
    // Iptal/red edilen siparisler "son alim" sayilmaz.
    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT TOP (:enFazla) KalemAdi, Birim, BirimFiyatDoviz, ParaBirimi, Kur, "
        "       TedarikciAdi, UrunLinki, SatinalmaTarihi "
        "FROM ( "
        "    SELECT k.KalemAdi, k.Birim, k.BirimFiyatDoviz, k.ParaBirimi, k.Kur, "
        "           t.FirmaAdi AS TedarikciAdi, k.UrunLinki, s.SatinalmaTarihi, "
        "           ROW_NUMBER() OVER (PARTITION BY k.KalemAdi "
        "                              ORDER BY s.SatinalmaTarihi DESC, k.SatinalmaKalemId DESC) AS sira "
        "    FROM dbo.satinalma_kalemleri k "
        "    JOIN dbo.satinalmalar s ON s.SatinalmaId = k.SatinalmaId "
        "    LEFT JOIN dbo.tedarikciler t ON t.TedarikciId = s.TedarikciId "
        "    WHERE k.KalemAdi LIKE :desen ESCAPE '\\' AND %1 "
        ") x "
        "WHERE sira = 1 "
        "ORDER BY SatinalmaTarihi DESC").arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
    query.bindValue(":enFazla", qBound(1, enFazla, 50));
    query.bindValue(":desen", desen);

    if (!query.exec())
    {
        qWarning() << "satinalmaKalemOnerileri basarisiz:" << query.lastError().text();
        return liste;
    }

    while (query.next())
    {
        QVariantMap satir;
        satir["kalemAdi"]     = query.value(0).toString();
        satir["birim"]        = query.value(1).toString();
        satir["birimFiyat"]   = query.value(2).toDouble();
        satir["paraBirimi"]   = query.value(3).toString();
        satir["kur"]          = query.value(4).toDouble();
        satir["tedarikciAdi"] = query.value(5).toString();
        satir["urunLinki"]    = query.value(6).toString();
        satir["tarih"]        = query.value(7).toDate();
        liste.append(satir);
    }
    return liste;
}

QStringList Database::satinalmaNeIcinOnerileri(const QString &arama, int enFazla)
{
    QStringList liste;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return liste;

    const QString desen = likeDeseni(arama);
    if (desen.isEmpty())
        return liste;

    // Hem talep kalemlerinde hem eski (talepsiz) siparis kalemlerinde
    // yazilmis adlar onerilir.
    QSqlQuery query(m_db);
    query.prepare(
        "SELECT TOP (:enFazla) NeIcin FROM ( "
        "    SELECT NeIcin FROM dbo.satinalma_talep_kalemleri WHERE NeIcin LIKE :desen1 ESCAPE '\\' "
        "    UNION "
        "    SELECT NeIcin FROM dbo.satinalma_kalemleri WHERE NeIcin LIKE :desen2 ESCAPE '\\' "
        ") x WHERE NULLIF(LTRIM(RTRIM(NeIcin)), N'') IS NOT NULL ORDER BY NeIcin");
    query.bindValue(":enFazla", qBound(1, enFazla, 50));
    query.bindValue(":desen1", desen);
    query.bindValue(":desen2", desen);

    if (!query.exec())
    {
        qWarning() << "satinalmaNeIcinOnerileri basarisiz:" << query.lastError().text();
        return liste;
    }
    while (query.next())
        liste.append(query.value(0).toString());
    return liste;
}

QStringList Database::satinalmaSiteleriGetir()
{
    QStringList liste;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return liste;

    QSqlQuery query(m_db);
    if (!query.exec(QStringLiteral(
            "SELECT TOP 100 FirmaAdi FROM dbo.satinalma_teklif_firmalari "
            "WHERE Kaynak = N'İnternet' AND TedarikciId IS NULL "
            "GROUP BY FirmaAdi ORDER BY COUNT(*) DESC, FirmaAdi")))
    {
        qWarning() << "satinalmaSiteleriGetir basarisiz:" << query.lastError().text();
        return liste;
    }
    while (query.next())
        liste.append(query.value(0).toString());
    return liste;
}

// ---------------------------------------------------------------------------
// TALEP
// ---------------------------------------------------------------------------

QVariantList Database::talepListesiGetir(const QString &durumFiltresi, const QString &arama)
{
    ERP_IZ("talepListesiGetir");
    QVariantList liste;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return liste;

    // Acik talep: siparise donusmemis kalemi VAR ya da siparisleri henuz
    // gelmedi. "Benim siparisim ne durumda?" sorusu boyle talepten cevaplanir;
    // talep, butun siparisleri teslim alininca tamamlanir.
    QString filtre;
    if (durumFiltresi == QStringLiteral("acik"))
        filtre = QStringLiteral("(Durum IN (N'Teklif Toplanıyor', N'Kısmen Siparişte') "
                                " OR (Durum = N'Siparişe Dönüştü' AND AcikSiparis > 0))");
    else if (durumFiltresi == QStringLiteral("tamam"))
        filtre = QStringLiteral("Durum = N'Siparişe Dönüştü' AND AcikSiparis = 0");
    else if (durumFiltresi == QStringLiteral("iptal"))
        filtre = QStringLiteral("Durum = N'İptal'");
    else
        filtre = QStringLiteral("1 = 1");

    const QString desen = likeDeseni(arama);
    QString onek;
    const int aramaNo = belgeNoAyikla(arama, onek);
    QString aramaKosulu;
    if (!desen.isEmpty())
    {
        aramaKosulu = QStringLiteral(
            " AND (TalepNo = :aramaNo OR IsteyenKisi LIKE :desen1 ESCAPE '\\' "
            "      OR EXISTS (SELECT 1 FROM dbo.satinalma_talep_kalemleri a "
            "                 WHERE a.TalepId = x.TalepId "
            "                   AND (a.KalemAdi LIKE :desen2 ESCAPE '\\' OR a.NeIcin LIKE :desen3 ESCAPE '\\')) "
            // Tedarikci / site adiyla da: "X firmasina sorduklarim".
            "      OR EXISTS (SELECT 1 FROM dbo.satinalma_teklif_firmalari f "
            "                 WHERE f.TalepId = x.TalepId AND f.FirmaAdi LIKE :desen4 ESCAPE '\\'))");
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "WITH x AS ( "
        "  SELECT t.TalepId, t.TalepNo, t.TalepTarihi, t.IsteyenBirim, t.IsteyenKisi, t.IhtiyacTarihi, "
        "         t.Aciklama, ISNULL(ks.KalemSayisi, 0) AS KalemSayisi, "
        "         ISNULL(ks.SiparisliKalem, 0) AS SiparisliKalem, ISNULL(fs.FirmaSayisi, 0) AS FirmaSayisi, "
        "         ISNULL(ks.HazirKalem, 0) AS HazirKalem, ISNULL(ks.FiyatBekleyen, 0) AS FiyatBekleyen, "
        "         ISNULL(ks.KaynakBekleyen, 0) AS KaynakBekleyen, ISNULL(os.AcikSiparis, 0) AS AcikSiparis, "
        "         %1 AS Durum, "
        "         ISNULL(STUFF((SELECT TOP 4 N', ' + a.KalemAdi FROM dbo.satinalma_talep_kalemleri a "
        "                       WHERE a.TalepId = t.TalepId ORDER BY a.SiraNo, a.TalepKalemId "
        "                       FOR XML PATH(N''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N''), N'') "
        "           AS KalemOzeti, "
        "         ISNULL(STUFF((SELECT DISTINCT N', ' + a.NeIcin FROM dbo.satinalma_talep_kalemleri a "
        "                       WHERE a.TalepId = t.TalepId AND NULLIF(a.NeIcin, N'') IS NOT NULL "
        "                       FOR XML PATH(N''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N''), N'') "
        "           AS NeIcinOzeti "
        "  FROM dbo.satinalma_talepleri t "
        // Siparise donusmemis kalemler, alinacak yerin (secili fiyat satiri)
        // durumuna gore: fiyati belli (hazir), fiyati bekleniyor (0), yeri yok.
        "  OUTER APPLY ( "
        "      SELECT COUNT(*) AS KalemSayisi, "
        "             SUM(CASE WHEN sp.TalepKalemId IS NOT NULL THEN 1 ELSE 0 END) AS SiparisliKalem, "
        "             SUM(CASE WHEN sp.TalepKalemId IS NULL AND sec.EnYuksek > 0 THEN 1 ELSE 0 END) AS HazirKalem, "
        "             SUM(CASE WHEN sp.TalepKalemId IS NULL AND sec.Adet > 0 AND ISNULL(sec.EnYuksek, 0) = 0 "
        "                      THEN 1 ELSE 0 END) AS FiyatBekleyen, "
        "             SUM(CASE WHEN sp.TalepKalemId IS NULL AND sec.Adet = 0 THEN 1 ELSE 0 END) AS KaynakBekleyen "
        "      FROM dbo.satinalma_talep_kalemleri tk "
        "      LEFT JOIN (%2) sp ON sp.TalepKalemId = tk.TalepKalemId "
        "      OUTER APPLY (SELECT COUNT(*) AS Adet, MAX(fy.BirimFiyat) AS EnYuksek "
        "                   FROM dbo.satinalma_teklif_fiyatlari fy "
        "                   WHERE fy.TalepKalemId = tk.TalepKalemId AND fy.SecildiMi = 1) sec "
        "      WHERE tk.TalepId = t.TalepId "
        "  ) ks "
        "  OUTER APPLY (SELECT COUNT(*) AS FirmaSayisi FROM dbo.satinalma_teklif_firmalari f "
        "               WHERE f.TalepId = t.TalepId) fs "
        "  OUTER APPLY (SELECT COUNT(*) AS AcikSiparis FROM dbo.satinalmalar s "
        "               WHERE s.TalepId = t.TalepId AND %5) os "
        ") "
        "SELECT TOP 500 TalepId, TalepNo, TalepTarihi, IsteyenBirim, IsteyenKisi, IhtiyacTarihi, "
        "       DATEDIFF(day, CAST(SYSDATETIME() AS DATE), IhtiyacTarihi) AS GunKaldi, "
        "       Aciklama, KalemSayisi, SiparisliKalem, FirmaSayisi, Durum, KalemOzeti, NeIcinOzeti, "
        "       HazirKalem, FiyatBekleyen, KaynakBekleyen, AcikSiparis "
        "FROM x WHERE %3%4 "
        // Islem bekleyen talepler uste, teslimat bekleyenler arkalarina;
        // her grupta ihtiyac tarihi en yakin olan uste (tarihsizler sona).
        "ORDER BY CASE WHEN Durum IN (N'Teklif Toplanıyor', N'Kısmen Siparişte') THEN 0 "
        "              WHEN Durum = N'Siparişe Dönüştü' AND AcikSiparis > 0 THEN 1 ELSE 2 END, "
        "         CASE WHEN IhtiyacTarihi IS NULL THEN 1 ELSE 0 END, IhtiyacTarihi, TalepNo DESC")
        .arg(QString::fromUtf8(TALEP_DURUM_SQL), QString::fromUtf8(SIPARISLI_TALEP_KALEMLERI_SQL),
             filtre, aramaKosulu, QString::fromUtf8(ACIK_SIPARIS_KOSULU)));
    if (!desen.isEmpty())
    {
        // "SA-…" siparis numarasidir, talep numarasi sayilmaz.
        query.bindValue(":aramaNo", aramaNo > 0 && onek != QStringLiteral("SA") ? aramaNo : -1);
        query.bindValue(":desen1", desen);
        query.bindValue(":desen2", desen);
        query.bindValue(":desen3", desen);
        query.bindValue(":desen4", desen);
    }

    if (!query.exec())
    {
        qWarning() << "talepListesiGetir basarisiz:" << query.lastError().text();
        return liste;
    }

    while (query.next())
    {
        QVariantMap satir;
        satir["talepId"]             = query.value(0).toInt();
        satir["talepNo"]             = query.value(1).toInt();
        satir["talepTarihi"]         = query.value(2).toDate();
        satir["isteyenBirim"]        = query.value(3).toString();
        satir["isteyenKisi"]         = query.value(4).toString();
        satir["ihtiyacTarihi"]       = query.value(5).toDate();
        // Ihtiyac tarihi yoksa "kalan gun" anlamsizdir; QML null'a bakar.
        satir["ihtiyacGunuKaldi"]    = query.value(6).isNull() ? QVariant() : query.value(6).toInt();
        satir["aciklama"]            = query.value(7).toString();
        satir["kalemSayisi"]         = query.value(8).toInt();
        satir["siparisliKalemSayisi"] = query.value(9).toInt();
        satir["firmaSayisi"]         = query.value(10).toInt();
        satir["durum"]               = query.value(11).toString();
        satir["kalemOzeti"]          = query.value(12).toString();
        satir["neIcinOzeti"]         = query.value(13).toString();
        satir["hazirKalem"]          = query.value(14).toInt();
        satir["fiyatBekleyenKalem"]  = query.value(15).toInt();
        satir["kaynakBekleyenKalem"] = query.value(16).toInt();
        satir["acikSiparisSayisi"]   = query.value(17).toInt();
        liste.append(satir);
    }
    return liste;
}

QVariantMap Database::talepGetir(int talepId)
{
    ERP_IZ("talepGetir");
    QVariantMap sonuc;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return sonuc;

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "SELECT t.TalepId, t.TalepNo, t.TalepTarihi, t.IsteyenBirim, t.IsteyenKisi, t.IhtiyacTarihi, "
        "       t.Aciklama, t.IptalMi, t.IptalSebebi, %1 AS Durum "
        "FROM dbo.satinalma_talepleri t "
        "OUTER APPLY ( "
        "    SELECT COUNT(*) AS KalemSayisi, "
        "           SUM(CASE WHEN sp.TalepKalemId IS NOT NULL THEN 1 ELSE 0 END) AS SiparisliKalem "
        "    FROM dbo.satinalma_talep_kalemleri tk "
        "    LEFT JOIN (%2) sp ON sp.TalepKalemId = tk.TalepKalemId "
        "    WHERE tk.TalepId = t.TalepId "
        ") ks "
        "WHERE t.TalepId = :id")
        .arg(QString::fromUtf8(TALEP_DURUM_SQL), QString::fromUtf8(SIPARISLI_TALEP_KALEMLERI_SQL)));
    query.bindValue(":id", talepId);
    if (!query.exec() || !query.next())
    {
        if (query.lastError().isValid())
            qWarning() << "talepGetir basarisiz:" << query.lastError().text();
        return sonuc;
    }

    sonuc["talepId"]       = query.value(0).toInt();
    sonuc["talepNo"]       = query.value(1).toInt();
    sonuc["talepTarihi"]   = query.value(2).toDate();
    sonuc["isteyenBirim"]  = query.value(3).toString();
    sonuc["isteyenKisi"]   = query.value(4).toString();
    // Takvim "yyyy-MM-dd" bekliyor; QDate -> JS Date donusumunde saat dilimi
    // kaymasi olmasin diye metin olarak da veriliyor.
    sonuc["ihtiyacTarihi"] = query.value(5).isNull()
                                 ? QString() : query.value(5).toDate().toString("yyyy-MM-dd");
    sonuc["aciklama"]      = query.value(6).toString();
    sonuc["iptal"]         = query.value(7).toBool();
    sonuc["iptalSebebi"]   = query.value(8).toString();
    sonuc["durum"]         = query.value(9).toString();

    // Kalemler + (varsa) donustukleri aktif siparis.
    QVariantList kalemler;
    QSqlQuery kalemQuery(m_db);
    kalemQuery.prepare(QStringLiteral(
        "SELECT tk.TalepKalemId, tk.KalemAdi, tk.NeIcin, tk.Miktar, tk.Birim, tk.Aciklama, "
        "       sp.SatinalmaId, sp.SiparisNo, tk.Arastirilacak "
        "FROM dbo.satinalma_talep_kalemleri tk "
        "OUTER APPLY ( "
        "    SELECT TOP 1 s.SatinalmaId, s.SiparisNo FROM dbo.satinalma_kalemleri sk "
        "    JOIN dbo.satinalmalar s ON s.SatinalmaId = sk.SatinalmaId "
        "    WHERE sk.TalepKalemId = tk.TalepKalemId AND %1 ORDER BY s.SatinalmaId DESC "
        ") sp "
        "WHERE tk.TalepId = :id ORDER BY tk.SiraNo, tk.TalepKalemId")
        .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
    kalemQuery.bindValue(":id", talepId);
    if (kalemQuery.exec())
    {
        while (kalemQuery.next())
        {
            QVariantMap kalem;
            kalem["talepKalemId"] = kalemQuery.value(0).toInt();
            kalem["kalemAdi"]     = kalemQuery.value(1).toString();
            kalem["neIcin"]       = kalemQuery.value(2).toString();
            kalem["miktar"]       = kalemQuery.value(3).toDouble();
            kalem["birim"]        = kalemQuery.value(4).toString();
            kalem["aciklama"]     = kalemQuery.value(5).toString();
            kalem["satinalmaId"]  = kalemQuery.value(6).toInt();
            kalem["siparisNo"]    = kalemQuery.value(7).toInt();
            kalem["arastirilacak"] = kalemQuery.value(8).toBool();
            kalemler.append(kalem);
        }
    }
    else
    {
        qWarning() << "talep kalemleri okunamadi:" << kalemQuery.lastError().text();
    }
    sonuc["kalemler"] = kalemler;

    // Teklif veren firmalar. Aktif siparisi olan firma kilitlidir.
    QVariantList firmalar;
    QSqlQuery firmaQuery(m_db);
    firmaQuery.prepare(QStringLiteral(
        "SELECT f.TeklifFirmaId, f.TedarikciId, f.FirmaAdi, f.Kaynak, f.TeklifLinki, f.ParaBirimi, "
        "       f.Kur, f.TeslimSuresiGun, f.Notu, "
        "       CASE WHEN EXISTS (SELECT 1 FROM dbo.satinalmalar s "
        "                         WHERE s.TeklifFirmaId = f.TeklifFirmaId AND %1) "
        "            THEN 1 ELSE 0 END AS SiparisiVar "
        "FROM dbo.satinalma_teklif_firmalari f "
        "WHERE f.TalepId = :id ORDER BY f.SiraNo, f.TeklifFirmaId")
        .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
    firmaQuery.bindValue(":id", talepId);
    if (firmaQuery.exec())
    {
        while (firmaQuery.next())
        {
            QVariantMap firma;
            firma["teklifFirmaId"]   = firmaQuery.value(0).toInt();
            firma["tedarikciId"]     = firmaQuery.value(1).toInt();
            firma["firmaAdi"]        = firmaQuery.value(2).toString();
            firma["kaynak"]          = firmaQuery.value(3).toString();
            firma["teklifLinki"]     = firmaQuery.value(4).toString();
            firma["paraBirimi"]      = firmaQuery.value(5).toString();
            firma["kur"]             = firmaQuery.value(6).toDouble();
            firma["teslimSuresiGun"] = firmaQuery.value(7).toInt();
            firma["notu"]            = firmaQuery.value(8).toString();
            firma["siparisiVar"]     = firmaQuery.value(9).toInt() == 1;
            firmalar.append(firma);
        }
    }
    else
    {
        qWarning() << "teklif firmalari okunamadi:" << firmaQuery.lastError().text();
    }
    sonuc["firmalar"] = firmalar;

    QVariantList fiyatlar;
    QSqlQuery fiyatQuery(m_db);
    fiyatQuery.prepare(
        "SELECT fy.TalepKalemId, fy.TeklifFirmaId, fy.BirimFiyat, fy.SecildiMi, fy.UrunLinki, fy.Notu "
        "FROM dbo.satinalma_teklif_fiyatlari fy "
        "JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = fy.TeklifFirmaId "
        "WHERE f.TalepId = :id ORDER BY f.SiraNo, f.TeklifFirmaId");
    fiyatQuery.bindValue(":id", talepId);
    if (fiyatQuery.exec())
    {
        while (fiyatQuery.next())
        {
            QVariantMap fiyat;
            fiyat["talepKalemId"]  = fiyatQuery.value(0).toInt();
            fiyat["teklifFirmaId"] = fiyatQuery.value(1).toInt();
            fiyat["birimFiyat"]    = fiyatQuery.value(2).toDouble();
            fiyat["secildi"]       = fiyatQuery.value(3).toBool();
            fiyat["link"]          = fiyatQuery.value(4).toString();
            fiyat["notu"]          = fiyatQuery.value(5).toString();
            fiyatlar.append(fiyat);
        }
    }
    else
    {
        qWarning() << "teklif fiyatlari okunamadi:" << fiyatQuery.lastError().text();
    }
    sonuc["fiyatlar"] = fiyatlar;

    // Bu talepten olusmus siparisler (iptaller dahil, gecmis gorunsun).
    QVariantList siparisler;
    QSqlQuery siparisQuery(m_db);
    siparisQuery.prepare(QStringLiteral(
        "SELECT s.SatinalmaId, s.SiparisNo, ISNULL(t.FirmaAdi, f.FirmaAdi), s.Durum, "
        "       ISNULL(k.Tutar, 0), %1 "
        "FROM dbo.satinalmalar s "
        "LEFT JOIN dbo.tedarikciler t ON t.TedarikciId = s.TedarikciId "
        "LEFT JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = s.TeklifFirmaId "
        "OUTER APPLY (SELECT SUM(ToplamTutarTL) AS Tutar FROM dbo.satinalma_kalemleri "
        "             WHERE SatinalmaId = s.SatinalmaId) k "
        "WHERE s.TalepId = :id ORDER BY s.SiparisNo")
        .arg(semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("EksikKapatmaTarihi"))
                 ? QStringLiteral("CASE WHEN s.EksikKapatmaTarihi IS NULL THEN 0 ELSE 1 END")
                 : QStringLiteral("0")));
    siparisQuery.bindValue(":id", talepId);
    if (siparisQuery.exec())
    {
        while (siparisQuery.next())
        {
            QVariantMap siparis;
            siparis["satinalmaId"]   = siparisQuery.value(0).toInt();
            siparis["siparisNo"]     = siparisQuery.value(1).toInt();
            siparis["firmaAdi"]      = siparisQuery.value(2).toString();
            siparis["durum"]         = siparisQuery.value(3).toString();
            siparis["toplamTutarTL"] = siparisQuery.value(4).toDouble();
            siparis["eksikKapatildi"] = siparisQuery.value(5).toInt() == 1;
            siparisler.append(siparis);
        }
    }
    else
    {
        qWarning() << "talep siparisleri okunamadi:" << siparisQuery.lastError().text();
    }
    sonuc["siparisler"] = siparisler;
    return sonuc;
}

QVariantMap Database::talepKaydet(const QVariantMap &talep)
{
    ERP_IZ("talepKaydet");
    QVariantMap sonuc = basarisizSonuc();
    sonuc["talepId"] = 0;
    sonuc["talepNo"] = 0;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!satinalmaSemasiHazirMi())
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    // ---- Denetim (transaction'dan once) ----
    const QVariantList kalemlerGirdi = talep.value("kalemler").toList();
    const QVariantList firmalarGirdi = talep.value("firmalar").toList();
    const QVariantList fiyatlarGirdi = talep.value("fiyatlar").toList();

    if (kalemlerGirdi.isEmpty())
    {
        sonuc["hata"] = "Talepte en az bir kalem olmalı.";
        return sonuc;
    }
    for (int i = 0; i < kalemlerGirdi.size(); ++i)
    {
        const QVariantMap k = kalemlerGirdi.at(i).toMap();
        if (alan(k, "kalemAdi").isEmpty())
        {
            sonuc["hata"] = QString("%1. kalemin adı boş. Ne alınacağını yazın.").arg(i + 1);
            return sonuc;
        }
        if (k.value("miktar", 0).toDouble() <= 0.0)
        {
            sonuc["hata"] = QString("\"%1\" için miktar 0'dan büyük olmalı.").arg(alan(k, "kalemAdi"));
            return sonuc;
        }
    }
    for (int i = 0; i < firmalarGirdi.size(); ++i)
    {
        const QVariantMap f = firmalarGirdi.at(i).toMap();
        if (alan(f, "firmaAdi").isEmpty())
        {
            sonuc["hata"] = QString("%1. fiyat notunda nereden alınacağı boş.").arg(i + 1);
            return sonuc;
        }
        if (paraBirimiDuzelt(alan(f, "paraBirimi")).isEmpty())
        {
            sonuc["hata"] = QString("\"%1\" teklifinde para birimi TL, USD veya EUR olmalı.")
                                .arg(alan(f, "firmaAdi"));
            return sonuc;
        }
    }
    // Kalem basina en fazla bir secim.
    {
        QSet<QString> secilenKalemler;
        for (const QVariant &ham : fiyatlarGirdi)
        {
            const QVariantMap fy = ham.toMap();
            if (fy.value("birimFiyat", 0).toDouble() < 0.0)
            {
                sonuc["hata"] = "Birim fiyat eksi olamaz.";
                return sonuc;
            }
            if (!fy.value("secildi", false).toBool())
                continue;
            const QString anahtar = alan(fy, "kalemAnahtar");
            if (secilenKalemler.contains(anahtar))
            {
                sonuc["hata"] = "Bir kalem için yalnızca bir firma seçilebilir.";
                return sonuc;
            }
            secilenKalemler.insert(anahtar);
        }
    }

    int talepId = talep.value("talepId", 0).toInt();
    int talepNo = 0;

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }
    auto hataylaDon = [&](const QString &mesaj) {
        m_db.rollback();
        sonuc["hata"] = mesaj;
        return sonuc;
    };

    // ---- Baslik ----
    if (talepId <= 0)
    {
        QString noHatasi;
        talepNo = satinalmaNoAl(QStringLiteral("dbo.satinalma_talepleri"),
                                QStringLiteral("TalepNo"), noHatasi);
        if (talepNo <= 0)
            return hataylaDon(noHatasi);

        QSqlQuery ekle(m_db);
        ekle.prepare(
            "INSERT INTO dbo.satinalma_talepleri "
            "(TalepNo, IsteyenBirim, IsteyenKisi, IhtiyacTarihi, Aciklama, KullaniciId) "
            "OUTPUT INSERTED.TalepId "
            "VALUES (:talepNo, :isteyenBirim, :isteyenKisi, :ihtiyacTarihi, :aciklama, :kullaniciId)");
        ekle.bindValue(":talepNo", talepNo);
        ekle.bindValue(":isteyenBirim", metinParametresi(alan(talep, "isteyenBirim")));
        ekle.bindValue(":isteyenKisi", metinParametresi(alan(talep, "isteyenKisi")));
        ekle.bindValue(":ihtiyacTarihi", tarihParametresi(alan(talep, "ihtiyacTarihi")));
        ekle.bindValue(":aciklama", metinParametresi(alan(talep, "aciklama")));
        ekle.bindValue(":kullaniciId", intParametresi(m_aktifKullaniciId));
        if (!ekle.exec() || !ekle.next())
        {
            qWarning() << "talep eklenemedi:" << ekle.lastError().text();
            return hataylaDon("Talep kaydedilemedi: " + ekle.lastError().text());
        }
        talepId = ekle.value(0).toInt();
    }
    else
    {
        QSqlQuery guncelle(m_db);
        guncelle.prepare(
            "UPDATE dbo.satinalma_talepleri SET IsteyenBirim = :isteyenBirim, "
            "IsteyenKisi = :isteyenKisi, IhtiyacTarihi = :ihtiyacTarihi, Aciklama = :aciklama, "
            "GuncellemeTarihi = SYSDATETIME() "
            "OUTPUT INSERTED.TalepNo "
            "WHERE TalepId = :id AND IptalMi = 0");
        guncelle.bindValue(":isteyenBirim", metinParametresi(alan(talep, "isteyenBirim")));
        guncelle.bindValue(":isteyenKisi", metinParametresi(alan(talep, "isteyenKisi")));
        guncelle.bindValue(":ihtiyacTarihi", tarihParametresi(alan(talep, "ihtiyacTarihi")));
        guncelle.bindValue(":aciklama", metinParametresi(alan(talep, "aciklama")));
        guncelle.bindValue(":id", talepId);
        if (!guncelle.exec())
        {
            qWarning() << "talep guncellenemedi:" << guncelle.lastError().text();
            return hataylaDon("Talep kaydedilemedi: " + guncelle.lastError().text());
        }
        if (!guncelle.next())
            return hataylaDon("Talep bulunamadı ya da iptal edilmiş. Listeyi yenileyin.");
        talepNo = guncelle.value(0).toInt();
    }

    // ---- Mevcut durum: kalemler, siparise donusmus olanlar, kilitli firmalar ----
    QSet<int> mevcutKalemler;
    QHash<int, int> siparisliKalemler;   // talepKalemId -> siparisNo
    {
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral(
            "SELECT tk.TalepKalemId, sp.SiparisNo FROM dbo.satinalma_talep_kalemleri tk "
            "OUTER APPLY (SELECT TOP 1 s.SiparisNo FROM dbo.satinalma_kalemleri sk "
            "             JOIN dbo.satinalmalar s ON s.SatinalmaId = sk.SatinalmaId "
            "             WHERE sk.TalepKalemId = tk.TalepKalemId AND %1) sp "
            "WHERE tk.TalepId = :id").arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
        q.bindValue(":id", talepId);
        if (!q.exec())
            return hataylaDon("Talep kalemleri okunamadı: " + q.lastError().text());
        while (q.next())
        {
            const int id = q.value(0).toInt();
            mevcutKalemler.insert(id);
            if (!q.value(1).isNull())
                siparisliKalemler.insert(id, q.value(1).toInt());
        }
    }
    QSet<int> mevcutFirmalar;
    QSet<int> kilitliFirmalar;
    {
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral(
            "SELECT f.TeklifFirmaId, CASE WHEN EXISTS (SELECT 1 FROM dbo.satinalmalar s "
            "       WHERE s.TeklifFirmaId = f.TeklifFirmaId AND %1) THEN 1 ELSE 0 END "
            "FROM dbo.satinalma_teklif_firmalari f WHERE f.TalepId = :id")
            .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
        q.bindValue(":id", talepId);
        if (!q.exec())
            return hataylaDon("Teklif firmaları okunamadı: " + q.lastError().text());
        while (q.next())
        {
            mevcutFirmalar.insert(q.value(0).toInt());
            if (q.value(1).toInt() == 1)
                kilitliFirmalar.insert(q.value(0).toInt());
        }
    }

    // ---- Kalemler (upsert) ----
    QHash<QString, int> kalemIdleri;   // istemci anahtari -> TalepKalemId
    QSet<int> gelenKalemler;
    {
        QSqlQuery ekle(m_db);
        ekle.prepare("INSERT INTO dbo.satinalma_talep_kalemleri "
                     "(TalepId, SiraNo, KalemAdi, NeIcin, Miktar, Birim, Aciklama, Arastirilacak) "
                     "OUTPUT INSERTED.TalepKalemId "
                     "VALUES (:talepId, :sira, :kalemAdi, :neIcin, :miktar, :birim, :aciklama, :arastir)");
        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.satinalma_talep_kalemleri SET SiraNo = :sira, KalemAdi = :kalemAdi, "
                         "NeIcin = :neIcin, Miktar = :miktar, Birim = :birim, Aciklama = :aciklama, "
                         "Arastirilacak = :arastir "
                         "WHERE TalepKalemId = :id AND TalepId = :talepId");

        for (int i = 0; i < kalemlerGirdi.size(); ++i)
        {
            const QVariantMap k = kalemlerGirdi.at(i).toMap();
            const int id = k.value("talepKalemId", 0).toInt();
            const QString anahtar = alan(k, "anahtar");

            if (id > 0 && mevcutKalemler.contains(id))
            {
                gelenKalemler.insert(id);
                kalemIdleri.insert(anahtar, id);
                // Siparise donusmus kalem degismez: siparis ona dayaniyor.
                if (siparisliKalemler.contains(id))
                    continue;

                guncelle.bindValue(":sira", i);
                guncelle.bindValue(":kalemAdi", alan(k, "kalemAdi"));
                guncelle.bindValue(":neIcin", metinParametresi(alan(k, "neIcin")));
                guncelle.bindValue(":miktar", k.value("miktar").toDouble());
                guncelle.bindValue(":birim", metinParametresi(alan(k, "birim")));
                guncelle.bindValue(":aciklama", metinParametresi(alan(k, "aciklama")));
                guncelle.bindValue(":arastir", k.value("arastirilacak", false).toBool());
                guncelle.bindValue(":id", id);
                guncelle.bindValue(":talepId", talepId);
                if (!guncelle.exec())
                    return hataylaDon("Talep kalemi kaydedilemedi: " + guncelle.lastError().text());
                continue;
            }

            ekle.bindValue(":talepId", talepId);
            ekle.bindValue(":sira", i);
            ekle.bindValue(":kalemAdi", alan(k, "kalemAdi"));
            ekle.bindValue(":neIcin", metinParametresi(alan(k, "neIcin")));
            ekle.bindValue(":miktar", k.value("miktar").toDouble());
            ekle.bindValue(":birim", metinParametresi(alan(k, "birim")));
            ekle.bindValue(":aciklama", metinParametresi(alan(k, "aciklama")));
            ekle.bindValue(":arastir", k.value("arastirilacak", false).toBool());
            if (!ekle.exec() || !ekle.next())
                return hataylaDon("Talep kalemi kaydedilemedi: " + ekle.lastError().text());
            const int yeniId = ekle.value(0).toInt();
            ekle.finish();
            kalemIdleri.insert(anahtar, yeniId);
        }
    }

    // Listeden cikarilan kalemler: siparise donusmusse silinemez.
    for (const int id : std::as_const(mevcutKalemler))
    {
        if (gelenKalemler.contains(id))
            continue;
        if (siparisliKalemler.contains(id))
        {
            return hataylaDon(QString("SA-%1 siparişine dönüşmüş bir kalem silinemez. "
                                      "Gerekirse önce siparişi iptal edin.")
                                  .arg(siparisliKalemler.value(id), 4, 10, QChar('0')));
        }
        QSqlQuery sil(m_db);
        sil.prepare("DELETE FROM dbo.satinalma_teklif_fiyatlari WHERE TalepKalemId = :id");
        sil.bindValue(":id", id);
        QSqlQuery bagKopar(m_db);
        // Iptal edilmis siparislerin kalemleri bu talep kalemine bagli
        // kalabilir; bag koparilir ki kalem silinebilsin.
        bagKopar.prepare("UPDATE dbo.satinalma_kalemleri SET TalepKalemId = NULL WHERE TalepKalemId = :id");
        bagKopar.bindValue(":id", id);
        QSqlQuery kalemSil(m_db);
        kalemSil.prepare("DELETE FROM dbo.satinalma_talep_kalemleri WHERE TalepKalemId = :id");
        kalemSil.bindValue(":id", id);
        if (!sil.exec() || !bagKopar.exec() || !kalemSil.exec())
        {
            const QString hata = sil.lastError().isValid() ? sil.lastError().text()
                               : bagKopar.lastError().isValid() ? bagKopar.lastError().text()
                               : kalemSil.lastError().text();
            return hataylaDon("Talep kalemi silinemedi: " + hata);
        }
    }

    // ---- Firmalar (upsert) ----
    QHash<QString, int> firmaIdleri;
    QSet<int> gelenFirmalar;
    {
        QSqlQuery ekle(m_db);
        ekle.prepare("INSERT INTO dbo.satinalma_teklif_firmalari "
                     "(TalepId, SiraNo, TedarikciId, FirmaAdi, Kaynak, TeklifLinki, ParaBirimi, Kur, "
                     " TeslimSuresiGun, Notu) "
                     "OUTPUT INSERTED.TeklifFirmaId "
                     "VALUES (:talepId, :sira, :tedarikciId, :firmaAdi, :kaynak, :link, :pb, :kur, "
                     "        :teslim, :notu)");
        QSqlQuery guncelle(m_db);
        guncelle.prepare("UPDATE dbo.satinalma_teklif_firmalari SET SiraNo = :sira, "
                         "TedarikciId = :tedarikciId, FirmaAdi = :firmaAdi, Kaynak = :kaynak, "
                         "TeklifLinki = :link, ParaBirimi = :pb, Kur = :kur, TeslimSuresiGun = :teslim, "
                         "Notu = :notu WHERE TeklifFirmaId = :id AND TalepId = :talepId");

        for (int i = 0; i < firmalarGirdi.size(); ++i)
        {
            const QVariantMap f = firmalarGirdi.at(i).toMap();
            const int id = f.value("teklifFirmaId", 0).toInt();
            const QString anahtar = alan(f, "anahtar");
            const QString pb = paraBirimiDuzelt(alan(f, "paraBirimi"));
            const double kur = pb == QStringLiteral("TL") ? 1.0 : qMax(0.0, f.value("kur", 0).toDouble());
            const bool internet = alan(f, "kaynak") == QStringLiteral("İnternet");

            auto bagla = [&](QSqlQuery &q) {
                q.bindValue(":sira", i);
                q.bindValue(":tedarikciId", internet ? QVariant(QMetaType(QMetaType::Int))
                                                     : intParametresi(f.value("tedarikciId", 0).toInt()));
                q.bindValue(":firmaAdi", alan(f, "firmaAdi"));
                q.bindValue(":kaynak", internet ? QStringLiteral("İnternet") : QStringLiteral("Tedarikçi"));
                q.bindValue(":link", metinParametresi(alan(f, "teklifLinki")));
                q.bindValue(":pb", pb);
                q.bindValue(":kur", kur);
                q.bindValue(":teslim", intParametresi(f.value("teslimSuresiGun", 0).toInt()));
                q.bindValue(":notu", metinParametresi(alan(f, "notu")));
                q.bindValue(":talepId", talepId);
            };

            if (id > 0 && mevcutFirmalar.contains(id))
            {
                gelenFirmalar.insert(id);
                firmaIdleri.insert(anahtar, id);
                // Siparisi verilmis firmanin teklifi (para birimi, kur)
                // degismez: siparis o rakamlara dayaniyor.
                if (kilitliFirmalar.contains(id))
                    continue;
                bagla(guncelle);
                guncelle.bindValue(":id", id);
                if (!guncelle.exec())
                    return hataylaDon("Teklif firması kaydedilemedi: " + guncelle.lastError().text());
                continue;
            }

            bagla(ekle);
            if (!ekle.exec() || !ekle.next())
                return hataylaDon("Teklif firması kaydedilemedi: " + ekle.lastError().text());
            const int yeniId = ekle.value(0).toInt();
            ekle.finish();
            firmaIdleri.insert(anahtar, yeniId);
        }
    }

    for (const int id : std::as_const(mevcutFirmalar))
    {
        if (gelenFirmalar.contains(id))
            continue;
        if (kilitliFirmalar.contains(id))
            return hataylaDon("Siparişi verilmiş bir firmanın teklifi silinemez. "
                              "Gerekirse önce siparişi iptal edin.");
        QSqlQuery sil(m_db);
        // Fiyatlar CASCADE ile silinir; iptal edilmis siparislerdeki bag
        // (TeklifFirmaId) FK degildir, kopuk kalmasi zararsizdir.
        sil.prepare("DELETE FROM dbo.satinalma_teklif_firmalari WHERE TeklifFirmaId = :id");
        sil.bindValue(":id", id);
        if (!sil.exec())
            return hataylaDon("Teklif firması silinemedi: " + sil.lastError().text());
    }

    // ---- Fiyatlar: siparise donusmemis kalemlerin fiyatlari yeniden yazilir ----
    {
        QStringList korunacak;
        for (auto it = siparisliKalemler.constBegin(); it != siparisliKalemler.constEnd(); ++it)
            korunacak << QString::number(it.key());

        QSqlQuery sil(m_db);
        sil.prepare(QStringLiteral(
            "DELETE fy FROM dbo.satinalma_teklif_fiyatlari fy "
            "JOIN dbo.satinalma_talep_kalemleri tk ON tk.TalepKalemId = fy.TalepKalemId "
            "WHERE tk.TalepId = :id%1")
            .arg(korunacak.isEmpty() ? QString()
                                     : QStringLiteral(" AND fy.TalepKalemId NOT IN (%1)")
                                           .arg(korunacak.join(','))));
        sil.bindValue(":id", talepId);
        if (!sil.exec())
            return hataylaDon("Teklif fiyatları güncellenemedi: " + sil.lastError().text());

        QSqlQuery ekle(m_db);
        ekle.prepare("INSERT INTO dbo.satinalma_teklif_fiyatlari "
                     "(TeklifFirmaId, TalepKalemId, BirimFiyat, SecildiMi, UrunLinki, Notu) "
                     "VALUES (:firmaId, :kalemId, :fiyat, :secildi, :link, :notu)");
        for (const QVariant &ham : fiyatlarGirdi)
        {
            const QVariantMap fy = ham.toMap();
            const int kalemId = kalemIdleri.value(alan(fy, "kalemAnahtar"), 0);
            const int firmaId = firmaIdleri.value(alan(fy, "firmaAnahtar"), 0);
            if (kalemId <= 0 || firmaId <= 0 || siparisliKalemler.contains(kalemId))
                continue;
            ekle.bindValue(":firmaId", firmaId);
            ekle.bindValue(":kalemId", kalemId);
            ekle.bindValue(":fiyat", fy.value("birimFiyat").toDouble());
            ekle.bindValue(":secildi", fy.value("secildi", false).toBool());
            ekle.bindValue(":link", metinParametresi(alan(fy, "link")));
            ekle.bindValue(":notu", metinParametresi(alan(fy, "notu")));
            if (!ekle.exec())
                return hataylaDon("Teklif fiyatı kaydedilemedi: " + ekle.lastError().text());
        }
    }

    if (!m_db.commit())
        return hataylaDon("Talep kaydedilemedi: " + m_db.lastError().text());

    sonuc["basarili"] = true;
    sonuc["talepId"]  = talepId;
    sonuc["talepNo"]  = talepNo;
    return sonuc;
}

QVariantMap Database::talepIptalEt(int talepId, const QString &sebep)
{
    ERP_IZ("talepIptalEt");
    QVariantMap sonuc = basarisizSonuc();
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!satinalmaSemasiHazirMi())
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE t SET IptalMi = 1, IptalSebebi = :sebep, GuncellemeTarihi = SYSDATETIME() "
        "FROM dbo.satinalma_talepleri t "
        "WHERE t.TalepId = :id AND t.IptalMi = 0 "
        "  AND NOT EXISTS (SELECT 1 FROM dbo.satinalmalar s WHERE s.TalepId = t.TalepId AND %1)")
        .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
    query.bindValue(":sebep", metinParametresi(sebep));
    query.bindValue(":id", talepId);
    if (!query.exec())
    {
        qWarning() << "talepIptalEt basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Talep iptal edilemedi: " + query.lastError().text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Bu talepten verilmiş aktif sipariş var ya da talep zaten iptal. "
                        "Önce siparişleri iptal edin.";
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::talepSiparisOlustur(int talepId, const QVariantList &siparisBilgileri)
{
    ERP_IZ("talepSiparisOlustur");
    QVariantMap sonuc = basarisizSonuc();
    sonuc["siparisler"] = QVariantList();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!satinalmaSemasiHazirMi())
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    // Firma basina ekrandan gelen siparis bilgileri.
    QHash<int, QVariantMap> bilgiler;
    for (const QVariant &ham : siparisBilgileri)
    {
        const QVariantMap b = ham.toMap();
        bilgiler.insert(b.value("teklifFirmaId").toInt(), b);
    }

    // Okuma da yazma da tek transaction'da ve siparis numarasi kilidi
    // altinda: iki bilgisayar ayni talepten ayni anda siparis olusturursa
    // ikincisi birincinin bitmesini bekler ve donusmus kalemleri artik
    // gormez -- ayni kalem iki siparise girmez.
    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }
    auto hataylaDon = [&](const QString &mesaj) {
        m_db.rollback();
        sonuc["hata"] = mesaj;
        sonuc["siparisler"] = QVariantList();
        return sonuc;
    };
    {
        QString kilitHatasi;
        if (!satinalmaKilidiAl(QStringLiteral("SiparisNo"), kilitHatasi))
            return hataylaDon(kilitHatasi);
    }

    // Talep basligi (isteyen bilgisi siparislere de yazilir).
    QSqlQuery talepQuery(m_db);
    talepQuery.prepare("SELECT IsteyenBirim, IsteyenKisi, IhtiyacTarihi, IptalMi "
                       "FROM dbo.satinalma_talepleri WHERE TalepId = :id");
    talepQuery.bindValue(":id", talepId);
    if (!talepQuery.exec() || !talepQuery.next())
        return hataylaDon("Talep bulunamadı. Önce talebi kaydedin.");
    if (talepQuery.value(3).toBool())
        return hataylaDon("İptal edilmiş talepten sipariş oluşturulamaz.");
    const QVariant isteyenBirim  = talepQuery.value(0);
    const QVariant isteyenKisi   = talepQuery.value(1);
    const QVariant ihtiyacTarihi = talepQuery.value(2);

    // Secilmis ve henuz siparise donusmemis hucreler + o kalemlere teklif
    // veren firma sayisi (karsilastirma var mi?).
    struct Satir
    {
        int talepKalemId;
        QString kalemAdi, neIcin, birim, link;
        double miktar, birimFiyat;
        int teklifSayisi;
    };
    struct Grup
    {
        int teklifFirmaId, tedarikciId, teslimSuresiGun;
        QString firmaAdi, kaynak, link, paraBirimi;
        double kur;
        QVector<Satir> satirlar;
    };
    QVector<Grup> gruplar;
    {
        QSqlQuery q(m_db);
        q.prepare(QStringLiteral(
            "SELECT f.TeklifFirmaId, f.TedarikciId, f.FirmaAdi, f.Kaynak, f.TeklifLinki, f.ParaBirimi, "
            "       f.Kur, f.TeslimSuresiGun, tk.TalepKalemId, tk.KalemAdi, tk.NeIcin, tk.Birim, "
            "       tk.Miktar, fy.BirimFiyat, "
            "       (SELECT COUNT(*) FROM dbo.satinalma_teklif_fiyatlari d "
            "        WHERE d.TalepKalemId = tk.TalepKalemId) AS TeklifSayisi, "
            "       fy.UrunLinki "
            "FROM dbo.satinalma_teklif_fiyatlari fy "
            "JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = fy.TeklifFirmaId "
            "JOIN dbo.satinalma_talep_kalemleri tk ON tk.TalepKalemId = fy.TalepKalemId "
            // Fiyat 0: tedarikciye soruldu, cevap henuz gelmedi. Bu kalemler
            // talepte acik kalir, fiyat gelince ayrica siparis edilir.
            "WHERE tk.TalepId = :id AND fy.SecildiMi = 1 AND fy.BirimFiyat > 0 "
            "  AND tk.TalepKalemId NOT IN (%1) "
            "ORDER BY f.SiraNo, f.TeklifFirmaId, tk.SiraNo, tk.TalepKalemId")
            .arg(QString::fromUtf8(SIPARISLI_TALEP_KALEMLERI_SQL)));
        q.bindValue(":id", talepId);
        if (!q.exec())
        {
            qWarning() << "talepSiparisOlustur okuma basarisiz:" << q.lastError().text();
            return hataylaDon("Teklifler okunamadı: " + q.lastError().text());
        }
        while (q.next())
        {
            const int firmaId = q.value(0).toInt();
            if (gruplar.isEmpty() || gruplar.last().teklifFirmaId != firmaId)
            {
                Grup g;
                g.teklifFirmaId   = firmaId;
                g.tedarikciId     = q.value(1).toInt();
                g.firmaAdi        = q.value(2).toString();
                g.kaynak          = q.value(3).toString();
                g.link            = q.value(4).toString();
                g.paraBirimi      = q.value(5).toString();
                g.kur             = q.value(6).toDouble();
                g.teslimSuresiGun = q.value(7).toInt();
                gruplar.append(g);
            }
            Satir s;
            s.talepKalemId = q.value(8).toInt();
            s.kalemAdi     = q.value(9).toString();
            s.neIcin       = q.value(10).toString();
            s.birim        = q.value(11).toString();
            s.miktar       = q.value(12).toDouble();
            s.birimFiyat   = q.value(13).toDouble();
            s.teklifSayisi = q.value(14).toInt();
            // Urun sayfasi fiyata aittir; eski kayitlarda yalnizca firmada durur.
            s.link         = q.value(15).toString().trimmed();
            if (s.link.isEmpty())
                s.link = gruplar.last().link.trimmed();
            gruplar.last().satirlar.append(s);
        }
    }
    if (gruplar.isEmpty())
        return hataylaDon("Siparişe dönüştürülecek kalem yok. Kalemlerde nereden alınacağını ve "
                          "fiyatını yazın.");

    const double esik = satinalmaOnayEsigiGetir();

    // Denetim: yazmadan once, firma firma.
    for (const Grup &g : std::as_const(gruplar))
    {
        if (g.paraBirimi != QStringLiteral("TL") && g.kur <= 0.0)
            return hataylaDon(QString("\"%1\" teklifi %2 cinsinden; kur girilmemiş.")
                                  .arg(g.firmaAdi, g.paraBirimi));
        for (const Satir &s : g.satirlar)
        {
            // Linkin kayitsiz kalmasi eski duzenin en can sikici tarafiydi:
            // ayni parca tekrar lazim oldugunda sifirdan aranmak zorunda kaliniyordu.
            if (g.kaynak == QStringLiteral("İnternet") && s.link.isEmpty())
                return hataylaDon(QString("\"%1\" %2 sitesinden alınıyor; ürün sayfasının linkini girin.")
                                      .arg(s.kalemAdi, g.firmaAdi));
        }
        const QVariantMap b = bilgiler.value(g.teklifFirmaId);
        if (!gecerliTeslimatSekliMi(alan(b, "teslimatSekli")))
            return hataylaDon(QString("\"%1\" siparişi için teslimat şeklini seçin.").arg(g.firmaAdi));
    }

    QSqlQuery baslik(m_db);
    baslik.prepare(
        "INSERT INTO dbo.satinalmalar "
        "(TedarikciId, KullaniciId, SatinalmaTarihi, Durum, SiparisKaynagi, SiparisLinki, "
        " IsteyenBirim, IsteyenKisi, IhtiyacTarihi, BeklenenTeslimTarihi, TeslimatSekli, "
        " PatronOnayiGerekliMi, PatronOnayliMi, PatronOnayTarihi, OnayiIsaretleyenKullaniciId, "
        " SiparisNo, TalepId, TeklifFirmaId) "
        "OUTPUT INSERTED.SatinalmaId "
        "VALUES (:tedarikciId, :kullaniciId, :tarih, :durum, :kaynak, :link, "
        "        :isteyenBirim, :isteyenKisi, :ihtiyacTarihi, :beklenen, :teslimatSekli, "
        "        :onayGerekli, :onayli, :onayTarihi, :onaylayan, "
        "        :siparisNo, :talepId, :teklifFirmaId)");
    QSqlQuery kalemEkle(m_db);
    kalemEkle.prepare(
        "INSERT INTO dbo.satinalma_kalemleri "
        "(SatinalmaId, KalemAdi, Birim, Adet, BirimFiyatDoviz, ParaBirimi, Kur, BirimFiyatTL, "
        " ToplamTutarTL, UrunLinki, TalepKalemId, NeIcin) "
        "VALUES (:satinalmaId, :kalemAdi, :birim, :adet, :birimFiyat, :pb, :kur, :birimFiyatTL, "
        "        :toplamTL, :link, :talepKalemId, :neIcin)");

    QVariantList olusan;
    for (const Grup &g : std::as_const(gruplar))
    {
        const QVariantMap b = bilgiler.value(g.teklifFirmaId);
        const double kur = g.paraBirimi == QStringLiteral("TL") ? 1.0 : g.kur;

        double toplam = 0.0;
        for (const Satir &s : g.satirlar)
            toplam += kurusaYuvarla(kurusaYuvarla(s.birimFiyat * kur) * s.miktar);
        toplam = kurusaYuvarla(toplam);

        // Esik, bu talepten ayni yere verilmis aktif siparislerle BIRLIKTE
        // denetlenir: ayni alim parca parca siparis edilerek onaydan
        // kacirilmasin. Bu cagride az once yazilan siparisler de sayilir.
        double oncekiToplam = 0.0;
        if (esik > 0.0)
        {
            QSqlQuery onceki(m_db);
            onceki.prepare(QStringLiteral(
                "SELECT ISNULL(SUM(k.ToplamTutarTL), 0) FROM dbo.satinalmalar s "
                "JOIN dbo.satinalma_kalemleri k ON k.SatinalmaId = s.SatinalmaId "
                "LEFT JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = s.TeklifFirmaId "
                "WHERE s.TalepId = :talepId AND %1 AND %2")
                .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU),
                     g.tedarikciId > 0 ? QStringLiteral("s.TedarikciId = :tedarikciId")
                                       : QStringLiteral("s.TedarikciId IS NULL AND f.FirmaAdi = :firmaAdi")));
            onceki.bindValue(":talepId", talepId);
            if (g.tedarikciId > 0)
                onceki.bindValue(":tedarikciId", g.tedarikciId);
            else
                onceki.bindValue(":firmaAdi", g.firmaAdi);
            if (!onceki.exec() || !onceki.next())
                return hataylaDon("Önceki siparişler okunamadı: " + onceki.lastError().text());
            oncekiToplam = onceki.value(0).toDouble();
        }

        const bool onayGerekli = esik > 0.0 && oncekiToplam + toplam > esik;
        const bool onayli = onayGerekli && b.value("patronOnayli", false).toBool();
        const QString durum = (onayGerekli && !onayli) ? QStringLiteral("Patron Onayı Bekliyor")
                                                       : QStringLiteral("Sipariş Verildi");

        QString noHatasi;
        const int siparisNo = satinalmaNoAl(QStringLiteral("dbo.satinalmalar"),
                                            QStringLiteral("SiparisNo"), noHatasi);
        if (siparisNo <= 0)
            return hataylaDon(noHatasi);

        const bool internet = g.kaynak == QStringLiteral("İnternet");
        // Beklenen teslim girilmemisse teklifteki teslim suresinden hesaplanir.
        QVariant beklenen = tarihParametresi(alan(b, "beklenenTeslimTarihi"));
        if (beklenen.isNull() && g.teslimSuresiGun > 0)
            beklenen = QDateTime(QDate::currentDate().addDays(g.teslimSuresiGun), QTime(0, 0));

        baslik.bindValue(":tedarikciId", internet ? QVariant(QMetaType(QMetaType::Int))
                                                  : intParametresi(g.tedarikciId));
        baslik.bindValue(":kullaniciId", intParametresi(m_aktifKullaniciId));
        baslik.bindValue(":tarih", QDate::currentDate());
        baslik.bindValue(":durum", durum);
        baslik.bindValue(":kaynak", internet ? QStringLiteral("İnternet") : QStringLiteral("Tedarikçi"));
        baslik.bindValue(":link", metinParametresi(internet && g.link.trimmed().isEmpty()
                                                   ? g.satirlar.first().link : g.link));
        baslik.bindValue(":isteyenBirim", isteyenBirim);
        baslik.bindValue(":isteyenKisi", isteyenKisi);
        baslik.bindValue(":ihtiyacTarihi", ihtiyacTarihi);
        baslik.bindValue(":beklenen", beklenen);
        baslik.bindValue(":teslimatSekli", alan(b, "teslimatSekli"));
        baslik.bindValue(":onayGerekli", onayGerekli);
        baslik.bindValue(":onayli", onayli);
        // Onayi PATRON degil mudur isaretler (patronun programda hesabi yok).
        baslik.bindValue(":onayTarihi", onayli ? QVariant(QDateTime::currentDateTime())
                                               : QVariant(QMetaType(QMetaType::QDateTime)));
        baslik.bindValue(":onaylayan", onayli ? intParametresi(m_aktifKullaniciId)
                                              : QVariant(QMetaType(QMetaType::Int)));
        baslik.bindValue(":siparisNo", siparisNo);
        baslik.bindValue(":talepId", talepId);
        baslik.bindValue(":teklifFirmaId", g.teklifFirmaId);
        if (!baslik.exec() || !baslik.next())
        {
            qWarning() << "siparis olusturulamadi:" << baslik.lastError().text();
            return hataylaDon("Sipariş oluşturulamadı: " + baslik.lastError().text());
        }
        const int satinalmaId = baslik.value(0).toInt();
        baslik.finish();

        for (const Satir &s : g.satirlar)
        {
            const double birimFiyatTL = kurusaYuvarla(s.birimFiyat * kur);
            kalemEkle.bindValue(":satinalmaId", satinalmaId);
            kalemEkle.bindValue(":kalemAdi", s.kalemAdi);
            kalemEkle.bindValue(":birim", metinParametresi(s.birim));
            kalemEkle.bindValue(":adet", s.miktar);
            kalemEkle.bindValue(":birimFiyat", s.birimFiyat);
            kalemEkle.bindValue(":pb", g.paraBirimi);
            kalemEkle.bindValue(":kur", kur);
            kalemEkle.bindValue(":birimFiyatTL", birimFiyatTL);
            kalemEkle.bindValue(":toplamTL", kurusaYuvarla(birimFiyatTL * s.miktar));
            kalemEkle.bindValue(":link", metinParametresi(s.link));
            kalemEkle.bindValue(":talepKalemId", s.talepKalemId);
            kalemEkle.bindValue(":neIcin", metinParametresi(s.neIcin));
            if (!kalemEkle.exec())
                return hataylaDon("Sipariş kalemi yazılamadı: " + kalemEkle.lastError().text());
        }

        QVariantMap siparis;
        siparis["satinalmaId"]   = satinalmaId;
        siparis["siparisNo"]     = siparisNo;
        siparis["firmaAdi"]      = g.firmaAdi;
        siparis["durum"]         = durum;
        siparis["toplamTutarTL"] = toplam;
        olusan.append(siparis);
    }

    if (!m_db.commit())
        return hataylaDon("Siparişler oluşturulamadı: " + m_db.lastError().text());

    sonuc["basarili"]   = true;
    sonuc["siparisler"] = olusan;
    return sonuc;
}

// ---------------------------------------------------------------------------
// SIPARIS
// ---------------------------------------------------------------------------

QVariantList Database::siparisListesiGetir(const QString &filtre, const QString &arama)
{
    ERP_IZ("siparisListesiGetir");
    QVariantList liste;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return liste;

    QString kosul;
    if (filtre == QStringLiteral("acik"))
        kosul = QStringLiteral("Durum NOT IN (N'Teslim Alındı', N'İptal', N'Reddedildi')");
    else if (filtre == QStringLiteral("onay"))
        kosul = QStringLiteral("Durum = N'Patron Onayı Bekliyor'");
    else if (filtre == QStringLiteral("geciken"))
        kosul = QStringLiteral("Durum NOT IN (N'Teslim Alındı', N'İptal', N'Reddedildi') "
                               "AND BeklenenTeslimTarihi IS NOT NULL AND GecikmeGunu > 0");
    else if (filtre == QStringLiteral("kismi"))
        kosul = QStringLiteral("Durum = N'Kısmi Teslim'");
    else if (filtre == QStringLiteral("fatura"))
        kosul = QStringLiteral("Durum IN (N'Teslim Alındı', N'Kısmi Teslim') AND FaturaNo IS NULL");
    else if (filtre == QStringLiteral("tamam"))
        kosul = QStringLiteral("Durum = N'Teslim Alındı'");
    else if (filtre == QStringLiteral("iptal"))
        kosul = QStringLiteral("Durum IN (N'İptal', N'Reddedildi')");
    else
        kosul = QStringLiteral("1 = 1");

    const QString desen = likeDeseni(arama);
    QString onek;
    const int aramaNo = belgeNoAyikla(arama, onek);
    if (!desen.isEmpty())
    {
        kosul += QStringLiteral(
            " AND (SiparisNo = :aramaNo OR TalepNo = :aramaNo2 OR FirmaAdi LIKE :desen1 ESCAPE '\\' "
            // "Kargom nerede?": takip ya da site siparis numarasiyla da bulunur.
            "      OR KargoTakipNo LIKE :desen4 ESCAPE '\\' OR SiteSiparisNo LIKE :desen5 ESCAPE '\\' "
            "      OR EXISTS (SELECT 1 FROM dbo.satinalma_kalemleri a WHERE a.SatinalmaId = x.SatinalmaId "
            "                 AND (a.KalemAdi LIKE :desen2 ESCAPE '\\' OR a.NeIcin LIKE :desen3 ESCAPE '\\')))");
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "WITH x AS ( "
        "  SELECT s.SatinalmaId, s.SiparisNo, tl.TalepNo, "
        "         COALESCE(t.FirmaAdi, f.FirmaAdi, "
        "                  CASE WHEN s.SiparisKaynagi = N'İnternet' THEN N'İnternet' ELSE N'' END) AS FirmaAdi, "
        "         s.Durum, s.TeslimatSekli, s.SatinalmaTarihi, s.BeklenenTeslimTarihi, "
        "         %1 AS GecikmeGunu, ISNULL(k.KalemSayisi, 0) AS KalemSayisi, ISNULL(k.Tutar, 0) AS Tutar, "
        "         s.KargoFirmasi, s.KargoTakipNo, s.FaturaNo, s.IsteyenBirim, s.IsteyenKisi, "
        "         s.SiteSiparisNo, %3 AS EksikKapatildi, "
        "         ISNULL(STUFF((SELECT TOP 4 N', ' + a.KalemAdi FROM dbo.satinalma_kalemleri a "
        "                       WHERE a.SatinalmaId = s.SatinalmaId ORDER BY a.SatinalmaKalemId "
        "                       FOR XML PATH(N''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N''), N'') "
        "           AS KalemOzeti, "
        "         ISNULL(STUFF((SELECT DISTINCT N', ' + a.NeIcin FROM dbo.satinalma_kalemleri a "
        "                       WHERE a.SatinalmaId = s.SatinalmaId AND NULLIF(a.NeIcin, N'') IS NOT NULL "
        "                       FOR XML PATH(N''), TYPE).value(N'.', N'nvarchar(max)'), 1, 2, N''), N'') "
        "           AS NeIcinOzeti "
        "  FROM dbo.satinalmalar s "
        "  LEFT JOIN dbo.tedarikciler t ON t.TedarikciId = s.TedarikciId "
        "  LEFT JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = s.TeklifFirmaId "
        "  LEFT JOIN dbo.satinalma_talepleri tl ON tl.TalepId = s.TalepId "
        "  OUTER APPLY (SELECT COUNT(*) AS KalemSayisi, SUM(ToplamTutarTL) AS Tutar "
        "               FROM dbo.satinalma_kalemleri WHERE SatinalmaId = s.SatinalmaId) k "
        ") "
        "SELECT TOP 500 SatinalmaId, SiparisNo, TalepNo, FirmaAdi, Durum, TeslimatSekli, SatinalmaTarihi, "
        "       BeklenenTeslimTarihi, GecikmeGunu, KalemSayisi, Tutar, KargoFirmasi, KargoTakipNo, "
        "       FaturaNo, IsteyenBirim, IsteyenKisi, KalemOzeti, NeIcinOzeti, SiteSiparisNo, EksikKapatildi "
        "FROM x WHERE %2 "
        // Acik ve geciken siparisler uste; sonra en yeni.
        "ORDER BY CASE WHEN Durum NOT IN (N'Teslim Alındı', N'İptal', N'Reddedildi') "
        "               AND BeklenenTeslimTarihi IS NOT NULL AND GecikmeGunu > 0 THEN 0 ELSE 1 END, "
        "         SiparisNo DESC")
        .arg(QString::fromUtf8(GECIKME_GUNU_SQL), kosul,
             // Eksik kapatma izi (db/32); kurulu degilse hep 0.
             semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("EksikKapatmaTarihi"))
                 ? QStringLiteral("CASE WHEN s.EksikKapatmaTarihi IS NULL THEN 0 ELSE 1 END")
                 : QStringLiteral("0")));
    if (!desen.isEmpty())
    {
        // On ekli numara yalnizca kendi turunde aranir; yalin sayi ikisinde de.
        query.bindValue(":aramaNo", aramaNo > 0 && onek != QStringLiteral("TLP") ? aramaNo : -1);
        query.bindValue(":aramaNo2", aramaNo > 0 && onek != QStringLiteral("SA") ? aramaNo : -1);
        query.bindValue(":desen1", desen);
        query.bindValue(":desen2", desen);
        query.bindValue(":desen3", desen);
        query.bindValue(":desen4", desen);
        query.bindValue(":desen5", desen);
    }

    if (!query.exec())
    {
        qWarning() << "siparisListesiGetir basarisiz:" << query.lastError().text();
        return liste;
    }

    while (query.next())
    {
        QVariantMap satir;
        satir["satinalmaId"]          = query.value(0).toInt();
        satir["siparisNo"]            = query.value(1).toInt();
        satir["talepNo"]              = query.value(2).toInt();
        satir["tedarikciAdi"]         = query.value(3).toString();
        satir["durum"]                = query.value(4).toString();
        satir["teslimatSekli"]        = query.value(5).toString();
        satir["satinalmaTarihi"]      = query.value(6).toDate();
        satir["beklenenTeslimTarihi"] = query.value(7).toDate();
        satir["gecikmeGunu"]          = query.value(8).toInt();
        satir["kalemSayisi"]          = query.value(9).toInt();
        satir["toplamTutarTL"]        = query.value(10).toDouble();
        satir["kargoFirmasi"]         = query.value(11).toString();
        satir["kargoTakipNo"]         = query.value(12).toString();
        satir["faturaNo"]             = query.value(13).toString();
        satir["isteyenBirim"]         = query.value(14).toString();
        satir["isteyenKisi"]          = query.value(15).toString();
        satir["kalemOzeti"]           = query.value(16).toString();
        satir["neIcinOzeti"]          = query.value(17).toString();
        satir["siteSiparisNo"]        = query.value(18).toString();
        satir["eksikKapatildi"]       = query.value(19).toInt() == 1;
        liste.append(satir);
    }
    return liste;
}

QVariantMap Database::satinalmaGetir(int satinalmaId)
{
    ERP_IZ("satinalmaGetir");
    QVariantMap sonuc;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return sonuc;

    QSqlQuery query(m_db);
    query.prepare(
        "SELECT s.SatinalmaId, s.SiparisNo, s.TalepId, tl.TalepNo, "
        "       COALESCE(t.FirmaAdi, f.FirmaAdi, CASE WHEN s.SiparisKaynagi = N'İnternet' "
        "                THEN N'İnternet' ELSE N'' END), "
        "       s.SatinalmaTarihi, s.Aciklama, s.Durum, s.SiparisKaynagi, s.SiparisLinki, "
        "       s.IsteyenBirim, s.IsteyenKisi, s.IhtiyacTarihi, s.BeklenenTeslimTarihi, "
        "       s.TeslimAlmaTarihi, s.TeslimatSekli, s.KargoFirmasi, s.KargoTakipNo, "
        "       s.PatronOnayiGerekliMi, s.PatronOnayliMi, s.PatronOnayTarihi, ok.AdSoyad, "
        "       s.FaturaNo, s.FaturaTarihi, s.FaturaTutariTL, s.MuhasebeyeIletildiMi, s.RedSebebi, "
        "       s.TekTeklifGerekcesi, kk.AdSoyad, t.Telefon, t.IlgiliKisi, f.TeslimSuresiGun, "
        "       s.SiteSiparisNo "
        "FROM dbo.satinalmalar s "
        "LEFT JOIN dbo.tedarikciler t ON t.TedarikciId = s.TedarikciId "
        "LEFT JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = s.TeklifFirmaId "
        "LEFT JOIN dbo.satinalma_talepleri tl ON tl.TalepId = s.TalepId "
        "LEFT JOIN dbo.kullanicilar ok ON ok.KullaniciId = s.OnayiIsaretleyenKullaniciId "
        "LEFT JOIN dbo.kullanicilar kk ON kk.KullaniciId = s.KullaniciId "
        "WHERE s.SatinalmaId = :id");
    query.bindValue(":id", satinalmaId);
    if (!query.exec() || !query.next())
    {
        if (query.lastError().isValid())
            qWarning() << "satinalmaGetir basarisiz:" << query.lastError().text();
        return sonuc;
    }

    auto tarihMetni = [&](int i) {
        return query.value(i).isNull() ? QString()
                                       : query.value(i).toDate().toString("yyyy-MM-dd");
    };

    sonuc["satinalmaId"]          = query.value(0).toInt();
    sonuc["siparisNo"]            = query.value(1).toInt();
    sonuc["talepId"]              = query.value(2).toInt();
    sonuc["talepNo"]              = query.value(3).toInt();
    sonuc["tedarikciAdi"]         = query.value(4).toString();
    sonuc["satinalmaTarihi"]      = tarihMetni(5);
    sonuc["aciklama"]             = query.value(6).toString();
    sonuc["durum"]                = query.value(7).toString();
    sonuc["siparisKaynagi"]       = query.value(8).toString();
    sonuc["siparisLinki"]         = query.value(9).toString();
    sonuc["isteyenBirim"]         = query.value(10).toString();
    sonuc["isteyenKisi"]          = query.value(11).toString();
    sonuc["ihtiyacTarihi"]        = tarihMetni(12);
    sonuc["beklenenTeslimTarihi"] = tarihMetni(13);
    sonuc["teslimAlmaTarihi"]     = tarihMetni(14);
    sonuc["teslimatSekli"]        = query.value(15).toString();
    sonuc["kargoFirmasi"]         = query.value(16).toString();
    sonuc["kargoTakipNo"]         = query.value(17).toString();
    sonuc["patronOnayiGerekli"]   = query.value(18).toBool();
    sonuc["patronOnayli"]         = query.value(19).toBool();
    sonuc["patronOnayTarihi"]     = query.value(20).isNull()
                                        ? QString()
                                        : query.value(20).toDateTime().toString("dd.MM.yyyy HH:mm");
    sonuc["onayiIsaretleyen"]     = query.value(21).toString();
    sonuc["faturaNo"]             = query.value(22).toString();
    sonuc["faturaTarihi"]         = tarihMetni(23);
    sonuc["faturaTutariTL"]       = query.value(24).isNull() ? QVariant() : query.value(24).toDouble();
    sonuc["muhasebeyeIletildi"]   = query.value(25).toBool();
    sonuc["redSebebi"]            = query.value(26).toString();
    sonuc["tekTeklifGerekcesi"]   = query.value(27).toString();
    sonuc["olusturan"]            = query.value(28).toString();
    sonuc["tedarikciTelefon"]     = query.value(29).toString();
    sonuc["tedarikciIlgiliKisi"]  = query.value(30).toString();
    sonuc["teslimSuresiGun"]      = query.value(31).toInt();
    sonuc["siteSiparisNo"]        = query.value(32).toString();
    const int talepId = query.value(2).toInt();

    // Eksik kapatma izi (db/32). Kurulu degilse alanlar bos doner.
    sonuc["eksikKapatildi"]     = false;
    sonuc["eksikKapatmaSebebi"] = QString();
    sonuc["eksikKapatmaTarihi"] = QString();
    sonuc["eksikKapatan"]       = QString();
    if (semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("EksikKapatmaTarihi")))
    {
        QSqlQuery eksik(m_db);
        eksik.prepare("SELECT s.EksikKapatmaSebebi, s.EksikKapatmaTarihi, k.AdSoyad "
                      "FROM dbo.satinalmalar s "
                      "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = s.EksikKapatanKullaniciId "
                      "WHERE s.SatinalmaId = :id AND s.EksikKapatmaTarihi IS NOT NULL");
        eksik.bindValue(":id", satinalmaId);
        if (eksik.exec() && eksik.next())
        {
            sonuc["eksikKapatildi"]     = true;
            sonuc["eksikKapatmaSebebi"] = eksik.value(0).toString();
            sonuc["eksikKapatmaTarihi"] = eksik.value(1).toDateTime().toString("dd.MM.yyyy HH:mm");
            sonuc["eksikKapatan"]       = eksik.value(2).toString();
        }
        else if (eksik.lastError().isValid())
        {
            qWarning() << "eksik kapatma bilgisi okunamadi:" << eksik.lastError().text();
        }
    }

    // Dayandigi teklif karsilastirmasi: kalem basina tum firmalarin fiyati.
    QHash<int, QVariantList> karsilastirma;
    if (talepId > 0)
    {
        QSqlQuery q(m_db);
        q.prepare(
            "SELECT fy.TalepKalemId, f.FirmaAdi, fy.BirimFiyat, f.ParaBirimi, f.Kur, fy.SecildiMi "
            "FROM dbo.satinalma_teklif_fiyatlari fy "
            "JOIN dbo.satinalma_teklif_firmalari f ON f.TeklifFirmaId = fy.TeklifFirmaId "
            "WHERE f.TalepId = :id "
            "ORDER BY fy.TalepKalemId, fy.BirimFiyat * CASE WHEN f.ParaBirimi = N'TL' THEN 1 ELSE f.Kur END");
        q.bindValue(":id", talepId);
        if (q.exec())
        {
            while (q.next())
            {
                const double kur = q.value(3).toString() == QStringLiteral("TL") ? 1.0 : q.value(4).toDouble();
                QVariantMap teklif;
                teklif["firmaAdi"]     = q.value(1).toString();
                teklif["birimFiyat"]   = q.value(2).toDouble();
                teklif["paraBirimi"]   = q.value(3).toString();
                teklif["birimFiyatTL"] = kurusaYuvarla(q.value(2).toDouble() * kur);
                teklif["secildi"]      = q.value(5).toBool();
                karsilastirma[q.value(0).toInt()].append(teklif);
            }
        }
        else
        {
            qWarning() << "siparis karsilastirmasi okunamadi:" << q.lastError().text();
        }
    }

    QVariantList kalemler;
    double toplamTL = 0.0;
    QSqlQuery kalemQuery(m_db);
    kalemQuery.prepare(
        "SELECT SatinalmaKalemId, KalemAdi, Birim, Adet, GelenAdet, BirimFiyatDoviz, ParaBirimi, "
        "       Kur, BirimFiyatTL, ToplamTutarTL, UrunLinki, NeIcin, TalepKalemId "
        "FROM dbo.satinalma_kalemleri WHERE SatinalmaId = :id ORDER BY SatinalmaKalemId");
    kalemQuery.bindValue(":id", satinalmaId);
    if (kalemQuery.exec())
    {
        while (kalemQuery.next())
        {
            QVariantMap kalem;
            kalem["satinalmaKalemId"] = kalemQuery.value(0).toInt();
            kalem["kalemAdi"]      = kalemQuery.value(1).toString();
            kalem["birim"]         = kalemQuery.value(2).toString();
            kalem["adet"]          = kalemQuery.value(3).toDouble();
            kalem["gelenAdet"]     = kalemQuery.value(4).toDouble();
            kalem["birimFiyat"]    = kalemQuery.value(5).toDouble();
            kalem["paraBirimi"]    = kalemQuery.value(6).toString();
            kalem["kur"]           = kalemQuery.value(7).toDouble();
            kalem["birimFiyatTL"]  = kalemQuery.value(8).toDouble();
            kalem["toplamTutarTL"] = kalemQuery.value(9).toDouble();
            kalem["urunLinki"]     = kalemQuery.value(10).toString();
            kalem["neIcin"]        = kalemQuery.value(11).toString();
            kalem["teklifler"]     = karsilastirma.value(kalemQuery.value(12).toInt());
            toplamTL += kalemQuery.value(9).toDouble();
            kalemler.append(kalem);
        }
    }
    else
    {
        qWarning() << "satinalma kalemleri okunamadi:" << kalemQuery.lastError().text();
    }

    sonuc["kalemler"]      = kalemler;
    sonuc["toplamTutarTL"] = kurusaYuvarla(toplamTL);
    return sonuc;
}

QVariantMap Database::satinalmaSevkiyatGuncelle(int satinalmaId, const QVariantMap &bilgi)
{
    ERP_IZ("satinalmaSevkiyatGuncelle");
    QVariantMap sonuc = basarisizSonuc();
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!satinalmaSemasiHazirMi())
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    const QString sekil = alan(bilgi, "teslimatSekli");
    if (!gecerliTeslimatSekliMi(sekil))
    {
        sonuc["hata"] = "Teslimat şeklini seçin.";
        return sonuc;
    }
    const bool kargolu = kargoluTeslimatMi(sekil);
    const bool yolaCikti = bilgi.value("yolaCikti", false).toBool();

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.satinalmalar SET TeslimatSekli = :sekil, KargoFirmasi = :firma, "
        "KargoTakipNo = :takip, SiteSiparisNo = :siteNo, BeklenenTeslimTarihi = :beklenen, "
        "GuncellemeTarihi = SYSDATETIME() "
        "OUTPUT DELETED.Durum "
        "WHERE SatinalmaId = :id AND Durum NOT IN (N'İptal', N'Reddedildi')");
    query.bindValue(":sekil", sekil);
    // Kargo ile gelmeyen sipariste kargo alanlari anlamsizdir; bos yazilir.
    query.bindValue(":firma", kargolu ? metinParametresi(alan(bilgi, "kargoFirmasi"))
                                      : QVariant(QMetaType(QMetaType::QString)));
    query.bindValue(":takip", kargolu ? metinParametresi(alan(bilgi, "kargoTakipNo"))
                                      : QVariant(QMetaType(QMetaType::QString)));
    query.bindValue(":siteNo", metinParametresi(alan(bilgi, "siteSiparisNo")));
    query.bindValue(":beklenen", tarihParametresi(alan(bilgi, "beklenenTeslimTarihi")));
    query.bindValue(":id", satinalmaId);
    if (!query.exec())
    {
        qWarning() << "satinalmaSevkiyatGuncelle basarisiz:" << query.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Sevkiyat bilgisi kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }
    if (!query.next())
    {
        m_db.rollback();
        sonuc["hata"] = "Sipariş bulunamadı ya da iptal edilmiş. Listeyi yenileyin.";
        return sonuc;
    }
    const QString mevcutDurum = query.value(0).toString();
    query.finish();

    if (yolaCikti)
    {
        if (mevcutDurum == QStringLiteral("Patron Onayı Bekliyor"))
        {
            m_db.rollback();
            sonuc["hata"] = "Patron onayı işaretlenmeden sipariş yola çıkmış sayılamaz.";
            return sonuc;
        }
        if (mevcutDurum == QStringLiteral("Sipariş Verildi"))
        {
            QSqlQuery durum(m_db);
            durum.prepare("UPDATE dbo.satinalmalar SET Durum = N'Kargoda' WHERE SatinalmaId = :id");
            durum.bindValue(":id", satinalmaId);
            if (!durum.exec())
            {
                m_db.rollback();
                sonuc["hata"] = "Sipariş durumu değiştirilemedi: " + durum.lastError().text();
                return sonuc;
            }
        }
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Sevkiyat bilgisi kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::satinalmaFaturaGuncelle(int satinalmaId, const QVariantMap &bilgi)
{
    ERP_IZ("satinalmaFaturaGuncelle");
    QVariantMap sonuc = basarisizSonuc();
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!satinalmaSemasiHazirMi())
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    const QString faturaNo = alan(bilgi, "faturaNo");
    const bool muhasebe = bilgi.value("muhasebeyeIletildi", false).toBool();
    if (muhasebe && faturaNo.isEmpty())
    {
        sonuc["hata"] = "Muhasebeye iletmeden önce fatura numarasını girin.";
        return sonuc;
    }
    const double tutar = bilgi.value("faturaTutariTL", 0).toDouble();
    if (tutar < 0.0)
    {
        sonuc["hata"] = "Fatura tutarı eksi olamaz.";
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.satinalmalar SET FaturaNo = :no, FaturaTarihi = :tarih, FaturaTutariTL = :tutar, "
        "MuhasebeyeIletildiMi = :muhasebe, GuncellemeTarihi = SYSDATETIME() "
        "WHERE SatinalmaId = :id AND Durum NOT IN (N'İptal', N'Reddedildi')");
    query.bindValue(":no", metinParametresi(faturaNo));
    query.bindValue(":tarih", tarihParametresi(alan(bilgi, "faturaTarihi")));
    query.bindValue(":tutar", tutar > 0.0 ? QVariant(kurusaYuvarla(tutar))
                                          : QVariant(QMetaType(QMetaType::Double)));
    query.bindValue(":muhasebe", muhasebe);
    query.bindValue(":id", satinalmaId);
    if (!query.exec())
    {
        qWarning() << "satinalmaFaturaGuncelle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Fatura bilgisi kaydedilemedi: " + query.lastError().text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Sipariş bulunamadı ya da iptal edilmiş. Listeyi yenileyin.";
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::satinalmaOzetiGetir()
{
    QVariantMap ozet;
    ozet["acikTalep"]     = 0;
    ozet["onayBekleyen"]  = 0;
    ozet["acikSiparis"]   = 0;
    ozet["yolda"]         = 0;
    ozet["geciken"]       = 0;
    ozet["buAyTutarTL"]   = 0.0;
    ozet["faturasiEksik"] = 0;
    if (!baglantiHazir() || !satinalmaSemasiHazirMi())
        return ozet;

    QSqlQuery query(m_db);
    const QString sql = QStringLiteral(
        "SELECT "
        "  SUM(CASE WHEN %1 THEN 1 ELSE 0 END), "
        "  SUM(CASE WHEN s.Durum = N'Patron Onayı Bekliyor' THEN 1 ELSE 0 END), "
        "  SUM(CASE WHEN s.Durum = N'Kargoda' THEN 1 ELSE 0 END), "
        "  SUM(CASE WHEN %1 AND s.BeklenenTeslimTarihi < CAST(SYSDATETIME() AS DATE) THEN 1 ELSE 0 END), "
        "  SUM(CASE WHEN s.Durum IN (N'Teslim Alındı', N'Kısmi Teslim') AND s.FaturaNo IS NULL "
        "           THEN 1 ELSE 0 END), "
        "  SUM(CASE WHEN %2 AND s.SatinalmaTarihi >= DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1) "
        "           THEN ISNULL(k.Tutar, 0) ELSE 0 END), "
        "  (SELECT COUNT(*) FROM dbo.satinalma_talepleri t WHERE t.IptalMi = 0 AND EXISTS ( "
        "      SELECT 1 FROM dbo.satinalma_talep_kalemleri tk WHERE tk.TalepId = t.TalepId "
        "        AND tk.TalepKalemId NOT IN (%3))) "
        "FROM dbo.satinalmalar s "
        "OUTER APPLY (SELECT SUM(ToplamTutarTL) AS Tutar FROM dbo.satinalma_kalemleri "
        "             WHERE SatinalmaId = s.SatinalmaId) k")
        .arg(QString::fromUtf8(ACIK_SIPARIS_KOSULU), QString::fromUtf8(AKTIF_SIPARIS_KOSULU),
             QString::fromUtf8(SIPARISLI_TALEP_KALEMLERI_SQL));

    if (!query.exec(sql) || !query.next())
    {
        qWarning() << "satinalmaOzetiGetir basarisiz:" << query.lastError().text();
        return ozet;
    }

    ozet["acikSiparis"]   = query.value(0).toInt();
    ozet["onayBekleyen"]  = query.value(1).toInt();
    ozet["yolda"]         = query.value(2).toInt();
    ozet["geciken"]       = query.value(3).toInt();
    ozet["faturasiEksik"] = query.value(4).toInt();
    ozet["buAyTutarTL"]   = query.value(5).toDouble();
    ozet["acikTalep"]     = query.value(6).toInt();
    return ozet;
}

QVariantMap Database::satinalmaDurumGuncelle(int satinalmaId, const QString &yeniDurum,
                                              const QString &redSebebi)
{
    ERP_IZ("satinalmaDurumGuncelle");
    QVariantMap sonuc = basarisizSonuc();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("Durum")))
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }
    if (!elleAyarlanabilirDurumMu(yeniDurum))
    {
        // 'Teslim Alındı' / 'Kısmi Teslim' buraya DUSMEZ: ikisi de gelen
        // adetlerden hesaplandigi icin yalnizca satinalmaTeslimAl uretir.
        sonuc["hata"] = "Bu durum buradan verilemez.";
        return sonuc;
    }
    if (yeniDurum == QStringLiteral("Reddedildi") && redSebebi.trimmed().isEmpty())
    {
        // Sebepsiz red, "neden alinmadi?" sorusunu yine cevapsiz birakirdi.
        sonuc["hata"] = "Reddetme sebebini yazın.";
        return sonuc;
    }

    // db/32 kurulu degilse onceki durum ve eksik kapatma izi tutulmaz.
    const bool oncekiDurumKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"),
                                                   QStringLiteral("TeslimOncekiDurum"));
    const bool eksikKolonu = semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"),
                                             QStringLiteral("EksikKapatmaTarihi"));

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }
    auto hataylaDon = [&](const QString &mesaj) {
        m_db.rollback();
        sonuc["hata"] = mesaj;
        return sonuc;
    };

    // Mevcut durum satir kilidiyle okunur: kontrol ile yazma arasinda baska
    // bir islem (teslim alma, onay) araya girmesin.
    QString mevcutDurum;
    QString oncekiDurum;
    bool eksikKapatildi = false;
    QString faturaNo;
    {
        QSqlQuery mevcut(m_db);
        mevcut.prepare(QStringLiteral(
            "SELECT Durum, %1, %2, FaturaNo FROM dbo.satinalmalar WITH (UPDLOCK, ROWLOCK) "
            "WHERE SatinalmaId = :id")
            .arg(oncekiDurumKolonu ? QStringLiteral("TeslimOncekiDurum") : QStringLiteral("CAST(NULL AS NVARCHAR(30))"),
                 eksikKolonu ? QStringLiteral("CASE WHEN EksikKapatmaTarihi IS NULL THEN 0 ELSE 1 END")
                             : QStringLiteral("0")));
        mevcut.bindValue(":id", satinalmaId);
        if (!mevcut.exec() || !mevcut.next())
            return hataylaDon("Sipariş bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.");
        mevcutDurum = mevcut.value(0).toString();
        oncekiDurum = mevcut.value(1).toString();
        eksikKapatildi = mevcut.value(2).toInt() == 1;
        faturaNo = mevcut.value(3).toString().trimmed();
    }

    // Gecis kurallari. Ekran yalnizca gecerli gecisleri sunar; bu denetim,
    // eski bir ekranin / yarisin teslim alinmis siparisi iptal etmesini
    // (kalemleri talepte yeniden acilir, gelmis mal ikinci kez siparis
    // edilir) ya da onay bekleyeni onaysiz vermesini engeller.
    const bool teslimVar = mevcutDurum == QStringLiteral("Teslim Alındı")
                           || mevcutDurum == QStringLiteral("Kısmi Teslim");
    const bool teslimOncesi = mevcutDurum == QStringLiteral("Patron Onayı Bekliyor")
                              || mevcutDurum == QStringLiteral("Sipariş Verildi")
                              || mevcutDurum == QStringLiteral("Kargoda");
    // 'Sipariş Verildi' istegi = teslimi geri alma (bkz. Database.h).
    const bool teslimiGeriAl = yeniDurum == QStringLiteral("Sipariş Verildi");

    if (mevcutDurum == yeniDurum)
        return hataylaDon(QString("Sipariş zaten \"%1\" durumunda. Listeyi yenileyin.").arg(mevcutDurum));
    if (yeniDurum == QStringLiteral("İptal") || yeniDurum == QStringLiteral("Reddedildi"))
    {
        if (teslimVar)
            return hataylaDon("Malı gelmiş (teslim alınmış) sipariş iptal edilemez. Kalan gelmeyecekse "
                              "\"Eksik Kapat\" kullanın.");
        if (!teslimOncesi)
            return hataylaDon(QString("\"%1\" durumundaki sipariş iptal edilemez.").arg(mevcutDurum));
        // Iptal edilen sipariste fatura bilgisi artik duzeltilemez; muhasebeye
        // gitmis bir fatura iptal kaydinda unutulmasin.
        if (!faturaNo.isEmpty())
            return hataylaDon(QString("Siparişin faturası girilmiş (Fatura No: %1); iptal edilemez. "
                                      "Önce fatura bilgisini silin, iade gerekiyorsa muhasebeye bildirin.")
                                  .arg(faturaNo));
    }
    else if (teslimiGeriAl)
    {
        if (!teslimVar)
            return hataylaDon(mevcutDurum == QStringLiteral("İptal") || mevcutDurum == QStringLiteral("Reddedildi")
                ? QStringLiteral("İptal edilmiş sipariş yeniden açılamaz; gerekirse talepten yeni sipariş oluşturun.")
                : QString("\"%1\" durumundaki siparişin geri alınacak teslimi yok.").arg(mevcutDurum));
    }
    else if (yeniDurum == QStringLiteral("Kargoda"))
    {
        if (mevcutDurum != QStringLiteral("Sipariş Verildi"))
            return hataylaDon(QString("\"%1\" durumundaki sipariş yola çıkmış yapılamaz.").arg(mevcutDurum));
    }

    // Teslimi geri alinan siparis teslimden onceki durumuna doner: kargodaki
    // bir siparis "Sipariş Verildi"ye dusmesin. Bilgi yoksa (db/32 oncesi
    // teslim) 'Sipariş Verildi'.
    const QString hedefDurum = teslimiGeriAl && oncekiDurum == QStringLiteral("Kargoda")
                               ? QStringLiteral("Kargoda") : yeniDurum;

    // Eksik kapatilmis siparisin teslimi geri alinirsa, eksik miktar icin
    // talepte acilan kalemler kaldirilir; siparis yeniden tum miktari bekler.
    // O kalem baska bir siparise donusmusse geri alinmaz (ayni miktar iki
    // siparise girerdi).
    if (teslimiGeriAl && eksikKapatildi)
    {
        QList<int> eksikKalemler;
        {
            QSqlQuery q(m_db);
            q.prepare(QStringLiteral(
                "SELECT tk.TalepKalemId, sp.SiparisNo FROM dbo.satinalma_talep_kalemleri tk "
                "OUTER APPLY (SELECT TOP 1 s.SiparisNo FROM dbo.satinalma_kalemleri sk "
                "             JOIN dbo.satinalmalar s ON s.SatinalmaId = sk.SatinalmaId "
                "             WHERE sk.TalepKalemId = tk.TalepKalemId AND %1) sp "
                "WHERE tk.EksikKaynakSatinalmaId = :id").arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU)));
            q.bindValue(":id", satinalmaId);
            if (!q.exec())
                return hataylaDon("Eksik kalemler okunamadı: " + q.lastError().text());
            while (q.next())
            {
                if (!q.value(1).isNull())
                    return hataylaDon(QString("Eksik kalan miktar SA-%1 siparişiyle yeniden sipariş edildi; "
                                              "teslim geri alınamaz. Gerekirse önce o siparişi iptal edin.")
                                          .arg(q.value(1).toInt(), 4, 10, QChar('0')));
                eksikKalemler << q.value(0).toInt();
            }
        }
        for (const int kalemId : std::as_const(eksikKalemler))
        {
            for (const char *sql : { "DELETE FROM dbo.satinalma_teklif_fiyatlari WHERE TalepKalemId = :id",
                                     "UPDATE dbo.satinalma_kalemleri SET TalepKalemId = NULL WHERE TalepKalemId = :id",
                                     "DELETE FROM dbo.satinalma_talep_kalemleri WHERE TalepKalemId = :id" })
            {
                QSqlQuery q(m_db);
                q.prepare(QString::fromLatin1(sql));
                q.bindValue(":id", kalemId);
                if (!q.exec())
                    return hataylaDon("Eksik kalem talepten kaldırılamadı: " + q.lastError().text());
            }
        }
    }

    QStringList ekAlanlar;
    if (teslimiGeriAl)
    {
        ekAlanlar << QStringLiteral("TeslimAlmaTarihi = NULL");
        if (oncekiDurumKolonu)
            ekAlanlar << QStringLiteral("TeslimOncekiDurum = NULL");
        if (eksikKolonu)
            ekAlanlar << QStringLiteral("EksikKapatmaSebebi = NULL") << QStringLiteral("EksikKapatmaTarihi = NULL")
                      << QStringLiteral("EksikKapatanKullaniciId = NULL");
    }

    QSqlQuery query(m_db);
    query.prepare(QStringLiteral(
        "UPDATE dbo.satinalmalar SET Durum = :durum, RedSebebi = :redSebebi%1, "
        "GuncellemeTarihi = SYSDATETIME() WHERE SatinalmaId = :id")
        .arg(ekAlanlar.isEmpty() ? QString() : QStringLiteral(", ") + ekAlanlar.join(QStringLiteral(", "))));
    query.bindValue(":durum", hedefDurum);
    query.bindValue(":redSebebi", metinParametresi(redSebebi));
    query.bindValue(":id", satinalmaId);

    if (!query.exec())
    {
        qWarning() << "satinalmaDurumGuncelle basarisiz:" << query.lastError().text();
        return hataylaDon("Sipariş durumu değiştirilemedi: " + query.lastError().text());
    }
    if (query.numRowsAffected() == 0)
        return hataylaDon("Sipariş bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.");

    // Teslimi geri alma: gelen adetler de temizlenmezse yarim teslim edilmis
    // gibi gorunen bir kayit kalir; ayni transaction icinde.
    if (teslimiGeriAl)
    {
        QSqlQuery sifirla(m_db);
        sifirla.prepare("UPDATE dbo.satinalma_kalemleri SET GelenAdet = 0 WHERE SatinalmaId = :id");
        sifirla.bindValue(":id", satinalmaId);
        if (!sifirla.exec())
        {
            qWarning() << "gelen adetler sifirlanamadi:" << sifirla.lastError().text();
            return hataylaDon("Teslim bilgisi geri alınamadı: " + sifirla.lastError().text());
        }
    }

    if (!m_db.commit())
        return hataylaDon("Sipariş durumu değiştirilemedi: " + m_db.lastError().text());

    sonuc["basarili"] = true;
    sonuc["durum"] = hedefDurum;
    return sonuc;
}

QVariantMap Database::satinalmaOnayiIsaretle(int satinalmaId)
{
    ERP_IZ("satinalmaOnayiIsaretle");
    QVariantMap sonuc = basarisizSonuc();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("Durum")))
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }

    QSqlQuery query(m_db);
    query.prepare(
        "UPDATE dbo.satinalmalar SET PatronOnayliMi = 1, PatronOnayTarihi = SYSDATETIME(), "
        "OnayiIsaretleyenKullaniciId = :kullaniciId, Durum = N'Sipariş Verildi', "
        "GuncellemeTarihi = SYSDATETIME() "
        // Yalnizca onayda BEKLEYEN siparis isaretlenebilir: iptal edilmis ya
        // da zaten teslim alinmis bir siparis onaya donusturulmesin.
        "WHERE SatinalmaId = :id AND Durum = N'Patron Onayı Bekliyor'");
    query.bindValue(":kullaniciId", intParametresi(m_aktifKullaniciId));
    query.bindValue(":id", satinalmaId);

    if (!query.exec())
    {
        qWarning() << "satinalmaOnayiIsaretle basarisiz:" << query.lastError().text();
        sonuc["hata"] = "Onay işaretlenemedi: " + query.lastError().text();
        return sonuc;
    }
    if (query.numRowsAffected() == 0)
    {
        sonuc["hata"] = "Sipariş onay bekleyen durumda değil. Listeyi yenileyin.";
        return sonuc;
    }

    sonuc["basarili"] = true;
    return sonuc;
}

QVariantMap Database::satinalmaTeslimAl(int satinalmaId, const QVariantList &gelenAdetler)
{
    ERP_IZ("satinalmaTeslimAl");
    QVariantMap sonuc = basarisizSonuc();
    sonuc["durum"] = QString();

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalma_kalemleri"), QStringLiteral("GelenAdet")))
    {
        sonuc["hata"] = QString::fromUtf8(SATINALMA_SEMA_YOK);
        return sonuc;
    }
    if (gelenAdetler.isEmpty())
    {
        sonuc["hata"] = "Teslim alınacak kalem yok.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }

    // Yalnizca bekleyen (verilmis / yoldaki / kismi gelmis) siparis teslim
    // alinir: onay bekleyen, iptal edilmis ya da kapanmis siparis alinmaz.
    QString mevcutDurum;
    {
        QSqlQuery durumQuery(m_db);
        durumQuery.prepare("SELECT Durum FROM dbo.satinalmalar WITH (UPDLOCK, ROWLOCK) WHERE SatinalmaId = :id");
        durumQuery.bindValue(":id", satinalmaId);
        if (!durumQuery.exec() || !durumQuery.next())
        {
            m_db.rollback();
            sonuc["hata"] = "Sipariş bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
            return sonuc;
        }
        mevcutDurum = durumQuery.value(0).toString();
        QString engel;
        if (mevcutDurum == QStringLiteral("Patron Onayı Bekliyor"))
            engel = QStringLiteral("Patron onayı işaretlenmeden sipariş teslim alınamaz.");
        else if (mevcutDurum == QStringLiteral("İptal") || mevcutDurum == QStringLiteral("Reddedildi"))
            engel = QStringLiteral("İptal edilmiş sipariş teslim alınamaz.");
        else if (mevcutDurum == QStringLiteral("Teslim Alındı"))
            engel = QStringLiteral("Sipariş zaten teslim alındı. Düzeltmek için önce teslimi geri alın.");
        if (!engel.isEmpty())
        {
            m_db.rollback();
            sonuc["hata"] = engel;
            return sonuc;
        }
    }

    // Siparis edilen adetler veritabanindan okunur; ekrandan gelen sayiya
    // guvenilmez (arada kalem degismis olabilir) ve "fazla geldi" girisi
    // engellenir.
    QHash<int, double> siparisAdetleri;
    {
        QSqlQuery kalemQuery(m_db);
        kalemQuery.prepare("SELECT SatinalmaKalemId, Adet FROM dbo.satinalma_kalemleri "
                           "WHERE SatinalmaId = :id");
        kalemQuery.bindValue(":id", satinalmaId);
        if (!kalemQuery.exec())
        {
            m_db.rollback();
            sonuc["hata"] = "Sipariş kalemleri okunamadı: " + kalemQuery.lastError().text();
            return sonuc;
        }
        while (kalemQuery.next())
            siparisAdetleri.insert(kalemQuery.value(0).toInt(), kalemQuery.value(1).toDouble());
    }
    if (siparisAdetleri.isEmpty())
    {
        m_db.rollback();
        sonuc["hata"] = "Sipariş bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }

    QSqlQuery guncelle(m_db);
    guncelle.prepare("UPDATE dbo.satinalma_kalemleri SET GelenAdet = :gelen "
                     "WHERE SatinalmaKalemId = :kalemId AND SatinalmaId = :id");

    double toplamSiparis = 0.0;
    double toplamGelen = 0.0;
    QHash<int, double> girilen;

    for (const QVariant &ham : gelenAdetler)
    {
        const QVariantMap satir = ham.toMap();
        const int kalemId = satir.value("satinalmaKalemId").toInt();
        if (!siparisAdetleri.contains(kalemId))
            continue;   // araya baska bir kullanici girmis olabilir: yok say

        const double siparis = siparisAdetleri.value(kalemId);
        double gelen = satir.value("gelenAdet", 0).toDouble();
        if (gelen < 0.0)
            gelen = 0.0;
        if (gelen > siparis)
            gelen = siparis;   // siparis edilenden fazlasi kaydedilmez

        guncelle.bindValue(":gelen", gelen);
        guncelle.bindValue(":kalemId", kalemId);
        guncelle.bindValue(":id", satinalmaId);
        if (!guncelle.exec())
        {
            qWarning() << "gelen adet yazilamadi:" << guncelle.lastError().text();
            m_db.rollback();
            sonuc["hata"] = "Teslim bilgisi kaydedilemedi: " + guncelle.lastError().text();
            return sonuc;
        }
        girilen.insert(kalemId, gelen);
    }

    // Ekranda gorunmeyen / gonderilmeyen kalemler de toplama katilir, yoksa
    // tek kalem teslim alindiginda siparis "tamamen geldi" sanilabilir.
    for (auto it = siparisAdetleri.constBegin(); it != siparisAdetleri.constEnd(); ++it)
    {
        toplamSiparis += it.value();
        toplamGelen += girilen.value(it.key(), 0.0);
    }

    if (toplamGelen <= 0.0)
    {
        m_db.rollback();
        sonuc["hata"] = "Gelen miktar girilmedi. Hiçbir şey gelmediyse siparişi açık bırakın.";
        return sonuc;
    }

    // Kurus/gram farklarinin "eksik geldi" sayilmamasi icin kucuk bir tolerans.
    const bool tamami = toplamGelen >= toplamSiparis - 0.0005;
    const QString durum = tamami ? QStringLiteral("Teslim Alındı")
                                 : QStringLiteral("Kısmi Teslim");

    // Teslimden onceki durum (Sipariş Verildi / Kargoda) saklanir; "Teslimi
    // Geri Al" siparisi oraya dondurur. Kismi teslimden sonraki teslimde ilk
    // deger korunur. db/32 kurulu degilse yazilmaz.
    const bool oncekiDurumYaz = mevcutDurum != QStringLiteral("Kısmi Teslim")
        && semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("TeslimOncekiDurum"));

    QSqlQuery baslik(m_db);
    baslik.prepare(QStringLiteral("UPDATE dbo.satinalmalar SET Durum = :durum, TeslimAlmaTarihi = :tarih%1, "
                                  "GuncellemeTarihi = SYSDATETIME() WHERE SatinalmaId = :id")
                       .arg(oncekiDurumYaz ? QStringLiteral(", TeslimOncekiDurum = :onceki") : QString()));
    if (oncekiDurumYaz)
        baslik.bindValue(":onceki", mevcutDurum);
    baslik.bindValue(":durum", durum);
    // Her teslimde bugunun tarihi yazilir: tamamlanan sipariste son malin
    // geldigi gundur (kismi teslimde o ana kadarki son teslim).
    baslik.bindValue(":tarih", QDate::currentDate());
    baslik.bindValue(":id", satinalmaId);
    if (!baslik.exec())
    {
        qWarning() << "teslim durumu yazilamadi:" << baslik.lastError().text();
        m_db.rollback();
        sonuc["hata"] = "Teslim bilgisi kaydedilemedi: " + baslik.lastError().text();
        return sonuc;
    }

    if (!m_db.commit())
    {
        m_db.rollback();
        sonuc["hata"] = "Teslim bilgisi kaydedilemedi: " + m_db.lastError().text();
        return sonuc;
    }

    sonuc["basarili"] = true;
    sonuc["durum"]    = durum;
    return sonuc;
}

QVariantMap Database::satinalmaEksikKapat(int satinalmaId, const QString &sebep, bool eksikleriTalebeAc)
{
    ERP_IZ("satinalmaEksikKapat");
    QVariantMap sonuc = basarisizSonuc();
    sonuc["acilanKalemSayisi"] = 0;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("SATINALMA")))
    {
        sonuc["hata"] = QString::fromUtf8(TEDARIKCI_YETKI_YOK);
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalmalar"), QStringLiteral("EksikKapatmaTarihi"))
        || !semaKolonuVarMi(m_db, QStringLiteral("dbo.satinalma_talep_kalemleri"),
                            QStringLiteral("EksikKaynakSatinalmaId")))
    {
        sonuc["hata"] = "Eksik kapatma için db/32_satinalma_eksik_kapatma.sql betiği çalıştırılmalı.";
        return sonuc;
    }
    const QString temizSebep = sebep.trimmed();
    if (temizSebep.isEmpty())
    {
        // "Kalan neden gelmedi?" sorusu sonradan cevapsiz kalmasin.
        sonuc["hata"] = "Kalanın neden gelmeyeceğini yazın.";
        return sonuc;
    }

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }
    auto hataylaDon = [&](const QString &mesaj) {
        m_db.rollback();
        sonuc["hata"] = mesaj;
        sonuc["acilanKalemSayisi"] = 0;
        return sonuc;
    };

    int siparisNo = 0;
    int talepId = 0;
    {
        QSqlQuery q(m_db);
        q.prepare("SELECT Durum, SiparisNo, TalepId FROM dbo.satinalmalar WITH (UPDLOCK, ROWLOCK) "
                  "WHERE SatinalmaId = :id");
        q.bindValue(":id", satinalmaId);
        if (!q.exec() || !q.next())
            return hataylaDon("Sipariş bulunamadı; kayıt silinmiş olabilir. Listeyi yenileyin.");
        // Hic gelmemis siparis eksik kapatilmaz, iptal edilir.
        if (q.value(0).toString() != QStringLiteral("Kısmi Teslim"))
            return hataylaDon("Yalnızca kısmi teslim edilmiş sipariş eksik kapatılabilir. "
                              "Hiçbir şey gelmediyse siparişi iptal edin.");
        siparisNo = q.value(1).toInt();
        talepId = q.value(2).isNull() ? 0 : q.value(2).toInt();
    }

    // Eksik kalan kalemler talepte yeni kalem olarak acilir: siparisin
    // kalemleri "siparise donusmus" sayildigi icin eksik miktar baska turlu
    // talepte gorunmez. Fiyat/yer bilerek tasinmaz -- bu tedarikci
    // gondermiyor, yeni yer bulunacak.
    int acilan = 0;
    if (eksikleriTalebeAc && talepId > 0)
    {
        QSqlQuery eksikler(m_db);
        eksikler.prepare(
            "SELECT tk.KalemAdi, tk.NeIcin, tk.Birim, sk.Adet - sk.GelenAdet, tk.SiraNo "
            "FROM dbo.satinalma_kalemleri sk "
            "JOIN dbo.satinalma_talep_kalemleri tk ON tk.TalepKalemId = sk.TalepKalemId "
            "WHERE sk.SatinalmaId = :id AND sk.Adet - sk.GelenAdet > 0.0005 "
            "ORDER BY tk.SiraNo, tk.TalepKalemId");
        eksikler.bindValue(":id", satinalmaId);
        if (!eksikler.exec())
            return hataylaDon("Eksik kalemler okunamadı: " + eksikler.lastError().text());

        struct Eksik { QVariant kalemAdi, neIcin, birim; double miktar; };
        QVector<Eksik> liste;
        while (eksikler.next())
            liste.append({ eksikler.value(0), eksikler.value(1), eksikler.value(2),
                           eksikler.value(3).toDouble() });

        int sira = 0;
        {
            QSqlQuery q(m_db);
            q.prepare("SELECT ISNULL(MAX(SiraNo), 0) FROM dbo.satinalma_talep_kalemleri WHERE TalepId = :id");
            q.bindValue(":id", talepId);
            if (!q.exec() || !q.next())
                return hataylaDon("Talep kalemleri okunamadı: " + q.lastError().text());
            sira = q.value(0).toInt();
        }

        const QString aciklama = QString("SA-%1 siparişinden eksik gelen miktar.")
                                     .arg(siparisNo, 4, 10, QChar('0'));
        QSqlQuery ekle(m_db);
        ekle.prepare("INSERT INTO dbo.satinalma_talep_kalemleri "
                     "(TalepId, SiraNo, KalemAdi, NeIcin, Miktar, Birim, Aciklama, Arastirilacak, "
                     " EksikKaynakSatinalmaId) "
                     "VALUES (:talepId, :sira, :kalemAdi, :neIcin, :miktar, :birim, :aciklama, 0, :kaynak)");
        for (const Eksik &e : std::as_const(liste))
        {
            ekle.bindValue(":talepId", talepId);
            ekle.bindValue(":sira", ++sira);
            ekle.bindValue(":kalemAdi", e.kalemAdi);
            ekle.bindValue(":neIcin", e.neIcin);
            ekle.bindValue(":miktar", e.miktar);
            ekle.bindValue(":birim", e.birim);
            ekle.bindValue(":aciklama", aciklama);
            ekle.bindValue(":kaynak", satinalmaId);
            if (!ekle.exec())
                return hataylaDon("Eksik kalem talebe eklenemedi: " + ekle.lastError().text());
            ++acilan;
        }

        // Talep artik eksik kalemleriyle yeniden acik; guncellenme anı da degisir.
        if (acilan > 0)
        {
            QSqlQuery q(m_db);
            q.prepare("UPDATE dbo.satinalma_talepleri SET GuncellemeTarihi = SYSDATETIME() WHERE TalepId = :id");
            q.bindValue(":id", talepId);
            if (!q.exec())
                return hataylaDon("Talep güncellenemedi: " + q.lastError().text());
        }
    }

    // Gelen adetler ve teslim tarihi oldugu gibi kalir: siparisin neyi ne
    // kadar getirdigi gorunur, eksik kapatma izi ayrica yazilir.
    QSqlQuery kapat(m_db);
    kapat.prepare("UPDATE dbo.satinalmalar SET Durum = N'Teslim Alındı', EksikKapatmaSebebi = :sebep, "
                  "EksikKapatmaTarihi = SYSDATETIME(), EksikKapatanKullaniciId = :kullaniciId, "
                  "GuncellemeTarihi = SYSDATETIME() "
                  "WHERE SatinalmaId = :id AND Durum = N'Kısmi Teslim'");
    kapat.bindValue(":sebep", temizSebep.left(500));
    kapat.bindValue(":kullaniciId", intParametresi(m_aktifKullaniciId));
    kapat.bindValue(":id", satinalmaId);
    if (!kapat.exec())
        return hataylaDon("Sipariş kapatılamadı: " + kapat.lastError().text());
    if (kapat.numRowsAffected() != 1)
        return hataylaDon("Sipariş kısmi teslim durumunda değil. Listeyi yenileyin.");

    if (!m_db.commit())
        return hataylaDon("Sipariş kapatılamadı: " + m_db.lastError().text());

    sonuc["basarili"] = true;
    sonuc["acilanKalemSayisi"] = acilan;
    return sonuc;
}

// ===========================================================================
// CIHAZ MALIYETLERI (Yonetim + Satinalma)
//
// Yetki uc kademelidir (bkz. cihazYetkisi):
//   * YONETIM duzenleyebilir : her sey (cihaz ekle / arsivle, ad, kar orani,
//                              urun eslesmesi, recete).
//   * SATINALMA duzenleyebilir: yalnizca recete kalemleri (parca, adet, fiyat).
//   * Kar orani, satis fiyati, katalog fiyati ve maliyet gecmisindeki satis
//     fiyati yalnizca YONETIM'i GOREBILEN kullaniciya doner; digerlerinden
//     sunucuda ayiklanir.
// ===========================================================================
namespace
{
    const QStringList CIHAZ_KALEM_TURLERI = {
        QStringLiteral("Malzeme"), QStringLiteral("İşçilik"),
        QStringLiteral("Dış Hizmet"), QStringLiteral("Genel Gider")
    };

    // Kar/satis bilgisini yetkisi olmayan kullaniciya gitmeden ayiklar.
    void cihazFiyatBilgisiniAyikla(QVariantMap &cihaz)
    {
        cihaz.remove(QStringLiteral("karOrani"));
        cihaz.remove(QStringLiteral("satisFiyatiTL"));
        cihaz.remove(QStringLiteral("katalogFiyat"));
        cihaz.remove(QStringLiteral("katalogParaBirimi"));
        cihaz.remove(QStringLiteral("urunId"));
        cihaz.remove(QStringLiteral("urunKodu"));
        cihaz.remove(QStringLiteral("urunAciklamasi"));
    }
}

bool Database::modulGorebilirMi(const QString &modulKodu)
{
    if (m_aktifKullaniciId <= 0)
        return false;
    const QVariantList moduller = kullaniciModulleriniGetir(m_aktifKullaniciId);
    for (const QVariant &v : moduller)
        if (v.toMap().value("modulKodu").toString() == modulKodu)
            return true;
    return false;
}

QVariantMap Database::cihazYetkisi()
{
    QVariantMap y;
    const bool yonetimGorur = modulGorebilirMi(QStringLiteral("YONETIM"));
    const bool tamYetki = modulDuzenleyebilirMi(QStringLiteral("YONETIM"));
    y["fiyatGorebilir"] = yonetimGorur;
    y["tamYetki"] = tamYetki;
    y["kalemDuzenleyebilir"] = tamYetki || modulDuzenleyebilirMi(QStringLiteral("SATINALMA"));
    // db/17 / db/24 durumu: ekran eksik betigi soyleyebilsin.
    y["semaHazir"] = baglantiHazir()
        && semaKolonuVarMi(m_db, QStringLiteral("dbo.cihazlar"), QStringLiteral("CihazId"));
    y["urunEslesmesiVar"] = baglantiHazir()
        && semaKolonuVarMi(m_db, QStringLiteral("dbo.cihazlar"), QStringLiteral("UrunId"));
    return y;
}

int Database::cihazListesiGetirBaslat(const QString &arama, bool arsivDahil)
{
    const int istekNo = ++m_listeIstekSayaci;
    if (!m_listeWorker)
    {
        emit cihazListesiHazir(istekNo, QVariantList());
        return istekNo;
    }
    // Sonuc, fiyat bilgisi ayiklanmak uzere cihazListesiAyikla'dan gecer.
    m_cihazFiyatGorebilir = modulGorebilirMi(QStringLiteral("YONETIM"));
    QMetaObject::invokeMethod(m_listeWorker, "cihazListesiCalistir", Qt::QueuedConnection,
                              Q_ARG(int, istekNo), Q_ARG(QString, arama), Q_ARG(bool, arsivDahil));
    return istekNo;
}

void Database::cihazListesiAyikla(int istekNo, const QVariantList &liste)
{
    if (m_cihazFiyatGorebilir)
    {
        emit cihazListesiHazir(istekNo, liste);
        return;
    }
    QVariantList ayiklanmis;
    for (const QVariant &v : liste)
    {
        QVariantMap c = v.toMap();
        cihazFiyatBilgisiniAyikla(c);
        ayiklanmis << c;
    }
    emit cihazListesiHazir(istekNo, ayiklanmis);
}

QVariantMap Database::cihazGetir(int cihazId)
{
    ERP_IZ("cihazGetir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }

    const bool fiyatGorebilir = modulGorebilirMi(QStringLiteral("YONETIM"));
    const bool urunSutunu = semaKolonuVarMi(m_db, QStringLiteral("dbo.cihazlar"), QStringLiteral("UrunId"));

    // ---- Cihaz ----
    QSqlQuery cq(m_db);
    cq.prepare(QStringLiteral(
        "SELECT c.CihazId, c.CihazAdi, c.Aciklama, c.KarOrani, c.ToplamMaliyetTL, c.SatisFiyatiTL, "
        "       c.AktifMi, c.GuncellemeTarihi, %1 "
        "FROM dbo.cihazlar c %2 WHERE c.CihazId = :id")
        .arg(urunSutunu ? QStringLiteral("c.UrunId, u.UrunKodu, u.UrunAciklamasi, u.BirimFiyat, u.ParaBirimi")
                        : QStringLiteral("NULL, NULL, NULL, NULL, NULL"),
             urunSutunu ? QStringLiteral("LEFT JOIN dbo.urunler u ON u.UrunId = c.UrunId") : QString()));
    cq.bindValue(":id", cihazId);
    if (!cq.exec())
    {
        sonuc["hata"] = "Cihaz okunamadı: " + cq.lastError().text();
        return sonuc;
    }
    if (!cq.next())
    {
        sonuc["hata"] = "Cihaz bulunamadı; silinmiş olabilir. Listeyi yenileyin.";
        return sonuc;
    }
    QVariantMap cihaz;
    cihaz["cihazId"] = cq.value(0).toInt();
    cihaz["cihazAdi"] = cq.value(1).toString();
    cihaz["aciklama"] = cq.value(2).toString();
    cihaz["karOrani"] = cq.value(3).toDouble();
    cihaz["toplamMaliyetTL"] = cq.value(4).toDouble();
    cihaz["satisFiyatiTL"] = cq.value(5).toDouble();
    cihaz["aktifMi"] = cq.value(6).toBool();
    cihaz["guncellemeTarihi"] = tarihSaatStr(cq.value(7));
    cihaz["urunId"] = cq.value(8).toInt();
    cihaz["urunKodu"] = cq.value(9).toString();
    // Katalog aciklamasi uzun olabilir; ekranda tek satir gosterilir.
    cihaz["urunAciklamasi"] = cq.value(10).toString().left(200);
    cihaz["katalogFiyat"] = cq.value(11).isNull() ? QVariant() : cq.value(11).toDouble();
    cihaz["katalogParaBirimi"] = cq.value(12).toString();
    if (!fiyatGorebilir)
        cihazFiyatBilgisiniAyikla(cihaz);

    // ---- Recete + son alim onerileri ----
    // Oneri: ayni adla, kalemin fiyat tarihinden SONRA yapilmis en son aktif
    // alim ve fiyati recetedekinden farkliysa. Elle girilen guncel fiyat eski
    // bir alimla ezilmesin diye tarih kosulu var.
    const bool oneriVar = satinalmaSemasiHazirMi();
    QSqlQuery kq(m_db);
    kq.prepare(QStringLiteral(
        "SELECT r.ReceteKalemId, r.Grup, r.KalemTuru, r.KalemAdi, r.Adet, r.Birim, r.BirimFiyat, "
        "       r.ParaBirimi, r.Kur, r.BirimFiyatTL, r.ToplamTutarTL, r.TedarikciAdi, r.SonSatinalmaId, "
        "       r.FiyatTarihi, r.Aciklama, %1 "
        "FROM dbo.cihaz_recete_kalemleri r %2 "
        "WHERE r.CihazId = :id ORDER BY r.SiraNo, r.ReceteKalemId")
        .arg(oneriVar ? QStringLiteral("o.SatinalmaId, o.BirimFiyatDoviz, o.ParaBirimi AS OParaBirimi, "
                                       "o.Kur AS OKur, o.SatinalmaTarihi, o.TedarikciAdi AS OTedarikci")
                      : QStringLiteral("NULL, NULL, NULL, NULL, NULL, NULL"),
             oneriVar ? QStringLiteral(
                 "OUTER APPLY (SELECT TOP 1 k.SatinalmaId, k.BirimFiyatDoviz, k.ParaBirimi, k.Kur, "
                 "                     s.SatinalmaTarihi, ISNULL(t.FirmaAdi, s.SiparisKaynagi) AS TedarikciAdi "
                 "             FROM dbo.satinalma_kalemleri k "
                 "             JOIN dbo.satinalmalar s ON s.SatinalmaId = k.SatinalmaId "
                 "             LEFT JOIN dbo.tedarikciler t ON t.TedarikciId = s.TedarikciId "
                 "             WHERE k.KalemAdi = r.KalemAdi AND %1 "
                 "               AND (r.FiyatTarihi IS NULL OR s.SatinalmaTarihi > r.FiyatTarihi) "
                 "               AND (r.SonSatinalmaId IS NULL OR k.SatinalmaId <> r.SonSatinalmaId) "
                 "             ORDER BY s.SatinalmaTarihi DESC, k.SatinalmaKalemId DESC) o")
                 .arg(QString::fromUtf8(AKTIF_SIPARIS_KOSULU))
                      : QString()));
    kq.bindValue(":id", cihazId);
    if (!kq.exec())
    {
        sonuc["hata"] = "Reçete okunamadı: " + kq.lastError().text();
        return sonuc;
    }
    QVariantList kalemler;
    while (kq.next())
    {
        QVariantMap k;
        k["receteKalemId"] = kq.value(0).toInt();
        k["grup"] = kq.value(1).toString();
        k["kalemTuru"] = kq.value(2).toString();
        k["kalemAdi"] = kq.value(3).toString();
        k["adet"] = kq.value(4).toDouble();
        k["birim"] = kq.value(5).toString();
        k["birimFiyat"] = kq.value(6).toDouble();
        k["paraBirimi"] = kq.value(7).toString();
        k["kur"] = kq.value(8).toDouble();
        k["birimFiyatTL"] = kq.value(9).toDouble();
        k["toplamTutarTL"] = kq.value(10).toDouble();
        k["tedarikciAdi"] = kq.value(11).toString();
        k["sonSatinalmaId"] = kq.value(12).toInt();
        k["fiyatTarihi"] = kq.value(13).isNull() ? QString() : kq.value(13).toDate().toString(Qt::ISODate);
        k["aciklama"] = kq.value(14).toString();

        QVariant oneri;
        if (!kq.value(15).isNull())
        {
            const double oFiyat = kq.value(16).toDouble();
            const QString oPara = kq.value(17).toString();
            // Ayni fiyat/para birimi ise oneri anlamsiz.
            if (std::abs(oFiyat - k["birimFiyat"].toDouble()) > 0.00005 || oPara != k["paraBirimi"].toString())
            {
                oneri = QVariantMap{
                    { "satinalmaId", kq.value(15).toInt() },
                    { "birimFiyat", oFiyat },
                    { "paraBirimi", oPara },
                    { "kur", kq.value(18).toDouble() },
                    { "tarih", kq.value(19).toDate().toString(Qt::ISODate) },
                    { "tedarikciAdi", kq.value(20).toString() },
                };
            }
        }
        k["oneri"] = oneri;
        kalemler << k;
    }

    // ---- Maliyet gecmisi (son 100) ----
    QVariantList gecmis;
    QSqlQuery gq(m_db);
    gq.prepare(QStringLiteral(
        "SELECT TOP 100 g.DegisiklikTarihi, g.DegisenKalemAdi, g.EskiBirimFiyatTL, g.YeniBirimFiyatTL, "
        "       g.EskiToplamMaliyetTL, g.YeniToplamMaliyetTL, g.KarOrani, g.YeniSatisFiyatiTL, "
        "       g.TedarikciAdi, k.AdSoyad, g.Aciklama "
        "FROM dbo.cihaz_maliyet_gecmisi g "
        "LEFT JOIN dbo.kullanicilar k ON k.KullaniciId = g.KullaniciId "
        "WHERE g.CihazId = :id ORDER BY g.DegisiklikTarihi DESC, g.GecmisId DESC"));
    gq.bindValue(":id", cihazId);
    if (gq.exec())
    {
        while (gq.next())
        {
            QVariantMap g;
            g["tarih"] = tarihSaatStr(gq.value(0));
            g["degisenKalemAdi"] = gq.value(1).toString();
            g["eskiBirimFiyatTL"] = gq.value(2).isNull() ? QVariant() : gq.value(2).toDouble();
            g["yeniBirimFiyatTL"] = gq.value(3).isNull() ? QVariant() : gq.value(3).toDouble();
            g["eskiToplamTL"] = gq.value(4).toDouble();
            g["yeniToplamTL"] = gq.value(5).toDouble();
            if (fiyatGorebilir)
            {
                g["karOrani"] = gq.value(6).toDouble();
                g["yeniSatisFiyatiTL"] = gq.value(7).toDouble();
            }
            g["tedarikciAdi"] = gq.value(8).toString();
            g["personel"] = gq.value(9).toString();
            g["aciklama"] = gq.value(10).toString();
            gecmis << g;
        }
    }
    else
    {
        qWarning() << "cihazGetir (gecmis) basarisiz:" << gq.lastError().text();
    }

    sonuc["basarili"] = true;
    sonuc["cihaz"] = cihaz;
    sonuc["kalemler"] = kalemler;
    sonuc["gecmis"] = gecmis;
    return sonuc;
}

QVariantMap Database::cihazKaydet(int cihazId, const QVariantMap &veri)
{
    ERP_IZ("cihazKaydet");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["cihazId"] = cihazId;
    const bool yeniCihaz = cihazId <= 0;

    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!semaKolonuVarMi(m_db, QStringLiteral("dbo.cihazlar"), QStringLiteral("CihazId")))
    {
        sonuc["hata"] = "Cihaz tabloları bulunamadı; db/17 betiği çalıştırılmamış.";
        return sonuc;
    }

    const bool tamYetki = modulDuzenleyebilirMi(QStringLiteral("YONETIM"));
    const bool kalemYetkisi = tamYetki || modulDuzenleyebilirMi(QStringLiteral("SATINALMA"));
    if (!kalemYetkisi)
    {
        sonuc["hata"] = "Cihaz maliyetlerini düzenleme yetkiniz yok.";
        return sonuc;
    }
    if (cihazId <= 0 && !tamYetki)
    {
        sonuc["hata"] = "Yeni cihazı yalnızca Yönetim yetkisi olan kullanıcı ekleyebilir.";
        return sonuc;
    }
    const bool urunSutunu = semaKolonuVarMi(m_db, QStringLiteral("dbo.cihazlar"), QStringLiteral("UrunId"));

    // ---- Mevcut hal (gecmis satiri ve yetkisiz alanlari korumak icin) ----
    QString cihazAdi = alan(veri, "cihazAdi");
    QString aciklama = alan(veri, "aciklama");
    double karOrani = veri.value("karOrani", 0).toDouble();
    int urunId = veri.value("urunId").toInt();
    double eskiToplam = 0.0;
    double eskiKar = 0.0;
    struct EskiKalem { QString ad; double birimFiyatTL = 0; QDate fiyatTarihi; int sonSatinalmaId = 0; };
    QHash<int, EskiKalem> eskiKalemler;

    if (cihazId > 0)
    {
        QSqlQuery mevcut(m_db);
        mevcut.prepare(QStringLiteral("SELECT CihazAdi, Aciklama, KarOrani, ToplamMaliyetTL%1 "
                                      "FROM dbo.cihazlar WHERE CihazId = :id")
                           .arg(urunSutunu ? QStringLiteral(", UrunId") : QString()));
        mevcut.bindValue(":id", cihazId);
        if (!mevcut.exec() || !mevcut.next())
        {
            sonuc["hata"] = "Cihaz bulunamadı; silinmiş olabilir. Listeyi yenileyin.";
            return sonuc;
        }
        eskiKar = mevcut.value(2).toDouble();
        eskiToplam = mevcut.value(3).toDouble();
        // Satinalma yetkisi yalnizca receteyi degistirir: cihaz bilgileri
        // istemciden gelse bile kayitli halleri korunur.
        if (!tamYetki)
        {
            cihazAdi = mevcut.value(0).toString();
            aciklama = mevcut.value(1).toString();
            karOrani = eskiKar;
            urunId = urunSutunu ? mevcut.value(4).toInt() : 0;
        }

        QSqlQuery ek(m_db);
        ek.prepare("SELECT ReceteKalemId, KalemAdi, BirimFiyatTL, FiyatTarihi, SonSatinalmaId "
                   "FROM dbo.cihaz_recete_kalemleri WHERE CihazId = :id");
        ek.bindValue(":id", cihazId);
        if (!ek.exec())
        {
            sonuc["hata"] = "Reçete okunamadı: " + ek.lastError().text();
            return sonuc;
        }
        while (ek.next())
            eskiKalemler.insert(ek.value(0).toInt(),
                                { ek.value(1).toString(), ek.value(2).toDouble(),
                                  ek.value(3).toDate(), ek.value(4).toInt() });
    }

    if (cihazAdi.isEmpty())
    {
        sonuc["hata"] = "Cihaz adı boş olamaz.";
        return sonuc;
    }
    if (!std::isfinite(karOrani) || karOrani < 0 || karOrani > 1000)
    {
        sonuc["hata"] = "Kâr oranı 0 ile 1000 arasında olmalıdır.";
        return sonuc;
    }

    // ---- Kalemleri denetle ve TL karsiliklarini SUNUCUDA hesapla ----
    struct YeniKalem
    {
        int id = 0;
        QString grup, tur, ad, birim, paraBirimi, tedarikci, aciklama;
        double adet = 0, birimFiyat = 0, kur = 1, birimFiyatTL = 0, toplamTL = 0;
        int sonSatinalmaId = 0;
        QDate fiyatTarihi;
    };
    QList<YeniKalem> yeniKalemler;
    double yeniToplam = 0.0;
    const QVariantList gelenKalemler = veri.value("kalemler").toList();
    for (int i = 0; i < gelenKalemler.size(); ++i)
    {
        const QVariantMap g = gelenKalemler.at(i).toMap();
        YeniKalem k;
        k.id = g.value("receteKalemId").toInt();
        k.grup = alan(g, "grup").left(100);
        k.tur = alan(g, "kalemTuru");
        k.ad = alan(g, "kalemAdi");
        k.birim = alan(g, "birim").left(20);
        k.paraBirimi = alan(g, "paraBirimi").toUpper();
        k.tedarikci = alan(g, "tedarikciAdi").left(250);
        k.aciklama = alan(g, "aciklama").left(500);
        k.adet = g.value("adet").toDouble();
        k.birimFiyat = g.value("birimFiyat").toDouble();
        k.kur = g.value("kur", 1).toDouble();
        k.sonSatinalmaId = g.value("sonSatinalmaId").toInt();
        k.fiyatTarihi = QDate::fromString(g.value("fiyatTarihi").toString(), Qt::ISODate);

        const QString satir = QStringLiteral("%1. satır").arg(i + 1);
        if (k.ad.isEmpty())
        {
            sonuc["hata"] = satir + ": kalem adı boş olamaz.";
            return sonuc;
        }
        if (k.ad.length() > 300)
        {
            sonuc["hata"] = satir + ": kalem adı en fazla 300 karakter olabilir.";
            return sonuc;
        }
        if (k.tur.isEmpty())
            k.tur = CIHAZ_KALEM_TURLERI.first();
        if (!CIHAZ_KALEM_TURLERI.contains(k.tur))
        {
            sonuc["hata"] = satir + ": geçersiz kalem türü.";
            return sonuc;
        }
        if (!std::isfinite(k.adet) || k.adet <= 0)
        {
            sonuc["hata"] = satir + " (" + k.ad + "): adet sıfırdan büyük olmalıdır.";
            return sonuc;
        }
        if (!std::isfinite(k.birimFiyat) || k.birimFiyat < 0)
        {
            sonuc["hata"] = satir + " (" + k.ad + "): birim fiyat negatif olamaz.";
            return sonuc;
        }
        if (k.paraBirimi.isEmpty())
            k.paraBirimi = QStringLiteral("TL");
        if (k.paraBirimi != QStringLiteral("TL") && k.paraBirimi != QStringLiteral("USD")
            && k.paraBirimi != QStringLiteral("EUR"))
        {
            sonuc["hata"] = satir + " (" + k.ad + "): geçersiz para birimi.";
            return sonuc;
        }
        if (k.paraBirimi == QStringLiteral("TL"))
            k.kur = 1.0;
        else if (!std::isfinite(k.kur) || k.kur <= 1.0)
        {
            // Goc tekliflerindeki "Kur=1" hatasi burada tekrarlanmasin.
            sonuc["hata"] = satir + " (" + k.ad + "): dövizli kalemde kur 1'den büyük olmalıdır.";
            return sonuc;
        }

        k.birimFiyatTL = kurusaYuvarla(k.birimFiyat * k.kur);
        k.toplamTL = kurusaYuvarla(k.adet * k.birimFiyatTL);
        yeniToplam += k.toplamTL;

        // Fiyat tarihi: fiyati degisen / yeni kalemde bugun (oneri uygulandiysa
        // istemci alimin tarihini gonderir); degismeyende kayitli tarih kalir.
        const auto eski = eskiKalemler.constFind(k.id);
        const bool fiyatDegisti = eski == eskiKalemler.constEnd()
                                  || std::abs(eski->birimFiyatTL - k.birimFiyatTL) > 0.005;
        if (!fiyatDegisti)
        {
            k.fiyatTarihi = eski->fiyatTarihi;
            k.sonSatinalmaId = eski->sonSatinalmaId;
        }
        else if (!k.fiyatTarihi.isValid() || k.sonSatinalmaId <= 0)
        {
            k.fiyatTarihi = QDate::currentDate();
        }
        yeniKalemler << k;
    }
    yeniToplam = kurusaYuvarla(yeniToplam);
    const double yeniSatis = kurusaYuvarla(yeniToplam * (1.0 + karOrani / 100.0));

    if (!m_db.transaction())
    {
        sonuc["hata"] = "İşlem başlatılamadı: " + m_db.lastError().text();
        return sonuc;
    }
    const auto geriAl = [&](const QString &hata) {
        m_db.rollback();
        sonuc["hata"] = hata;
        return sonuc;
    };

    // ---- Cihaz ----
    {
        QSqlQuery c(m_db);
        const QString urunAta = urunSutunu ? QStringLiteral(", UrunId = :urunId") : QString();
        if (cihazId > 0)
        {
            c.prepare(QStringLiteral(
                "UPDATE dbo.cihazlar SET CihazAdi = :ad, Aciklama = :aciklama, KarOrani = :kar, "
                "  ToplamMaliyetTL = :toplam, SatisFiyatiTL = :satis, GuncellemeTarihi = SYSDATETIME()%1 "
                "WHERE CihazId = :id").arg(urunAta));
            c.bindValue(":id", cihazId);
        }
        else
        {
            c.prepare(QStringLiteral(
                "INSERT INTO dbo.cihazlar (CihazAdi, Aciklama, KarOrani, ToplamMaliyetTL, SatisFiyatiTL, KullaniciId%1) "
                "OUTPUT INSERTED.CihazId VALUES (:ad, :aciklama, :kar, :toplam, :satis, :kullanici%2)")
                .arg(urunSutunu ? QStringLiteral(", UrunId") : QString(),
                     urunSutunu ? QStringLiteral(", :urunId") : QString()));
            c.bindValue(":kullanici", m_aktifKullaniciId > 0 ? QVariant(m_aktifKullaniciId)
                                                             : QVariant(QMetaType(QMetaType::Int)));
        }
        c.bindValue(":ad", cihazAdi.left(250));
        c.bindValue(":aciklama", metinParametresi(aciklama.left(1000)));
        c.bindValue(":kar", karOrani);
        c.bindValue(":toplam", yeniToplam);
        c.bindValue(":satis", yeniSatis);
        if (urunSutunu)
            c.bindValue(":urunId", urunId > 0 ? QVariant(urunId) : QVariant(QMetaType(QMetaType::Int)));
        if (!c.exec())
            return geriAl("Cihaz kaydedilemedi: " + c.lastError().text());
        if (cihazId <= 0)
        {
            if (!c.next())
                return geriAl(QStringLiteral("Cihaz kaydedilemedi: yeni cihazın numarası alınamadı."));
            cihazId = c.value(0).toInt();
        }
    }

    // ---- Kalemler: gelmeyenler silinir, gelenler guncellenir / eklenir ----
    QSet<int> kalanIdler;
    for (const YeniKalem &k : std::as_const(yeniKalemler))
        if (k.id > 0 && eskiKalemler.contains(k.id))
            kalanIdler.insert(k.id);
    QStringList cikarilanlar;
    for (auto it = eskiKalemler.cbegin(); it != eskiKalemler.cend(); ++it)
    {
        if (kalanIdler.contains(it.key()))
            continue;
        QSqlQuery sil(m_db);
        sil.prepare("DELETE FROM dbo.cihaz_recete_kalemleri WHERE ReceteKalemId = :id AND CihazId = :cihaz");
        sil.bindValue(":id", it.key());
        sil.bindValue(":cihaz", cihazId);
        if (!sil.exec())
            return geriAl("Reçete kalemi silinemedi: " + sil.lastError().text());
        cikarilanlar << it->ad;
    }

    QStringList fiyatiDegisenler, eklenenler;
    const YeniKalem *tekDegisen = nullptr;
    double tekEskiBirimTL = 0.0;
    for (int sira = 0; sira < yeniKalemler.size(); ++sira)
    {
        const YeniKalem &k = yeniKalemler.at(sira);
        const bool guncelle = kalanIdler.contains(k.id);
        QSqlQuery q(m_db);
        if (guncelle)
        {
            q.prepare("UPDATE dbo.cihaz_recete_kalemleri SET Grup = :grup, KalemTuru = :tur, KalemAdi = :ad, "
                      "  Adet = :adet, Birim = :birim, BirimFiyat = :fiyat, ParaBirimi = :para, Kur = :kur, "
                      "  BirimFiyatTL = :fiyatTL, ToplamTutarTL = :toplamTL, TedarikciAdi = :tedarikci, "
                      "  SonSatinalmaId = :satinalma, FiyatTarihi = :tarih, SiraNo = :sira, Aciklama = :aciklama "
                      "WHERE ReceteKalemId = :id AND CihazId = :cihaz");
            q.bindValue(":id", k.id);
        }
        else
        {
            q.prepare("INSERT INTO dbo.cihaz_recete_kalemleri (CihazId, Grup, KalemTuru, KalemAdi, Adet, Birim, "
                      "  BirimFiyat, ParaBirimi, Kur, BirimFiyatTL, ToplamTutarTL, TedarikciAdi, SonSatinalmaId, "
                      "  FiyatTarihi, SiraNo, Aciklama) "
                      "VALUES (:cihaz, :grup, :tur, :ad, :adet, :birim, :fiyat, :para, :kur, :fiyatTL, :toplamTL, "
                      "  :tedarikci, :satinalma, :tarih, :sira, :aciklama)");
        }
        q.bindValue(":cihaz", cihazId);
        q.bindValue(":grup", metinParametresi(k.grup));
        q.bindValue(":tur", k.tur);
        q.bindValue(":ad", k.ad);
        q.bindValue(":adet", k.adet);
        q.bindValue(":birim", metinParametresi(k.birim));
        q.bindValue(":fiyat", k.birimFiyat);
        q.bindValue(":para", k.paraBirimi);
        q.bindValue(":kur", k.kur);
        q.bindValue(":fiyatTL", k.birimFiyatTL);
        q.bindValue(":toplamTL", k.toplamTL);
        q.bindValue(":tedarikci", metinParametresi(k.tedarikci));
        q.bindValue(":satinalma", k.sonSatinalmaId > 0 ? QVariant(k.sonSatinalmaId) : QVariant(QMetaType(QMetaType::Int)));
        q.bindValue(":tarih", k.fiyatTarihi.isValid() ? QVariant(k.fiyatTarihi) : QVariant(QMetaType(QMetaType::QDate)));
        q.bindValue(":sira", sira);
        q.bindValue(":aciklama", metinParametresi(k.aciklama));
        if (!q.exec())
            return geriAl("Reçete kalemi kaydedilemedi (" + k.ad + "): " + q.lastError().text());

        if (!guncelle)
        {
            eklenenler << k.ad;
        }
        else if (std::abs(eskiKalemler.value(k.id).birimFiyatTL - k.birimFiyatTL) > 0.005)
        {
            fiyatiDegisenler << k.ad;
            tekDegisen = &k;
            tekEskiBirimTL = eskiKalemler.value(k.id).birimFiyatTL;
        }
    }

    // ---- Maliyet gecmisi: kayit basina tek satir; yeni cihazda, toplam
    //      maliyet ya da kar orani degistiginde yazilir. ----
    const bool toplamDegisti = std::abs(yeniToplam - eskiToplam) > 0.005;
    const bool karDegisti = !yeniCihaz && std::abs(karOrani - eskiKar) > 0.005;
    if (yeniCihaz || toplamDegisti || karDegisti)
    {
        QStringList parcalar;
        if (yeniCihaz)
            parcalar << QStringLiteral("Cihaz oluşturuldu");
        if (!fiyatiDegisenler.isEmpty())
            parcalar << QStringLiteral("Fiyatı değişen: ") + fiyatiDegisenler.join(QStringLiteral(", "));
        if (!eklenenler.isEmpty() && !yeniCihaz)
            parcalar << QStringLiteral("Eklenen: ") + eklenenler.join(QStringLiteral(", "));
        if (!cikarilanlar.isEmpty())
            parcalar << QStringLiteral("Çıkarılan: ") + cikarilanlar.join(QStringLiteral(", "));
        if (karDegisti)
            parcalar << QStringLiteral("Kâr oranı %%1 → %%2")
                            .arg(QLocale(QLocale::Turkish).toString(eskiKar, 'f', 2),
                                 QLocale(QLocale::Turkish).toString(karOrani, 'f', 2));
        if (parcalar.isEmpty())
            parcalar << QStringLiteral("Adet / kur değişikliği");

        const bool tekFiyat = fiyatiDegisenler.size() == 1 && eklenenler.isEmpty() && cikarilanlar.isEmpty();
        QSqlQuery g(m_db);
        g.prepare("INSERT INTO dbo.cihaz_maliyet_gecmisi (CihazId, ReceteKalemId, DegisenKalemAdi, "
                  "  EskiBirimFiyatTL, YeniBirimFiyatTL, EskiToplamMaliyetTL, YeniToplamMaliyetTL, KarOrani, "
                  "  YeniSatisFiyatiTL, TedarikciAdi, SatinalmaId, KullaniciId, Aciklama) "
                  "VALUES (:cihaz, :kalem, :ad, :eskiBirim, :yeniBirim, :eskiToplam, :yeniToplam, :kar, "
                  "  :satis, :tedarikci, :satinalma, :kullanici, :aciklama)");
        g.bindValue(":cihaz", cihazId);
        g.bindValue(":kalem", tekFiyat ? QVariant(tekDegisen->id) : QVariant(QMetaType(QMetaType::Int)));
        g.bindValue(":ad", tekFiyat ? QVariant(tekDegisen->ad.left(300)) : QVariant(QMetaType(QMetaType::QString)));
        g.bindValue(":eskiBirim", tekFiyat ? QVariant(tekEskiBirimTL) : QVariant(QMetaType(QMetaType::Double)));
        g.bindValue(":yeniBirim", tekFiyat ? QVariant(tekDegisen->birimFiyatTL) : QVariant(QMetaType(QMetaType::Double)));
        g.bindValue(":eskiToplam", eskiToplam);
        g.bindValue(":yeniToplam", yeniToplam);
        g.bindValue(":kar", karOrani);
        g.bindValue(":satis", yeniSatis);
        g.bindValue(":tedarikci", tekFiyat ? metinParametresi(tekDegisen->tedarikci) : QVariant(QMetaType(QMetaType::QString)));
        g.bindValue(":satinalma", tekFiyat && tekDegisen->sonSatinalmaId > 0
                                      ? QVariant(tekDegisen->sonSatinalmaId) : QVariant(QMetaType(QMetaType::Int)));
        g.bindValue(":kullanici", m_aktifKullaniciId > 0 ? QVariant(m_aktifKullaniciId) : QVariant(QMetaType(QMetaType::Int)));
        g.bindValue(":aciklama", parcalar.join(QStringLiteral(" · ")).left(500));
        if (!g.exec())
            return geriAl("Maliyet geçmişi yazılamadı: " + g.lastError().text());
    }

    if (!m_db.commit())
        return geriAl("Cihaz kaydedilemedi: " + m_db.lastError().text());

    sonuc["basarili"] = true;
    sonuc["cihazId"] = cihazId;
    return sonuc;
}

QVariantMap Database::cihazAktifDurumDegistir(int cihazId, bool aktif)
{
    ERP_IZ("cihazAktifDurumDegistir");
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    if (!baglantiHazir())
    {
        sonuc["hata"] = "Veritabanına bağlanılamadı.";
        return sonuc;
    }
    if (!modulDuzenleyebilirMi(QStringLiteral("YONETIM")))
    {
        sonuc["hata"] = "Cihazı arşivleme yetkiniz yok.";
        return sonuc;
    }
    QSqlQuery q(m_db);
    q.prepare("UPDATE dbo.cihazlar SET AktifMi = :aktif, GuncellemeTarihi = SYSDATETIME() WHERE CihazId = :id");
    q.bindValue(":aktif", aktif);
    q.bindValue(":id", cihazId);
    if (!q.exec())
    {
        sonuc["hata"] = "Cihaz güncellenemedi: " + q.lastError().text();
        return sonuc;
    }
    sonuc["basarili"] = true;
    return sonuc;
}

QVariantList Database::cihazUrunAra(const QString &arama)
{
    QVariantList liste;
    const QString t = arama.trimmed();
    if (t.isEmpty() || !baglantiHazir())
        return liste;
    const bool aktifSutunu = semaKolonuVarMi(m_db, QStringLiteral("dbo.urunler"), QStringLiteral("AktifMi"));
    QSqlQuery q(m_db);
    q.prepare(QStringLiteral(
        "SELECT TOP 20 UrunId, UrunKodu, LEFT(UrunAciklamasi, 200), BirimFiyat, ParaBirimi "
        "FROM dbo.urunler "
        "WHERE (UrunKodu LIKE :d1 ESCAPE N'\\' OR UrunAciklamasi LIKE :d2 ESCAPE N'\\') "
        "  AND ISNULL(UrunKodu, N'') NOT LIKE N'MANUEL%' %1 "
        "ORDER BY UrunKodu").arg(aktifSutunu ? QStringLiteral("AND AktifMi = 1") : QString()));
    q.bindValue(":d1", likeDeseni(t));
    q.bindValue(":d2", likeDeseni(t));
    if (!q.exec())
    {
        qWarning() << "cihazUrunAra basarisiz:" << q.lastError().text();
        return liste;
    }
    while (q.next())
        liste << QVariantMap{ { "urunId", q.value(0).toInt() },
                              { "urunKodu", q.value(1).toString() },
                              { "urunAciklamasi", q.value(2).toString() },
                              { "birimFiyat", q.value(3).toDouble() },
                              { "paraBirimi", q.value(4).toString() } };
    return liste;
}
