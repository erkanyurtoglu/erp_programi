#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickImageProvider>

#include "src/Database.h"
#include "src/PdfOnizleyici.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

    QGuiApplication app(argc, argv);
    app.setOrganizationName("Liya");
    app.setApplicationName("Liya Teklif Programi (Qt)");

    Database database;
    // Chromium'u pencere acilmadan hazirla: aksi halde ilk PDF butonunda
    // ~2 sn arayuz donuyordu. Acilisa eklenen sure, ekranda bir sey yokken gecer.
    database.pdfMotorunuHazirla();
    PdfOnizleyici pdfOnizleyici;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("database", &database);
    engine.rootContext()->setContextProperty("pdfOnizleyici", &pdfOnizleyici);
    engine.addImageProvider("pdfsayfa", pdfOnizleyici.resimSaglayici());

    engine.loadFromModule("erp_programi", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
