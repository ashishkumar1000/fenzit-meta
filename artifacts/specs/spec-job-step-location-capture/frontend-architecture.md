# Frontend Architecture — fenzo-app

Verified against current code (see file paths cited). `fenzo-app` is a **bare React Native CLI app — not Expo** (confirmed: no `expo` package anywhere in `package.json` dependencies).

## 1. Current state (verified)

**`NewJobScreen.tsx`** (`src/features/newJob/NewJobScreen.tsx`, 626 lines, read in full): builds `serviceLocation` as derived plain text only —
```ts
const serviceLocation = useMemo(() => {
  const customer = customers.find(c => c.id === draft.customerId);
  if (!customer) return '';
  return [customer.address, customer.city].filter(Boolean).join(', ');
}, [customers, draft.customerId]);
```
There is **no editable location field and no address/location picker on this screen at all** — the file's own comment flags this as a known gap ("The fix is an editable service-location field on the form"). This corrects an earlier assumption that a job-location picker already existed; it does not. **This feature does not need to add one either** — CAP-1 only needs a boolean toggle, unrelated to location-picking UI.

**`AddressPickerSheet`** (`src/features/addressPicker/AddressPickerSheet.tsx`) has exactly one production usage site: `AddressPickerField.tsx` inside `AddCustomerScreen`, for **customer address only**. Never wired into job creation. Not touched by this feature.

**`jobs.ts` service** (`src/services/resources/jobs.ts`): `CreateJobRequest` (lines 73-93) and `ApiJob` (lines 135-200) carry no latitude/longitude fields. The only coordinates anywhere in the job domain are on the embedded customer inside `GET /jobs/:id` (`JobDetailCustomer.latitude/longitude`, both nullable) — customer-level geodata, unrelated to this feature.

`WorkflowTemplateStep` (lines 46-55) — the shape a new step field extends:
```ts
export interface WorkflowTemplateStep {
  key: string;
  label: string;
  requiresPhoto: boolean;
  requiresSignature: boolean;
  setsStatus: string | null;
  advancesOn: string | null;
}
```

`advanceWorkflow` (lines 408-413) currently posts only `{ step }`:
```ts
async function advanceWorkflow(id: string, step: string, idempotencyKey: string): Promise<ApiJob> {
  const res = await apiClient.post<ApiJob>(`/jobs/${id}/workflow`, { step }, {
    headers: { 'X-Idempotency-Key': idempotencyKey },
  });
  return res.data;
}
```

**Step-completion divert pattern** — `useWorkflowAdvance.ts` (`src/features/technicianApp/`), the hook powering the technician job-detail stepper:
```ts
const advance = useCallback(async (step: string) => {
  if (!jobId || pendingRef.current) return;
  const targetStep = detail?.workflowTemplate?.steps?.find(s => s.key === step);
  if (targetStep?.requiresSignature) {
    onCaptureSignature(targetStep.key);
    return;
  }
  ...
```
A step requiring signature is **diverted to a dedicated capture screen** (`SignatureScreen.tsx`) instead of calling `advanceWorkflow` directly; that screen owns capture → upload → advance. **This is the exact pattern a `requiresLocation` step must follow.**

**Idempotency-key retry convention** (same hook):
```ts
const keyRef = useRef<string | null>(null);
...
const key = (keyRef.current ??= generateIdempotencyKey());
const job = await jobService.advanceWorkflow(jobId, step, key);
keyRef.current = null; // server answered — a retry may be a new submit
```
Minted once per action, reused across retries until the server responds, cleared only on genuine server answer (not on transport failure). This is the **only** retry-safety primitive in the codebase today — there is no offline queue.

**Permission handling** — `photoPicker.ts` (`src/features/technicianApp/`), lines 98-111:
```ts
async function takePhoto(onPicked: (outcome: PickOutcome) => void): Promise<void> {
  try {
    if (Platform.OS === 'android') {
      const granted = await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.CAMERA, {
        title: 'Camera permission',
        message: CAMERA_PERMISSION_MESSAGE,
        buttonPositive: 'Allow',
        buttonNegative: 'Cancel',
      });
      if (granted !== PermissionsAndroid.RESULTS.GRANTED) {
        onPicked({ files: [], error: CAMERA_PERMISSION_MESSAGE });
        return;
      }
    }
    const res = await launchCamera(...);
```
Convention: `PermissionsAndroid.request`, Android-gated, denial short-circuits into a `{ files: [], error: <message> }` outcome shape (not a thrown exception), with a named exported denial-copy constant. iOS relies on the native picker library handling the permission implicitly via Info.plist. **Geolocation differs from camera on iOS** — it requires an explicit authorization request (`Geolocation.requestAuthorization()` or the chosen library's equivalent) even though camera doesn't; the permission flow must account for this platform difference explicitly.

**No geolocation library, no `AsyncStorage`, no `NetInfo`** exist in this codebase today (verified: zero grep hits for `geolocation|expo-location|getCurrentPosition` across `src/`; `package.json` has neither `@react-native-async-storage/async-storage` nor `@react-native-community/netinfo`). Local persistence uses `react-native-mmkv`. Offline handling is explicitly deferred via `EPIC4` TODO markers in `useWorkflowAdvance.ts` and `useSignatureSave.ts` (e.g., "EPIC4: enqueue here... until the offline queue exists, surface the failure inline; the button doubles as the retry").

**Architecture context (verified):** `fenzo-app` runs RN 0.86.0 with React Native's New Architecture enabled (`android/gradle.properties:35`, `newArchEnabled=true`). `package.json` already lists `react-native-nitro-modules@^0.35.10` as a dependency (pulled in transitively by `react-native-mmkv` v4, which is itself a Nitro module) — the Nitro JSI runtime is already present and working in this app.

## 2. Changes required

### 2.1 Add geolocation dependency
Docs: https://react-native-nitro-geolocation.pages.dev/guide/index.html

Add `react-native-nitro-geolocation` (using its `/compat` subpath API, which mirrors `@react-native-community/geolocation`'s callback shape). Not `react-native-geolocation-service` — that library is bridge-only, last published ~4 years ago, and a poor fit for a New-Architecture app; not `expo-location` — no Expo runtime here. `react-native-nitro-geolocation` requires `react-native-nitro-modules` as a peer dependency, which this app already has (see above) — no new native runtime is added, only the geolocation package itself. Requires native config: Android `ACCESS_FINE_LOCATION` (and `ACCESS_COARSE_LOCATION`) manifest permissions, iOS `NSLocationWhenInUseUsageDescription` in `Info.plist`.

### 2.2 Permission flow (consent shown once)
New module mirroring `photoPicker.ts`'s conventions:
- Check current permission status first.
- `granted` → proceed directly, no modal.
- `undetermined` → show consent copy once ("Location required to verify step completion"), then request OS permission (`PermissionsAndroid.request(ACCESS_FINE_LOCATION, ...)` on Android; `Geolocation.requestAuthorization(...)` from `react-native-nitro-geolocation/compat` on iOS).
- `denied` (previously) → skip consent modal, show a Settings-redirect prompt instead.
- Denial outcome shape follows the same `{ error: <message> }` pattern as `photoPicker.ts`, not a thrown exception.

### 2.3 `WorkflowTemplateStep` type + `useWorkflowAdvance.ts` divert
Add `requiresLocation: boolean` to `WorkflowTemplateStep` (mirrors `requiresSignature`). A step may have both `requiresSignature` and `requiresLocation` true — both captures are required before the step advances, chained rather than one silently pre-empting the other. In `useWorkflowAdvance.ts`'s `advance` callback:
```ts
if (targetStep?.requiresSignature) {
  onCaptureSignature(targetStep.key, { thenRequiresLocation: !!targetStep.requiresLocation });
  return;
}
if (targetStep?.requiresLocation) {
  onCaptureLocation(targetStep.key);
  return;
}
```
`SignatureScreen` (whichever container/hook currently ends its flow by calling `advanceWorkflow`) must check the `thenRequiresLocation` flag it's handed: if true, after a successful signature capture it navigates onward to `LocationCaptureScreen` instead of calling `advanceWorkflow` itself; `LocationCaptureScreen` is then the one that finally calls `advanceWorkflow`, carrying both the signature reference and the location fields in one request. If `thenRequiresLocation` is false/absent, `SignatureScreen` keeps its current behavior unchanged (capture → upload → advance directly). A step with `requiresLocation` alone (no signature) reaches `LocationCaptureScreen` directly via the second branch, exactly as before.

A new `LocationCaptureScreen` (or inline sheet, matching whichever the signature flow uses) owns: permission check → GPS fetch (`Geolocation.getCurrentPosition(...)` from `react-native-nitro-geolocation/compat`, 15s timeout, per field-service norms) → on success or graceful failure (CAP-4) → call `advanceWorkflow` with the coordinates attached (plus the signature reference, when it was diverted here after a signature capture).

### 2.4 Extend `advanceWorkflow` request
```ts
async function advanceWorkflow(
  id: string, step: string, idempotencyKey: string,
  location?: { latitude: number; longitude: number; accuracy: number }
): Promise<ApiJob> {
  const res = await apiClient.post<ApiJob>(`/jobs/${id}/workflow`,
    { step, ...(location ?? {}) },
    { headers: { 'X-Idempotency-Key': idempotencyKey } });
  return res.data;
}
```
Reuse the existing `keyRef` idempotency pattern unchanged — no new retry/queue mechanism (per SPEC.md Constraints).

### 2.5 `NewJobScreen.tsx` — toggle only
Add a single switch: "Require technician location when completing steps" (default ON), wired to `captureLocationOnSteps` on the create-job payload. No location-picker UI is added — none exists today for jobs, and none is needed for this feature (CAP-1 is a boolean, not a coordinate).

### 2.6 `CreateJobRequest` / `ApiJob` types
Add `captureLocationOnSteps: boolean` to both, mirroring how the backend DTO exposes it.
