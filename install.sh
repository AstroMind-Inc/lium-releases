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

main() {
  local os arch asset bin_name version base_url expected actual install_dir
  local -a sha256_cmd
  # tmp is intentionally NOT local: the EXIT trap below fires after main returns,
  # and a local tmp would be out of scope there, so set -u would abort cleanup
  # with "tmp: unbound variable" on the success path.

  os="$(uname -s)"
  case "${os}" in
    Darwin) os="darwin" ;;
    Linux) os="linux" ;;
    # Git Bash, MSYS2, and Cygwin report these; WSL reports Linux and installs
    # the Linux binary. Native PowerShell/cmd has no bash — use install.ps1.
    MINGW* | MSYS* | CYGWIN* | Windows_NT) os="windows" ;;
    *) die "unsupported OS: ${os} (on native Windows, use install.ps1)" ;;
  esac

  arch="$(uname -m)"
  case "${arch}" in
    x86_64 | amd64) arch="amd64" ;;
    arm64 | aarch64) arch="arm64" ;;
    *) die "unsupported architecture: ${arch}" ;;
  esac

  asset="lium.${os}-${arch}"
  # Windows release binaries carry a .exe suffix, and the installed file needs
  # it too so a Windows shell treats it as executable.
  bin_name="lium"
  if [[ "${os}" == "windows" ]]; then
    asset="${asset}.exe"
    bin_name="lium.exe"
  fi
  version="${LIUM_VERSION:-latest}"
  # The version becomes a URL path segment for both the binary and its
  # checksum. Without validation, ../ can traverse into an attacker-owned
  # repository and make a malicious binary verify against its own checksum.
  if [[ "${version}" != "latest" &&
    ! "${version}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]]; then
    die "invalid LIUM_VERSION: ${version}"
  fi

  # Resolve the checksum tool before downloading anything. Verification is
  # mandatory, and a missing tool should produce a useful error.
  if command -v sha256sum >/dev/null 2>&1; then
    sha256_cmd=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    sha256_cmd=(shasum -a 256)
  else
    die "no SHA-256 tool found (need sha256sum or shasum) — cannot verify the download"
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' EXIT

  # Two download strategies, chosen automatically. During the pre-GA testing
  # window the repo is internal, so the anonymous release URLs 404; an
  # authenticated gh member can still fetch the assets, and gh follows the
  # signed-asset redirect correctly where a plain curl with an Authorization
  # header does not. When the repo is public again gh is simply skipped and the
  # unchanged curl path runs, so the public behavior needs no re-validation.
  # gh is opportunistic, never required: not installed or not authenticated
  # falls through silently to curl.
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    say "Downloading ${asset} (${version}) via gh…"
    # No tag argument means the latest non-prerelease, matching the semantics of
    # the releases/latest/download URL; an explicit tag fetches that exact
    # release (prerelease included), matching the pinned curl URL.
    if [[ "${version}" == "latest" ]]; then
      gh release download -R "${REPO}" \
        --pattern "${asset}" --pattern "checksums.txt" --dir "${tmp}" ||
        die "gh release download failed for ${asset} (latest) from ${REPO}; check 'gh auth status' and that your account can read ${REPO}"
    else
      gh release download "${version}" -R "${REPO}" \
        --pattern "${asset}" --pattern "checksums.txt" --dir "${tmp}" ||
        die "gh release download failed for ${asset} (${version}) from ${REPO}; check 'gh auth status' and that your account can read ${REPO}"
    fi
    # The curl path saves the binary as ${tmp}/lium; rename to match so the
    # checksum/verify/install code below is shared rather than duplicated.
    mv "${tmp}/${asset}" "${tmp}/lium" ||
      die "gh did not download an asset named ${asset} from the ${version} release of ${REPO}"
  else
    if [[ "${version}" == "latest" ]]; then
      base_url="https://github.com/${REPO}/releases/latest/download"
    else
      base_url="https://github.com/${REPO}/releases/download/${version}"
    fi

    say "Downloading ${asset} (${version})…"
    curl -fsSL -o "${tmp}/lium" "${base_url}/${asset}" ||
      die "download failed: ${base_url}/${asset} (if the repo is not public yet, install gh and run: gh auth login)"
    curl -fsSL -o "${tmp}/checksums.txt" "${base_url}/checksums.txt" ||
      die "download failed: ${base_url}/checksums.txt (if the repo is not public yet, install gh and run: gh auth login)"
  fi

  # Verify the binary against the release's published checksum before
  # installing anything onto PATH.
  expected="$(awk -v name="${asset}" '
    {
      file = $2
      sub(/^\*/, "", file)
      if (file == name || file == "bin/" name) {
        print $1
        exit
      }
    }
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
  mv "${tmp}/lium" "${install_dir}/${bin_name}"

  say "Installed ${install_dir}/${bin_name}"
  "${install_dir}/${bin_name}" --version || true

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
}

# Keep all side effects behind the final line: if a `curl | bash` transfer is
# truncated, bash may receive function definitions but cannot run a partial
# installer.
main "$@"
