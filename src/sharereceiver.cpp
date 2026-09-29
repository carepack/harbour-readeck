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

    // Claim the OrganizationName.ApplicationName the share sheet expects
    // (see harbour-readeck.desktop's [X-Sailjail] section) last: this is
    // what unblocks a pending D-Bus-activated call, so the object above
    // must already be registered by the time it can arrive.
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
