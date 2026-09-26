#include "PdfOnizleyici.h"

#include <QBuffer>
#include <QCoreApplication>
#include <QFile>
#include <QImage>
#include <QMutex>
#include <QMutexLocker>
#include <QPainter>
#include <QPdfDocument>
#include <QQuickAsyncImageProvider>
#include <QQuickImageResponse>
#include <QQuickTextureFactory>
#include <QRunnable>
#include <QThreadPool>
#include <cmath>
#include <unordered_map>

namespace {

// Acik bir belge. PDF dosyadan degil bellekten okunur: QPdfDocument dosyayi
// acik tutsaydi, pencere kapaninca gecici PDF (pdfOnizlemesiniSil) silinemezdi.
struct AcikBelge
{
    QByteArray veri;
    QBuffer tampon;
    QPdfDocument belge;

    explicit AcikBelge(QByteArray icerik) : veri(std::move(icerik))
    {
        tampon.setBuffer(&veri);
    }
};

// Belgeyi, ona son referansi tutan kim olursa olsun (QML'deki kapat() ya da
// o sirada cizim yapan is parcacigi) guvenle birakir: QPdfDocument bir QObject
// ve ana is parcaciginda olusturuldu, bu yuzden orada silinmeli.
std::shared_ptr<AcikBelge> belgeSarmala(AcikBelge *belge)
{
    return std::shared_ptr<AcikBelge>(belge, [](AcikBelge *b) {
        QMetaObject::invokeMethod(QCoreApplication::instance(), [b]() { delete b; }, Qt::QueuedConnection);
    });
}

} // namespace

// Acik belgeler; QML is parcacigi (ac/kapat) ile cizim is parcaciklari
// arasinda paylasilir.
struct PdfBelgeDeposu
{
    QMutex kilit;
    std::unordered_map<int, std::shared_ptr<AcikBelge>> belgeler;
    int sonAnahtar = 0;

    std::shared_ptr<AcikBelge> al(int anahtar)
    {
        QMutexLocker l(&kilit);
        const auto it = belgeler.find(anahtar);
        return it == belgeler.end() ? nullptr : it->second;
    }
};

namespace {

// Bir sayfanin cizimi: QThreadPool'da calisir, bitince finished() yayinlar.
// QPdfDocument::render pdfium'a erisimi kendi icinde kilitledigi icin
// is parcaciklarindan cagrilabilir; cizim tamamen islemcide yapilir.
class SayfaYaniti : public QQuickImageResponse, public QRunnable
{
public:
    SayfaYaniti(std::shared_ptr<PdfBelgeDeposu> depo, int anahtar, int sayfaNo, int genislik)
        : m_depo(std::move(depo)), m_anahtar(anahtar), m_sayfaNo(sayfaNo), m_genislik(genislik)
    {
        setAutoDelete(false); // yaniti QML motoru siler
    }

    QQuickTextureFactory *textureFactory() const override
    {
        return QQuickTextureFactory::textureFactoryForImage(m_resim);
    }

    QString errorString() const override { return m_hata; }

    void run() override
    {
        const std::shared_ptr<AcikBelge> acik = m_depo->al(m_anahtar);
        if (!acik || m_sayfaNo < 0 || m_sayfaNo >= acik->belge.pageCount()) {
            m_hata = QStringLiteral("Sayfa bulunamadı.");
        } else {
            const QSizeF olcu = acik->belge.pagePointSize(m_sayfaNo);
            const int genislik = qBound(100, m_genislik, 4000);
            const int yukseklik = olcu.width() > 0
                ? qMax(1, int(std::lround(genislik * olcu.height() / olcu.width())))
                : genislik;
            const QImage cizim = acik->belge.render(m_sayfaNo, QSize(genislik, yukseklik));
            if (cizim.isNull()) {
                m_hata = QStringLiteral("Sayfa çizilemedi.");
            } else {
                // pdfium arka plani saydam birakir; sayfa kagit gibi beyaz olsun.
                m_resim = QImage(cizim.size(), QImage::Format_RGB32);
                m_resim.fill(Qt::white);
                QPainter p(&m_resim);
                p.drawImage(0, 0, cizim);
            }
        }
        emit finished();
    }

private:
    std::shared_ptr<PdfBelgeDeposu> m_depo;
    int m_anahtar;
    int m_sayfaNo;
    int m_genislik;
    QImage m_resim;
    QString m_hata;
};

// "image://pdfsayfa/<anahtar>/<sayfaNo>" -> SayfaYaniti.
class PdfSayfaSaglayici : public QQuickAsyncImageProvider
{
public:
    explicit PdfSayfaSaglayici(std::shared_ptr<PdfBelgeDeposu> depo) : m_depo(std::move(depo))
    {
        // Ayni anda en fazla birkac sayfa: gorunen sayfalar once biter.
        m_havuz.setMaxThreadCount(3);
    }

    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &istenenBoyut) override
    {
        const QStringList parcalar = id.split('/');
        const int anahtar = parcalar.value(0).toInt();
        const int sayfaNo = parcalar.value(1).toInt();
        const int genislik = istenenBoyut.width() > 0 ? istenenBoyut.width() : 1200;
        auto *yanit = new SayfaYaniti(m_depo, anahtar, sayfaNo, genislik);
        m_havuz.start(yanit);
        return yanit;
    }

private:
    std::shared_ptr<PdfBelgeDeposu> m_depo;
    QThreadPool m_havuz;
};

} // namespace

PdfOnizleyici::PdfOnizleyici(QObject *parent)
    : QObject(parent), m_depo(std::make_shared<PdfBelgeDeposu>())
{
}

PdfOnizleyici::~PdfOnizleyici() = default;

QVariantMap PdfOnizleyici::ac(const QString &yol)
{
    QVariantMap sonuc;
    sonuc["basarili"] = false;
    sonuc["anahtar"] = -1;
    sonuc["sayfalar"] = QVariantList();
    sonuc["hata"] = QString();

    QFile dosya(yol);
    if (!dosya.open(QIODevice::ReadOnly)) {
        sonuc["hata"] = dosya.errorString();
        return sonuc;
    }

    const std::shared_ptr<AcikBelge> acik = belgeSarmala(new AcikBelge(dosya.readAll()));
    dosya.close();

    // Bellekteki (rastgele erisimli) kaynaktan yukleme senkron tamamlanir.
    acik->tampon.open(QIODevice::ReadOnly);
    acik->belge.load(&acik->tampon);
    if (acik->belge.status() != QPdfDocument::Status::Ready) {
        sonuc["hata"] = QStringLiteral("PDF açılamadı (hata kodu %1).")
                            .arg(int(acik->belge.error()));
        return sonuc;
    }

    QVariantList sayfalar;
    for (int i = 0; i < acik->belge.pageCount(); ++i)
    {
        const QSizeF olcu = acik->belge.pagePointSize(i);
        QVariantMap s;
        s["genislik"] = olcu.width();
        s["yukseklik"] = olcu.height();
        sayfalar.append(s);
    }

    int anahtar;
    {
        QMutexLocker l(&m_depo->kilit);
        anahtar = ++m_depo->sonAnahtar;
        m_depo->belgeler.emplace(anahtar, acik);
    }
    sonuc["basarili"] = true;
    sonuc["anahtar"] = anahtar;
    sonuc["sayfalar"] = sayfalar;
    return sonuc;
}

void PdfOnizleyici::kapat(int anahtar)
{
    QMutexLocker l(&m_depo->kilit);
    m_depo->belgeler.erase(anahtar);
}

QQuickImageProvider *PdfOnizleyici::resimSaglayici() const
{
    return new PdfSayfaSaglayici(m_depo);
}
