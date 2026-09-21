#include "readeckclient.h"

#include <functional>

#include <QCoreApplication>
#include <QSettings>
#include <QJsonArray>
#include <QJsonParseError>
#include <QHttpMultiPart>
#include <QUuid>
#include <QDateTime>

namespace {
// Sailfish OS ships Qt 5.6, which predates QNetworkAccessManager::sendCustomRequest()
// (added in Qt 5.8). This override reproduces the same mechanism manually so the
// Readeck API's PATCH-based bookmark updates keep working on stock SDK targets.
class PatchCapableNetworkAccessManager : public QNetworkAccessManager
{
public:
    explicit PatchCapableNetworkAccessManager(QObject *parent) : QNetworkAccessManager(parent) {}

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoingData) override
    {
        if (request.attribute(QNetworkRequest::CustomVerbAttribute).isValid()) {
            return QNetworkAccessManager::createRequest(CustomOperation, request, outgoingData);
        }
        return QNetworkAccessManager::createRequest(op, request, outgoingData);
    }
};
}

ReadeckClient::ReadeckClient(QObject *parent)
    : QObject(parent)
    , m_manager(new PatchCapableNetworkAccessManager(this))
    , m_busy(false)
    , m_unreadCount(0)
    , m_coverIndex(0)
    , m_coverSelectionPending(false)
{
    QCoreApplication::setOrganizationName(QStringLiteral("harbour-readeck"));
    QCoreApplication::setApplicationName(QStringLiteral("harbour-readeck"));

    restoreSession();

    connect(&m_oauthPollTimer, &QTimer::timeout, this, &ReadeckClient::pollOAuthLogin);
}

QString ReadeckClient::endpoint() const { return m_endpoint; }
QString ReadeckClient::username() const { return m_username; }
bool ReadeckClient::isLoggedIn() const { return !m_token.isEmpty() && !m_endpoint.isEmpty(); }
bool ReadeckClient::busy() const { return m_busy; }
QString ReadeckClient::lastError() const { return m_lastError; }
int ReadeckClient::unreadCount() const { return m_unreadCount; }
QVariantList ReadeckClient::coverBookmarks() const { return m_coverBookmarks; }
int ReadeckClient::coverIndex() const { return m_coverIndex; }
bool ReadeckClient::coverSelectionPending() const { return m_coverSelectionPending; }
bool ReadeckClient::oauthInProgress() const { return m_oauthInProgress; }
QString ReadeckClient::oauthUserCode() const { return m_oauthUserCode; }

void ReadeckClient::setCoverSelectionPending(bool pending)
{
    if (m_coverSelectionPending == pending) {
        return;
    }
    m_coverSelectionPending = pending;
    emit coverSelectionPendingChanged();
}

void ReadeckClient::setBusy(bool busy)
{
    if (m_busy == busy) {
        return;
    }
    m_busy = busy;
    emit busyChanged();
}

void ReadeckClient::setLastError(const QString &error)
{
    m_lastError = error;
    emit lastErrorChanged();
}

void ReadeckClient::persistSession()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("session"));
    settings.setValue(QStringLiteral("endpoint"), m_endpoint);
    settings.setValue(QStringLiteral("username"), m_username);
    settings.setValue(QStringLiteral("token"), m_token);
    settings.endGroup();
}

void ReadeckClient::restoreSession()
{
    QSettings settings;
    settings.beginGroup(QStringLiteral("session"));
    m_endpoint = settings.value(QStringLiteral("endpoint")).toString();
    m_username = settings.value(QStringLiteral("username")).toString();
    m_token = settings.value(QStringLiteral("token")).toString();
    settings.endGroup();
}

QString ReadeckClient::normalizeEndpoint(const QString &input)
{
    QString trimmed = input.trimmed();
    while (trimmed.endsWith('/')) {
        trimmed.chop(1);
    }
    if (trimmed.isEmpty()) {
        return trimmed;
    }
    if (!trimmed.startsWith(QStringLiteral("http://")) && !trimmed.startsWith(QStringLiteral("https://"))) {
        trimmed.prepend(QStringLiteral("https://"));
    }
    return trimmed;
}

QString ReadeckClient::encodeIdSegment(const QString &id)
{
    // Bookmark IDs are always server-generated, but they still end up spliced
    // directly into a URL path below: percent-encode defensively so a stray
    // '/', '?', '#' or space can never reshape the request's path or query.
    return QString::fromUtf8(QUrl::toPercentEncoding(id));
}

QString ReadeckClient::apiUrl(const QString &path) const
{
    return m_endpoint + QStringLiteral("/api") + path;
}

QNetworkRequest ReadeckClient::buildRequest(const QString &path, const QUrlQuery &query) const
{
    QUrl url(apiUrl(path));
    if (!query.isEmpty()) {
        url.setQuery(query);
    }
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setRawHeader("Accept", "application/json");
    if (!m_token.isEmpty()) {
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_token.toUtf8());
    }
    return request;
}

QString ReadeckClient::extractErrorMessage(QNetworkReply *reply, const QByteArray &body)
{
    QJsonParseError parseError;
    QJsonDocument doc = QJsonDocument::fromJson(body, &parseError);
    if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
        const QJsonObject obj = doc.object();
        if (obj.contains(QStringLiteral("message"))) {
            const QString message = obj.value(QStringLiteral("message")).toString();
            if (!message.isEmpty()) {
                return message;
            }
        }
        if (obj.contains(QStringLiteral("errors")) && obj.value(QStringLiteral("errors")).isArray()) {
            QStringList errors;
            for (const QJsonValue &v : obj.value(QStringLiteral("errors")).toArray()) {
                errors << v.toString();
            }
            if (!errors.isEmpty()) {
                return errors.join(QStringLiteral(", "));
            }
        }
    }
    return reply->errorString();
}

QVariantMap ReadeckClient::bookmarkToVariant(const QJsonObject &obj)
{
    QVariantMap map = obj.toVariantMap();

    const QJsonObject resources = obj.value(QStringLiteral("resources")).toObject();
    const QJsonObject thumbnail = resources.value(QStringLiteral("thumbnail")).toObject();
    const QJsonObject image = resources.value(QStringLiteral("image")).toObject();
    const QJsonObject icon = resources.value(QStringLiteral("icon")).toObject();

    QString imageUrl = thumbnail.value(QStringLiteral("src")).toString();
    if (imageUrl.isEmpty()) {
        imageUrl = image.value(QStringLiteral("src")).toString();
    }
    map[QStringLiteral("imageUrl")] = imageUrl;
    map[QStringLiteral("iconUrl")] = icon.value(QStringLiteral("src")).toString();

    QStringList labels;
    for (const QJsonValue &v : obj.value(QStringLiteral("labels")).toArray()) {
        labels << v.toString();
    }
    map[QStringLiteral("labels")] = labels;
    map[QStringLiteral("labelsText")] = labels.join(QStringLiteral(", "));

    QStringList authors;
    for (const QJsonValue &v : obj.value(QStringLiteral("authors")).toArray()) {
        authors << v.toString();
    }
    map[QStringLiteral("authorsText")] = authors.join(QStringLiteral(", "));

    return map;
}

void ReadeckClient::loginWithToken(const QString &endpoint, const QString &token)
{
    // Manual fallback for servers predating Readeck 0.21 (no OAuth
    // support): a personal API token created in the web UI (Profile ->
    // API tokens), pasted here.
    const QString normalized = normalizeEndpoint(endpoint);
    const QString trimmedToken = token.trimmed();
    if (normalized.isEmpty() || trimmedToken.isEmpty()) {
        emit loginFailed(tr("Please fill in the server address and API token."));
        return;
    }
    setBusy(true);
    setLastError(QString());
    finishLogin(normalized, trimmedToken);
}

void ReadeckClient::startOAuthLogin(const QString &endpoint)
{
    // Browser-based login via Readeck's OAuth2 Device Code flow (see
    // https://readeck.org/en/docs/external-auth). Readeck OAuth clients
    // are ephemeral and must be re-registered for every login attempt
    // (valid 10 minutes), so step one is always a fresh client
    // registration -- there is no client_id to reuse across logins.
    const QString normalized = normalizeEndpoint(endpoint);
    if (normalized.isEmpty()) {
        emit loginFailed(tr("Please enter a server address."));
        return;
    }

    setBusy(true);
    setLastError(QString());

    QJsonObject body;
    body[QStringLiteral("client_name")] = QStringLiteral("Readeck for Sailfish");
    body[QStringLiteral("client_uri")] = QStringLiteral("https://github.com/carepack/harbour-readeck");
    // QUuid::WithoutBraces was only added in Qt 5.11; Sailfish OS ships
    // Qt 5.6, so the braces are stripped by hand instead.
    body[QStringLiteral("software_id")] = QUuid::createUuid().toString().remove(QLatin1Char('{')).remove(QLatin1Char('}'));
    body[QStringLiteral("software_version")] = QStringLiteral("0.1.0");
    QJsonArray grantTypes;
    grantTypes.append(QStringLiteral("urn:ietf:params:oauth:grant-type:device_code"));
    body[QStringLiteral("grant_types")] = grantTypes;

    QNetworkRequest request(QUrl(normalized + QStringLiteral("/api/oauth/client")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, normalized]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() != QNetworkReply::NoError) {
            setBusy(false);
            emit loginFailed(tr("This server doesn't support browser login (needs Readeck 0.21+). "
                                 "Use \"Sign in with an API token\" instead."));
            reply->deleteLater();
            return;
        }
        const QString clientId = QJsonDocument::fromJson(raw).object().value(QStringLiteral("client_id")).toString();
        if (clientId.isEmpty()) {
            setBusy(false);
            emit loginFailed(tr("Unexpected response from server."));
            reply->deleteLater();
            return;
        }
        m_oauthClientId = clientId;
        requestDeviceCode(normalized);
        reply->deleteLater();
    });
}

void ReadeckClient::requestDeviceCode(const QString &endpoint)
{
    QJsonObject body;
    body[QStringLiteral("client_id")] = m_oauthClientId;
    body[QStringLiteral("scope")] = QStringLiteral("bookmarks:read bookmarks:write profile:read");

    QNetworkRequest request(QUrl(endpoint + QStringLiteral("/api/oauth/device")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, endpoint]() {
        const QByteArray raw = reply->readAll();
        setBusy(false);
        if (reply->error() != QNetworkReply::NoError) {
            emit loginFailed(extractErrorMessage(reply, raw));
            reply->deleteLater();
            return;
        }

        const QJsonObject obj = QJsonDocument::fromJson(raw).object();
        const QString deviceCode = obj.value(QStringLiteral("device_code")).toString();
        const QString verificationUrl = obj.value(QStringLiteral("verification_uri_complete")).toString();
        const int expiresIn = obj.value(QStringLiteral("expires_in")).toInt(300);
        const int interval = qMax(1, obj.value(QStringLiteral("interval")).toInt(5));

        if (deviceCode.isEmpty() || verificationUrl.isEmpty()) {
            emit loginFailed(tr("Unexpected response from server."));
            reply->deleteLater();
            return;
        }

        m_oauthDeviceCode = deviceCode;
        m_oauthUserCode = obj.value(QStringLiteral("user_code")).toString();
        m_oauthEndpoint = endpoint;
        m_oauthExpiresAtMs = QDateTime::currentMSecsSinceEpoch() + qint64(expiresIn) * 1000;
        m_oauthInProgress = true;
        emit oauthInProgressChanged();
        emit oauthUserCodeChanged();

        m_oauthPollTimer.setInterval(interval * 1000);
        m_oauthPollTimer.start();
        emit oauthLoginUrlReady(verificationUrl);
        reply->deleteLater();
    });
}

void ReadeckClient::pollOAuthLogin()
{
    if (!m_oauthInProgress) {
        return;
    }
    if (QDateTime::currentMSecsSinceEpoch() > m_oauthExpiresAtMs) {
        cancelOAuthLogin();
        emit loginFailed(tr("Login request expired. Please try again."));
        return;
    }

    QJsonObject body;
    body[QStringLiteral("grant_type")] = QStringLiteral("urn:ietf:params:oauth:grant-type:device_code");
    body[QStringLiteral("device_code")] = m_oauthDeviceCode;
    body[QStringLiteral("client_id")] = m_oauthClientId;

    QNetworkRequest request(QUrl(m_oauthEndpoint + QStringLiteral("/api/oauth/token")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject obj = QJsonDocument::fromJson(raw).object();

        if (status == 201) {
            const QString accessToken = obj.value(QStringLiteral("access_token")).toString();
            const QString endpoint = m_oauthEndpoint;
            cancelOAuthLogin();
            if (accessToken.isEmpty()) {
                emit loginFailed(tr("Unexpected response while completing login."));
            } else {
                setBusy(true);
                finishLogin(endpoint, accessToken);
            }
            reply->deleteLater();
            return;
        }

        // A 400 with "authorization_pending" or "slow_down" just means
        // "keep waiting" -- anything else ends the attempt.
        const QString error = obj.value(QStringLiteral("error")).toString();
        if (error != QStringLiteral("authorization_pending") && error != QStringLiteral("slow_down")) {
            cancelOAuthLogin();
            if (error == QStringLiteral("access_denied")) {
                emit loginFailed(tr("You declined the login request."));
            } else if (error == QStringLiteral("expired_token")) {
                emit loginFailed(tr("Login request expired. Please try again."));
            } else {
                const QString message = obj.value(QStringLiteral("error_description")).toString();
                emit loginFailed(message.isEmpty() ? extractErrorMessage(reply, raw) : message);
            }
        }
        reply->deleteLater();
    });
}

void ReadeckClient::cancelOAuthLogin()
{
    m_oauthPollTimer.stop();
    setBusy(false);
    m_oauthInProgress = false;
    m_oauthClientId.clear();
    m_oauthDeviceCode.clear();
    m_oauthUserCode.clear();
    m_oauthEndpoint.clear();
    emit oauthInProgressChanged();
    emit oauthUserCodeChanged();
}

void ReadeckClient::finishLogin(const QString &endpoint, const QString &token)
{
    // Verifies the token by calling GET /api/profile, which every valid
    // Bearer token can read -- shared by both the OAuth flow (the token
    // is an opaque access_token by then, nothing left to validate
    // client-side) and the manual API-token fallback.
    const QString previousEndpoint = m_endpoint;
    const QString previousToken = m_token;
    m_endpoint = endpoint;
    m_token = token;

    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/profile")));
    connect(reply, &QNetworkReply::finished, this, [this, reply, endpoint, token, previousEndpoint, previousToken]() {
        const QByteArray raw = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        setBusy(false);

        if (reply->error() == QNetworkReply::NoError && status == 200) {
            const QJsonObject obj = QJsonDocument::fromJson(raw).object();
            const QString username = obj.value(QStringLiteral("user")).toObject()
                                          .value(QStringLiteral("username")).toString();
            m_endpoint = endpoint;
            m_token = token;
            m_username = username;
            persistSession();
            emit endpointChanged();
            emit usernameChanged();
            emit isLoggedInChanged();
            emit loginSucceeded();
        } else {
            m_endpoint = previousEndpoint;
            m_token = previousToken;
            const QString message = (status == 401)
                ? tr("Server rejected the token. Check the server address and try again.")
                : extractErrorMessage(reply, raw);
            setLastError(message);
            emit loginFailed(message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::logout()
{
    // Best-effort server-side revocation (only meaningful for an OAuth
    // access token; a manually-pasted personal API token predates OAuth
    // and this route may reject it, which is fine -- the token still
    // works for as long as the user leaves it valid on the server, this
    // app just forgets it either way).
    if (!m_endpoint.isEmpty() && !m_token.isEmpty()) {
        QJsonObject body;
        body[QStringLiteral("token")] = m_token;
        QNetworkRequest request(QUrl(m_endpoint + QStringLiteral("/api/oauth/revoke")));
        request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        request.setRawHeader("Authorization", QByteArray("Bearer ") + m_token.toUtf8());
        QNetworkReply *reply = m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
        connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
    }

    m_token.clear();
    m_username.clear();
    persistSession();
    emit usernameChanged();
    emit isLoggedInChanged();
}

void ReadeckClient::loadBookmarks(const QString &filter, const QString &search, int offset, bool reset)
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    query.addQueryItem(QStringLiteral("offset"), QString::number(offset));
    query.addQueryItem(QStringLiteral("sort"), QStringLiteral("-created"));

    if (filter == QStringLiteral("unread")) {
        query.addQueryItem(QStringLiteral("is_archived"), QStringLiteral("false"));
    } else if (filter == QStringLiteral("archive")) {
        query.addQueryItem(QStringLiteral("is_archived"), QStringLiteral("true"));
    } else if (filter == QStringLiteral("favorites")) {
        query.addQueryItem(QStringLiteral("is_marked"), QStringLiteral("true"));
    }
    if (!search.isEmpty()) {
        query.addQueryItem(QStringLiteral("search"), search);
    }

    setBusy(true);
    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/bookmarks"), query));
    connect(reply, &QNetworkReply::finished, this, [this, reply, reset]() {
        const QByteArray raw = reply->readAll();
        setBusy(false);
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonDocument doc = QJsonDocument::fromJson(raw);
            QVariantList items;
            for (const QJsonValue &v : doc.array()) {
                items << bookmarkToVariant(v.toObject());
            }
            bool ok = false;
            int totalCount = reply->rawHeader("Total-Count").toInt(&ok);
            if (!ok) {
                totalCount = items.count();
            }
            emit bookmarksReceived(items, totalCount, reset);
        } else {
            const QString message = extractErrorMessage(reply, raw);
            setLastError(message);
            emit bookmarksFailed(message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::loadArticle(const QString &bookmarkId)
{
    setBusy(true);
    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/bookmarks/") + encodeIdSegment(bookmarkId) + QStringLiteral("/article")));
    connect(reply, &QNetworkReply::finished, this, [this, reply, bookmarkId]() {
        const QByteArray raw = reply->readAll();
        setBusy(false);
        if (reply->error() == QNetworkReply::NoError) {
            emit articleReceived(bookmarkId, QString::fromUtf8(raw));
        } else {
            const QString message = extractErrorMessage(reply, raw);
            emit articleFailed(bookmarkId, message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::loadLabels()
{
    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/bookmarks/labels")));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonDocument doc = QJsonDocument::fromJson(raw);
            QVariantList labels;
            for (const QJsonValue &v : doc.array()) {
                labels << v.toObject().toVariantMap();
            }
            emit labelsReceived(labels);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::createBookmark(const QString &url, const QString &title, const QStringList &labels, const QString &html)
{
    setBusy(true);

    QNetworkReply *reply;
    if (html.isEmpty()) {
        QJsonObject body;
        body[QStringLiteral("url")] = url;
        if (!title.isEmpty()) {
            body[QStringLiteral("title")] = title;
        }
        if (!labels.isEmpty()) {
            body[QStringLiteral("labels")] = QJsonArray::fromStringList(labels);
        }
        reply = m_manager->post(buildRequest(QStringLiteral("/bookmarks")), QJsonDocument(body).toJson(QJsonDocument::Compact));
    } else {
        // Submitting a "html" part makes the server use it as-is instead
        // of fetching the URL itself. buildRequest() is not reused here:
        // it forces a JSON content type, which would clash with the
        // multipart/form-data boundary QNetworkAccessManager sets for us.
        auto *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

        auto addTextPart = [multiPart](const QString &name, const QString &value) {
            QHttpPart part;
            part.setHeader(QNetworkRequest::ContentDispositionHeader,
                            QVariant(QStringLiteral("form-data; name=\"%1\"").arg(name)));
            part.setBody(value.toUtf8());
            multiPart->append(part);
        };

        addTextPart(QStringLiteral("url"), url);
        if (!title.isEmpty()) {
            addTextPart(QStringLiteral("title"), title);
        }
        for (const QString &label : labels) {
            addTextPart(QStringLiteral("labels"), label);
        }

        QHttpPart htmlPart;
        htmlPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                            QVariant(QStringLiteral("form-data; name=\"html\"; filename=\"page.html\"")));
        htmlPart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant(QStringLiteral("text/html")));
        htmlPart.setBody(html.toUtf8());
        multiPart->append(htmlPart);

        QNetworkRequest request(QUrl(apiUrl(QStringLiteral("/bookmarks"))));
        request.setRawHeader("Accept", "application/json");
        if (!m_token.isEmpty()) {
            request.setRawHeader("Authorization", QByteArray("Bearer ") + m_token.toUtf8());
        }
        reply = m_manager->post(request, multiPart);
        multiPart->setParent(reply);
    }

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        setBusy(false);
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::NoError && status == 202) {
            const QString id = QString::fromUtf8(reply->rawHeader("Bookmark-Id"));
            emit bookmarkCreated(id);
        } else {
            const QString message = extractErrorMessage(reply, raw);
            emit bookmarkCreateFailed(message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::updateBookmark(const QString &bookmarkId, const QVariantMap &changes)
{
    QJsonObject body = QJsonObject::fromVariantMap(changes);

    QNetworkRequest request = buildRequest(QStringLiteral("/bookmarks/") + encodeIdSegment(bookmarkId));
    request.setAttribute(QNetworkRequest::CustomVerbAttribute, QByteArray("PATCH"));

    QNetworkReply *reply = m_manager->post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, bookmarkId, changes]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() == QNetworkReply::NoError) {
            emit bookmarkUpdated(bookmarkId, changes);
        } else {
            const QString message = extractErrorMessage(reply, raw);
            emit bookmarkUpdateFailed(bookmarkId, message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::deleteBookmark(const QString &bookmarkId)
{
    QNetworkReply *reply = m_manager->deleteResource(buildRequest(QStringLiteral("/bookmarks/") + encodeIdSegment(bookmarkId)));
    connect(reply, &QNetworkReply::finished, this, [this, reply, bookmarkId]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() == QNetworkReply::NoError) {
            emit bookmarkDeleted(bookmarkId);
        } else {
            const QString message = extractErrorMessage(reply, raw);
            emit bookmarkDeleteFailed(bookmarkId, message);
        }
        reply->deleteLater();
    });
}

void ReadeckClient::loadCoverBookmarks()
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("20"));
    query.addQueryItem(QStringLiteral("is_archived"), QStringLiteral("false"));
    query.addQueryItem(QStringLiteral("sort"), QStringLiteral("-created"));

    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/bookmarks"), query));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        if (reply->error() == QNetworkReply::NoError) {
            const QJsonDocument doc = QJsonDocument::fromJson(raw);
            QVariantList items;
            for (const QJsonValue &v : doc.array()) {
                items << bookmarkToVariant(v.toObject());
            }
            m_coverBookmarks = items;
            m_coverIndex = 0;
            emit coverBookmarksChanged();
            emit coverIndexChanged();
        }
        reply->deleteLater();
    });
}

void ReadeckClient::coverNext()
{
    if (m_coverBookmarks.isEmpty()) {
        return;
    }
    m_coverIndex = (m_coverIndex + 1) % m_coverBookmarks.count();
    emit coverIndexChanged();
    setCoverSelectionPending(true);
}

void ReadeckClient::refreshUnreadCount()
{
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
    query.addQueryItem(QStringLiteral("is_archived"), QStringLiteral("false"));

    QNetworkReply *reply = m_manager->get(buildRequest(QStringLiteral("/bookmarks"), query));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        if (reply->error() == QNetworkReply::NoError) {
            bool ok = false;
            const int totalCount = reply->rawHeader("Total-Count").toInt(&ok);
            if (ok && totalCount != m_unreadCount) {
                m_unreadCount = totalCount;
                emit unreadCountChanged();
            }
        }
        reply->deleteLater();
    });
}
