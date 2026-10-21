#include "Tanilama.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QMutex>
#include <QRecursiveMutex>
#include <QStandardPaths>
#include <QTextStream>
#include <QThread>
#include <QTimer>

std::atomic<const char *> g_aktifUiIslem{nullptr};

namespace
{
    QFile g_gunlukDosyasi;
    // RECURSIVE: yazma yolunda (QFile/QTextStream) Qt'nin kendisi bir uyari
    // basarsa yakalayici AYNI thread'de yeniden cagrilir. Duz bir QMutex ile
    // bu, kendi kendini kilitleyip gunlugu tamamen susturan bir deadlock'a
    // donusuyordu: ilk oturumdan sonraki calistirmalarda dosyaya yalnizca
    // "Yeni oturum" satiri yazilip gerisi hic gorunmuyordu.
    QRecursiveMutex g_gunlukKilidi;
    QtMessageHandler g_oncekiYakalayici = nullptr;

    // Yeniden girisi tamamen kessin: bir mesaji yazarken olusan mesaj yok sayilir.
    thread_local bool g_yaziyor = false;

    // Uygulama basindan beri gecen sure; izleyici ile UI thread'i ayni saati
    // kullansin diye tek bir monoton sayac paylasilir.
    QElapsedTimer &saat()
    {
        static QElapsedTimer s;
        if (!s.isValid())
            s.start();
        return s;
    }

    // UI thread'inin en son "yasiyorum" dedigi an (saat() cinsinden ms).
    std::atomic<qint64> g_sonDarbe{0};

    void mesajYakalayici(QtMsgType tur, const QMessageLogContext &baglam, const QString &mesaj)
    {
        if (g_yaziyor)
            return;                       // yazarken olusan mesaj -- yok say
        g_yaziyor = true;
        struct Bayrak { ~Bayrak() { g_yaziyor = false; } } bayrak;

        if (g_oncekiYakalayici)
            g_oncekiYakalayici(tur, baglam, mesaj);

        const char *etiket = "BILGI";
        switch (tur)
        {
        case QtDebugMsg:    etiket = "AYIKLA"; break;
        case QtInfoMsg:     etiket = "BILGI";  break;
        case QtWarningMsg:  etiket = "UYARI";  break;
        case QtCriticalMsg: etiket = "KRITIK"; break;
        case QtFatalMsg:    etiket = "OLUMCUL"; break;
        }

        QMutexLocker kilit(&g_gunlukKilidi);
        if (!g_gunlukDosyasi.isOpen())
            return;
        QTextStream akis(&g_gunlukDosyasi);
        akis.setEncoding(QStringConverter::Utf8);
        akis << QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss.zzz")
             << " [" << etiket << "] " << mesaj << '\n';
        akis.flush();
    }
}

QString gunlugeYazmayaBasla()
{
    saat();

    const QString klasor = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(klasor);
    const QString yol = klasor + QStringLiteral("/erp_gunluk.txt");

    QMutexLocker kilit(&g_gunlukKilidi);
    g_gunlukDosyasi.setFileName(yol);
    // Append: onceki calistirmalarin kayitlari da kalsin (sikayet sonradan gelir).
    if (!g_gunlukDosyasi.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text))
        return QString();

    QTextStream akis(&g_gunlukDosyasi);
    akis.setEncoding(QStringConverter::Utf8);
    akis << "\n==== Yeni oturum: "
         << QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss") << " ====\n";
    akis.flush();

    g_oncekiYakalayici = qInstallMessageHandler(mesajYakalayici);
    return yol;
}

void uiIzleyicisiniBaslat(int beklemeEsigiMs)
{
    saat();
    g_sonDarbe.store(saat().elapsed(), std::memory_order_relaxed);

    // UI thread'inin nabzi: olay dongusu calistigi surece bu timer tetiklenir.
    // Olay dongusu bloke olursa (senkron bir SQL sorgusu, agir bir hesap, ...)
    // tetiklenemez ve izleyici bunu fark eder.
    auto *nabiz = new QTimer(QCoreApplication::instance());
    nabiz->setInterval(100);
    QObject::connect(nabiz, &QTimer::timeout, QCoreApplication::instance(), []() {
        g_sonDarbe.store(saat().elapsed(), std::memory_order_relaxed);
    });
    nabiz->start();

    auto *izleyici = QThread::create([beklemeEsigiMs]() {
        bool takildi = false;
        qint64 takilmaBasi = 0;
        const char *takilmaIslemi = nullptr;

        while (!QThread::currentThread()->isInterruptionRequested())
        {
            QThread::msleep(100);
            const qint64 simdi = saat().elapsed();
            const qint64 sessizlik = simdi - g_sonDarbe.load(std::memory_order_relaxed);

            if (!takildi && sessizlik > beklemeEsigiMs)
            {
                takildi = true;
                takilmaBasi = simdi - sessizlik;
                takilmaIslemi = g_aktifUiIslem.load(std::memory_order_relaxed);
                qWarning().nospace()
                    << "[DONMA] Arayuz " << sessizlik << " ms'dir cevap vermiyor. O anki islem: "
                    << (takilmaIslemi ? takilmaIslemi : "(veritabani disi bir is)");
            }
            else if (takildi && sessizlik <= beklemeEsigiMs)
            {
                takildi = false;
                qWarning().nospace()
                    << "[DONMA] Arayuz cozuldu. Toplam donma: " << (simdi - takilmaBasi)
                    << " ms. Sorumlu islem: "
                    << (takilmaIslemi ? takilmaIslemi : "(veritabani disi bir is)");
            }
        }
    });
    QObject::connect(QCoreApplication::instance(), &QCoreApplication::aboutToQuit, izleyici, [izleyici]() {
        izleyici->requestInterruption();
        izleyici->quit();
        izleyici->wait(1000);
    });
    izleyici->start();
}

ErpIslemIzi::ErpIslemIzi(const char *ad)
    : m_ad(ad)
    , m_onceki(nullptr)
    , m_uiThreadi(QCoreApplication::instance()
                  && QThread::currentThread() == QCoreApplication::instance()->thread())
    , m_baslangicNs(saat().nsecsElapsed())
{
    // Yalnizca UI thread'indeki cagrilar izlenir: donmaya sebep olabilen
    // (arayuzu bekleten) cagrilar bunlardir. Worker thread'indeki sorgular
    // zaten tasarim geregi uzun surebilir.
    if (m_uiThreadi)
    {
        m_onceki = g_aktifUiIslem.load(std::memory_order_relaxed);
        g_aktifUiIslem.store(m_ad, std::memory_order_relaxed);
    }
}

ErpIslemIzi::~ErpIslemIzi()
{
    if (!m_uiThreadi)
        return;

    const qint64 sureMs = (saat().nsecsElapsed() - m_baslangicNs) / 1000000;
    g_aktifUiIslem.store(m_onceki, std::memory_order_relaxed);

    // Ic ice cagrilarda (ör. teklifSil -> teklifNoGetir) yalnizca EN DISTAKI
    // yavas cagri raporlanir; gunluk ayni donmayi onlarca kez tekrarlamasin.
    if (sureMs >= 300 && m_onceki == nullptr)
        qWarning().nospace() << "[YAVAS] Arayuz thread'inde '" << m_ad << "' " << sureMs << " ms surdu.";
}
