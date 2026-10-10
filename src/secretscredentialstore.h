#pragma once

#include <QString>
#include <QVariantMap>
#include <QScopedPointer>

namespace Sailfish { namespace Secrets { class SecretManager; } }

// Stores one combined-JSON secret (e.g. username+token) via Sailfish
// Secrets, synchronously. See docs/plans/2026-10-10-1328-feat-sailfish-
// secrets-credential-storage-plan.md (KTD1-KTD8) for why: standalone
// device-lock secret, synchronous startRequest()+waitForFinished() calls,
// explicit storage/encryption plugin names, one long-lived SecretManager.
//
// SecretManager is only forward-declared here (not included) so callers
// of this class -- readeckclient.h, and everything that includes it --
// don't transitively need the Sailfish Secrets headers. The destructor is
// declared (not defaulted inline) and defined in the .cpp, where
// SecretManager is complete, which QScopedPointer's own destructor needs.
class SecretsCredentialStore
{
public:
    enum class Outcome { Succeeded, NotFound, Failed };

    explicit SecretsCredentialStore(const QString &secretName);
    ~SecretsCredentialStore();

    Outcome store(const QVariantMap &fields);
    Outcome load(QVariantMap *outFields);
    Outcome remove();

private:
    Outcome removeInternal();

    QString m_secretName;
    QScopedPointer<Sailfish::Secrets::SecretManager> m_manager;
};
