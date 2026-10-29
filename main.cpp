#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>
#include <QElapsedTimer>
#include <QDebug>

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