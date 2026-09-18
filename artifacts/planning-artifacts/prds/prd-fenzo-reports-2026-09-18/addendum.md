# Addendum — Report Module PRD (2026-09-18)

Technical research and rationale that belongs outside the PRD proper. Downstream
inputs for `bmad-architecture` / story writing.

## 1. PDF engine decision (2026-09-18)

**Decision: pdfmake v1, behind a `PdfRenderer` port, Puppeteer/Gotenberg later.**

Render free-tier constraint: 512 MB RAM, 0.1 CPU. NestJS app idles 100–150 MB;
headless Chromium adds ~250–400 MB during render → OOM risk. pdfmake is pure JS
(~few MB), streams output, no browser.

| Option | Memory | Design freedom | Verdict |
|---|---|---|---|
| **pdfmake** | ~30–50 MB | Good: brand colours, logo image, tables, custom fonts, columns; no CSS | **Chosen for v1** |
| Puppeteer + HTML | +250–400 MB (Chromium) | Full CSS (charts, gradients) | Growth path on paid tier |
| @react-pdf/renderer | Small | Flexbox engine, no full CSS | Alternative; pdfmake's doc-definition is simpler for table-heavy reports |
| Gotenberg (Docker sidecar) | None in BE | Full CSS | Best for standalone-module future; adds a 2nd service to manage now |
| pdfkit | Small | Programmatic drawing only | Too low-level for table reports |
| html-pdf / html-pdf-node | — | — | Deprecated/unmaintained — avoid |

pdfmake notes: fonts must be embedded (bundled `Inter` regular/bold as base64
vfonts); `pageMargins` + `footer` for page numbers; logo via `image` node;
long tables auto-paginate (`layout`, header rows repeat).

## 2. Architecture pattern (researched)

Standard pattern across report engines (go-report-engine, .NET
ReportGenerator, Laravel report-registry, reporting-service LLD):
**registry + strategy + pipeline**:

```
Registry (report_type → definition)
  definition = { id, label, paramSchema, dataFetcher(tenantId, params), templateBuilder(data) }
Engine pipeline: validate params → claim queued row (RPC) → fetch data
  → templateBuilder → PdfRenderer port → upload R2 → mark ready/failed → notify
```

- **Registry pattern**: new report = register definition; engine untouched.
- **Strategy/Port**: `PdfRenderer` interface; pdfmake impl v1, Puppeteer/
  Gotenberg impl later — definitions unaffected.
- **State machine on a table** (`report_requests`) instead of a broker/queue:
  no existing job system in fenzit-be; free tier can't run one. In-process
  worker polls `queued` rows; Postgres RPC does atomic claim
  (queued→generating, `PT<status>` SQLSTATE) to prevent double-run.
- **Independence seam**: module imports only `common/` + `storage`; data access
  via Supabase client directly (no imports from jobs/customers modules).
  Extraction checklist: config/env, DB client, R2 creds, notification insert →
  outbox/interface.

## 3. Existing backend patterns to reuse (fenzit-be recon)

- Module skeleton: `src/jobs/jobs.module.ts` + `jobs.controller.ts` (NestJS v11
  + Fastify v5, global prefix `api/v1`, Swagger decorators, `@Roles(...)`,
  `@CurrentUser()`).
- Auth: global JWT guard; `tenantId` claim; `Role.OWNER` for all report routes.
- Idempotency: `IdempotencyInterceptor` + `idempotency_log` (24 h replay) —
  fits FR-1 as-is (replays create-response).
- Error shape: global exception filter `{ statusCode, error_code, message }`;
  add error codes to `error-code.enum.ts`.
- R2: `src/storage/storage.service.ts` (AWS SDK v3) — presign read; extend with
  direct `PutObjectCommand` for report uploads (attachments flow confirms via
  webhook because the *client* uploads; the backend uploads itself here).
- RPC convention: Postgres RPC with `PT<http-status>` SQLSTATE → mapped in
  service layer (see `confirm_attachment`).
- Notification fanout: insert into `notifications` → AFTER INSERT trigger
  broadcasts on Realtime (existing).
- Env: add `REPORT_PRESIGN_TTL_SECONDS` (default 600),
  `REPORT_POLL_INTERVAL_SECONDS` (default 5), `REPORT_MAX_JOBS` (default
  5000), `REPORT_MAX_ATTEMPTS` (default 3) to the Joi schema.
- Deploy: Render docker runtime; `bun dist/src/main.js`.

## 4. Existing frontend patterns to reuse (fenzo-app recon)

- New `src/features/reports/` + route `Reports` on owner `RootStackParamList`;
  entry tile in `features/more/MoreScreen.tsx`.
- Multi-select: `src/components/ui/MultiSelect.tsx` (technician options from
  profile roster).
- Date range: compose two pickers per `features/newJob/components/
  DateTimeFields.tsx`; IST math via `utils/istDate.ts` (no date library).
- API: `src/services/resources/reports.ts` (thin apiClient calls, like
  `attachments.ts`); axios `paramsSerializer` already emits `?ids=a&ids=b`.
- Polling: new pattern (first in app) — small interval loop in `useReports`
  while any request non-terminal; stop when terminal; Realtime
  report-ready notification also refreshes via `OwnerRealtimeBridge`.
- Open PDF: `Linking.openURL` helper in `utils/linking.ts`; presigned URL from
  status endpoint (plain fetch/open, never with auth header).
- States: tiered store + `registerReset()`; `EmptyState`, `InlineError`,
  `ActivityIndicator`; submit guard while POST in flight.

## 5. Brand assets & theme tokens (for the template kit story)

- **Logo (already copied to this run folder):**
  `assets/fenzit-logo.png` — copied from
  `fenzo-app/src/assets/branding/logo@3x.png` (360×360 PNG, 13.5 KB).
  The build story copies it into the BE module (e.g.
  `src/reports/templates/brand-kit/assets/fenzit-logo.png`) and embeds it as
  base64 or via fs read — pdfmake accepts `{ image, width }` nodes.
- **Theme tokens (source of truth: `fenzo-app/src/theme/colors.ts`),**
  mapped to the PDF template kit:
  | Token | Hex | PDF use |
  |---|---|---|
  | Primary (Fenzit Blue) | `#1A56DB` | header band, section titles, table header row |
  | Done / success | `#06956F` | completed status, positive summary numbers |
  | Scheduled / warning | `#D97706` | scheduled/in-progress status |
  | Cancelled / danger | `#C92A2A` | cancelled status, failed |
  | Background | `#F9FAFB` | page/card backgrounds |
  | Text | `#111827` | body text |
  | Cool-gray borders | (see `colors.ts` gray scale) | table borders, card strokes |
- **Fonts:** Inter (Regular 400 / SemiBold 600 / Bold 700 recommended for
  PDF). The FE app embeds static Inter TTFs per `src/theme/fonts.ts`; the BE
  kit bundles the same TTFs as base64 vfonts for pdfmake (pdfmake requires
  embedded fonts; system fonts are not available in Bun).
- **Template-machine layout (pdfmake):** brand kit exports helpers —
  `pageHeader(tenant, title, range)`, `summaryCardRow(cards)`,
  `jobsTable(rows)`, `pageFooter()` returning doc-definition fragments;
  each report template file composes only structure from these helpers.

## 6. Sources

- https://transformy.io/guides/html-to-pdf-node-js/
- https://www.shipgarden.com/gallery/gotenberg-vs-puppeteer-vs-react-pdf-nextjs-pdf-generation-2026
- https://pdf4.dev/blog/pdf-generation-express
- https://www.marketingscoop.com/developer/typescript-pdf-libraries-compared-by-use-case-in-2026/
- https://www.resumelens.org/blog/nodejs/nodejs-pdf-generation
- https://github.com/AshishBagdane/go-report-engine
- https://docs.mostlyoptimal.com/architecture/reporting_architecture.html
- https://www.techinterview.org/post/3233471758/lld-reporting-service/
- https://github.com/Shaunebu/Shaunebu.Bussiness.ReportGenerator
- https://packagist.org/packages/3neti/report-registry