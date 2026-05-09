<p align="center">
  <img src="https://raw.githubusercontent.com/engels74/cdiag.link/main/public/favicon.svg" alt="claude-diag Logo" width="256" height="256">
</p>

<h1 align="center">claude-diag</h1>

<p align="center">
  <strong>Redacted Claude Code diagnostics for sharing and support</strong>
</p>

<p align="center">
  <a href="https://github.com/engels74/claude-diag/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Python-3.12%2B-3776AB?logo=python&logoColor=white" alt="Python 3.12+">
  <img src="https://img.shields.io/badge/Bash-4EAA25?logo=gnubash&logoColor=white" alt="Bash">
  <img src="https://img.shields.io/badge/stdlib-only-2E7D32" alt="Python stdlib only">
  <img src="https://img.shields.io/badge/Claude_Code-diagnostics-191919" alt="Claude Code diagnostics">
  <a href="https://deepwiki.com/engels74/claude-diag"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>
</p>

## Usage

Run the bootstrapper:

```sh
curl -fsSL https://sh.cdiag.link | bash
```

Or download and run the single-file script directly:

```sh
python3 claude-diag.py
```

## What It Does

`claude-diag` generates a local Markdown diagnostic report for Claude Code support. It redacts secrets, emails, hostnames, public IPs, and user paths before the report is saved, printed, or optionally shared.

## Repository

- `claude-diag.py` - single-file Python diagnostic tool
- `bootstrap.sh` - installer/bootstrapper served from `https://sh.cdiag.link`

## License

AGPL-3.0. See [LICENSE](LICENSE).
