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

# LIUM_VERSION is interpolated into the download URL, and curl removes ../
# path segments before sending the request. Without this guard a tag
# containing ../ redirects both the binary and checksums.txt to an arbitrary
# GitHub repository, so an attacker who sets this variable supplies the
# artifact and the checksum it is verified against — defeating the check
# below entirely.
if [[ "${version}" != "latest" && ! "${version}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  die "invalid LIUM_VERSION: ${version}"
fi

# A SHA-256 tool is required, not optional: without one there is nothing to
# verify against and installing anyway would silently skip the check.
if command -v sha256sum >/dev/null 2>&1; then
  sha256_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  sha256_cmd=(shasum -a 256)
else
  die "no SHA-256 tool found (need sha256sum or shasum) — cannot verify the download"
fi

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
# installing anything onto PATH. sha256sum in binary mode prefixes the name
# with '*', so strip it rather than silently failing to match.
expected="$(awk -v name="${asset}" '
  { sub(/^\*/, "", $2) }
  $2 == name || $2 == "bin/" name { print $1; exit }
' "${tmp}/checksums.txt")"
[[ -n "${expected}" ]] || die "checksums.txt has no entry for ${asset}"
actual="$("${sha256_cmd[@]}" "${tmp}/lium" | awk '{print $1}')"
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
