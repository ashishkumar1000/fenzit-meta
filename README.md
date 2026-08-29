# Fenzo Meta

Fenzo Meta is the control-plane repo for AI-assisted work across the Fenzo product: the `fenzo-app` frontend and the `fenzit-be` backend.

This repo is not an application. It is the durable layer that gives an AI agent (via BMAD) shared context and filesystem access to both child repos at once, so it can plan and make changes across both in a single session.

> **metarepo** (_n_): a repo that coordinates work across multiple child repos by giving agents shared cross-repo context and routing metadata, rather than being the main home of application code.

## What Lives Here

- `docs/repo-catalog.yaml` — the list of registered child repos (id, remote, local path, role, default branch)
- `docs/repos/<repo-id>/` — durable notes per child repo (architecture, cross-repo contracts, conventions)
- `docs/initiatives/` — durable notes for work that spans both repos
- `scripts/setup-workspace.mjs` — clones every registered repo from `docs/repo-catalog.yaml` into `workspace/core/`
- `workspace/core/` — local clones of the registered repos (gitignored — not part of this repo's history)
- `_bmad/` — BMAD install (modules: core, bmm, tea, cis; tool: Claude Code), shared across both child repos
- `CLAUDE.md` — operating rules for the agent, most importantly: which repo's git history a change belongs to

## Getting Started

1. Install dependencies and clone the registered child repos:

   ```bash
   bun install
   bun run workspace:setup
   ```

   This repo uses **bun only** (enforced by a `preinstall` check) — don't use `npm`/`yarn`/`pnpm`.

   This clones:
   - `fenzo-app` → `workspace/core/frontend/fenzo-app`
   - `fenzit-be` → `workspace/core/backend/fenzit-be`

2. BMAD is already installed at this repo's root (`_bmad/`, modules core+bmm+tea+cis, Claude Code tool integration). This is what gives the agent one shared skill/config layer that can see and edit both repos. To add more modules or update later:

   ```bash
   bunx bmad-method install --directory . --action update --modules bmm,tea,cis --tools claude-code
   ```

3. Create a feature branch here in the meta repo if you're tracking cross-repo initiative docs:

   ```bash
   git checkout -b <feature-name>
   ```

4. Before implementation starts, create matching feature branches inside `workspace/core/frontend/fenzo-app` and `workspace/core/backend/fenzit-be` — those are independent git working trees with their own history and remotes.

5. Point BMAD/the agent at this meta repo root. It can now read, edit, and commit in both `workspace/core/frontend/fenzo-app` and `workspace/core/backend/fenzit-be` in the same session.

## Day-to-Day Workflow

- **Changing the frontend or backend?** Work inside `workspace/core/frontend/fenzo-app` or `workspace/core/backend/fenzit-be` directly — each is its own git repo with its own remote and commits. This meta repo's git status does not reflect their status.
- **Changing something that spans both repos?** Note it under `docs/initiatives/` — repo map, shared acceptance criteria, rollout notes — so the context survives across sessions.
- **Changing routing/catalog metadata?** Edit `docs/repo-catalog.yaml` — e.g. to register a new repo or change a default branch.

## Adding Another Repo Later

Add an entry to `docs/repo-catalog.yaml` (id, path, remote, role, default_branch, status, docs_dir) and create a matching `docs/repos/<repo-id>/` folder. Re-run `bun run workspace:setup` — it clones only what's missing and skips repos that already exist locally.
