#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrlQuery>
#include <QVariantMap>
#include <QVariantList>
#include <QStringList>
#include <QTimer>

// Talks to a Readeck server's REST API (https://readeck.org) and persists
// the session (server URL, username, API token) in the app's private
// QSettings storage. One instance lives for the whole app lifetime and is
// exposed to QML as the "readeckClient" context property.
class ReadeckClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString endpoint READ endpoint NOTIFY endpointChanged)
    Q_PROPERTY(QString username READ username NOTIFY usernameChanged)
    Q_PROPERTY(bool isLoggedIn READ isLoggedIn NOTIFY isLoggedInChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(int unreadCount READ unreadCount NOTIFY unreadCountChanged)
    Q_PROPERTY(QVariantList coverBookmarks READ coverBookmarks NOTIFY coverBookmarksChanged)
    Q_PROPERTY(int coverIndex READ coverIndex NOTIFY coverIndexChanged)
    Q_PROPERTY(bool coverSelectionPending READ coverSelectionPending WRITE setCoverSelectionPending NOTIFY coverSelectionPendingChanged)
    Q_PROPERTY(bool oauthInProgress READ oauthInProgress NOTIFY oauthInProgressChanged)
    Q_PROPERTY(QString oauthUserCode READ oauthUserCode NOTIFY oauthUserCodeChanged)

public:
    explicit ReadeckClient(QObject *parent = nullptr);

    QString endpoint() const;
    QString username() const;
    bool isLoggedIn() const;
    bool busy() const;
    QString lastError() const;
    int unreadCount() const;
    QVariantList coverBookmarks() const;
    int coverIndex() const;
    bool coverSelectionPending() const;
    void setCoverSelectionPending(bool pending);
    bool oauthInProgress() const;
    QString oauthUserCode() const;

    // Browser-based login via Readeck's OAuth2 Device Code flow (added in
    // Readeck 0.21 -- see https://readeck.org/en/docs/external-auth): the
    // user grants access on the server's own web page, so this app never
    // sees their password. Emits oauthLoginUrlReady(url) for QML to open
    // (Qt.openUrlExternally -- not done here in C++ via QDesktopServices,
    // whose sailjail behavior isn't reliably documented), then polls
    // until the user finishes, denies, or the request expires. Outcome
    // arrives via the same loginSucceeded()/loginFailed() signals the
    // token-based login below uses.
    Q_INVOKABLE void startOAuthLogin(const QString &endpoint);
    Q_INVOKABLE void cancelOAuthLogin();

    // Polls once immediately; call from QML on every foreground
    // transition. The poll QTimer can miss ticks while the app is
    // backgrounded (the user is off in the system browser approving the
    // request), so this catches a completed login without waiting for
    // the next scheduled tick.
    Q_INVOKABLE void pollOAuthLogin();

    // Manual fallback for Readeck servers predating 0.21 (no OAuth
    // support): paste a personal API token created in Profile -> API
    // tokens. This was this app's only login method before OAuth existed.
    Q_INVOKABLE void loginWithToken(const QString &endpoint, const QString &token);

    Q_INVOKABLE void logout();

    // filter: "unread" | "archive" | "favorites" | "all"
    Q_INVOKABLE void loadBookmarks(const QString &filter, const QString &search, int offset, bool reset);
    Q_INVOKABLE void loadArticle(const QString &bookmarkId);
    Q_INVOKABLE void loadLabels();

    // Renders the already-loaded article HTML to a PDF in the given
    // directory (chosen by the user in PdfLocationDialog.qml, always
    // one of downloadsPath()/documentsPath() or a subfolder of one --
    // the only trees this app's Sailjail permissions grant write access
    // to) via QTextDocument + QPdfWriter (both plain QtGui -- no
    // QtPrintSupport, which isn't part of this Sailfish OS target's Qt
    // build at all). Synchronous: local file I/O and CPU-bound layout
    // only, no network round-trip, so there's nothing to usefully do
    // asynchronously. Returns the saved file's path, or an empty string
    // on failure (with the reason left in lastError, same as every
    // other failure path).
    Q_INVOKABLE QString exportArticlePdf(const QString &title, const QString &html, const QString &directory);

    // Roots offered by PdfLocationDialog.qml for browsing/export -- the
    // XDG user directories the "UserDirs" Sailjail permission in
    // harbour-readeck.desktop grants read/write access to. There is no
    // permission for arbitrary access to the rest of $HOME (Sailjail
    // whitelists specific trees only -- see
    // /etc/sailjail/permissions/UserDirs.permission on-device, which is
    // exactly these six), so these are the full set of folders the app
    // can actually browse/save into under the sandbox.
    Q_INVOKABLE QString downloadsPath() const;
    Q_INVOKABLE QString documentsPath() const;
    Q_INVOKABLE QString picturesPath() const;
    Q_INVOKABLE QString videosPath() const;
    Q_INVOKABLE QString musicPath() const;
    Q_INVOKABLE QString publicPath() const;

    // html: when non-empty, submitted as the page's content directly
    // (multipart upload) instead of letting the server fetch the URL
    // itself -- useful for paywalled pages the server's own fetcher
    // cannot read.
    Q_INVOKABLE void createBookmark(const QString &url, const QString &title, const QStringList &labels, const QString &html = QString());
    Q_INVOKABLE void updateBookmark(const QString &bookmarkId, const QVariantMap &changes);
    Q_INVOKABLE void deleteBookmark(const QString &bookmarkId);

    Q_INVOKABLE void refreshUnreadCount();

    // Small independent unread-article list for the cover, so it can be
    // browsed with the cover's "next" action without disturbing whatever
    // filter/search state BookmarksPage currently has loaded.
    Q_INVOKABLE void loadCoverBookmarks();
    Q_INVOKABLE void coverNext();

signals:
    void endpointChanged();
    void usernameChanged();
    void isLoggedInChanged();
    void busyChanged();
    void lastErrorChanged();
    void unreadCountChanged();
    void coverBookmarksChanged();
    void coverIndexChanged();
    void coverSelectionPendingChanged();
    void oauthInProgressChanged();
    void oauthUserCodeChanged();

    void loginSucceeded();
    void loginFailed(const QString &message);
    void oauthLoginUrlReady(const QString &url);

    void bookmarksReceived(const QVariantList &items, int totalCount, bool reset);
    void bookmarksFailed(const QString &message);

    void articleReceived(const QString &bookmarkId, const QString &html);
    void articleFailed(const QString &bookmarkId, const QString &message);

    void labelsReceived(const QVariantList &labels);

    void bookmarkCreated(const QString &bookmarkId);
    void bookmarkCreateFailed(const QString &message);

    void bookmarkUpdated(const QString &bookmarkId, const QVariantMap &changes);
    void bookmarkUpdateFailed(const QString &bookmarkId, const QString &message);

    void bookmarkDeleted(const QString &bookmarkId);
    void bookmarkDeleteFailed(const QString &bookmarkId, const QString &message);

private:
    QString apiUrl(const QString &path) const;
    QNetworkRequest buildRequest(const QString &path, const QUrlQuery &query = QUrlQuery()) const;
    static QString normalizeEndpoint(const QString &input);
    static QString encodeIdSegment(const QString &id);
    static QString extractErrorMessage(QNetworkReply *reply, const QByteArray &body);
    static QVariantMap bookmarkToVariant(const QJsonObject &obj);

    void setBusy(bool busy);
    void setLastError(const QString &error);
    void persistSession();
    void restoreSession();
    void requestDeviceCode(const QString &endpoint);
    void finishLogin(const QString &endpoint, const QString &token);

    QNetworkAccessManager *m_manager;
    QString m_endpoint;
    QString m_token;
    QString m_username;
    bool m_busy;
    QString m_lastError;
    int m_unreadCount;
    QVariantList m_coverBookmarks;
    int m_coverIndex;
    bool m_coverSelectionPending;

    // OAuth Device Code flow state, valid only while m_oauthInProgress.
    QTimer m_oauthPollTimer;
    bool m_oauthInProgress = false;
    QString m_oauthClientId;
    QString m_oauthDeviceCode;
    QString m_oauthUserCode;
    QString m_oauthEndpoint;
    qint64 m_oauthExpiresAtMs = 0;
};
