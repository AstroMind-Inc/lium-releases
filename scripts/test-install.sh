#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
installer="${repo_root}/install.sh"

fail() {
  printf 'test-install.sh: %s\n' "$*" >&2
  exit 1
}

# Build a fake `gh` in $1 that records its argv to $GH_LOG, exits $2 for
# `gh auth status`, and for `gh release download` writes each --pattern file
# (plus a matching checksums.txt) into the --dir, so the gh download branch can
# be exercised end to end with no network and no real release.
make_gh_shim() {
  cat >"$1/gh" <<SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"\${GH_LOG}"
case "\$1" in
  auth) exit ${2} ;;
  release)
    shift 2 # drop "release" "download"
    dir="."
    patterns=()
    while [[ \$# -gt 0 ]]; do
      case "\$1" in
        --dir | -D) dir="\$2"; shift 2 ;;
        --pattern) patterns+=("\$2"); shift 2 ;;
        -R) shift 2 ;;
        *) shift ;; # tag argument or anything else
      esac
    done
    if command -v sha256sum >/dev/null 2>&1; then sha() { sha256sum "\$1"; }
    else sha() { shasum -a 256 "\$1"; }; fi
    : >"\${dir}/checksums.txt"
    for p in "\${patterns[@]}"; do
      [[ "\${p}" == "checksums.txt" ]] && continue
      printf '#!/bin/sh\necho "lium vTEST"\n' >"\${dir}/\${p}"
      printf '%s  %s\n' "\$(sha "\${dir}/\${p}" | awk '{print \$1}')" "\${p}" >>"\${dir}/checksums.txt"
    done
    exit 0 ;;
esac
exit 0
SHIM
  chmod +x "$1/gh"
}

# LIUM_VERSION controls a URL path segment. Traversal, alternate repositories,
# and malformed tags must fail before the first download.
for version in \
  '../../../../attacker-org/evil-repo/releases/download/v1' \
  '../v1.2.3' \
  'v1.2' \
  'v1.2.3/evil' \
  'v1.2.3%2f..%2fevil' \
  'release-candidate'; do
  output="$(LIUM_VERSION="${version}" bash "${installer}" 2>&1 || true)"
  [[ "${output}" == "install.sh: invalid LIUM_VERSION: ${version}" ]] ||
    fail "invalid version was not rejected before download: ${version}; output=${output}"
done

# The final main call is the only side effect at top level. A curl transfer
# truncated anywhere before it must define code but execute nothing.
truncated="$(awk '/^main "\$@"$/ { exit } { print }' "${installer}")"
output="$(bash <<<"${truncated}" 2>&1)" ||
  fail "truncated installer should parse without running"
[[ -z "${output}" ]] ||
  fail "truncated installer produced output (and may have run): ${output}"

[[ "$(awk 'NF { line = $0 } END { print line }' "${installer}")" == 'main "$@"' ]] ||
  fail 'main "$@" is not the final non-empty line'

# Windows shells (Git Bash / MSYS2 / Cygwin) must resolve to the .exe release
# asset. Shim uname (to report a Windows kernel) and curl (to record the URL and
# stop before any download), so the OS/arch -> asset mapping is exercised with no
# network access.
for uname_s in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
  shim="$(mktemp -d)"
  # Force the curl branch regardless of whether the host has an authenticated
  # gh, so this test always exercises the OS/arch -> asset URL mapping.
  make_gh_shim "${shim}" 1
  export GH_LOG="${shim}/gh.log"
  : >"${GH_LOG}"
  cat >"${shim}/uname" <<SHIM
#!/usr/bin/env bash
case "\$1" in
  -s) printf '%s\n' '${uname_s}' ;;
  -m) printf '%s\n' 'x86_64' ;;
esac
SHIM
  cat >"${shim}/curl" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in https://*) printf '%s\n' "${arg}" >>"${CURL_LOG}" ;; esac
done
exit 22
SHIM
  chmod +x "${shim}/uname" "${shim}/curl"
  export CURL_LOG="${shim}/urls"
  : >"${CURL_LOG}"
  PATH="${shim}:${PATH}" bash "${installer}" >/dev/null 2>&1 || true
  grep -q '/lium\.windows-amd64\.exe$' "${CURL_LOG}" ||
    fail "windows shell ${uname_s} did not request the .exe asset; urls=$(cat "${CURL_LOG}")"
  unset CURL_LOG GH_LOG
  rm -rf "${shim}"
done

# With gh installed and authenticated, the installer must download via the gh
# branch, rename the asset to the shared ${tmp}/lium name, pass checksum
# verification, and install — for both latest and a pinned tag. A curl shim that
# fails loudly proves the network path is not touched.
for spec in "latest:" "pinned:v1.2.3"; do
  label="${spec%%:*}"
  pin="${spec#*:}"
  shim="$(mktemp -d)"
  dest="$(mktemp -d)"
  make_gh_shim "${shim}" 0
  cat >"${shim}/curl" <<'SHIM'
#!/usr/bin/env bash
printf 'curl was called: %s\n' "$*" >>"${CURL_LOG}"
exit 1
SHIM
  chmod +x "${shim}/curl"
  export GH_LOG="${shim}/gh.log"
  export CURL_LOG="${shim}/curl.log"
  : >"${GH_LOG}"
  : >"${CURL_LOG}"
  env_args=("PATH=${shim}:${PATH}" "LIUM_INSTALL_DIR=${dest}")
  if [[ -n "${pin}" ]]; then env_args+=("LIUM_VERSION=${pin}"); fi
  out="$(env "${env_args[@]}" bash "${installer}" 2>&1)" ||
    fail "gh branch (${label}) failed: ${out}"
  printf '%s\n' "${out}" | grep -q 'via gh' ||
    fail "gh branch (${label}) did not announce the gh strategy: ${out}"
  printf '%s\n' "${out}" | grep -q 'Checksum verified.' ||
    fail "gh branch (${label}) did not verify the checksum: ${out}"
  [[ -s "${CURL_LOG}" ]] &&
    fail "gh branch (${label}) fell through to curl: $(cat "${CURL_LOG}")"
  [[ -x "${dest}/lium" ]] ||
    fail "gh branch (${label}) did not install the binary into ${dest}"
  if [[ "${label}" == "pinned" ]]; then
    grep -q "release download ${pin} " "${GH_LOG}" ||
      fail "pinned gh branch did not pass the tag ${pin} to gh: $(cat "${GH_LOG}")"
  fi
  unset GH_LOG CURL_LOG
  rm -rf "${shim}" "${dest}"
done

# gh installed but NOT authenticated must fall through silently to curl, never
# error out or prompt. Shim gh to fail `auth status`, and curl to record the URL
# and stop, so branch selection is observable with no network.
shim="$(mktemp -d)"
make_gh_shim "${shim}" 1
cat >"${shim}/curl" <<'SHIM'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in https://*) printf '%s\n' "${arg}" >>"${CURL_LOG}" ;; esac
done
exit 22
SHIM
chmod +x "${shim}/curl"
export GH_LOG="${shim}/gh.log"
export CURL_LOG="${shim}/curl.log"
: >"${GH_LOG}"
: >"${CURL_LOG}"
PATH="${shim}:${PATH}" bash "${installer}" >/dev/null 2>&1 || true
[[ -s "${CURL_LOG}" ]] ||
  fail "unauthenticated gh did not fall through to curl"
grep -q 'release download' "${GH_LOG}" &&
  fail "unauthenticated gh attempted a release download instead of falling through"
unset GH_LOG CURL_LOG
rm -rf "${shim}"

# Anonymous user with no gh on PATH: the curl branch runs and, on a failed
# download (as during the internal window), the error must carry the actionable
# gh hint. Shim curl to simulate the 404.
shim="$(mktemp -d)"
cat >"${shim}/curl" <<'SHIM'
#!/usr/bin/env bash
exit 22
SHIM
chmod +x "${shim}/curl"
# A PATH that has the shim curl and coreutils but no gh.
no_gh_path="${shim}:/usr/bin:/bin"
out="$(PATH="${no_gh_path}" GH_TOKEN='' GITHUB_TOKEN='' bash "${installer}" 2>&1 || true)"
printf '%s\n' "${out}" | grep -q 'download failed:' ||
  fail "anonymous curl branch did not report a download failure: ${out}"
printf '%s\n' "${out}" | grep -q 'if the repo is not public yet' ||
  fail "anonymous curl failure lacked the gh hint: ${out}"
rm -rf "${shim}"

printf 'installer security tests passed\n'
