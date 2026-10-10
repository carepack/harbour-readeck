#pragma once

#include <QString>
#include <QVariantMap>

#include <Secrets/secretmanager.h>

// Stores one combined-JSON secret (e.g. username+token) via Sailfish
// Secrets, synchronously. See docs/plans/2026-10-10-1328-feat-sailfish-
// secrets-credential-storage-plan.md (KTD1-KTD8) for why: standalone
// device-lock secret, synchronous startRequest()+waitForFinished() calls,
// explicit storage/encryption plugin names, one long-lived SecretManager.
class SecretsCredentialStore
{
public:
    enum class Outcome { Succeeded, NotFound, Failed };

    explicit SecretsCredentialStore(const QString &secretName);

    Outcome store(const QVariantMap &fields);
    Outcome load(QVariantMap *outFields);
    Outcome remove();

private:
    Outcome removeInternal();

    QString m_secretName;
    Sailfish::Secrets::SecretManager m_manager;
};
