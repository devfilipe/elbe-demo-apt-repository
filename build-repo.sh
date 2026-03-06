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

# Migrate any .deb/.dsc/.tar.* files from repo root into pool layout
for f in "${REPO_DIR}"/*.deb; do
    [ -f "$f" ] || continue
    fname="$(basename "$f")"
    pkg_name="${fname%%_*}"
    first="${pkg_name:0:1}"
    pool_dir="${REPO_DIR}/pool/main/${first}/${pkg_name}"
    mkdir -p "${pool_dir}"
    mv "$f" "${pool_dir}/${fname}"
    echo "Migrated ${fname} → pool/main/${first}/${pkg_name}/"
done
for f in "${REPO_DIR}"/*.dsc "${REPO_DIR}"/*.tar.*; do
    [ -f "$f" ] || continue
    fname="$(basename "$f")"
    pkg_name="${fname%%_*}"
    first="${pkg_name:0:1}"
    pool_dir="${REPO_DIR}/pool/main/${first}/${pkg_name}"
    mkdir -p "${pool_dir}"
    mv "$f" "${pool_dir}/${fname}"
done

# Count .deb files recursively (pool layout)
DEB_COUNT=$(find "${REPO_DIR}/pool" -name '*.deb' 2>/dev/null | wc -l)
SRC_COUNT=$(find "${REPO_DIR}/pool" -name '*.dsc' 2>/dev/null | wc -l)

SIGN=false
if [ -f "${KEYS_DIR}/private.gpg" ]; then
    SIGN=true
    gpg --homedir "${GNUPG_HOME}" --batch --import "${KEYS_DIR}/private.gpg" 2>/dev/null || true
    KEY_EMAIL="${1:-$(gpg --homedir "${GNUPG_HOME}" --batch --list-secret-keys --with-colons 2>/dev/null | grep '^uid' | head -1 | cut -d: -f10 | grep -oP '<\K[^>]+' || echo "elbe-demo@local")}"
else
    echo "Warning: No GPG private key found — generating unsigned index (requires [trusted=yes] in APT source)."
fi

echo "Scanning packages (pool layout)..."
cd "${REPO_DIR}"

# Scan recursively — Filename entries will be pool/main/<x>/<pkg>/<file>
if [ "${DEB_COUNT}" -gt 0 ]; then
    dpkg-scanpackages --multiversion . > Packages
else
    : > Packages
fi
gzip -9c Packages > Packages.gz

if [ "${SRC_COUNT}" -gt 0 ]; then
    echo "Scanning ${SRC_COUNT} source package(s)..."
    dpkg-scansources . > Sources
    gzip -9c Sources > Sources.gz
else
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

if [ "${SIGN}" = "true" ]; then
    echo "Signing repository..."
    gpg --homedir "${GNUPG_HOME}" --batch --yes --default-key "${KEY_EMAIL}" \
        --armor --detach-sign --output Release.gpg Release
    gpg --homedir "${GNUPG_HOME}" --batch --yes --default-key "${KEY_EMAIL}" \
        --armor --clearsign --output InRelease Release
    gpg --homedir "${GNUPG_HOME}" --export "${KEY_EMAIL}" > repo-key.gpg
else
    echo "Skipping GPG signing (no private key). Using unsigned Release only."
    # Remove InRelease so apt doesn't try to parse it as a clearsigned document.
    # With [trusted=yes] in the APT source, apt accepts Release without a signature.
    rm -f InRelease Release.gpg
fi

echo ""
echo "Repository updated successfully."
echo "  Binary packages:  ${DEB_COUNT} .deb file(s) in pool layout"
echo "  Source packages:  ${SRC_COUNT} .dsc file(s)"
echo "  Index:    Packages, Packages.gz, Sources, Sources.gz"
echo "  Signed:   Release, Release.gpg, InRelease"
echo ""
echo "APT source lines (inside ELBE container):"
echo "  deb     file://${REPO_DIR} ./"
echo "  deb-src file://${REPO_DIR} ./"
