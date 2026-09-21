#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <sailfishapp.h>
#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QTranslator>
#include <QLocale>

#include "readeckclient.h"
#include "bookmarklistmodel.h"
#include "sharereceiver.h"

int main(int argc, char *argv[])
{
    qmlRegisterType<BookmarkListModel>("harbour.readeck", 1, 0, "BookmarkListModel");

    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));

    // Loads translations/harbour-readeck-<locale>.qm matching the
    // system locale (falling back through e.g. "de_DE" -> "de" -> none,
    // in which case qsTr() calls just show their English source text).
    // Without this, only Silica's own stock UI strings follow the
    // system locale while this app's own text stays English regardless
    // -- an inconsistent mixed-language result, not a missing-file one.
    QTranslator translator;
    if (translator.load(QLocale::system(), QStringLiteral("harbour-readeck"), QStringLiteral("-"),
                         SailfishApp::pathTo(QStringLiteral("translations")).toLocalFile())) {
        app->installTranslator(&translator);
    }

    QScopedPointer<QQuickView> view(SailfishApp::createView());

    ReadeckClient readeckClient;
    view->rootContext()->setContextProperty("readeckClient", &readeckClient);

    ShareReceiver shareReceiver;
    view->rootContext()->setContextProperty("shareReceiver", &shareReceiver);

    // As early as possible, before the (comparatively slow) QML tree is
    // even parsed: the share sheet's call to us seems to give up if we
    // don't answer promptly when D-Bus activation had to cold-start the
    // app. A share arriving before QML is ready is queued rather than
    // lost -- see ShareReceiver::handleShare()/setReady().
    shareReceiver.registerService();

    view->setSource(SailfishApp::pathTo("qml/harbour-readeck.qml"));
    view->show();

    // QML's `Connections { target: shareReceiver }` now exists; flush
    // any share that arrived while it was still loading.
    shareReceiver.setReady();

    return app->exec();
}
