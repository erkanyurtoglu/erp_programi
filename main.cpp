#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QElapsedTimer>
#include <QDebug>
#include <QFont>
#include <QScopeGuard>
#include <QTextLayout>
#include <QThread>

#include <memory>

#include "src/Database.h"
#include "src/PdfOnizleyici.h"
#include "src/Tanilama.h"
#include "src/KurServisi.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

    QGuiApplication app(argc, argv);
    app.setOrganizationName("Liya");
    app.setApplicationName("Liya Teklif Programi (Qt)");

    const QString gunlukYolu = gunlugeYazmayaBasla();
    qInfo() << "Gunluk dosyasi:" << gunlukYolu;
    uiIzleyicisiniBaslat();

    // Arayuzdeki semboller (◀ ✕ ✓ 🔒 ...) Segoe UI'da yok. Qt bunlar icin ilk
    // seferde Windows'taki tum yedek yazi tiplerini tek tek okur (~300 ms,
    // Debug'da daha uzun) ve bu, sembollu ilk sayfa (Teklif Ver, teklif
    // listeleri) acilirken UI thread'ini donduruyordu. Sonuc tum thread'lerin
    // paylastigi yazi tipi veritabanina yazildigi icin sorgu burada, acilisla
    // paralel bir thread'de bir kez tetiklenir.
    std::unique_ptr<QThread> yaziTipiIsitici(QThread::create([]() {
        QElapsedTimer olcum;
        olcum.start();
        // Aile adi Theme.qml'deki fontAilesi ile ayni olmali.
        QTextLayout yerlesim(QStringLiteral(u"◀✕✓"), QFont(QStringLiteral("Segoe UI")));
        yerlesim.beginLayout();
        yerlesim.createLine();
        yerlesim.endLayout();
        qInfo() << "[olcum] yedek yazi tipi isitmasi:" << olcum.elapsed() << "ms";
    }));
    yaziTipiIsitici->start();
    const auto isiticiyiBekle = qScopeGuard([&]() { yaziTipiIsitici->wait(); });

    QElapsedTimer acilis;
    acilis.start();

    Database database;
    qInfo() << "[olcum] acilis: veritabani nesnesi" << acilis.restart() << "ms";

    PdfOnizleyici pdfOnizleyici;
    qInfo() << "[olcum] acilis: PdfOnizleyici" << acilis.restart() << "ms";

    KurServisi kurServisi;
    kurServisi.yenile();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("database", &database);
    engine.rootContext()->setContextProperty("pdfOnizleyici", &pdfOnizleyici);
    engine.rootContext()->setContextProperty("kurServisi", &kurServisi);
    engine.addImageProvider("pdfsayfa", pdfOnizleyici.resimSaglayici());

    engine.loadFromModule("erp_programi", "Main");
    qInfo() << "[olcum] acilis: QML yuklendi" << acilis.restart() << "ms";

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}