#!/usr/bin/env bash
# build-repo.sh — (Re)generate APT repository metadata from .deb files in repo/.
#
# Usage:
#   1. Copy .deb files into repo/
#   2. Run: ./build-repo.sh
#
# Prerequisites: dpkg-dev, gzip, gpg (all available in the ELBE dev container).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/repo"
GNUPG_HOME="${SCRIPT_DIR}/.gnupg"
KEYS_DIR="${SCRIPT_DIR}/keys"

# Sanity checks
if [ ! -d "${REPO_DIR}" ]; then
    echo "Error: repo/ directory not found."
    exit 1
fi

DEB_COUNT=$(find "${REPO_DIR}" -maxdepth 1 -name '*.deb' | wc -l)
if [ "${DEB_COUNT}" -eq 0 ]; then
    echo "Error: no .deb files found in repo/. Copy packages there first."
    exit 1
fi

if [ ! -f "${KEYS_DIR}/private.gpg" ]; then
    echo "Error: GPG private key not found. Run ./gen-keys.sh first."
    exit 1
fi

# Import private key if not already in the local keyring
gpg --homedir "${GNUPG_HOME}" --batch --import "${KEYS_DIR}/private.gpg" 2>/dev/null || true

# Detect signing key email from the imported private key
KEY_EMAIL="${1:-$(gpg --homedir "${GNUPG_HOME}" --batch --list-secret-keys --with-colons 2>/dev/null | grep '^uid' | head -1 | cut -d: -f10 | grep -oP '<\K[^>]+' || echo "elbe-demo@local")}"

echo "Scanning .deb packages..."
cd "${REPO_DIR}"

# Generate Packages index (binary)
dpkg-scanpackages --multiversion . > Packages
gzip -9c Packages > Packages.gz

# Generate Sources index (source packages) if any .dsc files exist
SRC_COUNT=$(find "${REPO_DIR}" -maxdepth 1 -name '*.dsc' | wc -l)
if [ "${SRC_COUNT}" -gt 0 ]; then
    echo "Scanning ${SRC_COUNT} source package(s)..."
    dpkg-scansources . > Sources
    gzip -9c Sources > Sources.gz
else
    echo "No source packages (.dsc) found — skipping Sources index."
    # Create empty Sources so Release checksums remain consistent
    : > Sources
    gzip -9c Sources > Sources.gz
fi

echo "Generating Release file..."

# Generate Release
cat > Release <<RELEOF
Origin: elbe-demo-local
Label: ELBE Demo Local Repository
Suite: stable
Codename: local
Architectures: amd64 arm64 armhf all
Components: .
Description: Local APT repository for ELBE demo project
RELEOF
# Remove leading whitespace from heredoc
sed -i 's/^    //' Release

# Append checksums (include Sources indices)
INDEX_FILES="Packages Packages.gz Sources Sources.gz"
{
    echo "MD5Sum:"
    for f in ${INDEX_FILES}; do
        [ -f "$f" ] && echo " $(md5sum "$f" | cut -d' ' -f1) $(wc -c < "$f") $f"
    done
    echo "SHA256:"
    for f in ${INDEX_FILES}; do
        [ -f "$f" ] && echo " $(sha256sum "$f" | cut -d' ' -f1) $(wc -c < "$f") $f"
    done
} >> Release

echo "Signing repository..."

# Sign: Release.gpg (detached) and InRelease (inline)
gpg --homedir "${GNUPG_HOME}" --batch --yes --default-key "${KEY_EMAIL}"         --armor --detach-sign --output Release.gpg Release
gpg --homedir "${GNUPG_HOME}" --batch --yes --default-key "${KEY_EMAIL}"         --armor --clearsign --output InRelease Release

# Ensure public key is in repo
gpg --homedir "${GNUPG_HOME}" --export "${KEY_EMAIL}" > repo-key.gpg

echo ""
echo "Repository updated successfully."
echo "  Binary packages:  ${DEB_COUNT} .deb file(s)"
echo "  Source packages:  ${SRC_COUNT} .dsc file(s)"
echo "  Index:    Packages, Packages.gz, Sources, Sources.gz"
echo "  Signed:   Release, Release.gpg, InRelease"
echo ""
echo "APT source lines (inside ELBE container):"
echo "  deb     file://${REPO_DIR} ./"
echo "  deb-src file://${REPO_DIR} ./"
