<#
.SYNOPSIS
  Lium CLI installer for native Windows (PowerShell). Detects the architecture,
  downloads the latest release .exe, verifies its checksum, and installs it on
  PATH. No runtime dependencies - the CLI is a single static binary.

.DESCRIPTION
  Usage:
    irm https://raw.githubusercontent.com/AstroMind-Inc/lium-releases/main/install.ps1 | iex

  Options (environment variables):
    LIUM_VERSION      Release tag to install (default: latest)
    LIUM_INSTALL_DIR  Target directory (default: %LOCALAPPDATA%\Programs\lium)

  On WSL, Git Bash, MSYS2, or Cygwin, use install.sh instead - it installs the
  Linux binary (WSL) or the .exe (Git Bash / MSYS2 / Cygwin).
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Die raises a terminating error rather than calling exit, so `irm | iex` reports
# the failure without killing the caller's session.
function Die($message) {
    throw "install.ps1: $message"
}

$repo = 'AstroMind-Inc/lium-releases'

# GitHub requires TLS 1.2+, which Windows PowerShell 5.1 does not enable by
# default. PowerShell 7+ already negotiates it and is unaffected.
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Older frameworks may not expose Tls12 as an enum member; the download will
    # surface a clear TLS error if the negotiated protocol is actually too old.
}

# Architecture.
switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $arch = 'amd64' }
    'ARM64' { $arch = 'arm64' }
    default { Die "unsupported architecture: $($env:PROCESSOR_ARCHITECTURE)" }
}
$asset = "lium.windows-$arch.exe"

# Version. It becomes a URL path segment for both the binary and its checksum;
# without validation, ../ can traverse into an attacker-owned repository and make
# a malicious binary verify against its own checksum. Mirrors install.sh.
$version = if ($env:LIUM_VERSION) { $env:LIUM_VERSION } else { 'latest' }
$semver = '^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$'
if ($version -ne 'latest' -and $version -notmatch $semver) {
    Die "invalid LIUM_VERSION: $version"
}

$baseUrl = if ($version -eq 'latest') {
    "https://github.com/$repo/releases/latest/download"
} else {
    "https://github.com/$repo/releases/download/$version"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("lium-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $exe = Join-Path $tmp 'lium.exe'
    $sums = Join-Path $tmp 'checksums.txt'

    Write-Host "Downloading $asset ($version)..."
    Invoke-WebRequest -Uri "$baseUrl/$asset" -OutFile $exe -UseBasicParsing
    Invoke-WebRequest -Uri "$baseUrl/checksums.txt" -OutFile $sums -UseBasicParsing

    # Verify against the release's published checksum before installing anything
    # onto PATH. The file may be listed by bare name or with a bin/ prefix, and
    # may use the `*` binary-mode marker - accept all three, like install.sh.
    $expected = $null
    foreach ($line in Get-Content $sums) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2) {
            $file = $parts[1].Trim().TrimStart('*')
            if ($file -eq $asset -or $file -eq "bin/$asset") {
                $expected = $parts[0].Trim().ToLower()
                break
            }
        }
    }
    if (-not $expected) { Die "checksums.txt has no entry for $asset" }
    $actual = (Get-FileHash -Algorithm SHA256 -Path $exe).Hash.ToLower()
    if ($actual -ne $expected) {
        Die "checksum mismatch for ${asset}: expected $expected, got $actual"
    }
    Write-Host 'Checksum verified.'

    $installDir = if ($env:LIUM_INSTALL_DIR) {
        $env:LIUM_INSTALL_DIR
    } else {
        Join-Path $env:LOCALAPPDATA 'Programs\lium'
    }
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Move-Item -Force -Path $exe -Destination (Join-Path $installDir 'lium.exe')
    Write-Host "Installed $installDir\lium.exe"

    # Add to the user PATH if it is not already there. This persists for future
    # sessions; the current session is updated below so `lium` works right away.
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($userPath) { $entries = $userPath -split ';' | Where-Object { $_ -ne '' } }
    if ($entries -notcontains $installDir) {
        $newPath = if ($userPath) { "$userPath;$installDir" } else { $installDir }
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$installDir"
        Write-Host ''
        Write-Host "Added $installDir to your user PATH. Open a new terminal for other apps to see it."
    }

    & (Join-Path $installDir 'lium.exe') --version

    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  lium login    # one-time browser login'
    Write-Host '  lium          # interactive chat'
    Write-Host '  lium guide    # guide for AI coding agents (Claude Code, Cursor)'
} finally {
    Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue
}
