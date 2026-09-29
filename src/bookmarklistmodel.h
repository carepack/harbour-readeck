#pragma once

#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>

// Flat list model backing the bookmarks list view. Items are plain
// QVariantMaps as returned by ReadeckClient (already flattened from the
// Readeck API's bookmarkSummary JSON objects). The QML side feeds this
// model via resetItems()/appendItems() and patches it in place via
// updateItem()/removeItem() so list scroll position survives edits.
class BookmarkListModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        UrlRole,
        SiteNameRole,
        SiteRole,
        DescriptionRole,
        AuthorsTextRole,
        IsMarkedRole,
        IsArchivedRole,
        StateRole,
        LoadedRole,
        TypeRole,
        ReadProgressRole,
        LabelsRole,
        LabelsTextRole,
        WordCountRole,
        ReadingTimeRole,
        ImageUrlRole,
        IconUrlRole,
        CreatedRole
    };
    Q_ENUM(Roles)

    explicit BookmarkListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;

    Q_INVOKABLE void resetItems(const QVariantList &items);
    Q_INVOKABLE void appendItems(const QVariantList &items);
    Q_INVOKABLE void updateItem(const QString &bookmarkId, const QVariantMap &changes);
    Q_INVOKABLE void removeItem(const QString &bookmarkId);
    Q_INVOKABLE QVariantMap get(int index) const;
    Q_INVOKABLE void clear();

signals:
    void countChanged();

private:
    int indexOfId(const QString &bookmarkId) const;

    QList<QVariantMap> m_items;
};
