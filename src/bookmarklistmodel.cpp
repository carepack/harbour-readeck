#include "bookmarklistmodel.h"

BookmarkListModel::BookmarkListModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int BookmarkListModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) {
        return 0;
    }
    return m_items.count();
}

QVariant BookmarkListModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.count()) {
        return QVariant();
    }
    const QVariantMap &item = m_items.at(index.row());
    switch (role) {
    case IdRole: return item.value(QStringLiteral("id"));
    case TitleRole: return item.value(QStringLiteral("title"));
    case UrlRole: return item.value(QStringLiteral("url"));
    case SiteNameRole: return item.value(QStringLiteral("site_name"));
    case SiteRole: return item.value(QStringLiteral("site"));
    case DescriptionRole: return item.value(QStringLiteral("description"));
    case AuthorsTextRole: return item.value(QStringLiteral("authorsText"));
    case IsMarkedRole: return item.value(QStringLiteral("is_marked"));
    case IsArchivedRole: return item.value(QStringLiteral("is_archived"));
    case StateRole: return item.value(QStringLiteral("state"));
    case LoadedRole: return item.value(QStringLiteral("loaded"));
    case TypeRole: return item.value(QStringLiteral("type"));
    case ReadProgressRole: return item.value(QStringLiteral("read_progress"));
    case LabelsRole: return item.value(QStringLiteral("labels"));
    case LabelsTextRole: return item.value(QStringLiteral("labelsText"));
    case WordCountRole: return item.value(QStringLiteral("word_count"));
    case ReadingTimeRole: return item.value(QStringLiteral("reading_time"));
    case ImageUrlRole: return item.value(QStringLiteral("imageUrl"));
    case IconUrlRole: return item.value(QStringLiteral("iconUrl"));
    case CreatedRole: return item.value(QStringLiteral("created"));
    default: return QVariant();
    }
}

QHash<int, QByteArray> BookmarkListModel::roleNames() const
{
    return {
        { IdRole, "bookmarkId" },
        { TitleRole, "title" },
        { UrlRole, "url" },
        { SiteNameRole, "siteName" },
        { SiteRole, "site" },
        { DescriptionRole, "description" },
        { AuthorsTextRole, "authorsText" },
        { IsMarkedRole, "isMarked" },
        { IsArchivedRole, "isArchived" },
        { StateRole, "state" },
        { LoadedRole, "loaded" },
        { TypeRole, "type" },
        { ReadProgressRole, "readProgress" },
        { LabelsRole, "labels" },
        { LabelsTextRole, "labelsText" },
        { WordCountRole, "wordCount" },
        { ReadingTimeRole, "readingTime" },
        { ImageUrlRole, "imageUrl" },
        { IconUrlRole, "iconUrl" },
        { CreatedRole, "created" }
    };
}

int BookmarkListModel::count() const
{
    return m_items.count();
}

int BookmarkListModel::indexOfId(const QString &bookmarkId) const
{
    for (int i = 0; i < m_items.count(); ++i) {
        if (m_items.at(i).value(QStringLiteral("id")).toString() == bookmarkId) {
            return i;
        }
    }
    return -1;
}

void BookmarkListModel::resetItems(const QVariantList &items)
{
    beginResetModel();
    m_items.clear();
    for (const QVariant &v : items) {
        m_items << v.toMap();
    }
    endResetModel();
    emit countChanged();
}

void BookmarkListModel::appendItems(const QVariantList &items)
{
    if (items.isEmpty()) {
        return;
    }
    beginInsertRows(QModelIndex(), m_items.count(), m_items.count() + items.count() - 1);
    for (const QVariant &v : items) {
        m_items << v.toMap();
    }
    endInsertRows();
    emit countChanged();
}

void BookmarkListModel::updateItem(const QString &bookmarkId, const QVariantMap &changes)
{
    const int row = indexOfId(bookmarkId);
    if (row < 0) {
        return;
    }
    QVariantMap &item = m_items[row];
    for (auto it = changes.constBegin(); it != changes.constEnd(); ++it) {
        item[it.key()] = it.value();
    }
    const QModelIndex idx = index(row);
    emit dataChanged(idx, idx);
}

void BookmarkListModel::removeItem(const QString &bookmarkId)
{
    const int row = indexOfId(bookmarkId);
    if (row < 0) {
        return;
    }
    beginRemoveRows(QModelIndex(), row, row);
    m_items.removeAt(row);
    endRemoveRows();
    emit countChanged();
}

QVariantMap BookmarkListModel::get(int index) const
{
    if (index < 0 || index >= m_items.count()) {
        return QVariantMap();
    }
    return m_items.at(index);
}

void BookmarkListModel::clear()
{
    beginResetModel();
    m_items.clear();
    endResetModel();
    emit countChanged();
}
