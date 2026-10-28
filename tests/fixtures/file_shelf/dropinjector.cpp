// Inject external-style Qt drag events at the real QQuickWindow boundary.
#include <QtCore/QCoreApplication>
#include <QtCore/QMimeData>
#include <QtCore/QVariantMap>
#include <QtGui/QDragEnterEvent>
#include <QtGui/QDragLeaveEvent>
#include <QtGui/QDropEvent>
#include <QtQml/QQmlExtensionPlugin>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

class DropInjector : public QObject {
    Q_OBJECT
    QMimeData mime;
public:
    Q_INVOKABLE bool enter(QQuickItem *item, const QStringList &uris, int actions) {
        mime.clear();
        QList<QUrl> urls;
        for (const auto &uri : uris) urls << QUrl(uri);
        mime.setUrls(urls);
        const QPoint position = item->mapToScene(QPointF(item->width()/2, item->height()/2)).toPoint();
        QDragEnterEvent enter(position, Qt::DropActions(actions), &mime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(item->window(), &enter);
        return enter.isAccepted();
    }
    Q_INVOKABLE void leave(QQuickItem *item) {
        QDragLeaveEvent event;
        QCoreApplication::sendEvent(item->window(), &event);
    }
    Q_INVOKABLE QVariantMap drop(QQuickItem *item, const QStringList &uris, int actions) {
        const bool entered = enter(item, uris, actions);
        const QPoint position = item->mapToScene(QPointF(item->width()/2, item->height()/2)).toPoint();
        QDropEvent event(position, Qt::DropActions(actions), &mime, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(item->window(), &event);
        return {{"entered", entered}, {"accepted", event.isAccepted()}, {"action", int(event.dropAction())}};
    }
};

class ShelfTestPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<DropInjector>(uri, 1, 0, "DropInjector"); }
};

#include "dropinjector.moc"
