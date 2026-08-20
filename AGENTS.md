# AGENTS.md

This file provides guidance to AI coding agents when working with code in this
repository.

`claude-diag` is a two-file product: `claude-diag.py` (single-file, stdlib-only diagnostic
report generator, ~2300 lines) and `bootstrap.sh` (curl-pipe installer). No package, no build
step, no dependency manifest, no `pyproject.toml`.

## Commands

```sh
python3 claude-diag.py --self-test         # the entire test suite; prints RESULT: OK/FAIL, exits 0/1
python3 claude-diag.py --yes --no-context --no-save   # fast smoke run, report to stdout
python3 claude-diag.py --yes --no-save     # full smoke run incl. the `claude -p /context` subprocess
python3 claude-diag.py --debug             # self-test fixture, then a real report
```

No linter, formatter, or type-checker config is committed. `--self-test` is the only gate; run it
before every commit that touches `claude-diag.py`.

`bash bootstrap.sh` does **not** exercise local changes — it downloads `claude-diag.py` from the
live `https://sh.cdiag.link` deployment and needs an interactive `/dev/tty`. To test Python edits,
invoke `claude-diag.py` directly.

## Deployment

`.github/workflows/deploy-pages.yml` runs on every push to `main`: it copies `bootstrap.sh` to
`public/index.html` and `claude-diag.py` to `public/claude-diag.py` and publishes to GitHub Pages
behind `sh.cdiag.link`. There is no staging step — a merge to `main` is what
`curl -fsSL https://sh.cdiag.link | bash` executes on users' machines minutes later.

Renovate automerges every update including majors with `ignoreTests: true`, so action versions in
that workflow change without review.

## Hard constraints

- **stdlib only.** The curl-pipe path runs a bare interpreter with no `pip install`; a third-party
  import breaks the product. Write a local helper instead.
- **Python 3.12 floor.** `bootstrap.sh` refuses older interpreters (it prefers 3.14, then 3.13,
  then 3.12). PEP 695 `type` aliases and `@dataclass(slots=True)` are fine; do not introduce
  3.13/3.14-only syntax.
- **Never call `subprocess` from a section function.** Use `run(cmd, timeout)`, which normalizes a
  timeout to `("[command timed out]", 124)` and a missing binary to `("[not installed]", 127)` —
  sections branch on those exact strings. Read files with `safe_read()` (caps at 512 KB), not
  `open()`.
- **stdout is the report; stderr is the UI.** Progress, status lines, panels, and prompts go to
  stderr; only `write_report_stdout()` writes stdout, keeping `--yes --no-save > report.md` clean.
- **Keep injectable streams.** `finish_report`, `save_report`, `publish_report`, `prompt_confirm`,
  and `prompt_select` take keyword-only `input_stream` / `output_stream` / `stdout_stream` /
  `publisher` with real defaults; the self-test drives them with `io.StringIO` and a fake
  publisher. Match that shape for new interactive code.
- **`_ = ` discard assignments** (33 of them: `_ = p.add_argument(...)`, `_ = stream.write(...)`)
  exist because the file is written for a strict type checker. Match the surrounding style rather
  than removing them.
- **Sensitive content is summarized, never dumped.** `section_hooks` prints event names, matcher
  counts, and command counts only. Memory and agent file bodies appear solely behind
  `--include-memories`, still redacted.

## Redactor

`Redactor` is the reason the tool exists. Every section takes a `redact: Redact` callable, and
`build_report()` re-runs `redact()` over the fully joined report as a final pass. Its behaviour is
deliberate:

- Public IPs become `[REDACTED:IP]`; RFC1918, loopback, and `0.x` addresses are **kept** — they are
  diagnostically useful and non-identifying.
- `~/.claude/**` paths survive verbatim so reports stay readable. Other home paths collapse to
  `[HOME-PATH-N]` aliases keyed by parent directory, `~/.claude/projects/<encoded>` to
  `[PROJECT-N]`, and the cwd to `$PWD`.
- Substitution order in `__call__` matters: secret patterns, then IPs, then query strings and auth
  headers, then hostname, then paths.
- The instance is stateful — alias numbers come from insertion order. One `Redactor` is created in
  `main()` and threaded through everything; do not construct a second one mid-report.

## Change workflows

**Adding a report section** — all four steps, or the progress counter silently desyncs:

1. Write `section_<name>(redact: Redact, ...) -> str` in the `sections` block, returning Markdown
   that starts with `## Title` and ends with a newline.
2. Register it in `build_report()` via `add("<label>", lambda: section_<name>(redact))`.
3. Increment the hardcoded `total = 17` at the top of `build_report()`.
4. Run `python3 claude-diag.py --yes --no-context --no-save` and confirm it renders.

**Changing redaction** — edit `Redactor`, then add the new shape to `SELF_TEST_FIXTURE` with an
obviously fake value, add the raw value to `forbidden` and the placeholder to `expected` in
`self_test()` (or to `keep` if it must survive), and confirm `--self-test` still says `RESULT: OK`.

**Bumping the version** — change `__version__` only. It feeds the report header, the footer, the
PasteMyst `User-Agent`, and `--version`.

## Tests

`self_test()` is hand-rolled, no framework. It runs the redaction fixture inline, then aggregates
four helpers that each return a `list[str]` of failure descriptions: `_self_test_context` (fake
`claude` executable written to a temp dir and prepended to `PATH`), `_self_test_publish` (PasteMyst
payload and response parsing, pure functions), `_self_test_prompts`, and `_self_test_final_flow`
(save → publish → print ordering, fake publisher).

New tests go in the matching helper, or a new `_self_test_*` returning `list[str]` wired into that
aggregation. Never let a test reach the real PasteMyst API or the real `claude` binary.

## Traps

- The `CLAUDE.md` / `AGENTS.md` string literals inside `claude-diag.py` (`section_memories`,
  `SELF_TEST_FIXTURE`, and the `expected` list in `self_test`) are functional: they are paths the
  tool inspects on the *user's* machine and redaction fixtures. Editing repository guidance never
  means touching them.
- `CNAME` exists at the repo root and is also regenerated by the workflow. Changing the domain
  means changing both, plus `SCRIPT_URL` in `bootstrap.sh`.

## Reference rules

- `.agents/rules/python-314-pro.md` — general Python 3.14 idioms and a ruff/uv/pytest/basedpyright
  toolchain. Background only: it advocates 3.14-only constructs (t-strings, bracketless
  `except A, B:`, `Path.copy()`) and a `pyproject.toml` layout this repo deliberately does not
  have. Where it conflicts, the 3.12 floor and the single-file stdlib layout win.
