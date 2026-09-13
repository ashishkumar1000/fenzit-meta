# Story 3: Backend — advance_workflow_step RPC accepts location

## Source

- `SPEC.md` CAP-2 (RPC half — "the advance request carries latitude/longitude/accuracy; the resulting `activity_logs` row for that step contains the captured coordinates in `metadata`")
- `SPEC.md` Constraints — location data is persisted via the existing `activity_logs.metadata` JSONB column on the per-step-advance insert already performed by `advance_workflow_step`; no new `step_completions` table
- `stories.yaml` id `"3"` — "Backend: advance_workflow_step RPC accepts location"

## Acceptance Criteria

1. `advance_workflow_step` gains six new, optional, trailing parameters:
   - `p_latitude DOUBLE PRECISION DEFAULT NULL`
   - `p_longitude DOUBLE PRECISION DEFAULT NULL`
   - `p_accuracy DOUBLE PRECISION DEFAULT NULL`
   - `p_location_captured BOOLEAN DEFAULT NULL`
   - `p_reason TEXT DEFAULT NULL`
   - `p_accuracy_flagged BOOLEAN DEFAULT NULL`
   The last three exist because Story 4 needs somewhere to record *why* location wasn't captured, or that it was low-accuracy — this RPC does no validation of its own, it only stores what `WorkflowService` already decided.
2. When `p_latitude` AND `p_longitude` are both provided (non-NULL), the existing `activity_logs` insert's `metadata` column is populated with an object containing `latitude`, `longitude`, `accuracy`, and any of `locationCaptured`/`reason`/`accuracyFlagged` that were supplied (nulls stripped, never written as explicit `null` keys).
3. A **partial** coordinate pair — `p_latitude` set but `p_longitude` NULL, or vice versa — is treated as no coordinates: falls through to the metadata shape in AC4, never written as a partial `{latitude: ..., longitude: null}` object.
4. When neither coordinate is provided but `p_location_captured` is (e.g. `false`, recording an omission), `metadata` is populated with just `{locationCaptured, reason}` (nulls stripped).
5. When none of the six new parameters are provided, `metadata` is inserted as `NULL` — identical to today's behavior.
6. No other RPC logic changes: the tenant-scoped row lock, the status/expected-step guards (`PT409` on conflict), the `current_step`/`status`/`completed_at` update, and the owner `notifications` insert all remain byte-for-byte as they are today.
7. Existing callers that omit the six new parameters continue to work unmodified (backward compatible signature — additive only, per `fenzo-meta` CLAUDE.md cross-repo ordering rule for additive backend changes).

## Implementation Notes

This is a `CREATE OR REPLACE FUNCTION advance_workflow_step(...)` migration, based on the current definition in `supabase/migrations/20260909000003_rpc_notify_owner_on_advance.sql:11-87`:

```sql
CREATE OR REPLACE FUNCTION advance_workflow_step(
  p_job_id UUID, p_tenant_id UUID, p_actor_id UUID,
  p_step TEXT, p_new_status TEXT, p_expected_current_step TEXT,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_accuracy DOUBLE PRECISION DEFAULT NULL,
  p_location_captured BOOLEAN DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_accuracy_flagged BOOLEAN DEFAULT NULL
) RETURNS SETOF jobs ...
```

The `activity_logs` insert becomes (per `backend-architecture.md` section 2.3):

```sql
INSERT INTO activity_logs (job_id, tenant_id, event_type, actor_id, metadata)
VALUES (
  p_job_id, p_tenant_id, 'step_' || p_step, p_actor_id,
  CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
    jsonb_strip_nulls(jsonb_build_object(
      'latitude', p_latitude, 'longitude', p_longitude, 'accuracy', p_accuracy,
      'locationCaptured', p_location_captured, 'reason', p_reason,
      'accuracyFlagged', p_accuracy_flagged
    ))
  WHEN p_location_captured IS NOT NULL THEN
    jsonb_strip_nulls(jsonb_build_object('locationCaptured', p_location_captured, 'reason', p_reason))
  ELSE NULL END
);
```

Keep every other statement in the function body — the row lock, the `PT409` guard raises, the `jobs` update, the `notifications` insert — exactly as they are in the current migration. Copy the full function body forward and only touch the signature and the one `INSERT INTO activity_logs` statement.

**Explicitly out of scope for this story:** no validation logic of any kind — no coordinate range check, no accuracy threshold check, no `requires_location`/`capture_location_on_steps` gate. This RPC performs no content validation today (confirmed in `backend-architecture.md` section 1: "No content validation of any kind happens in this RPC") and that division of responsibility must hold per `SPEC.md` Constraints. All of that validation is Story 4's job, in NestJS `WorkflowService.advanceWorkflowStep`, before this RPC is ever called. This story only threads six already-decided (or absent) values through to storage.

## Dependencies

- Independent of Stories 1 and 2 at the database level — this migration touches only the RPC function, not `jobs` or `workflow_templates`.
- Logically precedes Story 4, which is the first caller to actually pass non-NULL values into the three new parameters. Story 4 cannot be meaningfully tested end-to-end until this migration is deployed (per the `done_checkpoint` on Story 4 and the cross-repo ordering rule — backend ships before frontend consumes it).

## Testing Notes

- Call the RPC with `p_latitude`/`p_longitude`/`p_accuracy` set → assert `activity_logs.metadata` contains exactly `{"latitude": ..., "longitude": ..., "accuracy": ...}` (no null `locationCaptured`/`reason`/`accuracyFlagged` keys).
- Call the RPC with `p_latitude` set but `p_longitude` NULL (partial pair) → assert `metadata` does NOT contain a partial coordinate object; it falls through per AC3/AC4.
- Call the RPC with only `p_location_captured: false, p_reason: 'not_provided'` (no coordinates) → assert `metadata` is exactly `{"locationCaptured": false, "reason": "not_provided"}`.
- Call the RPC with all six set, including `p_accuracy_flagged: true` → assert it appears in `metadata` alongside the coordinates.
- Call the RPC with none of the six set (existing call shape, e.g. from current NestJS code before Story 4 lands) → assert `metadata` is `NULL`, matching pre-migration behavior exactly.
- Regression: assert the row lock, `PT409` conflict behavior, `current_step`/`status`/`completed_at` update, and the owner `notifications` insert are unchanged — run the existing RPC test suite unmodified against the new signature and confirm all pass.
