# Heuristic Quality Calibration

This repository tracks `fuck-u-code` as an audit input, not as a hard gate.

## Why the defaults are misleading here

- The Swift analyzer currently falls back to the regex parser in our environment because the packaged Tree-sitter WASM files are missing.
- In that fallback mode, many Swift files report `No functions found`, which makes `complexity`, `structure_analysis`, `error_handling`, and `code_duplication` look healthier than they really are.
- Shell release scripts do get parsed, so `comment_ratio` and file length are still useful there.

The calibration decision for this repo is therefore:

- `swiftformat`, `swiftlint`, `xcodebuild build`, and `xcodebuild test` are blocking quality gates.
- `fuck-u-code` remains non-blocking and is used to spot files that deserve manual review or follow-up issues.

## Baseline used for calibration

Audit run on `2026-04-08` with:

```bash
./scripts/heuristic-quality-report.sh
```

Observed project-level signals from that run:

- `overallScore`: `79.7`
- `comment_ratio` average: `63.3`, but with a `0` minimum and many false positives in tests, generated-like glue, and UI composition files
- `code_duplication` average: `99.6`, but Swift fallback parsing frequently reported `No functions found`
- `structure_analysis` average: `95.9`, also inflated by fallback parsing
- `error_handling` average: `89.8`, again inflated on Swift files with fallback parsing

## Repository thresholds

Use these thresholds when reviewing `fuck-u-code` output:

| Metric | Gate policy | Repository threshold |
| --- | --- | --- |
| `comment_ratio` | Review-only for most files; required on high-risk integration code | `warning` below `8%`; open a follow-up issue below `5%` for `scripts/`, `Services/Hooks/`, `Services/Remote/`, `Services/Window/`, `Services/Tmux/` |
| `error_handling` | Never gate on score alone | Only actionable when a human can point to a swallowed error, `try?`, ignored result, or missing surfaced failure path |
| `code_duplication` | Never gate on score alone | Actionable only when the duplicated logic is behaviorally coupled and changed in parallel, as with tmux / terminal helpers |
| `structure_analysis` | Never gate on score alone | Use as a prompt to inspect files larger than roughly `250` code lines or files mixing unrelated responsibilities |

## Severity mapping

- `warning`: note it in review or capture a small cleanup issue if the file is already being edited.
- `task`: create a `bd` issue when the heuristic lines up with maintainability pain that is easy to isolate.
- `bug`: only escalate if the heuristic corresponds to a real behavior risk, such as silent failure or two branches that can drift.

## Configuration

Repository defaults live in [`.fuckucoderc.json`](../.fuckucoderc.json):

- downweights parser-sensitive structural metrics
- increases the weight of documentation so low-comment high-risk scripts are easier to spot
- excludes `.beads`, `build`, `releases`, `sidecar`, `docs/media`, and archived app bundles

This calibration is intentionally conservative. If `fuck-u-code` ships a stable Swift Tree-sitter parser in CI later, we should revisit the thresholds and decide whether any of these metrics can become blocking.
