# Fenzo Meta — Agent Operating Rules

This repo is a control-plane meta repo. It coordinates two independent child repos, each with their own git history and remote:

- `workspace/core/frontend/fenzo-app` → https://github.com/ashishkumar1000/fenzo-app.git
- `workspace/core/backend/fenzit-be` → https://github.com/ashishkumar1000/fenzit-be.git

## Rule: commit and push in the repo the change belongs to — never here

Before running `git add`, `git commit`, or `git push`, check which repo the changed files are actually in:

- Changed a file under `workspace/core/frontend/fenzo-app/`? Run the git commands with that directory as the working directory (or `git -C workspace/core/frontend/fenzo-app ...`), and push to its own remote.
- Changed a file under `workspace/core/backend/fenzit-be/`? Same thing, scoped to that directory and its own remote.
- Changed a file under `docs/`, `artifacts/`, `_bmad/custom/`, or another meta-repo-only path? That commit belongs here, in `fenzo-meta`.

Never run one `git add -A && git commit` from the `fenzo-meta` root and expect it to capture frontend/backend changes — `workspace/core/*` is gitignored here on purpose, and each child repo has its own `.git`. If a commit needs to span a frontend change and a backend change, that means two separate commits in two separate repos (optionally noted together under `docs/initiatives/`), not one commit here.

A pre-commit hook in this repo (`hooks/pre-commit`, wired up via `pnpm install`) rejects any commit here that touches `workspace/core/**` or `workspace/external/**` as a last-resort safety net — but don't rely on it catching mistakes; get the working directory right in the first place.

## Rule: bun only

This repo uses **bun**, never `npm`, `yarn`, or `pnpm` — enforced by a `preinstall` check in `package.json`. Always run `bun install`, `bun run <script>`, `bunx <pkg>` here. Don't generate or commit a `package-lock.json`, `yarn.lock`, or `pnpm-lock.yaml`. This applies to the child repos too — `fenzo-app` and `fenzit-be` are bun-only as well, each with their own `bun.lock`.

## Rule: cross-repo change ordering

`fenzo-app` and `fenzit-be` deploy independently, on their own timelines — a story that touches both is never one atomic release, even though it can be one BMAD session.

- If the change is additive/backward-compatible on the backend (new field, new endpoint, existing behavior untouched): land and merge the `fenzit-be` side first, then the `fenzo-app` side that consumes it.
- If the backend change is breaking (renaming/removing a field, changing a response shape): split it into two backend-safe steps — (1) `fenzit-be` adds the new shape *alongside* the old one, (2) `fenzo-app` switches to the new shape, (3) only afterward, once nothing depends on the old shape, remove it from `fenzit-be` in a separate change.
- Never treat "I edited both repos in this session" as "these ship together." Say explicitly which one should merge/deploy first when handing off a cross-repo story.

## Rule: feature branches

Before implementation work starts on a story that touches a child repo, create a matching feature branch inside that child repo's own working tree (not in `fenzo-meta`, unless the work is meta-repo-only, e.g. a catalog or docs change).

## Where things live

See `README.md` for the full model (`docs/repo-catalog.yaml`, `docs/repos/<id>/`, `docs/initiatives/`, `workspace/core/`). Use BMAD skills under `.claude/skills` (installed via the `bmad-method` npm package: core, bmm, tea, cis) for planning and dev workflows.
