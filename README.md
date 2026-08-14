# Lium CLI

Talk to [Lium](https://lium.ai) agents from your terminal — or hand the
controls to Claude Code, Cursor, or any AI coding agent that can run shell
commands.

Lium Workbenches are agent-native data applications: scoped data
connections, domain tools, knowledge, and evaluations, with an analyst agent
on top. This CLI lets you (or your coding agent) ask questions, run deep
analyses, generate reports, and move files in and out — without leaving your
editor.

> **Note:** first public release coming soon. Until binaries appear under
> [Releases](https://github.com/AstroMind-Inc/lium-releases/releases), the
> install command below will not find anything to download.

## Install

macOS and Linux (Intel and ARM), single static binary, no dependencies:

```bash
curl -fsSL https://raw.githubusercontent.com/AstroMind-Inc/lium-releases/main/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/AstroMind-Inc/lium-releases/main/install.ps1 | iex
```

On WSL, Git Bash, MSYS2, or Cygwin, use the `curl … | bash` command above
instead — it installs the Linux binary on WSL and the `.exe` on the others.
Both installers verify the download against the release's published sha256
checksum before installing.

Then:

```bash
lium login    # one-time browser login (or sign-up)
lium          # interactive chat in your workspace
```

## Use it from Claude Code or Cursor

Paste this into your coding agent:

```text
Set up the Lium CLI so you can work with my Lium Workbenches from this session.

IMPORTANT: lium is a non-interactive CLI for you. NEVER run bare `lium` with no
arguments — that opens an interactive UI for humans that you cannot drive.
Always pass the prompt as an argument with --json.

1. Install it (single static binary, no dependencies), then verify:
   curl -fsSL https://raw.githubusercontent.com/AstroMind-Inc/lium-releases/main/install.sh | bash
   lium --version

2. Read `lium guide` in full and follow it for all Lium work from now on.

3. Run `lium login`, give me the URL it prints, and wait — I'll approve (or
   sign up) in my browser. If login says I have no organization yet, ask me
   what to name it and run `lium tenant create "<name>"`.

4. Run `lium workspace list --json` and `lium workspace templates --json`.
   Recommend a workspace or template that fits my work and ask me which to use.

5. Confirm with `lium whoami --json`, then send a first turn:
   lium --json "one-sentence summary of what this workspace can do"
```

That's the whole integration — `lium guide` teaches your agent the JSON turn
protocol, exit codes, how to relay the Lium agent's questions to you
(credentials never touch the agent's transcript), uploads, downloads, and
long-running analyses.

## Updating

The CLI checks for new releases once a day and prints a one-line notice when
an update is available. To update, rerun the install command above. Set
`LIUM_NO_UPDATE_CHECK=1` to disable the check.

## What's here

This repository hosts the install scripts (`install.sh` for macOS/Linux and
Windows shells, `install.ps1` for native Windows) and released binaries (with
checksums) only. The CLI is a thin client — all agent compute runs on the
Lium platform. Both installers verify each binary against the release's
published sha256 checksums before installing it.

## License

The Lium CLI is distributed under the [Apache License 2.0](LICENSE). Use of
the Lium service itself is governed by your Lium account terms.

Copyright 2026 AstroMind, Inc.

The CLI binary statically links permissively licensed open-source
dependencies. Their copyright and license notices are published with every
release as
[THIRD-PARTY-NOTICES.txt](https://github.com/AstroMind-Inc/lium-releases/releases/latest/download/THIRD-PARTY-NOTICES.txt).

## Support

Questions and issues: [lium.ai](https://lium.ai)
