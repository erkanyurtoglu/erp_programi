#include "Tanilama.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QMutex>
#include <QRecursiveMutex>
#include <QStandardPaths>
#include <QTextStream>
#include <QThread>
#include <QTimer>

#ifdef Q_OS_WIN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <dbghelp.h>
#endif

std::atomic<const char *> g_aktifUiIslem{nullptr};

namespace
{
#if defined(Q_OS_WIN) && defined(_M_X64)
    // UI thread'inin tutamaci; izleyici donma aninda onu kisa sure durdurup
    // cagri yiginini okur. "(veritabani disi bir is)" diye gecen donmalarin
    // (QML, cizim, Windows API...) gercek sebebini gormek icin.
    HANDLE g_uiThreadTutamaci = nullptr;

    // Thread askidayken YALNIZCA bellek ayirmayan islemler yapilir (askidaki
    // thread heap kilidini tutuyor olabilir): adresler sabit diziye alinir,
    // semboller thread devam ettikten sonra cozulur.
    void uiYiginiYaz(qint64 sessizlikMs)
    {
        if (!g_uiThreadTutamaci)
            return;

        constexpr int AZAMI_CERCEVE = 40;
        DWORD64 adresler[AZAMI_CERCEVE];
        int cerceveSayisi = 0;

        if (SuspendThread(g_uiThreadTutamaci) == static_cast<DWORD>(-1))
            return;
        CONTEXT baglam{};
        baglam.ContextFlags = CONTEXT_FULL;
        if (GetThreadContext(g_uiThreadTutamaci, &baglam))
        {
            while (cerceveSayisi < AZAMI_CERCEVE && baglam.Rip != 0)
            {
                adresler[cerceveSayisi++] = baglam.Rip;
                DWORD64 tabanAdres = 0;
                PRUNTIME_FUNCTION fonksiyon = RtlLookupFunctionEntry(baglam.Rip, &tabanAdres, nullptr);
                if (!fonksiyon)
                {
                    // Yaprak fonksiyon: donus adresi yiginin tepesindedir.
                    baglam.Rip = *reinterpret_cast<DWORD64 *>(baglam.Rsp);
                    baglam.Rsp += 8;
                    continue;
                }
                PVOID isleyiciVerisi = nullptr;
                DWORD64 cerceveAdresi = 0;
                RtlVirtualUnwind(UNW_FLAG_NHANDLER, tabanAdres, baglam.Rip, fonksiyon, &baglam,
                                 &isleyiciVerisi, &cerceveAdresi, nullptr);
            }
        }
        ResumeThread(g_uiThreadTutamaci);

        static bool semboller = false;
        if (!semboller)
        {
            SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS | SYMOPT_LOAD_LINES);
            semboller = SymInitialize(GetCurrentProcess(), nullptr, TRUE);
        }

        QString metin = QStringLiteral("[DONMA] %1 ms -- arayuz thread'inin cagri yigini:").arg(sessizlikMs);
        for (int i = 0; i < cerceveSayisi; ++i)
        {
            alignas(SYMBOL_INFO) char tampon[sizeof(SYMBOL_INFO) + 256];
            auto *sembol = reinterpret_cast<SYMBOL_INFO *>(tampon);
            sembol->SizeOfStruct = sizeof(SYMBOL_INFO);
            sembol->MaxNameLen = 255;
            DWORD64 kayma = 0;

            char modulYolu[MAX_PATH] = {};
            HMODULE modul = nullptr;
            if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
                                   | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                                   reinterpret_cast<LPCSTR>(adresler[i]), &modul))
                GetModuleFileNameA(modul, modulYolu, MAX_PATH);
            const QString modulAdi = QFileInfo(QString::fromLocal8Bit(modulYolu)).fileName();

            QString ad = semboller && SymFromAddr(GetCurrentProcess(), adresler[i], &kayma, sembol)
                ? QString::fromLatin1(sembol->Name) : QStringLiteral("?");
            IMAGEHLP_LINE64 satir{};
            satir.SizeOfStruct = sizeof(satir);
            DWORD satirKaymasi = 0;
            if (semboller && SymGetLineFromAddr64(GetCurrentProcess(), adresler[i], &satirKaymasi, &satir))
                ad += QStringLiteral("  (%1:%2)").arg(QFileInfo(QString::fromLocal8Bit(satir.FileName)).fileName())
                                                .arg(satir.LineNumber);
            metin += QStringLiteral("\n    #%1 %2!%3").arg(i, 2).arg(modulAdi, ad);
        }
        qWarning().noquote() << metin;
    }
#endif

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

#if defined(Q_OS_WIN) && defined(_M_X64)
    // Bu fonksiyon UI thread'inde cagrilir (main.cpp).
    g_uiThreadTutamaci = OpenThread(THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION,
                                    FALSE, GetCurrentThreadId());
#endif

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
        // Uzun donmada yigin 2 sn'de bir kez, sonra 5 sn arayla (en fazla 4 kez)
        // yazilir: ayni yerde mi bekliyor, ilerliyor mu, gorulsun.
        qint64 sonrakiYiginMs = 0;
        int yiginSayisi = 0;

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
                sonrakiYiginMs = 2000;
                yiginSayisi = 0;
                qWarning().nospace()
                    << "[DONMA] Arayuz " << sessizlik << " ms'dir cevap vermiyor. O anki islem: "
                    << (takilmaIslemi ? takilmaIslemi : "(veritabani disi bir is)");
            }
#if defined(Q_OS_WIN) && defined(_M_X64)
            else if (takildi && sessizlik >= sonrakiYiginMs && yiginSayisi < 4)
            {
                uiYiginiYaz(sessizlik);
                ++yiginSayisi;
                sonrakiYiginMs = sessizlik + 5000;
            }
#endif
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
