# elbe-demo-apt-repository

Local **pool-layout** APT repository for the ELBE demo project. Holds custom
`.deb` packages that are installed into ELBE-built images.

> **Pool layout** means packages are stored under
> `repo/pool/main/<first-letter>/<package-name>/` — the standard Debian
> structure. This is required for `elbe cyclonedx-sbom` (SBOM generation) to
> resolve package origins correctly.

## Quick start

```bash
# 1. Generate GPG signing keys (once)
./gen-keys.sh

# 2. Copy .deb files into repo/
cp ../elbe-demo-pkg-hello/*.deb repo/

# 3. Build repository metadata
./build-repo.sh
```

## Using in ELBE XML

Add this to your ELBE image XML inside `<url-list>`:

```xml
<url-list>
  <url>
    <binary>file:///workspace/elbe-demo-apt-repository/repo ./</binary>
    <key>file:///workspace/elbe-demo-apt-repository/repo/repo-key.gpg</key>
  </url>
</url-list>
```

## Structure

```
elbe-demo-apt-repository/
├── build-repo.sh      # Regenerate APT metadata from .deb files
├── gen-keys.sh        # Generate GPG key pair (run once)
├── keys/              # GPG keys
│   ├── public.asc     # Public key (versioned)
│   └── private.gpg    # Private key (gitignored)
├── repo/              # Pool-layout APT repository (generated)
│   ├── pool/
│   │   └── main/
│   │       └── <x>/
│   │           └── <pkg>/
│   │               └── *.deb
│   ├── Packages
│   ├── Packages.gz
│   ├── Release
│   ├── Release.gpg    # Only present when GPG keys are configured
│   ├── InRelease      # Only present when GPG keys are configured
│   └── repo-key.gpg
└── README.md
```

## Prerequisites

All tools are available inside the ELBE dev container:

- `dpkg-scanpackages` (from `dpkg-dev`)
- `gpg`
- `gzip`
