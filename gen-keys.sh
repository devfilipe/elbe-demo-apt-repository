#!/usr/bin/env bash
# gen-keys.sh — Generate a GPG key pair for signing the local APT repository.
# Run this once. The private key stays local (gitignored); the public key
# is exported to repo/repo-key.gpg so APT clients can verify packages.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"
REPO_DIR="${SCRIPT_DIR}/repo"
GNUPG_HOME="${SCRIPT_DIR}/.gnupg"

mkdir -p "${KEYS_DIR}" "${REPO_DIR}" "${GNUPG_HOME}"
chmod 700 "${GNUPG_HOME}"

KEY_NAME="${1:-ELBE Demo Repo Signing Key}"
KEY_EMAIL="${2:-elbe-demo@local}"

# Check if key already exists
if [ -f "${KEYS_DIR}/private.gpg" ]; then
    echo "Key pair already exists in ${KEYS_DIR}/. Delete it first to regenerate."
    exit 0
fi

echo "Generating GPG key pair..."

# Generate key using batch mode (no passphrase for dev convenience)
gpg --homedir "${GNUPG_HOME}" --batch --gen-key <<GPGEOF
Key-Type: RSA
Key-Length: 4096
Name-Real: ${KEY_NAME}
Name-Email: ${KEY_EMAIL}
Expire-Date: 0
%no-protection
%commit
GPGEOF

# Export keys
gpg --homedir "${GNUPG_HOME}" --armor --export "${KEY_EMAIL}" > "${KEYS_DIR}/public.asc"
gpg --homedir "${GNUPG_HOME}" --armor --export-secret-keys "${KEY_EMAIL}" > "${KEYS_DIR}/private.gpg"
gpg --homedir "${GNUPG_HOME}" --export "${KEY_EMAIL}" > "${REPO_DIR}/repo-key.gpg"

chmod 600 "${KEYS_DIR}/private.gpg"

echo ""
echo "Done. Keys generated:"
echo "  Public:  ${KEYS_DIR}/public.asc"
echo "  Private: ${KEYS_DIR}/private.gpg  (gitignored)"
echo "  Binary:  ${REPO_DIR}/repo-key.gpg (for APT clients)"
