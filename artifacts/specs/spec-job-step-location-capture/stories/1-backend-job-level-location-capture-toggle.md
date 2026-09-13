# Story 1: Backend — job-level location-capture toggle

## Source

SPEC.md CAP-1; stories.yaml id "1".

## Acceptance Criteria

- `CreateJobDto` accepts an optional `captureLocationOnSteps: boolean` field; when omitted, the server defaults it to `true`.
- Creating a job persists the value into a new `jobs.capture_location_on_steps` column.
- Job list and job detail responses surface `captureLocationOnSteps` reflecting the persisted value.
- The value round-trips: create a job with the field explicitly `false`, then GET job detail — the response shows `false`.
- Existing jobs created before this migration read back as `true` (column default).

## Implementation Notes

**Migration** — additive, no backfill needed (pre-launch, per fenzo-meta CLAUDE.md: schema changes are free pre-launch):

```sql
ALTER TABLE jobs ADD COLUMN capture_location_on_steps BOOLEAN NOT NULL DEFAULT true;
```

Add as a new file under `supabase/migrations/`, following the repo's existing `<timestamp>_<description>.sql` naming convention (timestamp greater than the latest existing migration, e.g. `20260913000000_add_capture_location_on_steps.sql`).

**DTO** — `src/jobs/dto/create-job.dto.ts`: add `captureLocationOnSteps?: boolean` with the standard `@IsOptional() @IsBoolean()` decorators matching this DTO's existing style, plus `@ApiPropertyOptional()` — every existing field on this DTO is already Swagger-decorated (`@ApiProperty`/`@ApiPropertyOptional`), and the new field must follow suit or the generated API docs silently omit it. Do not default it in the DTO itself — default server-side (service layer or DB column default) so an omitted field falls through to `true` via the column default, not a hardcoded DTO default that could drift from the migration.

**Serialization** — `src/jobs/jobs.service.ts:213`, `JOB_COLUMNS`: add `capture_location_on_steps` to this constant so it's included in every select that uses it (list + detail queries share this list — this is the single place that keeps both in sync). Map it to `captureLocationOnSteps` in whatever response-shaping step already converts snake_case DB columns to camelCase for the job DTOs (follow the existing pattern for other boolean/scalar job columns, e.g. how `priority` or `status` are mapped today).

No RLS change needed — this is a new column on an already tenant-scoped table (`jobs`), no new table or policy required.

## Dependencies

None — first story in the epic, no upstream story required.

## Testing Notes

- DTO unit test: `captureLocationOnSteps` omitted → validation passes, no DTO-level default asserted (server/DB default is what's under test at the integration layer, not here).
- Integration/e2e test: create a job with `captureLocationOnSteps: false`, then fetch job detail — assert the field is `false`. Create a second job omitting the field — assert detail shows `true`.
- Regression check: existing job-creation tests that don't reference this field must still pass unmodified (additive field, no behavior change for callers that ignore it).
