#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

#include "src/Database.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

    QGuiApplication app(argc, argv);
    app.setOrganizationName("Liya");
    app.setApplicationName("Liya Teklif Programi (Qt)");

    Database database;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("database", &database);

    engine.loadFromModule("erp_programi", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}

