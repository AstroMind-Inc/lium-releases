#!/usr/bin/env bash
# Lium CLI installer: detects OS/arch, downloads the latest release binary,
# and installs it on PATH. No runtime dependencies — the CLI is a single
# static binary.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/AstroMind-Inc/lium-releases/main/install.sh | bash
#
# Options (environment variables):
#   LIUM_VERSION      Release tag to install (default: latest)
#   LIUM_INSTALL_DIR  Target directory (default: ~/.local/bin, then /usr/local/bin)
set -euo pipefail

REPO="AstroMind-Inc/lium-releases"

say() { printf '%s\n' "$*"; }
die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

os="$(uname -s)"
case "${os}" in
  Darwin) os="darwin" ;;
  Linux) os="linux" ;;
  *) die "unsupported OS: ${os}" ;;
esac

arch="$(uname -m)"
case "${arch}" in
  x86_64 | amd64) arch="amd64" ;;
  arm64 | aarch64) arch="arm64" ;;
  *) die "unsupported architecture: ${arch}" ;;
esac

asset="lium.${os}-${arch}"
version="${LIUM_VERSION:-latest}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

if [[ "${version}" == "latest" ]]; then
  base_url="https://github.com/${REPO}/releases/latest/download"
else
  base_url="https://github.com/${REPO}/releases/download/${version}"
fi

say "Downloading ${asset} (${version})…"
curl -fsSL -o "${tmp}/lium" "${base_url}/${asset}" || die "download failed: ${base_url}/${asset}"
curl -fsSL -o "${tmp}/checksums.txt" "${base_url}/checksums.txt" ||
  die "download failed: ${base_url}/checksums.txt"

# Verify the binary against the release's published checksum before
# installing anything onto PATH.
expected="$(awk -v name="${asset}" '$2 == name || $2 == "bin/"name { print $1; exit }' "${tmp}/checksums.txt")"
[[ -n "${expected}" ]] || die "checksums.txt has no entry for ${asset}"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${tmp}/lium" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "${tmp}/lium" | awk '{print $1}')"
fi
[[ "${actual}" == "${expected}" ]] ||
  die "checksum mismatch for ${asset}: expected ${expected}, got ${actual}"
say "Checksum verified."
chmod +x "${tmp}/lium"

install_dir="${LIUM_INSTALL_DIR:-}"
if [[ -z "${install_dir}" ]]; then
  if [[ -d "${HOME}/.local/bin" || ! -w /usr/local/bin ]]; then
    install_dir="${HOME}/.local/bin"
  else
    install_dir="/usr/local/bin"
  fi
fi
mkdir -p "${install_dir}"
mv "${tmp}/lium" "${install_dir}/lium"

say "Installed ${install_dir}/lium"
"${install_dir}/lium" --version || true

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *)
    say ""
    say "Add it to your PATH, e.g.:"
    say "  echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.zshrc && exec zsh"
    ;;
esac

say ""
say "Next steps:"
say "  lium login    # one-time browser login"
say "  lium          # interactive chat"
say "  lium guide    # guide for AI coding agents (Claude Code, Cursor)"
