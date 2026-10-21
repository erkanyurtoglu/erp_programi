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

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

    QGuiApplication app(argc, argv);
    app.setOrganizationName("Liya");
    app.setApplicationName("Liya Teklif Programi (Qt)");

    // Donma sikayetlerinin kaynagini olcebilmek icin: gunluk dosyasi + arayuz
    // thread'ini izleyen "nabiz" kontrolu (bkz. src/Tanilama.h).
    const QString gunlukYolu = gunlugeYazmayaBasla();
    qInfo() << "Gunluk dosyasi:" << gunlukYolu;
    uiIzleyicisiniBaslat();

    // Acilis asamalarinin her biri ayri olculur: "program acilirken donuyor"
    // sikayetinde hangi adimin bekledigi gunlukten dogrudan okunsun.
    QElapsedTimer acilis;
    acilis.start();

    Database database;
    qInfo() << "[olcum] acilis: veritabani nesnesi" << acilis.restart() << "ms";

    // NOT: PDF motoru (QWebEnginePage -> Chromium) burada ONCEDEN hazirlanmiyor.
    // Olusturulmasi bu makinede ~5 saniye suruyor ve bu sure boyunca UI thread'i
    // tamamen bloke oluyordu: program her acilista, giris ekrani gorunmeden once
    // "Yanıt Vermiyor" durumunda bekliyordu (bkz. gunlukteki [DONMA] kayitlari).
    // Motor zaten ilk PDF olusturulurken kendiliginden hazirlaniyor
    // (TeklifPdfOlusturucu::motoruHazirla), yani maliyet ortadan kalkmiyor --
    // her acilistan, YALNIZCA PDF alan kullanicinin ilk PDF'ine kayiyor.
    PdfOnizleyici pdfOnizleyici;
    qInfo() << "[olcum] acilis: PdfOnizleyici" << acilis.restart() << "ms";

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("database", &database);
    engine.rootContext()->setContextProperty("pdfOnizleyici", &pdfOnizleyici);
    engine.addImageProvider("pdfsayfa", pdfOnizleyici.resimSaglayici());

    engine.loadFromModule("erp_programi", "Main");
    qInfo() << "[olcum] acilis: QML yuklendi" << acilis.restart() << "ms";

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}