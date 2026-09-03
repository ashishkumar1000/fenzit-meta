# Fenzit Meta — Agent Operating Rules

Control-plane meta-repo. Two child repos, each with its own git history and remote:

- `workspace/core/frontend/fenzo-app` → https://github.com/ashishkumar1000/fenzo-app.git
- `workspace/core/backend/fenzit-be` → https://github.com/ashishkumar1000/fenzit-be.git

## Commit in the repo the change belongs to — never here

- Files under `workspace/core/frontend/fenzo-app/` → run git with that directory as cwd (or `git -C workspace/core/frontend/fenzo-app ...`), push to its own remote. Same for `workspace/core/backend/fenzit-be/`.
- Files under `docs/`, `artifacts/`, `_bmad/custom/`, or other meta-repo-only paths → commit here in `fenzit-meta`.
- Never `git add -A && git commit` from the meta-repo root — `workspace/core/*` is gitignored here on purpose. A change spanning both repos = two commits in two repos (optionally noted together under `docs/initiatives/`).
<!-- Why: each child repo has its own .git, so a root-level add/commit can never capture their changes. -->
- Last-resort net: `hooks/pre-commit` (installed via the husky `prepare` script) rejects commits here touching `workspace/core/**` or `workspace/external/**` — but don't rely on it; get the cwd right.

## Bun only

This repo and both child repos use **bun** — never npm, yarn, or pnpm (enforced by the `preinstall` check in `package.json`). Use `bun install`, `bun run <script>`, `bunx <pkg>`. Never generate or commit `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml` — each repo keeps its own `bun.lock`.

## Cross-repo change ordering

`fenzo-app` and `fenzit-be` deploy independently — a story touching both is one BMAD session but never one atomic release.

- Additive backend change (new field/endpoint, existing behavior untouched) → merge/deploy `fenzit-be` first, then `fenzo-app`.
- Breaking backend change (rename/remove a field, changed response shape) → three steps: (1) `fenzit-be` adds the new shape alongside the old, (2) `fenzo-app` switches to it, (3) only once nothing depends on the old shape, `fenzit-be` removes it in a separate change.
- Never treat "edited both repos in one session" as "these ship together" — always state which repo merges/deploys first when handing off.

## Where things live

Full model in `README.md`: `docs/repo-catalog.yaml`, `docs/repos/<id>/`, `docs/initiatives/`, `workspace/core/`. Use BMAD skills under `.claude/skills` (installed via the `bmad-method` package: core, bmm, tea, cis) for planning and dev workflows.
