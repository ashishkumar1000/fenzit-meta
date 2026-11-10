---
title: 'Story 21-5: fenzit-app invite — pick the phone number from the phone book, or type it'
type: 'feature'
epic: 'epic-21'
repo: 'fenzit-app'
status: 'review'
spec: 'artifacts/specs/spec-invite-sms-download-link/SPEC.md'
stories_source: 'artifacts/specs/spec-invite-sms-download-link/stories.yaml'
deploy_order: 'independent of the backend; ships with or after 21-4'
spec_checkpoint: true
---

## Status

Built and pushed to fenzit-app `main` as commit `397a896`. The Android device test on the Pixel 6 is still open (see Device test). The design below reflects what was built, with these changes from the first draft: the picker is an icon at the end of the phone field instead of a separate button, the icon is a custom SVG (`ContactCardIcon`), and the name and phone fields use the floating label. Also covered: the same picker on the Add customer phone field, and the Technicians screen title now reads "Employees".

## Intent

When an owner invites an employee, they can either type the phone number or pick one contact from their phone book. Typing stays the default. The picker fills the name and the number, and the owner can still edit both before sending.

## Decisions (owner-approved 2026-11-10)

1. **Picker, not full contacts access.** The phone's own contacts screen opens, the owner picks one contact, and the app receives only that contact. The app never reads the whole phone book.
2. **Library: `react-native-pick-contact`, pinned at exactly `0.0.6`.** Checked on 2026-11-10:
   - Published 2026-08-11, which is older than our two-week rule. Zero dependencies. MIT licence.
   - Its Android manifest declares no permissions. The code reads only the one phone row the owner picks, so the Android picker does not need `READ_CONTACTS`.
   - It uses TurboModules (New Architecture), as CLAUDE.md requires. Peer dependency is React Native 0.76 or later; we are on 0.86 or 0.87.
   - Risk: one maintainer and a 0.0.x version. Pin it exactly. Fallback is in the section below.
   - Correction: the earlier suggestion of `react-native-contacts` was wrong. That library has no picker and always needs full contacts access. It is not used.
3. **Default country code: `+91`.** Matches `DIAL_CODE` in `src/constants/phone.ts`. The pilot is single-country.
4. **No privacy-policy change for this story.** The library asks for no contacts permission, so no new Play Data safety entry is needed.

## Library contract (verified from the 0.0.6 source)

```ts
export type Contact = {
  name: string;          // display name, always present
  phone: string;         // the number the owner tapped, as stored in the phone book
  givenName?: string;
  familyName?: string;
  email?: string;        // ignored by this story
  thumbnailUri?: string; // ignored by this story
};
export function pickContact(): Promise<Contact | null>;
```

- Resolves `null` when the owner cancels.
- Rejects when the picker cannot open. The sheet catches this.
- `phone` is raw text from the phone book. It can contain spaces, dashes, brackets, `+91` or a leading `0`. It is cleaned by `toLocalMobile` (see plan).
- The app uses `name` and `phone` only. `email`, `thumbnailUri`, `givenName` and `familyName` are never read, stored or shown.

## Acceptance criteria

1. **Two ways in, one field.** The phone field keeps its label. Under it sits a helper line, "Type the number, or pick it from your contacts.". A contact-card icon at the end of the field opens the picker. Typing works as it does today. (Built as an icon, not a separate button. Known gap: while a picker error shows, the helper line is hidden, because the field shows the error in its place. Open for owner decision.)
2. **Picker fills the form.** A successful pick sets the name from `contact.name` (trimmed) and the phone from the cleaned number. Under the name field a caption reads "From your contacts. Change it if needed." when the name came from a pick. The owner can edit both before Send invite.
3. **Number cleaning.** Spaces, dashes, brackets and symbols are removed. A leading `91` on a 12-digit result, or a leading `0` on an 11-digit result, is dropped. The result must be exactly `PHONE_LENGTH` (10) digits. Any other result is rejected.
4. **Not a usable number.** If the picked number does not clean to 10 digits, show: "This number isn't a 10-digit mobile number. Type the number instead." The form keeps its previous name and phone.
5. **Several numbers.** The system picker shows the contact's numbers and returns the one the owner taps. The app does not ask again.
6. **Cancel.** A `null` result changes nothing in the form and shows no message.
7. **Picker fails.** A rejected call shows: "Couldn't open your contacts. Type the number instead." Typing still works and the sheet stays open.
8. **Name.** A blank `contact.name` leaves the typed name as it was.
9. **Copy.** Plain English, sentence case. Role words are "Employee", "Admin" and "Viewer". Never "Technician".
10. **Nothing stored.** The picked contact fills the form only. It is not saved to app storage, the backend, analytics or logs. Do not log the phone number.
11. **Disabled while sending.** The picker icon is disabled while the invite is being sent (`submitting`). A caption under it reads "You can't change the number while the invite is sent." A disabled control always says why.
12. **Timeout and freeze.** The picker call is a native hand-off with no network. The button shows a disabled state while the picker is open, so a double tap cannot open two pickers.
13. **Layout and accessibility.**
    - The picker is a 44 px touch target at the end of the phone field, with a 40 px soft-blue tile and a custom contact-card SVG (`ContactCardIcon`, 26 px, brand blue; grey while disabled). Shared as `PickContactButton`.
    - Accessibility label "Pick from contacts" with the hint "Opens your phone's contacts".
    - A picked result, or an error, is announced to screen readers through a live region.
    - Focus goes back to the phone field after a pick or a cancel.
    - The error text is linked to the phone field, so screen readers read them together.
    - Works at 360, 390, 768 and 1280 px. The keyboard must not cover the picker button or the error text when the phone field has focus. Long error text wraps; it must not cut off.

## Code plan

| Step | File | Change |
|---|---|---|
| 1 | `package.json`, `bun.lock` | `bun add --exact react-native-pick-contact@0.0.6`. Nothing else in dependencies changes. |
| 2 | `src/features/technicians/pickedPhone.ts` (new) | Pure function `toLocalMobile(raw: string): string \| null`. Imports `PHONE_LENGTH` from `./constants`. No side effects. |
| 3 | `src/features/technicians/components/AddTechnicianSheet.tsx` | Import `pickContact` from `react-native-pick-contact` and `toLocalMobile` from `../pickedPhone`. Add `pickError` and `nameFromPick` state. Add `handlePickContact`: on success, `markEdited()`, set name and `nameFromPick`, set phone or set `pickError`; on `null`, return; on rejection, set the failure message. After the phone `Input`, add the helper line, the secondary button with its icon and disabled caption, and the error text (linked to the field). Under the name `Input`, add the caption when `nameFromPick` is true. Add the live region and return focus to the phone field after a pick or cancel. |
| 4 | `src/features/technicians/components/AddTechnicianSheet.test.tsx` | Add the mock below and the test cases in the section after this table. |
| 5 | Native build | `bun run android:standalone` with the Pixel 6 connected. This links the new TurboModule. |

Shape of `handlePickContact` (for the builder, not final code):

```ts
const handlePickContact = async () => {
  setPickError('');
  try {
    const contact = await pickContact();
    if (!contact) return;               // cancelled: no change
    markEdited();
    const name = contact.name.trim();
    if (name) setName(name);
    const local = toLocalMobile(contact.phone);
    if (local !== null) setPhone(local);
    else setPickError("This number isn't a 10-digit mobile number. Type the number instead.");
  } catch {
    setPickError("Couldn't open your contacts. Type the number instead.");
  }
};
```

Check the `markEdited()` placement against the existing "edit clears stale server error" rule in the sheet. A pick is an edit, so it clears `submitError`.

## Test plan (mock first, then write after the owner confirms the device behaviour)

**Mock pattern.** The sheet test already mocks other modules with `jest.mock(...)` at the top. Add:

```ts
jest.mock('react-native-pick-contact', () => ({ pickContact: jest.fn() }));
```

Use `jest.mocked(pickContact).mockResolvedValueOnce({ name, phone })` in each case. This keeps the native TurboModule out of Jest.

Test cases:
- **Cleaning (pure, `pickedPhone.test.ts`):** `+91 98765 43210` → `9876543210`; `098765-43210` → `9876543210`; `(0) 98765 43210` → `9876543210`; `9876543210` → `9876543210`; `919876543210` → `9876543210`; `98765` → null; `+1 415 555 0100` → null; empty string → null.
- **Fill:** a valid contact fills name and phone; the Send button enables when the other fields are valid.
- **Blank name:** a contact with name `"  "` keeps the typed name.
- **Not usable:** a 5-digit number shows the message and leaves prior name and phone.
- **Cancel:** `null` leaves the form exactly as it was, with no message.
- **Failure:** a rejected promise shows the failure message, the sheet stays open, and typing still works.
- **Submitting:** while `submitting` is true, the picker button is disabled and its caption is shown.
- **Name caption:** the caption "From your contacts. Change it if needed." shows after a pick and clears when the owner edits the name.
- **Helper line:** the helper line is always shown above the picker button.
- **Copy:** the two error messages match the wording in criteria 4 and 7 exactly.
- **Focus and announce:** after a pick or cancel, focus returns to the phone field; a pick or error is announced through the live region.
- **Double tap:** two presses while the picker is open call `pickContact` once.
- **Error clears:** a pick after a server error clears the server error.

## Device test (Pixel 6, after the owner confirms the build)

1. Install the debug build with `bun run android:standalone`.
2. Open the owner app, Employees, Add. Tap the contact icon at the end of the phone field. The phone's own contacts screen must open with no permission dialog. If a permission dialog appears, stop and report it, because the library's no-permission claim has failed on this device.
3. Pick a contact with a `+91` number. Name and phone fill in. Edit one field and check it saves.
4. Pick a contact with two numbers and choose the second one. The second number fills in.
5. Pick a contact with an international number (`+1`). The "not a 10-digit mobile number" message appears and the form keeps its values.
6. Cancel the picker. The form does not change.
7. Check that the app's permissions page (Settings, Apps, Fenzit, Permissions) lists no Contacts permission.
8. Send an invite with a picked number and check the invite row appears with the right name.
9. At 360 px width, with the phone field focused, check that the keyboard does not cover the picker button or the error text. Check that long error text wraps.

Record the result in the story's dev notes with the device and date.

## Fallback if the library fails on the Pixel 6

- **Step 1:** check that the library's Android code is linked in the build (the module name `PickContact` appears in the app's native build output).
- **Step 2:** if the picker needs a permission on this device, stop. Do not add `READ_CONTACTS` without a new owner decision, because that changes the privacy disclosures.
- **Step 3:** if the library is broken, the fallback is a small native module of about 70 lines (Android `ACTION_PICK` on `ContactsContract.CommonDataKinds.Phone.CONTENT_URI`, iOS `CNContactPickerViewController`). It keeps the same JavaScript API, so the sheet code does not change. This is a new decision, so ask the owner first.

## Repo hygiene

- The `fenzit-app` working tree has uncommitted attendance changes (for example, `src/features/attendance/today/PunchButton.tsx`). They are not part of this story. Stage only the five files in the code plan.
- Commit in `fenzit-app` only. The commit message ends with the `Co-Authored-By` line.
- Do not run `bun add` for anything else in the same change.

## Out of scope

- Reading the whole phone book, searching it, or syncing it.
- Storing contacts in the backend.
- Changing the invite endpoint or the SMS (stories 21-1 and 21-2).
- Picking numbers for anything other than the invite.
- The iOS build and iOS device test (no Xcode machine set up yet). iOS is a follow-up task.

## Done when

- The Android build is installed on the Pixel 6, and the owner has tested the picker and the typing path (device test above).
- The tests in the test plan are written and pass, and `bun run test` is clean.
- `/bmad-code-review` has run and its findings are triaged.
- The owner has agreed to the commit. The commit lands in `fenzit-app` only, with the five files named in the code plan. Nothing is pushed without consent.
