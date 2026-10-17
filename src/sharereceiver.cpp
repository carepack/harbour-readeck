#include "sharereceiver.h"

#include <QDBusConnection>
#include <QDBusArgument>
#include <QVariantList>
#include <QDebug>

namespace {

// Qt's D-Bus demarshalling of the share call's "a{sv}" argument into a
// QVariantMap converts each entry's key, but a value that is itself a
// nested container variant -- "resources" is "av" containing "av"
// containing "a{sv}" (see the header comment for the exact shape) --
// comes through as an opaque QDBusArgument rather than a native
// QVariantList/QVariantMap (confirmed by logging typeName() == "QDBusArgument"
// live against the real share call). This recursively unwraps it.
QVariant unwrapDBusArgument(const QVariant &value)
{
    if (value.userType() != qMetaTypeId<QDBusArgument>()) {
        return value;
    }
    const QDBusArgument arg = value.value<QDBusArgument>();
    // qdbus_cast (rather than hand-rolled beginArray()/endArray() calls)
    // for the container cases: manually interleaving a recursive
    // unwrapDBusArgument() call between beginArray() and endArray() on
    // the *same* argument corrupts its shared read position (observed
    // live as a "write from a read-only object" warning and empty
    // results, previously an outright segfault). qdbus_cast reads a
    // whole container in one call with correct scoping.
    switch (arg.currentType()) {
    case QDBusArgument::ArrayType: {
        QVariantList list;
        for (const QVariant &v : qdbus_cast<QVariantList>(arg)) {
            list << unwrapDBusArgument(v);
        }
        return list;
    }
    case QDBusArgument::MapType: {
        QVariantMap map;
        const QVariantMap raw = qdbus_cast<QVariantMap>(arg);
        for (auto it = raw.constBegin(); it != raw.constEnd(); ++it) {
            map[it.key()] = unwrapDBusArgument(it.value());
        }
        return map;
    }
    case QDBusArgument::VariantType: {
        QVariant inner;
        arg >> inner;
        return unwrapDBusArgument(inner);
    }
    default:
        return arg.asVariant();
    }
}

} // namespace

ShareReceiver::ShareReceiver(QObject *parent)
    : QObject(parent)
{
}

void ShareReceiver::registerService()
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    // registerObject needs a target QObject; it carries a ShareAdaptor
    // child that advertises the "org.sailfishos.share" interface
    // (registerObject defaults to exporting attached
    // QDBusAbstractAdaptor children). Created once and reused on repeat
    // calls -- registerObject() itself is safe to call again for the
    // same object/path, but creating a second target each time would
    // leak one QObject+ShareAdaptor pair per call.
    if (!m_target) {
        m_target = new QObject(this);
        new ShareAdaptor(m_target, this);
    }
    bus.registerObject(QStringLiteral("/share/link"), m_target);

    // Second interface on the same service (not a second service): the
    // freedesktop.org "D-Bus Activation" standard interface, at the
    // object path the spec derives from this service's own name
    // (harbour-readeck.harbour-readeck -> /harbour_readeck/harbour_readeck).
    // Lets the system's "open with" chooser activate this app for an
    // http/https link -- see AppActivationAdaptor and
    // harbour-readeck.desktop's MimeType/X-DBusActivatable.
    if (!m_appActivationTarget) {
        m_appActivationTarget = new QObject(this);
        new AppActivationAdaptor(m_appActivationTarget, this);
    }
    bus.registerObject(QStringLiteral("/harbour_readeck/harbour_readeck"), m_appActivationTarget);

    // Claim the OrganizationName.ApplicationName the share sheet expects
    // (see harbour-readeck.desktop's [X-Sailjail] section) last: this is
    // what unblocks a pending D-Bus-activated call, so the objects above
    // must already be registered by the time one can arrive.
    bus.registerService(QStringLiteral("harbour-readeck.harbour-readeck"));
}

void ShareReceiver::setReady()
{
    m_ready = true;
    if (m_hasPending) {
        m_hasPending = false;
        emit bookmarkShared(m_pendingUrl, m_pendingTitle);
    }
}

void ShareReceiver::handleShare(const QVariantMap &args)
{
    const QVariant resourcesRaw = args.value(QStringLiteral("resources"));
    qWarning("readeck share: resources raw typeName=%s", resourcesRaw.typeName());
    const QVariant resourcesUnwrapped = unwrapDBusArgument(resourcesRaw);
    qWarning("readeck share: resources unwrapped typeName=%s", resourcesUnwrapped.typeName());

    const QVariantList items = resourcesUnwrapped.toList();
    qWarning("readeck share: items.count=%d", items.count());
    if (items.isEmpty()) {
        qWarning("readeck share: items empty, aborting");
        return;
    }

    const QVariant firstRaw = items.first();
    qWarning("readeck share: items.first() raw typeName=%s", firstRaw.typeName());
    QVariant first = unwrapDBusArgument(firstRaw);
    qWarning("readeck share: items.first() unwrapped typeName=%s", first.typeName());

    QVariantMap resource;
    if (first.userType() == QVariant::Map) {
        // Primary, confirmed-live shape: each item in "resources" is the
        // resource dict directly, no further nesting.
        qWarning("readeck share: used direct-map path (no extra nesting)");
        resource = first.toMap();
    } else {
        // Fallback: tolerate one extra "av" wrapping layer, in case some
        // other sender double-wraps it the way an early hand-built test
        // call here did.
        const QVariantList nested = first.toList();
        qWarning("readeck share: variants.count=%d", nested.count());
        if (!nested.isEmpty()) {
            const QVariant second = unwrapDBusArgument(nested.first());
            qWarning("readeck share: nested.first() unwrapped typeName=%s", second.typeName());
            resource = second.toMap();
        } else if (first.canConvert(QVariant::Map)) {
            qWarning("readeck share: used fallback via canConvert(Map)");
            resource = first.toMap();
        } else {
            qWarning("readeck share: no usable resource shape found");
        }
    }

    qWarning() << "readeck share: resource keys=" << resource.keys();

    const QString url = resource.value(QStringLiteral("status")).toString();
    const QString title = resource.value(QStringLiteral("linkTitle")).toString();
    qWarning() << "readeck share: url=" << url << "title=" << title;
    if (url.isEmpty()) {
        qWarning("readeck share: url empty, aborting");
        return;
    }
    // This slot must return quickly regardless of QML's load state: the
    // share sheet's own call to us appears to give up if we don't answer
    // promptly when D-Bus activation had to cold-start the app, so the
    // page push is queued for setReady() rather than made to wait here.
    deliverOrQueue(url, title);
}

void ShareReceiver::handleOpen(const QString &url)
{
    // org.freedesktop.Application.Open has no standardized title field in
    // platformData, so unlike a share (which gets a title from the share
    // sheet's own call), an Open-delivered URL always arrives titleless --
    // matching how AddBookmarkPage's "Title (optional)" field already
    // tolerates an empty title.
    deliverOrQueue(url, QString());
}

void ShareReceiver::deliverOrQueue(const QString &url, const QString &title)
{
    if (m_ready) {
        qWarning("readeck share: emitting bookmarkShared immediately");
        emit bookmarkShared(url, title);
    } else {
        qWarning("readeck share: queueing (not ready yet)");
        m_pendingUrl = url;
        m_pendingTitle = title;
        m_hasPending = true;
    }
}

ShareAdaptor::ShareAdaptor(QObject *targetObject, ShareReceiver *receiver)
    : QDBusAbstractAdaptor(targetObject)
    , m_receiver(receiver)
{
}

void ShareAdaptor::share(const QVariantMap &args)
{
    m_receiver->handleShare(args);
}

AppActivationAdaptor::AppActivationAdaptor(QObject *targetObject, ShareReceiver *receiver)
    : QDBusAbstractAdaptor(targetObject)
    , m_receiver(receiver)
{
}

void AppActivationAdaptor::Open(const QStringList &uris, const QVariantMap &platformData)
{
    Q_UNUSED(platformData)
    for (const QString &uri : uris) {
        if (uri.startsWith(QStringLiteral("http://")) || uri.startsWith(QStringLiteral("https://"))) {
            m_receiver->handleOpen(uri);
            return;
        }
    }
}

void AppActivationAdaptor::Activate(const QVariantMap &platformData)
{
    Q_UNUSED(platformData)
    emit m_receiver->activateRequested();
}
