#include <QCoreApplication>
#include <QGuiApplication>
#include <QIcon>
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
    app.setWindowIcon(QIcon(QStringLiteral(":/qt/qml/erp_programi/logo.png")));

    const QString gunlukYolu = gunlugeYazmayaBasla();
    qInfo() << "Gunluk dosyasi:" << gunlukYolu;
    uiIzleyicisiniBaslat();

    std::unique_ptr<QThread> yaziTipiIsitici(QThread::create([]() {
        QElapsedTimer olcum;
        olcum.start();

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