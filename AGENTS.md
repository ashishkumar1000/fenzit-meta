# AGENTS.md

All agent operating rules for this workspace live in [CLAUDE.md](CLAUDE.md) — read it first; it is the single source of truth (BMAD flow, repo and commit boundaries, bun-only, test timing, cross-repo ordering, and the Ponytail × BMAD integration).

Ponytail skills (`ponytail`, `ponytail-review`, `ponytail-audit`, `ponytail-debt`, `ponytail-gain`, `ponytail-help`) are installed under `.agents/skills/` (symlinked into `.zcode/skills/` and `.claude/skills/`) via the skills CLI, tracked in `skills-lock.json`. See the "Ponytail × BMAD" section of CLAUDE.md for how they interact with BMAD: BMAD owns scope, ponytail owns implementation style.
