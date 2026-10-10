#include "secretscredentialstore.h"

#include <QJsonDocument>
#include <QJsonObject>

#include <Secrets/secret.h>
#include <Secrets/storesecretrequest.h>
#include <Secrets/storedsecretrequest.h>
#include <Secrets/deletesecretrequest.h>
#include <Secrets/result.h>

namespace {

// Confirmed in U1's spike: StandaloneDeviceLockSecret has no usable default
// plugin -- leaving these unset fails every request with
// SecretManagerNotInitializedError despite SecretManager::isInitialized()
// being true. Confirmed against the daemon's own `secrets-tool --list-plugins`.
const QString kStoragePlugin = QStringLiteral("org.sailfishos.secrets.plugin.storage.sqlite");
const QString kEncryptionPlugin = QStringLiteral("org.sailfishos.secrets.plugin.encryption.openssl");

Sailfish::Secrets::Secret::Identifier identifierFor(const QString &secretName)
{
    return Sailfish::Secrets::Secret::Identifier(secretName, QString(), kStoragePlugin);
}

bool isNotFoundError(Sailfish::Secrets::Result::ErrorCode code)
{
    return code == Sailfish::Secrets::Result::InvalidSecretError
            || code == Sailfish::Secrets::Result::InvalidSecretIdentifierError;
}

}

SecretsCredentialStore::SecretsCredentialStore(const QString &secretName)
    : m_secretName(secretName)
{
}

SecretsCredentialStore::Outcome SecretsCredentialStore::store(const QVariantMap &fields)
{
    Sailfish::Secrets::Secret secret(identifierFor(m_secretName));
    secret.setData(QJsonDocument::fromVariant(fields).toJson(QJsonDocument::Compact));

    Sailfish::Secrets::StoreSecretRequest req;
    req.setManager(&m_manager);
    req.setSecretStorageType(Sailfish::Secrets::StoreSecretRequest::StandaloneDeviceLockSecret);
    req.setEncryptionPluginName(kEncryptionPlugin);
    req.setUserInteractionMode(Sailfish::Secrets::SecretManager::PreventInteraction);
    req.setDeviceLockUnlockSemantic(Sailfish::Secrets::SecretManager::DeviceLockKeepUnlocked);
    req.setSecret(secret);
    req.startRequest();
    req.waitForFinished();

    return req.result().code() == Sailfish::Secrets::Result::Succeeded
            ? Outcome::Succeeded : Outcome::Failed;
}

SecretsCredentialStore::Outcome SecretsCredentialStore::load(QVariantMap *outFields)
{
    Sailfish::Secrets::StoredSecretRequest req;
    req.setManager(&m_manager);
    req.setIdentifier(identifierFor(m_secretName));
    req.setUserInteractionMode(Sailfish::Secrets::SecretManager::PreventInteraction);
    req.startRequest();
    req.waitForFinished();

    if (req.result().code() == Sailfish::Secrets::Result::Succeeded) {
        if (outFields) {
            *outFields = QJsonDocument::fromJson(req.secret().data()).object().toVariantMap();
        }
        return Outcome::Succeeded;
    }

    return isNotFoundError(req.result().errorCode()) ? Outcome::NotFound : Outcome::Failed;
}

SecretsCredentialStore::Outcome SecretsCredentialStore::remove()
{
    Sailfish::Secrets::DeleteSecretRequest req;
    req.setManager(&m_manager);
    req.setIdentifier(identifierFor(m_secretName));
    req.setUserInteractionMode(Sailfish::Secrets::SecretManager::PreventInteraction);
    req.startRequest();
    req.waitForFinished();

    if (req.result().code() == Sailfish::Secrets::Result::Succeeded) {
        return Outcome::Succeeded;
    }

    // R7: a secret that was never stored (or already deleted) still counts
    // as a successful removal -- the caller never special-cases "never existed".
    return isNotFoundError(req.result().errorCode()) ? Outcome::Succeeded : Outcome::Failed;
}
