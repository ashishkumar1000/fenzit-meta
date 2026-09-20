# Story 12.4: Backend — PDF template machine (brand kit + pdfmake renderer)

Status: ready-for-dev
baseline_commit: 18ea107 (fenzit-be) + the staged 12-1..12-3 work on top of it
(migrations 48–52, the `src/reports/` module incl. `engine/` — uncommitted)

> **Implemented 2026-09-20.** pdfmake 0.3.11 + @types 0.3.3 installed
> (user-run; `bun.lock` created but gitignored). Logo + three Inter static
> TTFs (v4.0, from the rsms release zip — Regular 407 KB / SemiBold 414 KB /
> Bold 415 KB) in `templates/brand-kit/assets/`. Kit shipped:
> `brand-theme.ts` (tokens), `brand-assets.ts` (logo data URI + font
> **paths**), `page-chrome.ts` (the four helpers). `PdfmakeRenderer` binds
> `PDF_RENDERER` (stub deleted): fonts register once, `render(doc)` →
> Buffer, access policies locked (no external URLs; local reads allowlisted
> to the fonts dir). Typecheck clean.
>
> **Smoke-verified live** (temp script, deleted after): a 90-row two-page
> doc with the logo, Inter fonts, repeating table header and footer
> callbacks rendered a valid `%PDF-` (43 KB in 57 ms). Two pdfmake 0.3 gotchas
> baked into the kit so they never resurface: font sources must be **string
> paths** (Buffers are typed as PDFFontSource but crash
> `Printer.resolveUrls`), and images take data URIs. Visual check of the
> smoke PDF is with the user (sandbox can't rasterize).

## Story

As a **report template author**,
I want a shared brand kit and a `PdfRenderer` port backed by pdfmake,
So that every report is branded consistently and the renderer can be swapped later without touching templates.

## Acceptance Criteria

1. **Brand kit owns the brand** — **Given** the kit module
   (`src/reports/templates/brand-kit/`) **When** inspected **Then** it owns:
   the Fenzit logo (`assets/fenzit-logo.png`, 360×360, copied from
   `fenzo-app/src/assets/branding/logo@3x.png` — same file the PRD run
   folder already holds), the Inter TTF font files (`Inter-Regular.ttf`,
   `Inter-SemiBold.ttf`, `Inter-Bold.ttf` — weights 400, 600, 700) loaded
   from `assets/fonts/` and embedded as base64 vfonts, and the theme tokens:
   Primary `#1A56DB`, Done `#06956F`, Scheduled `#D97706`, Cancelled `#C92A2A`,
   background `#F9FAFB`, text `#111827`, cool-gray borders (from the FE
   `colors.ts` gray scale).
2. **Page chrome helpers** — **Given** the kit **When** a template composes
   **Then** it gets `pageHeader(tenant, title, range)`,
   `summaryCardRow(cards)`, `jobsTable(rows)` and `pageFooter()`
   (page numbers + generation timestamp + Fenzit wordmark + confidential
   note) returning doc-definition fragments; **no template hard-codes a
   colour, font, or the logo** — all styling flows from the kit.
3. **Pdfmake renderer behind the port** — **Given** the
   `PdfRenderer` port (defined in 12-3) **When** the pdfmake implementation
   renders a doc definition **Then** it returns valid PDF bytes with the
   embedded Inter fonts and the logo available to templates,
   auto-paginating long tables with repeating header rows and page numbers
   in the footer; the module's `PDF_RENDERER` token now binds
   `PdfmakeRenderer` (the stub is deleted).
4. **Dependency tree** — **Given** the dependency tree **When** inspected
   **Then** only `pdfmake` (+ `@types/pdfmake` dev) is added — no
   Chromium/browser dep — and the module still imports only `common/` +
   `storage` (NFR5).
5. **Backend-only story, no app code** — **Given** this story merges,
   **When** reviewed **Then** it ships the kit, the renderer binding, the
   dependency and docs; the first template/fetcher is 12-5 and the FE is
   12-6.

## Tasks / Subtasks

- [ ] Task 1: Assets (AC: 1)
  - [ ] `src/reports/templates/brand-kit/assets/fenzit-logo.png` — copied
        from the PRD run folder copy / fenzo-app (identical file).
  - [ ] `src/reports/templates/brand-kit/assets/fonts/Inter-{Regular,
        SemiBold,Bold}.ttf` — static Inter TTFs downloaded by the user
        (sandbox blocks the fetch); embedded as base64 vfonts.
- [ ] Task 2: Brand kit files (AC: 1, 2)
  - [ ] `brand-theme.ts` — the token map (colours, borders, page margins,
        font names).
  - [ ] `brand-assets.ts` — load fonts from `src/reports/templates/brand-kit/assets/fonts/*.ttf`
        via `fs.readFileSync()`, encode as base64 vfonts, cache at module load.
        Logo data URI (embedded PNG). Map returned as `{ fonts: ..., vfs: ... }`.
  - [ ] `page-chrome.ts` (+ split files if the ~300-line rule demands) —
        the four helpers returning pdfmake fragments, styled only from
        `brand-theme`.
- [ ] Task 3: Renderer (AC: 3)
  - [ ] `engine/pdfmake-renderer.ts` — `PdfRenderer` implementation:
        `PdfPrinter`/`Printer` with the kit's fonts + vfs, `render(doc) →
        Buffer` (collect chunks, never write a temp file), table layouts
        with repeating header rows.
  - [ ] `reports.module.ts` — `PDF_RENDERER` binds `PdfmakeRenderer`;
        **delete `pdf-renderer.stub.ts`** (created in 12-3 as a placeholder, 
        now replaced by the real pdfmake implementation).
- [ ] Task 4: Dependency + docs (AC: 4)
  - [ ] `bun add pdfmake` + `bun add -d @types/pdfmake` (user runs it —
        sandbox network blocked; fenzit-be has **no lockfile**, never
        commit one).
  - [ ] Update `src/reports/README.md` (brand kit section, renderer
        binding) and `docs/` if any contract surface changed (it should
        not — the port signature is unchanged).

## Dev Notes

### Repo and tooling facts

- Repo is **fenzit-be**; work on `main`; review/commit parked (build now).
- **bun only**; **no lockfile** — `bun add` may create `bun.lock`; never
  stage it (`.gitignore` covers it if configured — verify before commit).
- Sandbox network is blocked (proxy) — the user runs `bun add pdfmake`,
  `bun add -d @types/pdfmake`, and the Inter TTF download via `!`.
- **pdfmake version:** Use 0.3.x (current stable; 0.3.11 verified).
  Server-side API: `new Printer(fonts, vfs).createPdfKitDocument(doc)`.
  Do NOT use 0.2.x (`new PdfPrinter(fonts)` API differs). Verify against
  `node_modules/pdfmake/.d.ts` after install.

### Design decisions already made

- Fonts: static TTFs only (Regular/SemiBold/Bold) — pdfmake maps
  bold/semibold through the font descriptor; a variable TTF cannot do that.
- The kit reads its assets at module load (`fs.readFileSync` +
  `toString('base64')`) and caches — no per-render I/O.
- Templates get typed fragment builders (not raw objects) so 12-5's
  template stays structural; the `ReportDocument` type stays
  `Record<string, unknown>` (port unchanged from 12-3).
- Renderer returns a `Buffer` — the pipeline already uploads
  `application/pdf` via `putObject`.

### References

- [Source: artifacts/planning-artifacts/epics-reports.md — Story 12.4]
- [Source: PRD §5.2 FR-T1/FR-T2 + theme block; addendum §5 — asset paths,
  token table, font guidance, helper names]
- [Source: artifacts/implementation-artifacts/12-3-...md] — the
  `PdfRenderer` port + `PDF_RENDERER` token this story binds.