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

say "Downloading ${asset} (${version})…"
if [[ "${version}" == "latest" ]]; then
  url="https://github.com/${REPO}/releases/latest/download/${asset}"
else
  url="https://github.com/${REPO}/releases/download/${version}/${asset}"
fi
curl -fsSL -o "${tmp}/lium" "${url}" || die "download failed: ${url}"
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
