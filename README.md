# EvoDesign

An AI Designer That Learns to Improve Its Own Taste.

EvoDesign is an AI self-evolution experiment exploring whether an AI designer can improve not only its outputs, but also the rules and prompts that generate those outputs.

## Current Phase

Phase 2 — Evidence-backed Evolution

Phase 1 remains the Generation Zero baseline. Generation 001 is the first recorded evolution cycle.

本机 Codex 自动化已配置为托管每日进化；最新状态见 `rsi-status.json`。

## Live Demo

https://evodesign.pages.dev/

## Phase 1

Phase 1 includes:

- Project introduction
- Automation vs Evolution
- Evolution Loop
- Future System Diagram
- Project Overview Table
- Concept Evolution Preview
- Reflection Example
- Future Design DNA
- Roadmap

## Phase 2 Evidence

- `AGENTS.md` — long-term evolution rules
- `prompts/current.md` — active Design Prompt v1.0
- `prompts/history/v1.0.md` — immutable prompt history
- `prompts/evolve.md` — repeatable evolution-cycle instructions
- `reflections/2026-09-23-gen-001.md` — Generation 001 reflection
- `generations/gen-001.json` — structured generation record
- `logs/2026-09-23-gen-001.log` — execution log
- `rsi-status.json` — machine-readable scheduler, freshness and generation snapshot
- `scripts/evolve.sh` — locked, validated daily evolution runner

Concept previews remain explicitly labeled as concept material. The audit snapshot is maintained separately so external checks do not need to infer local Codex automation from Git history.

## Project Structure

- `index.html` — complete semantic HTML5 concept page
- `styles.css` — responsive editorial visual system
- `script.js` — lightweight scroll-reveal interaction only
- `assets/` — reserved for local static assets (the current site has no external dependencies)

## Technology

- HTML5
- CSS3
- Vanilla JavaScript
- Cloudflare Pages

## Local Preview

Open `index.html` directly in a browser, or serve the directory locally:

```bash
python -m http.server 8000
```

Then visit `http://localhost:8000`.

## Cloudflare Pages

This is a pure static HTML website. No build step is required.

```bash
npx wrangler pages project create evodesign
npx wrangler pages deploy . --project-name=evodesign
```

If Wrangler is not authenticated, first run:

```bash
npx wrangler login
```

## Automatic Deployment

EvoDesign currently uses Cloudflare Pages Direct Upload. Pushes to the GitHub `main` branch are deployed through:

```text
GitHub Actions → Wrangler → Cloudflare Pages
```

The workflow is defined in `.github/workflows/deploy-cloudflare.yml` and always targets the existing `evodesign` Pages project from the repository root.

Required GitHub Actions Secrets:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

Secrets must be configured in GitHub repository settings and must never be committed to this repository.

## Daily Evolution

The daily evolution chain is:

```text
Daily Codex automation → scripts/evolve.sh --preflight → Codex (workspace-write)
→ reflection / generation / log evidence → validation → Git commit and push
→ GitHub Actions → Wrangler → the existing evodesign Cloudflare Pages project
```

### Schedule

One Codex automation runs daily at **09:00 America/Los_Angeles**. It uses the
repository's `scripts/evolve.sh` runner and never starts a second concurrent run.
Each next generation is created only by a verified scheduled or manual run; the current generation and recent decision are recorded in `rsi-status.json`.

The runner uses `gpt-5.5` explicitly. It relies on the local Codex login, so no
GitHub Actions secret is required.


### Preflight

Before enabling or troubleshooting the schedule, run the read-only check from
the repository root:

```bash
scripts/evolve.sh --preflight
```

Preflight verifies the `main` branch, a clean worktree, `origin/main`, the
current and next generation records, Codex authentication, Git credentials,
required prompts/rules, the deployment workflow, and the run lock. It does not
modify the site, create evidence, commit, or push.

The evidence-file requirement does not prohibit a justified website change.
When a real weakness is found, the scheduled run may make one minimal change
to the allowed website or prompt files and record it in the same generation
evidence. Repeated `NO_CHANGE` decisions must either implement the smallest
useful fix or identify a new concrete evidence gap; they must not repeat the
old contract-based reason that website files were not allowed.

### Manual Run

The normal command starts one real evolution cycle and is intended for a
deliberate recovery or test run only:

```bash
scripts/evolve.sh
```

Do not start a manual run while the scheduled run is active. The runner uses an
external lock and aborts instead of running two generations concurrently.

### Counter Smoke Test

Before changing `scripts/evolve.sh`, run the read-only counter sanity check:

```bash
bash scripts/evolution_smoke_test.sh
```

It verifies the `10#$number` numeric parsing and the highest-on-disk
algorithm against an isolated temp directory. Run it any time the runner's
generation-numbering logic is touched. Preflight also performs a
`LIVENESS_DRIFT` cross-check (helper vs. highest gen-N.json on disk) and
logs a `freeze_watch=...` line so a frozen runner becomes visible in the
preflight trace on the next run.

### Disable Daily Evolution

View the single Codex automation in the Codex task settings, then pause or
delete that automation to disable it. Re-enable the same automation (without
creating a duplicate) after running `scripts/evolve.sh --preflight` again.
Operational logs are kept outside the repository under
`~/.local/state/evodesign/`; repository `logs/` contains only per-generation
evidence.

## Future

Phase 2.2 enables the daily, evidence-first evolution runner. Generation 002
and later generations are created only by a verified scheduled execution.
