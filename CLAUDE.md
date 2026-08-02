# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`claude-diag` is a two-file distribution: `claude-diag.py` (single-file, stdlib-only diagnostic
generator, ~2300 lines) and `bootstrap.sh` (curl-pipe installer). There is no package, no build
step, and no dependency manifest.

## Essential Commands

Run everything from the repository root.

```sh
python3 claude-diag.py --self-test        # the entire test suite; prints "RESULT: OK" / "RESULT: FAIL", exit 0/1
python3 claude-diag.py --yes --no-save    # non-interactive smoke run; report to stdout, no file written
python3 claude-diag.py --yes --no-context # same, but skips the `claude -p /context` subprocess (much faster)
python3 claude-diag.py --debug            # runs the self-test fixture first, then a real report
python3 claude-diag.py --version
```

There is no linter, formatter, type-checker, or `pyproject.toml` committed. `--self-test` is the
only validation gate — always run it before committing a change to `claude-diag.py`.

`bash bootstrap.sh` does **not** exercise the local script: it downloads `claude-diag.py` from the
live `https://sh.cdiag.link` deployment (`bootstrap.sh:5`) and requires an interactive `/dev/tty`.
To test local Python changes, invoke `claude-diag.py` directly.

## Architecture Overview

Three cooperating pieces:

1. **`bootstrap.sh`** — picks a Python runtime (tries 3.14, 3.13, 3.12 under `/opt/homebrew`,
   `/usr/local`, then `PATH`, then `python3`, then `uv python find`), downloads the script to a
   `chmod 600` temp file, and hands off with stdin bound to `/dev/tty`.
2. **`claude-diag.py`** — organized by banner comments (`# ---- redactor --`, `helpers`, `sections`,
   `publish`, `cli`, `self-test`, `argparse`). `main()` → `build_report()` → `finish_report()`.
3. **`.github/workflows/deploy-pages.yml`** — on push to `main`, copies `bootstrap.sh` to
   `public/index.html` and `claude-diag.py` to `public/claude-diag.py` and deploys to GitHub Pages
   behind `sh.cdiag.link`.

`Redactor` (`claude-diag.py:55`) is the security core and the reason this tool exists. Every
section function receives a `redact: Redact` callable, and `build_report()` additionally re-runs
`redact()` over the fully joined report as a final pass (`claude-diag.py:2135`). Its behaviour is
deliberate, not incidental:

- Public IPs become `[REDACTED:IP]`; RFC1918/loopback/`0.x` addresses are **kept** (`_ip`, line 120)
  because they are diagnostically useful and non-identifying.
- `~/.claude/**` paths are preserved verbatim so reports stay readable; other home paths collapse to
  stable `[HOME-PATH-N]` aliases keyed by parent directory; `~/.claude/projects/<encoded>` collapses
  to `[PROJECT-N]`; the cwd becomes `$PWD`.

## Repository Conventions

- **stdlib only.** Every import in `claude-diag.py` is from the standard library. The curl-pipe
  install path runs a bare interpreter with no `pip install`, so a third-party import breaks the
  product. Add a small local helper instead.
- **Python 3.12 floor.** `bootstrap.sh:332` refuses anything older, and the code already uses PEP 695
  `type` aliases (lines 34-38). Do not introduce 3.13/3.14-only syntax.
- **Never call `subprocess` from a section.** Use `run(cmd, timeout)` (line 273); it normalizes
  timeouts to `("[command timed out]", 124)` and a missing binary to `("[not installed]", 127)`, which
  the sections branch on. Read files with `safe_read()` (line 286), which caps at 512 KB.
- **stdout is the report; stderr is the UI.** Progress, status lines, panels, and prompts all go to
  stderr (`write_progress`, `save_report`, `ui_status`); only `write_report_stdout()` touches stdout.
  This keeps `--yes --no-save > report.md` clean.
- **Injectable streams for testability.** I/O-performing functions take keyword-only
  `input_stream` / `output_stream` / `stdout_stream` / `publisher` parameters with real defaults
  (`finish_report`, `prompt_confirm`, `prompt_select`, `publish_report`). The self-test drives them
  with `io.StringIO` and a fake publisher. Preserve this shape when adding interactive code.
- **`_ = ` discard assignments** are used on 33 ignored return values (`_ = p.add_argument(...)`,
  `_ = output_stream.write(...)`). The file is written for a strict type checker even though no
  config is committed; match the surrounding style.
- **Sensitive content is summarized, never dumped.** `section_hooks` prints event names, matcher
  counts, and command counts only (line 898). Memory-file bodies appear solely behind the explicit
  `--include-memories` flag, and still pass through `redact`.

## Common Change Workflows

**Adding a report section** (all four steps, or the progress counter desynchronizes):

1. Write `section_<name>(redact: Redact, ...) -> str` in the `sections` block, returning Markdown
   that starts with `## Title` and ends with a newline.
2. Register it in `build_report()` via `add("<label>", lambda: section_<name>(redact))`.
3. Increment `total = 17` at `claude-diag.py:2102`.
4. Run `python3 claude-diag.py --yes --no-context --no-save` and confirm the section renders.

**Changing redaction behaviour:**

1. Edit `Redactor` patterns or handlers.
2. Add the new secret shape to `SELF_TEST_FIXTURE` (line 1504) using an obviously fake value.
3. Add the raw value to `forbidden` and the placeholder to `expected` inside `self_test()`; add to
   `keep` instead if the value must survive redaction.
4. Run `--self-test` and confirm `RESULT: OK`.

**Bumping the version:** change `__version__` (line 40) only. It feeds the report header, footer,
the PasteMyst `User-Agent`, and `--version`.

## Testing and Validation

`self_test()` (line 1526) is a hand-rolled harness with no framework. It runs the redaction fixture
inline, then aggregates four helpers that each return a `list[str]` of failure descriptions:

| Helper | Covers |
| --- | --- |
| `_self_test_context` | `/context` invocation and footer usage math, via a fake `claude` executable written to a temp dir and prepended to `PATH` |
| `_self_test_publish` | PasteMyst v2 payload shape and response parsing — pure functions, no network |
| `_self_test_prompts` | `prompt_confirm` / `prompt_select` defaults, retries, and EOF |
| `_self_test_final_flow` | save → publish → print ordering in `finish_report`, with a fake publisher |

New tests belong in the matching helper (or a new `_self_test_*` returning `list[str]`, wired into
the aggregation at lines 1588-1615). Never let a test hit the real PasteMyst API or the real
`claude` binary — inject a fake, as the existing helpers do.

## Critical Gotchas

- **Pushing to `main` publishes immediately.** There is no staging environment; `deploy-pages.yml`
  ships `bootstrap.sh` and `claude-diag.py` straight to `sh.cdiag.link`, which is what
  `curl -fsSL https://sh.cdiag.link | bash` executes on users' machines. Validate with `--self-test`
  before pushing.
- **Renovate automerges everything, including majors, with `ignoreTests: true`** (`renovate.json`).
  Dependency PRs land unreviewed, so GitHub Action version bumps in `deploy-pages.yml` can change
  under you.
- **`.augment/rules/python-314-pro.md` conflicts with this repository's runtime floor.** It
  advocates 3.14-only constructs (t-strings, bracketless `except A, B:`, `Path.copy()`, deferred
  annotations) plus a ruff/uv/pytest/`pyproject.toml` toolchain that this repository does not use.
  Follow `bootstrap.sh`'s 3.12 floor and the existing single-file layout; treat that rules file as
  general background only.
- **The `CLAUDE.md` / `AGENTS.md` strings in `claude-diag.py`** (lines 850-855, 1515-1516, 1576) are
  functional — they are paths the tool inspects on the user's machine and redaction fixtures. Do not
  "clean them up" when editing repository guidance.

## Additional Documentation

- `README.md` — read for the user-facing install and usage story before changing `bootstrap.sh` or
  the published URLs.
- `.github/workflows/deploy-pages.yml` — read before renaming either top-level script or changing
  what gets served at `sh.cdiag.link`.
