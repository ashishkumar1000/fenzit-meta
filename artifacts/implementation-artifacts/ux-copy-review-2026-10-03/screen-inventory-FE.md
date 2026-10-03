# Fenzo App — FE Screen & Copy Inventory (2026-10-03)

> Evidence file for the UX copy review. Produced by a read-only source exploration of
> `workspace/core/frontend/fenzo-app` at HEAD `c742a0b`. All paths relative to the app root;
> line numbers are file:line at HEAD. ~750+ distinct user-visible strings; there is NO i18n
> layer — all copy is inline string literals plus the label tables in §3.

## 1. Navigation map & role gating

Two nav trees chosen at the App gate (`src/App.tsx:42-82`): onboarding → auth → owner OR technician.

**Owner tree** — `src/navigation/RootNavigator.tsx` (stack) + `MainTabs.tsx` (tabs: Home, Jobs, Customers, More(labelled "Account"))
**Technician tree** — `src/navigation/TechnicianRootNavigator.tsx` (stack) + `TechnicianTabs.tsx` (tabs: Today, History, [Attendance — only when `attendanceAccess !== 'none'`, `TechnicianTabs.tsx:37-57`], Profile)
**Shared** — Notifications, DatePicker (registered in both stacks).

| # | Screen (route) | File | Who | Reached from |
|---|---|---|---|---|
| 1 | Boot splash | `src/features/splash/AnimatedBootSplash.tsx` + `Tagline.tsx` | Both | App launch |
| 2 | Onboarding | `src/features/onboarding/OnboardingScreen.tsx` | Both (owner-oriented copy) | First launch |
| 3 | Login step 1 (phone) | `src/features/auth/screens/PhoneScreen.tsx` | Both | Auth gate |
| 4 | Login step 2 (OTP) | `src/features/auth/screens/OtpScreen.tsx` | Both | Step 1 |
| 5 | Login step 3 (company setup) | `src/features/auth/screens/ProfileScreen.tsx` | Owner only (server 403s technicians) | Step 2 |
| 6 | Home tab | `src/screens/HomeScreen.tsx` | Owner | Tab bar |
| 7 | Jobs tab | `src/features/jobs/JobsScreen.tsx` | Owner | Tab bar |
| 8 | Customers tab | `src/features/customers/CustomersScreen.tsx` | Owner | Tab bar |
| 9 | Account tab (More) | `src/features/more/MoreScreen.tsx` | Owner | Tab bar |
| 10 | Technicians | `src/features/technicians/TechniciansScreen.tsx` | Owner | More tile, Home quick action |
| 11 | New job | `src/features/newJob/NewJobScreen.tsx` | Owner | Jobs/Home quick action |
| 12 | Select skills | `src/features/newJob/SelectSkillsScreen.tsx` | Owner | NewJob "Browse all" |
| 13 | Select customers | `src/features/newJob/SelectCustomersScreen.tsx` | Owner | NewJob "Browse all" |
| 14 | Select technicians | `src/features/newJob/SelectTechniciansScreen.tsx` | Owner (also weekly-off override) | NewJob "Browse all" |
| 15 | Job detail (owner) | `src/features/jobDetail/JobDetailScreen.tsx` | Owner | Any job list |
| 16 | Customer detail | `src/features/customerDetail/CustomerDetailScreen.tsx` | Owner | Customers list |
| 17 | Add customer | `src/features/customers/AddCustomerScreen.tsx` | Owner | Customers/Home/NewJob |
| 18 | Address picker sheet | `src/features/addressPicker/AddressPickerSheet.tsx` | Owner | AddCustomer address field; OfficeMapPicker search |
| 19 | Notifications | `src/features/notifications/NotificationsScreen.tsx` | BOTH | Bells (Home/Jobs/Today) |
| 20 | Reports | `src/features/reports/ReportsScreen.tsx` | Owner | More row |
| 21 | Attendance hub | `src/features/attendance/home/AttendanceHomeScreen.tsx` | Owner | Home tile, More row |
| 22 | Attendance dashboard (Today) | `src/features/attendance/dashboard/AttendanceDashboardScreen.tsx` | Owner | Hub "Today" tile |
| 23 | Attendance monthly | `src/features/attendance/monthly/AttendanceMonthlyScreen.tsx` | Owner | Hub "Monthly" tile |
| 24 | Employee month drill-down | `src/features/attendance/month-detail/AttendanceEmployeeMonthScreen.tsx` | Owner | Monthly row / flag deep-link |
| 25 | Attendance settings | `src/features/attendance/settings/SettingsScreen.tsx` | Owner | Hub "Settings" tile |
| 26 | Team enrolment (roster) | `src/features/attendance/enrolments/RosterScreen.tsx` | Owner | Settings |
| 27 | Full-screen date picker | `src/features/attendance/enrolments/DatePickerScreen.tsx` | BOTH | Roster, leave forms |
| 28 | Weekly off | `src/features/attendance/settings/WeeklyOffScreen.tsx` | Owner | Settings |
| 29 | Holidays | `src/features/attendance/settings/HolidaysScreen.tsx` | Owner | Settings, wizard |
| 30 | Office form | `src/features/attendance/offices/OfficeFormScreen.tsx` | Owner | Offices list / wizard |
| 31 | Office map picker | `src/features/attendance/offices/OfficeMapPickerScreen.tsx` | Owner | Office form |
| 32 | Attendance offices list | `src/features/attendance/offices/OfficesScreen.tsx` | Owner | Hub "Offices" tile |
| 33 | Setup wizard | `src/features/attendance/setup/SetupWizardScreen.tsx` | Owner | Hub focus-gate replace |
| 34 | Owner leave | `src/features/attendance/leave/OwnerLeaveScreen.tsx` | Owner | Hub "Leave" tile, Home strip, notification cards |
| 35 | Apply on behalf | `src/features/attendance/leave/ApplyOnBehalfScreen.tsx` | Owner | OwnerLeave CTA |
| 36 | Today tab | `src/features/technicianApp/TodayScreen.tsx` | Technician | Tab bar |
| 37 | History tab | `src/features/technicianApp/HistoryScreen.tsx` | Technician | Tab bar |
| 38 | Attendance tab | `src/features/attendance/me/AttendanceTabScreen.tsx` | Technician (access-gated) | Tab bar |
| 39 | Attendance intro | `src/features/attendance/me/AttendanceIntroScreen.tsx` | Technician | Attendance tab gate |
| 40 | My month | `src/features/attendance/me/AttendanceMyMonthScreen.tsx` + `AttendanceMyMonth.tsx` | Technician | Attendance tab banner; day sheet |
| 41 | Tech job detail | `src/features/technicianApp/TechJobDetailScreen.tsx` + `components/TechJobDetailContent.tsx` | Technician | Today/History cards, notifications |
| 42 | Signature capture | `src/features/technicianApp/SignatureScreen.tsx` | Technician | Workflow step |
| 43 | Location capture | `src/features/technicianApp/LocationCaptureScreen.tsx` | Technician | Workflow step |
| 44 | Leave apply | `src/features/attendance/leave/LeaveApplyScreen.tsx` | Technician | Attendance tab / day sheet |
| 45 | Tech profile tab | `src/features/technicianApp/ProfileScreen.tsx` | Technician | Tab bar |

Shared components rendered inside screens (all carry copy): `src/components/ui/*` (EmptyState, InlineError, InlineNotice, ConfirmDialog, Sheet, Input, Select, MultiSelect, DatePickerField, TimeField, Calendar, SegmentedControl, Badge, Button), `src/components/` (HomeHeader, Tile, TechnicianPicker, StatusBanner, AttachmentViewer), `src/features/jobDetail/components/*` (shared with technician detail: PersonRow, ActivityTimeline, SectionCard, JobHeaderCard), `src/features/jobs/components/JobCard.tsx` (shared), `src/features/profile/components/EditNameSheet.tsx` (shared).

## 2. Strings by screen

### 2.1 Boot splash — `src/features/splash/components/Tagline.tsx`
- Tagline (animated words, `:9`): `Assign.` `Track.` `Done.`

### 2.2 Onboarding — `src/features/onboarding/OnboardingScreen.tsx`, `data.ts`
- Header: `Skip` (OnboardingScreen.tsx:63)
- Slides (`data.ts:27-52`):
  - `Assign jobs in seconds` / `Send the right worker to the right job, with arrival times your customers can count on.`
  - `Track your team live` / `See where everyone is on a map, so you always know what is happening in the field.`
  - `Done, with proof` / `Every job closes with a photo and location — no more guesswork, no more callbacks.`
- Buttons (`OnboardingScreen.tsx:99`): `Next` / `Get started`

### 2.3 Login — Phone (`src/features/auth/screens/PhoneScreen.tsx`)
- Eyebrow `Step 1 of 3` (:59); heading `Set up your account` (:60); sub `We'll send a 6-digit code to this number.` (:62, OTP_LENGTH interpolated)
- Session-expired banner (:68): `Session expired — please log in again.`
- Input label `Your mobile number` (:76), placeholder `98765 43210` (:79), leading `+91` (DIAL_CODE)
- Local validation (`:51`): ``Enter your ${PHONE_LENGTH}-digit mobile number.``
- Button (:96): `Send OTP` / `Sending…`
- Server-error copies (`AuthFlow.tsx:34-43`): `That doesn't look like a valid mobile number.` / `Too many attempts. Please wait a few minutes and try again.` / fallback = **BE `err.message` verbatim**

### 2.4 Login — OTP (`src/features/auth/screens/OtpScreen.tsx`)
- `Step 2 of 3` (:96); `Enter the code` (:97); `Sent to +91 98765 43210` (:99)
- Resend link (:123-127): `Resending…` / `Resend OTP` / ``Resend OTP in ${m:ss}``
- `Change number` (:132); Button (:143): `Verify & continue` / `Verifying…`
- DEV-only banner (:114): `DEV — OTP is {devOtp} (tap to fill)`
- Error copies (`AuthFlow.tsx:159-181`): `Too many incorrect attempts. Please request a new code.` / `That code expired. Please request a new one.` / `That code is incorrect. Try again.` / fallback = **BE `apiError.message` verbatim** (:181)

### 2.5 Login — company setup (`src/features/auth/screens/ProfileScreen.tsx`)
- `Step 3 of 3` (:66); `Tell us about your business` (:67)
- Inputs: `Business name` (ph `e.g. Cool Air AC Services`), `Your name` (ph `e.g. Ravi Kumar`), `Business type` (MultiSelect, ph `Select your business type(s)`), `City` (ph `e.g. Mumbai`), `State` (ph `Select your state`), `GST number` (ph `27ABCDE1234F1Z5`, helper `Optional — needed only for GST invoices`), link `Add later` (:155)
- Validation (:42-52): `Enter your business name.` `Enter your name.` `Enter your city.` `Select your state.` `Select at least one business type.` `That doesn't look like a valid GSTIN.`
- Options — `auth/constants.ts:25-35`: `AC / HVAC service`, `Electrical service`, `Plumbing service`, `Appliance repair`, `Pest control`, `Cleaning service`, `Carpentry`, `General maintenance`, `Other`; plus 36 India state labels (`:42-79`).
- Button (:173): `Start using Fenzit` / `Setting up…`
- Server errors (`AuthFlow.tsx:46-54`): `Check your GSTIN and state — one of them looks invalid.` / `This account can't set up a company. Contact your business owner.` / fallback BE message

### 2.6 Home tab (owner) — `src/screens/HomeScreen.tsx` + components
- Error empty state (:159-162): `Couldn't load your account` / `Something went wrong. Please try again.` / `Try again`; refresh banner = **store error verbatim** (`:132`)
- Greeting (:220, also HomeHeader.tsx:106, TodayScreen.tsx:121): ``Good morning, ${firstName}`` (fallback `Good morning`) — **hardcoded "morning" at all hours**
- Attendance tile (HomeScreen:202-203): `Attendance` / `Who's in, leave & monthly review` (attendance-enabled tenants only)
- First-run card (:233-243): `Today's jobs` / `No jobs yet` / `Create your first job to assign it to a technician.` / `Add a technician first, then you can create and assign jobs.`
- QuickActions (`home/components/QuickActions.tsx`): `New job` (:92), `Add customer` (:114) + ``${n} total`` (:122), `Add technician` (:147) + ``${n} total`` (:155)
- Stat tiles (`components/HomeHeader.tsx`): `Today` (:147), `Upcoming` (:156); bell a11y (:121-125): `Notifications, N unread`
- TodaysJobsSection (`TodaysJobsSection.tsx`): `Today & needs attention` (:65); empty card `Nothing scheduled today` (:97), `You're all clear. Upcoming work shows in the tiles above.` (:102), button `Create a job` (:106)
- OverdueStrip (`OverdueStrip.tsx`): `Overdue` (:28) + count chip
- LeaveReviewStrip (`LeaveReviewStrip.tsx`): `Leave requests to review` (:28) + count
- GettingStartedCard (`GettingStartedCard.tsx`): `Get set up` (:41), ``${doneCount} of 3`` (:42), steps `Business account created` (:48), `Add your first technician` (:53), `Create your first job` (:59)

### 2.7 Jobs tab (owner) — `src/features/jobs/JobsScreen.tsx` + components
- Header: `Jobs` (:271); bell `Notifications`; button `New job` (:291)
- Scope segments (:56-61): `Today` `Upcoming` `Overdue` `History` (Overdue badge = count)
- Status chips (`StatusFilterBar.tsx:25-31`): `All` `Scheduled` `In progress` `Done` `Cancelled`
- Empty states (:70-123): `No jobs yet` + `Create your first job to assign it to a technician and track it through to completion.` / `Jobs booked for a future date and time will show up here.` / `Jobs a technician has started, but not yet finished, will show up here.` / `Jobs a technician has marked complete will show up here.` / `Jobs called off before completion will show up here.`; `No upcoming jobs` + `Jobs booked for tomorrow or later will show up here.`; `Nothing overdue` + `Jobs past their date that were never finished will show up here.`; `No history yet` + `Jobs marked complete or cancelled will show up here.`; CTA `Schedule a job` (:390)
- DispatchTip (`DispatchTip.tsx:24-25`): `Dispatch tip: ` + `Tap Overdue (N) to clear or reassign delayed assignments.`
- Errors (:329, :346): `Something went wrong` fallback; `Retry` (:337); banner = **store error verbatim**
- JobCard (`JobCard.tsx`): badges `Done` `In Progress` `Scheduled` `Cancelled` (:64-69), `Urgent` (:144); fallbacks `Service` (:93), `Technician` (:178); time formats (see §4); overdue badge ``N day(s) overdue`` (:165); history cancelled time = `Cancelled` (:115)

### 2.8 Customers tab — `src/features/customers/CustomersScreen.tsx`
- `Customers` (:103); button `Add` (:110); search ph `Search customers…` (:122)
- Empty states (:160-180): `No matches` + ``No customer matches "{q}".`` / `Couldn't load customers` + **error verbatim** / `No customers yet` + `Customers are added automatically when you create a job, or you can add them manually.`
- CustomerRow (`CustomerRow.tsx`): `Last {date}` (:52), job count `No jobs` / ``N job(s)`` (customers/format.ts:69-71); date format `12 Jun 25` (format.ts:105-110)

### 2.9 Add customer — `src/features/customers/AddCustomerScreen.tsx`
- `Add customer` (:141 title); `Customer name` (ph `e.g. Ramesh Kumar`), `Phone number` (ph `98765 43210`, leading `+91`), `City` (ph `Mumbai`), `Area` (ph `Andheri West`) (:157-197); address field via AddressPickerField: ph `Tap to search for an address`, helper `Shown to the technician on the job` (:163-164)
- Button (:221): `Add customer` / `Saving…`
- Server-error mapping (`useCreateCustomer.ts:28-37`): `A customer with this phone number already exists.` / `Check the name and phone number — one of them looks invalid.` / `Only the business owner can add customers.` / `Finish setting up your company before adding customers.` / other = BE message

### 2.10 Address picker — `src/features/addressPicker/*`
- Sheet titles (`AddressPickerSheet.tsx:138,150`): `Enter address` + `Saved as text — no map pin`; `Search address` + `Powered by Google Places`; search ph `Search address...` (:159)
- Empty/states (`SearchPhaseBody.tsx`): `Find a verified address` / `Start typing a building, street, or landmark to search.`; `Keep typing` / `A couple more characters to search.`; `No matching address` + ``We couldn't find a match for "{q}".``; CTA `Enter manually`; `Couldn't load suggestions`; error line = **BE/transport message verbatim** (:131, also useAddressAutosuggest.ts:118,240)
- Manual form (`ManualAddressForm.tsx`): back label `Back to address search`, ph `e.g. Flat 302, Sunrise Apartments, Andheri West`, submit `Use this address`

### 2.11 Account tab (More) — `src/features/more/MoreScreen.tsx`
- Title `Account & settings` (:117)
- Account card: role badge = `Owner`/`Technician` (profile/format.ts:27-29); `Edit name` (:146)
- Tiles/rows: `Technicians` + `Add your team` / ``N technician(s)`` (:69-72); `Notifications` + `Job & team updates` / `All caught up` / ``N unread`` (:75-80); `Customers` + `People you serve` / `Add your first customer` / ``N customer(s)`` (:85-89); `Reports` + `Job & attendance reports (PDF)` (:187); `Attendance` + `Who's in, leave & monthly review` (:203); `Log out` (:211)
- Log out dialog (:224-229): `Log out` / `You will need to verify your number again to sign back in.` / confirm `Log out` / cancel `Cancel`

### 2.12 Edit name sheet (shared) — `src/features/profile/components/EditNameSheet.tsx`
- `Edit your name` (:139); `Your name` (ph `e.g. Ramesh Kumar`) (:143,147); error `Something went wrong. Try again.` fallback (:45); save failure renders **BE message verbatim** when present

### 2.13 Technicians — `src/features/technicians/TechniciansScreen.tsx` + `AddTechnicianSheet`
- `Technicians` (:97); button `Add` (:104); skeleton a11y `Loading technicians`
- Errors (:122,138): `Couldn't load your team. Check your connection and try again.` / `Couldn't refresh your team. Check your connection and try again.`
- Empty (:151-152): `No technicians yet` / `Add your team so you can assign jobs to them. They'll get an SMS invite to download the Fenzit app.`
- AddTechnicianSheet: `Add technician` + `They'll get an SMS invite to download the Fenzit app and come online.`; `Name` (ph `e.g. Suresh Kumar`), `Phone number`, `Skills` (ph `Select skills` / `Loading skills…`); note `No skills set up yet — add one from the Skills screen (More tab).` (:129); button `Send invite` / `Sending…` (:188); error map (:39-45): `This phone number is already part of your team.` / `Check the phone number and skills — one of them looks invalid.` / `You don't have permission to invite technicians.` / other = BE message
- TechnicianRow status chips (`technicians/format.ts`): invited/active labels (see constants; e.g. `Invited`, `Active`)

### 2.14 New job — `src/features/newJob/NewJobScreen.tsx` + components
- Header `New job` (:607); back `Go back`
- Section heads: `Skill` (SkillPicker title), `Customer`, `Date & time` (:643), `Technician` (picker title), `Notes for technician` (:668)
- Section status text: `No skills are available yet. Try again shortly.` (:451), `No customers yet. Add your first customer to create a job.` (:508), `No technicians yet. A job has to be assigned to someone, so add a technician before creating one.` (:568), `No technician is tagged with this skill — showing everyone. Pick whoever will do the job.` (:586), `Try again` buttons; section errors = **store error verbatim** (:439,496,556)
- Inline links: `Customer not in list? Add new` (:637), `Add new technician` (:663)
- Past-slot error: `Pick a time in the future.` (:650)
- Notes ph `Any special instructions...` (:672)
- Button (:693): `Create job` / `Creating…`; submit error = **BE `err.message` verbatim** (:360, rendered :685)
- SkillPicker: count chip ``N available``, link `Browse all`, search ph `Search skills`
- CustomerPicker: ``N customer(s)``, `Browse all`, ph `Search customers`
- TechnicianPicker (`newJob/components/TechnicianPicker.tsx`): `Browse all technicians`, ph `Search technician...`
- DateTimeFields (`DateTimeFields.tsx`): labels `Date` / `Time` (:104-105); formats `17 Jun 2026` and `2:00 PM`; iOS sheet `Done` (:132)
- Select screens: titles `Select skills` / `Select customers` / `Select technicians`; subheads `{n} total`, `Clear`; subtitles `Choose the required capability for this job.` (skills), `Choose who this job is for.` (customers); ph `Search skills|customers|technicians`; empty texts (`SelectTechniciansScreen.tsx:274-277`): `No skills are available yet. Try again shortly.` (skills screen :191), `No customers yet. Add your first customer to create a job.`, `No active employees yet. Employees appear here once they accept their invite.` / `No technicians yet. A job has to be assigned to someone, so add a technician before creating one.` / ``No technicians match "{q}"``; footer button `Apply selection`

### 2.15 Job detail (owner) — `src/features/jobDetail/JobDetailScreen.tsx` + components
- Header title = `jobNumber` (BE) else `Job details` (:293); back `Go back`
- Not found (:301-306): `This job isn't available` / `It may have been removed or reassigned.` / `Go back`; load error (:310) = **error.message verbatim** fallback `Something went wrong`; `Retry`
- Workflow card (`WorkflowStatus.tsx`): `WORKFLOW STATUS` (:74); badge labels `All N steps finished` (:39) / `Job cancelled` (:42) / `Not started` (:45) / ``Step N of M`` (:47); step labels = **BE template step.label**
- Actions (`JobActionsSection.tsx`): `Edit job` (:23), `Cancel job` (:30)
- Customer card: `Customer` (:354); buttons `Call` (:395), `Direction` (:412); copy affordances `Copy customer phone number` (:365), copied note `Copied` (:379); hint `No address or location is saved for this customer yet.` (:419)
- Technician card: `Technician` (:426); `Call`, `Direction`; `Copy technician phone number`, `Copied`; hints `Direction is available once the technician's location is captured on a step.` (:493) and `Directions will take you to the technician's last known location, not live tracking.` (:503); skill chips = **BE skill names**
- Photos card: `Photos & signature` (:513); Activity card: `Activity Timeline` (:520)
- ActivityTimeline (`ActivityTimeline.tsx`): labels via eventLabels.ts — `Job created`, `Reassigned to another technician`, `Job cancelled`, `Synced an offline update`, step labels = **BE template**; unknown types render **raw BE event type**; captions `Location not captured` / ``Location not captured — {BE reason}`` / `Location captured` / distance chip + `· low GPS accuracy` (:172); timestamps `12 Aug, 2:14 PM` (en-IN)
- Cancel dialog (:547-552): `Cancel job` / `The technician will no longer see this job.` / confirm `Cancel job` / `Keep job`; failure Alert (:241-243): `Couldn't cancel the job` + **BE message** fallback `Please try again.`
- EditJobSheet (`components/EditJobSheet.tsx`): title `Edit job` + `Only scheduled jobs can be edited.`; fields `Description` (ph `What needs doing?`), `Schedule` (Date & time), `Notes for technician` (ph `Any special instructions...`), `Priority` pills `Normal`/`Urgent` (:70-73), `Technician` picker; hints (:56-59): `Empty or spacing-only text won't save — the field keeps its saved value.` / `You can't remove the technician here — they stay assigned until you pick a different one.`; button `Save changes` / `Saving…`; errors (editJobModel.ts): `Pick a time in the future.`, `End time can't be before start time`, `This job has already started and can't be changed`, `That technician is no longer available`, `Couldn't save your changes. Please try again.` — otherwise **flattened BE message(s)** verbatim
- JobHeaderCard: status badges same vocabulary as JobCard; `Unknown step` fallback (JobHeaderCard.tsx:103)

### 2.16 Customer detail — `src/features/customerDetail/CustomerDetailScreen.tsx`
- Header = customer name; back `Go back`; `Customer since {12 Aug 2026}` (:55 format)
- Not available (:285-286): `This customer isn't available` / `It may have been removed or is from another company.`; error (:294) = **error.message** / `Something went wrong`
- Empty jobs (:314-315): `No jobs yet` / `Jobs for this customer will appear here.`
- HistoryRow (`HistoryRow.tsx`): status labels `Done/In Progress/Scheduled/Cancelled` (:18 map); date `12 Aug 2026`

### 2.17 Notifications (shared) — `src/features/notifications/*`
- Header `Notifications`; `Mark all read` (:394); back `Go back`
- Filter chips (`NotificationFilterBar.tsx:20-24`): `All (n)` `Active (n)` `Completed (n)`
- Empty (:461-485): `No active jobs right now.` / `No completed jobs yet.` / `No notifications yet` + `Updates for you will show up here.` (technician) / `Updates from your technicians — job arrivals, progress, completions and report updates — will show up here.` (owner); CTA `Go to jobs`
- Errors (:407,417,423) = **store error verbatim** / `Something went wrong`; `Retry`
- Job card (`NotificationCard.tsx`): title ``{technician_name} · {job_number}`` (BE payload) else fallback `Job status updated` (notificationCardModel.ts:38,272); status banner = **BE step label uppercased**; timeline stages = **BE template labels**; button `View Job` (:104)
- Report card (`reportNotificationModel.ts`): `Report ready` / `Report failed` / `Report update`; message ``{reportLabel} is ready to view.`` / `Your report is ready to view.` / failedReportCopy (see Reports); badge labels `Ready`/`Failed`
- Attendance/leave/generic cards (`GenericNotificationCard.tsx`): title+message from FE registry — `Holiday added`, `Holiday removed`, `Check-in reminder` + `You haven't checked in yet today.`, `Check-out reminder` + `You haven't checked out yet today.`, `Not checked in` (notificationEventRegistry.ts:165-176); leave titles `Leave applied for you`, `Leave approved`, `Leave rejected`, `Leave revoked`, `Leave cancelled`, `Pending leave` + ``N leave request(s) waiting for approval.``, `Leave updated` (leaveNotificationModel.ts:182-269); messages interpolate **BE payload names/dates/reasons**; fallback `Job status updated` banner (notificationBannerModel.ts:24) with **BE name · job_number · step label**
- Bell badge (`bellBadge.ts:13`): count or `99+`

### 2.18 Reports (owner) — `src/features/reports/*`
- Header `Reports`; polling indicator `syncing...` (:321); back `Go back`
- Form (`ReportRequestForm.tsx`): `Report type`; options (`reportModel.ts:36-43`) `Technician job report` + `Jobs, timing and proofs for your team`, `Attendance report` + `Presence, late marks and hours for your offices`; `Office` (ph `All offices`, helper `Leave empty to include every office`), `Employees` (ph `All employees`, helper `Enrolled employees · leave empty to include everyone` / `Loading your team…`), `Technicians` (ph `All technicians`); range labels `From date` / `To date` (ReportRangeFields.tsx:130); format `17 Jun 2026`
- Validation (`reportModel.ts:119-124`): `Date range is required` / `Start date cannot be after end date` / `End date cannot be in the future` / `Range exceeds 92 days`
- Submit success (:361): `Report queued — you'll be notified when ready`; submit error (:193-194): `You have a report generating. Wait for it to finish before creating another.` / **BE message** / `Something went wrong. Try again.`
- Status badges (`reportModel.ts:131-145`): `Ready` `Generating` `Failed` `Queued`
- Failed-row copy (`reportModel.ts:152-160`): `Report generation failed. Try again.` / `Too many jobs in range. Narrow the date range.` / ``Error (code: {errorCode})`` / `This report failed. Try again.`
- History: `History` heading; retry error (:222) **BE message** / `Could not retry. Try again.`; open errors (:245,250): `This report is still generating. Try again shortly.` / `Failed to open PDF — try again` / `Could not open the report. Try again.`
- Sync-paused banner (:375): `Sync paused — pull to retry` + `Retry`
- Empty (:393-394): `No reports yet` / `Create your first report to get started`
- Row subtitles: `All technicians` / ``N technician(s)``; `All offices · all employees` / ``N offices · N employees`` (reportModel.ts:196-218)

### 2.19 Attendance hub (owner) — `home/AttendanceHomeScreen.tsx`
- Header `Attendance` (:85); tiles: `Today` + `Who's in and who's not`; `Monthly` + `Everyone's month at a glance`; `Leave` + `Pending requests & history`; `Offices` + `Locations & timing rules`; `Settings` + `Weekly off & holidays`

### 2.20 Attendance dashboard — `dashboard/*`
- Header `Today` (DashboardHeader); refresh
- WorkspaceSelector label: office name or `All offices` (:185)
- KPI tiles (`dashboardModel.ts:50-57`): `Tracked`, `Checked in`, `Not checked in`, `Short day`, `Late`, `On leave`
- PresentCard (`PresentCard.tsx`): `Live Sync` (:33), `Auto` (:35), caption ``{n}% workforce present today`` (:43)
- Flag strips (`dashboardModel.ts:104-127`): `Checkout missing` + `No check-out recorded for 1 past day.` / `No check-out recorded for N past days.`; `Fake location attempt` + `GPS spoofing blocked on 1 day.` / `GPS spoofing blocked on N days.` (plural strip title `Fake location attempts` :139); sheet rows: full date `Monday, 14 September 2026` + ` · {office}` + ` · N attempts`
- FlagListSheet title: `Checkout missing` / `Fake location attempts`
- Empty (:230-231): `No one is tracked today` / `Add employees to attendance to see today's summary here.`
- OfficeFilterSheet: `Filter by office` + `Choose which office the numbers show.`; `All offices`; `No offices registered yet`; `No employees tracked here today` / `No employees are tracked at this office today`; error `Couldn't load the offices. Check your connection and try again.`
- LoadErrorRetry: `Couldn't load the dashboard. Check your connection and try again.` + `Retry`

### 2.21 Attendance monthly (owner) — `monthly/*`
- Header row: month name `September 2026`; prev/next a11y `Previous month`/`Next month`; filter `All offices`/office name
- Empty (:218-219): `No attendance to review` / `No one has tracked days in this month. Try another month or office.`
- Row chips (`monthlyModel.ts:132-155`): ``{n} worked``, ``N half day(s)``, ``N late``, ``{n} leave``, ``N absent``, ``N missing checkout``; caption segments: office name, ``N weekly off(s)``, ``N holiday(s)``, ``{n} worked on holiday``
- Drill-down (`month-detail/AttendanceEmployeeMonthScreen.tsx`): header = employee name; hosts MonthCalendar + DayDetailSheet (below) + MyMonthSummary-style summary; error `Couldn't load the monthly view. Check your connection and try again.` (useMonthlyData.ts:46)

### 2.22 Attendance offices (owner) — `offices/*`
- OfficesScreen: header `Offices`; CTA card `Add new office` + `Configure geofence & shift hours`; segment tabs `All (n)` `Active (n)` `Archived (n)`; search ph `Search offices...`; empty `No offices yet` + `Add your first office to start tracking attendance. You'll place its pin on a map.` + `Add office`; filter empty ``No {archived }offices match "{q}"``; `Archived (n)` + `Show/Hide archived offices`; row badges `Active`/`Archived`; row facts ``{radius} m geofence``, `Timing not set` or `09:00 – 18:00`, ``{h}h full · {h}h half``; errors `Couldn't load offices. Check your connection and try again.` / `Couldn't refresh offices. Showing the last loaded list.`; announce `Offices updated`
- OfficeFormScreen: header `Edit office`/`Add office` + badge `Active`; `Office name` (ph `e.g. Andheri branch`); Location card (`OfficeLocationCard.tsx`): `Location`, `GPS Verified`, `Coordinates`, value or `No pin placed yet`, button `Place pin on map` / `Adjust pin on map`; rule fields (`OfficeRuleFields.tsx`): `Start time`, `End time`, `Late cut-off (minutes after start)` + helper `Grace period`, `Full-day hours`, `Half-day hours`; button `Create office`/`Save changes`; `Archive office`; errors (`officeFormModel.ts:97-132`): `Enter an office name`, `Keep the name within 80 characters`, `Place the office pin on the map`, `Radius must be 50–1000 metres`, `Use 24-hour time, e.g. 09:00`, `Use 24-hour time, e.g. 18:00`, `End time must be after the start time`, `Enter the late cut-off minutes`, `Late cut-off must be 0–120 minutes`, `Full-day hours must be greater than 0`, `Half-day hours must be greater than 0`, `Half-day hours must be less than full-day hours`; loads `Could not load this office. Check your connection and try again.`, `This office could not be loaded. Check your connection and try again.`, `That name is already used by another office`, `Employees are still assigned here — reassign them first`, banner `This office is no longer available. It may have been archived.`
- Archive dialog: `Archive office` + ``{name} will stop tracking attendance. This cannot be undone.`` / confirm `Archive office` / `Cancel`
- OfficeMapPickerScreen: header `Place office pin`; address row `Reading address…` / ``Pinned near: {Google address}`` / `lat, lng`; RadiusStepper: `{n} m` + `geofence radius` (a11y `Radius, N metres`); button `Confirm location`; `Open settings`; locate errors (`useLocateMe.ts:38-40`): `Turn on location to place the pin` / `Getting your location took too long. Try again.` / `Could not get your location. Try again.`

### 2.23 Team enrolment — `enrolments/*`
- Header `Team enrolment`; info notice `Turn tracking on per employee — they check in from their assigned office.`; footer `Dates before someone's start date stay Not tracked — nobody is marked absent before tracking begins.`; empty `Invite technicians first` + `Your team roster is empty. Invite technicians from the Home tab, then return here to enrol them.`; errors `Couldn't load your team. Check your connection and try again.` / `Couldn't refresh the roster. Showing the last loaded state.` / `Couldn't save this change. Try again.`
- EnrolmentRow: state pills `Active` `Upcoming` `Not tracked` (:53-57); secondary `Office: {name}`; `Starts {Wed, 30 Sept, 2026}`; toggle `Track attendance for {name}` + `Geofenced check-ins at their assigned office.` / `Tracking begins on their start date — nothing before that.`; move note ``Moves to {office} from {date}``
- Row actions: `Starts today` (chip), `Change office`, `Cancel the {date} start`, reassurance `Nothing happens until {date} — no reminders, no absent marks.`
- OfficePickerSheet: `Choose an office`; empty `No offices yet — add one from Attendance offices first.`; a11y `Assign {office} for {name}`
- ReassignOfficeSheet: `Change office`; button `Move to {office}` / `Pick an office`; field `Effective from` (opens DatePicker titled `Effective from`)
- DatePickerScreen (full-screen): title passed in (e.g. ``Start date for {name}``, `Effective from`, `Choose start date`/`Choose end date`); button `Pick a date` / ``Set {d MMM}``
- Disable confirm: title per kind; confirm `Turn off tracking` / `Cancel start`; cancel `Keep tracking` / `Keep start`

### 2.24 Weekly off (owner) — `settings/WeeklyOff*`
- Header `Weekly off`; refresh banner `Couldn't refresh weekly off. Showing the last loaded selection.`; load error `Couldn't load weekly off. Check your connection and try again.`; success flash `Employee weekly off removed` / `Employee weekly off saved`; default save flash `Weekly off saved`
- Default section: label `Effective from`; validation `Pick at least one working day — a full week off isn't allowed.` / `Pick at least one day off — or save empty to clear the rule.`; save error `Couldn't save. Try again.` or **BE message**; summary `All days working` (weeklyOffModel.ts:56)
- Day picker pills: `M T W T F S S` (full names Monday…Sunday as a11y)
- Overrides section: errors `Couldn't load overrides. Check your connection and try again.` / `Couldn't refresh overrides. Showing the last loaded list.`; picker states (`useOverrideSheet.ts:82-87`): `Loading your team…`, `No employees yet. Add an employee first, then set their weekly off here.`, `No active employees yet. Employees become active after they sign in to the app for the first time — then you can set their weekly off here.`; field button `Pick an employee` / `No employees yet`
- Override sheet: title `Set weekly off` / `Edit weekly off`; label `Effective from`; validation `Pick at least one working day — a full week off isn't allowed.`; remove dialog `Remove weekly off` + message; confirm `Remove` / `Cancel`; footer error `Couldn't save. Try again.` / **BE message**

### 2.25 Holidays (owner) — `settings/Holidays*`
- Header `Holidays` (via ScreenHeader); `Add holiday` CTA; refresh `Couldn't refresh holidays. Showing the last loaded list.`; load `Couldn't load holidays. Check your connection and try again.`; empty `No holidays yet` + `Add tenant-wide holidays so attendance marks these days off for everyone.` + `Add holiday`; flashes `Holiday added` / `Holiday updated` / `Holiday removed`
- HolidayFormSheet: `Add holiday` / `Edit holiday`; `Date` (helper `Date is immutable after creation.`), `Name` (ph `e.g. Diwali`); errors `Pick a valid date.` / `Name is required.` / `A holiday already exists on this date.`; footer `Couldn't save. Try again.` fallback; delete dialog `Delete holiday` + ``{name} ({date}) will be removed. Future dates notify tracked employees.`` / `Delete` / `Cancel`
- HolidayImpactNotice: `Checking impact…`; messages `This date overlaps {Priya|Ramesh}'s approved leave. It will no longer count as leave for them.` / `This date overlaps approved leave for {A, B and C}, plus N more employees. It will no longer count as leave for them.`

### 2.26 Setup wizard (owner) — `setup/*`
- Header `Attendance setup`; back label `Previous step` / `Exit setup`; primary `Continue` / `Enable attendance`; secondary `Skip for now` (holidays step)
- Steps (`wizardModel.ts:45-58`): titles `Offices`(step label), `Timings & hours`, `Weekly off`, `Holidays`, `Employees`; descriptions `Add the places your team works from.` / `Review each office's working hours and rules.` / `Pick the days your team is off each week.` / `Add one-off holidays on top of the weekly off.` / `Choose who tracks attendance and where.`
- Gate lines (:146-197): `Add at least one office to continue.` / `Every office needs its timings set before you continue.` / `Save your default weekly off first.` / `Add at least one office to enable attendance.` / `Turn on attendance for at least one employee assigned to a live office, starting today.`
- Rule summary: `09:00–18:00 · late after 15 min · 8 h full day`
- Steps' local copy: OfficesStep empty `No offices yet` + `Add your first office — its pin on the map and its working hours are what attendance is checked against.` + `Add office`; `Timings not set`; HolidaysStep empty `No upcoming holidays` + `Holidays are optional — weekly off already covers the regular days off. You can add one-off holidays here or any time later.` + `Manage holidays`; `1 upcoming holiday` / `N upcoming holidays`; EmployeesStep empty `Invite technicians first` + `Your team roster is empty. Invite technicians from the Home tab, then return here to enrol them.`; row chips `No office assigned` / `Not tracking attendance`; office empty `No offices yet. Add one from the Offices step first.`; tracking confirm `Turn off tracking` / `Keep tracking`; WeeklyOffStep: `Not set yet` / day list; `Pick the days your team is off each week — everyone works the rest.` / `Everyone works the other days. Individual overrides can be set per employee later.`
- Banners: `Couldn't save your progress. Check your connection and try again.`; `Attendance couldn't be enabled yet. Check the requirements below and try again.`; refresh banners `Couldn't refresh offices|your weekly off|holidays|your team. Showing the last loaded list.`; load errors `Couldn't load offices|your team|holidays|your weekly off. Check your connection and try again.`; permission line `You don't have permission to set up attendance.`

### 2.27 Owner leave — `leave/OwnerLeaveScreen.tsx` + components
- Header `Leave`; CTA card `Apply on behalf` + `Apply leave for a team member`; segments `Pending` / `All`
- Empty: `No pending requests` + `You're all caught up. New leave requests will show up here.` / `No leave requests yet` + `When your team applies for leave, it will show up here.`
- Errors: `Couldn't load leave requests. Check your connection and try again.` / `Couldn't refresh. Showing the last loaded list.` / writes render **BE message verbatim** (ownerLeaveModel.ts:223-238: offline lines `You're offline. Approving|Rejecting|Revoking|Cancelling|Sending the request needs a working connection.`, generic `Something went wrong. Please try again.`, preview `Couldn't load the preview. Check your connection.`)
- Success announces `Leave approved` / `Leave rejected` / `Leave revoked`
- LeaveRequestRow: `{name}` fallback `Team member`; ``{range} · N working days``; split suffix ``N of M days cancelled|revoked``; status chips `Pending` `Approved` `Rejected` `Cancelled` `Revoked` (leaveStatusModel.ts:40-46); compact suffixes ` · First half` / ` · Second half`
- Detail sheet (`LeaveDetailSheet.tsx`): titles `Leave request` / `{name}` / `Revoke leave` / `Cancel this leave request?`; KV rows `Type` (`Full day`/`First half`/`Second half`), `Dates`, `Working days`, `Status`; reason quoted (BE text); handled notice `This request was already handled` + `OK`
- LeaveDetailActions: `Reject` → reason ph `Add a reason (optional)` + counter `n / 500` → `Reject request`, `Back`; `Approve`; approved → `Revoke leave`; read-only → `Cancel request`
- RevokeSheet: `Reason (required)` ph `Why is this leave being revoked?`; confirm `Revoke leave` / `Revoke remaining days`; split hero (leaveSplitModel.ts): ``{range} stays|stay Approved|Pending (already started or past)``, ``{range} will be revoked (including today)``, `Nothing can be revoked — the remaining days are already started or past.`, `This request was already handled`
- CancelSheet: confirm `Cancel request` / `Cancel remaining days`; `Nothing can be cancelled — the remaining days are already started or past.`; `Back`, `Retry`, `OK`
- ApplyOnBehalfScreen: header `Apply on behalf`; `Team member`; `No office`; `Change`; hint `Choose who this leave is for.`; count slot `The working-days count appears once the request is submitted.`; submit button `Approve`; announce prefix `Leave applied for {name}`; error `This person isn't in your team anymore.`
- EmployeePickerSheet: `Choose team member` + `Who is this leave for?`; search ph `Search team members...`; `No office`

### 2.28 Attendance day calendar (shared: owner drill-down + technician My month) — `calendar/*`
- MonthCalendar/RealMonthPane: weekday letters; prev/next `Previous month`/`Next month`; `Loading attendance`
- DayDetailSheet: title = `daySheetTitle(workDate)` (e.g. `Wednesday, 24 Sept 2026` pattern) / `Day detail`; status badge = day-status vocabulary (below); flag chips `Late` / ``Late · {n}m``, `Early` / ``Early · {n}m``, `Fake location`, `Leave pending`, `Corrected` (dayStatusVisual.ts:118-165); detail rows `Check-in` / `Check-out` / `Worked` / `Office` with values like `2:14 PM · 28 m from Andheri branch` + `(next day)`; `· At the office`; correction note card `“{BE note}”` + `Regularized by {BE actor name}`; buttons `Correct day`, `Convert to full day`, `Cancel request`, `Apply leave`; announces `Correction saved`, `Full-day request sent`, `Leave cancelled`; `Loading request`
- Cancel-leave dialog: `Cancel leave request?` + `Are you sure you want to cancel this leave request for {day}? You can apply again any time.`; rows `Period` `Type` (`Full day`/`First half`/`Second half`) `Status` (`Waiting for approval`/`Approved`/`No longer active`); confirm `Cancel request` / `Keep request`
- Convert dialog: `Convert to full day?` + `Your half-day request for {day} will be cancelled, and a new full-day request will be sent. Your owner needs to approve it again. Your reason stays the same.`; rows `Now` (`Half day · …`), `After this` (`Full day · Waiting for approval`); confirm `Cancel and send new request` / `Keep half day`
- CorrectionStage: mode toggle `Times mode` / `Status mode`; `Check-in time` (ph `09:00`, helper `Pick a check-in time`), `Check-out time (optional)` (ph `18:00`), `Note (required)` (ph `What was wrong?`); error `Check-out must be after check-in`; status options = day-status labels + `Half day`; buttons `Save correction` / `Back`
- CorrectionHistory: disclosure `Correction history · {n} corrections`; `Show earlier corrections`; error `Couldn't load the correction history.`; actor fallback `Owner`; change line `{old} → {new}`
- Day-status vocabulary (`services/resources/attendanceDayStatus.ts:156-167`; also legend chips + CorrectionStage options): `Present`, `Not tracked`, `Not checked in yet`, `In progress`, `Weekly off`, `Holiday`, `Worked on holiday`, `Half-day leave`, `Half day`, `Leave`, `Absent`, `Checkout missing`
- DayStatusLegend: `Day status legend` + ``{n} Types``
- Correction offline errors (correctionSavePosture.ts): `You're offline. Correcting attendance needs a working connection.` / `Couldn't save the correction. Check your connection.`; month load `Couldn't load the month. Check your connection and try again.` (useMonthStatuses.ts:59)

### 2.29 Technician — Today tab — `technicianApp/TodayScreen.tsx` + `attendance/today/*`
- Greeting ``Good morning, {name}`` / `Good morning` (:121); bell `Notifications` + badge
- Section eyebrows (`todaySections.ts:21-23`): `IN PROGRESS` `SCHEDULED` `DONE TODAY`
- Empty (:204-217): `No job assigned yet` / `Your owner hasn't assigned you any jobs for today. Check back soon.` / pill `Tap to sync status`
- Errors: store error verbatim + `Retry`; dismissible banner
- PunchSection (`PunchSection.tsx`): announces `Checked in` / `Checked out` / `Refreshing attendance`; `Loading attendance`
- PunchButton (`PunchButton.tsx`): pills `READY` (:50), `SHIFT ACTIVE` (:61), `LOCKED` (:72), `LOCKED OUT` (:82); face label `Check in` / `Check out` (:127-135); sub-labels `Tap to punch`, `Tap to punch out`, `Outside Geofence`, ``Try again in {m:ss}``, `Turn on location to check in`, `Turn on precise location to check in`
- PunchStatusCard copy (`attendanceTodayModel.ts:388-461`): `Getting your location…`; `Within Office Geofence` + chip `READY TO PUNCH` + `You are at {office} ({28 m} away). Location verified via GPS.`; `Shift Active • In Office` + `READY TO PUNCH OUT` + `Checked in at {4:06 PM} ({2 h 05 m} elapsed). Ready to conclude your workday at {office}.`; `Outside Office Geofence` + `PUNCH DISABLED` + `You are {1,357 m} from {office} branch. Move within {200 m} to punch.`; `Out of Bounds for Check-out` + `LOCKED` + `You checked in at {time}. You are currently {N m} away. Move closer to punch out.`; offline `You're offline. Check-in needs a working connection.`; `Too many attempts. Try again in {m:ss}`
- Capture-failure copy (:284-298): `Couldn't get your location. Move to an open area and try again.` / `Attendance needs your location to check in and out. You can still view your records and apply for leave without it.` / `Location services are unavailable. Turn on location and try again.` / `Your location seems outdated. Refresh GPS and try again` / `Could not determine your location. Try again.`
- PunchCard tiles: `Check in` / `Check out` (times or `—`), pill `Total logged` + `{0 h 01 m}`, late `Checked in late by {12 min}`, early `Checked out early by {N}` + ``{N} before shift``
- Pre-flight dialogs (`checkInDialogs.ts`): `It's a holiday. Check in anyway?` + `You are checking in on a holiday.` + `Check in` / `Cancel`; `You're on leave today. Checking in will cancel today's leave. Continue?` + `Your owner will be notified. Only today's leave is cancelled — your other leave days are not affected.` + `Check in` / `Don't check in`
- Punch outcome messages (`attendanceTodayModel.ts:205-233`): rate-limit fallback `Too many attempts. Try again in 10 minutes.`; default `Something went wrong with that request.` — otherwise **BE message verbatim** (server PRD copy e.g. "You are 600 m from …")

### 2.30 Technician — History tab — `technicianApp/HistoryScreen.tsx`
- `History` (:68); empty `No past jobs yet` + `Completed and cancelled jobs will show up here.`; errors verbatim + `Retry`

### 2.31 Technician — Attendance tab — `attendance/me/AttendanceTabScreen.tsx` + me components
- Header `Attendance` + today line `Today, Thursday · 12 Oct` (attendanceMeModel.ts:216-229)
- history_only (:235-243): `Attendance tracking ended on {Wed, 30 Sept, 2026}` / `Attendance tracking has ended` + `You can no longer check in or out, and nothing new is being recorded.`
- upcoming: `Attendance starts on {date}` (attendanceMeModel.ts:61) / fallback `Attendance start scheduled` + `Here's what's already set up for you.`
- BannerCards: `Apply for leave` + chip `Time off` + `Request planned time off or sick leave`; `My month` + chip `{October}` + `Attendance history, calendar & summary`
- AttendanceSummaryView: `Shift & location policy` + `Active rule`; rows (attendanceMeModel.ts:152-188): `Office` + value + chip `Assigned branch`; `Timings` + `9:30 AM – 6:00 PM` + chip `8h shift`/`8h 30m shift`; `Late cut-off` + `Late after 9:45 AM` + chip `15m grace`; `Weekly offs` + `Mon, Sun` / `No weekly offs` + chip `Friday off` / `2 days off`
- Leave section: `Leave`; apply row `Apply for leave`
- Upcoming extra: button `Finish the intro now`
- Errors: `Couldn't refresh just now — these details may be out of date.`; summary load `Could not load your attendance details. Check your connection and try again.`; month `Couldn't load your month summary. Check your connection and try again.`; announce `Refreshing attendance`
- AttendanceLeaveSection/Leave history: `Couldn't load leave requests. Check your connection and try again.`; announce `Leave cancelled`; request rows per 2.27 compact variant

### 2.32 Attendance intro (technician) — `me/AttendanceIntroScreen.tsx`
- `Mark attendance with a tap` (:30); `Check in and out from your office — Fenzo checks your location, so no paperwork and no arguments about who came in.` (:31); `Fenzo only reads your location the moment you check in or out — never in the background.` (:32); `Allow location access` (:33); `Not now — I'll browse without it` (:34); error fallback `Something went wrong. Check your connection and try again.`

### 2.33 My month (technician) — `me/AttendanceMyMonthScreen.tsx`, `AttendanceMyMonth.tsx`, `MyMonthSummary.tsx`, `MyMonthHolidays.tsx`
- Header `My month`; retry `Retry`; stale `Couldn't refresh just now — these numbers may be out of date.`
- Summary tiles a11y/labels (`MyMonthSummary.tsx:69`): `Worked {n}` `Absent {n}` `Days off {n}` `Holiday {n}`
- `Upcoming holidays` (MyMonthHolidays.tsx:23); holiday line `Sunday, 4 Oct 2026` + name
- Day-status legend (2.28); MonthCalendar shared with owner drill-down

### 2.34 Technician — job detail — `technicianApp/TechJobDetailScreen.tsx` + content
- Header = `jobNumber` (BE) else `Job`; back `Go back`; badges `Urgent` + `Done/In Progress/Scheduled/Cancelled`
- Unassigned (`DetailErrorViews.tsx`): `This job is no longer assigned to you` + `It may have been reassigned.` + `Go back`; not found: `This job isn't available` + `It may have been removed or reassigned.` + `Go back`; failed view message = **error.message** / `Something went wrong`
- Progress card (`TechJobDetailContent.tsx`): `Progress` + `Done` / ``{done} of {total}``; stepper rows: **BE step labels**, captions `Up next` / `Waiting to sync`; done timestamp `2:14 PM`
- Customer card: `Customer`; a11y `Open in maps`
- Job details card: `Job details`; date `12 Aug 2026`; time `2:00 – 4:00 PM`; skill = **BE skill name** or `Service`; description = BE text
- `Notes from owner` card (BE text)
- Photos card: `Photos`; grid caption `Up to 5 photos · JPG, PNG or HEIC · max 10 MB`; tile words `Preparing` `Uploading` `Saving`; `Failed`; `Limit reached (5)`; `Add photo`; a11y `View photo 1 of 5`, `Retry upload`; validation `Only JPG, PNG or HEIC up to 10 MB`; picker alert (`photoPicker.ts`): `Add photo` → `Take photo` / `Choose from gallery` / `Cancel`; `Camera permission` + `Camera permission is needed to take photos`; `Could not open the camera` / `Could not open the gallery` (or **OS errorMessage**)
- Customer signature card: `Customer signature`; placeholder `Captured at the signature step.`; `Re-capture`; a11y `View customer signature`
- History card: `History` + a11y `Show history`/`Hide history`; reuses ActivityTimeline
- Action bar (`WorkflowActionBar.tsx`): button label = **BE next-step label** or `Continue`; pill `Upload a photo to continue`; completed row `Job completed`; error line = **BE message** / `This job can no longer be updated` (409 fixed copy) / offline message

### 2.35 Signature capture — `technicianApp/SignatureScreen.tsx` + `useSignatureSave.ts`
- Header `Customer signature`; instruction `Please ask the customer to sign below.`; pad hint `Sign here`; buttons `Clear` / `Save signature`
- Errors: `Signature upload needs internet.` (offline); `Signature pad failed to load — go back and try again.`; other upload failures surface **BE message** via the shared upload pipeline

### 2.36 Location capture — `technicianApp/LocationCaptureScreen.tsx` + `geolocation.ts`
- Header `Verify location`; `Getting your location...`; buttons `Try again` / `Retrying…` / `Cancel`
- Error line = **BE/transport message** (err.message; e.g. `Location permission denied. Go to Settings to enable location access.`, `Location access was denied. Go to Settings and select "Allow While Using App".`, `Location permission is needed to verify step completion.`, `Location access is needed to verify step completion.`)
- OS rationale dialog (`geolocation.ts:42`): title `Location Permission`, message `Allow Fenzo to access your location to verify step completion`

### 2.37 Technician profile — `technicianApp/ProfileScreen.tsx`
- Role line `Technician` (hardcoded, :71); `Edit name`; phone row; `Log out` row; dialog `Log out` / `You will need to verify your number again to sign back in.` / `Log out` / `Cancel`

### 2.38 Leave apply (technician) — `leave/LeaveApplyScreen.tsx` + fields
- Header `Apply for leave`; a11y `View leave policy`; policy sheet `Shift & location policy`; policy load error `Could not load your policy details. Check your connection and try again.` or **BE message**
- Fields: `Type` segments `Full day` / `First half` / `Second half` (leaveApplyModel.ts:51-53); `Dates`; rows `From` / `To` (placeholder `Optional`, `Clear`); count chip ``N working day(s)``; hints `Pick dates to see the working-days count.`; reset note `Leave type reset to Full day — half day applies to a single date only.`; preview errors: FE `Couldn't update the working-days count. Check your connection.` else **BE message verbatim**
- `Reason (required)`; preset chips `Sick leave` `Personal` `Family event` `Doctor visit`; ph `Why do you need leave?`; counter `n / 500`
- Submit `Submit for approval`; errors `You're offline. Submitting leave needs a working connection.` / **BE message verbatim** / `Something went wrong. Please try again.`; announce `Leave request submitted`; picker titles `Choose start date` / `Choose end date`

### 2.39 Shared components (copy emitted anywhere)
- EmptyState: props `title` / `description` / `ctaLabel`
- InlineError: dismiss `Dismiss`; InlineNotice: dismiss `Dismiss`
- ConfirmDialog default cancel `Go back`
- Sheet header close `Close`
- Select placeholder default `Select…`; MultiSelect confirm `Done`
- TimeField: `Clear`, a11y `Opens the time picker.`, iOS `Done`
- DatePickerField a11y: ``{label}: {date}`` / ``{label}: not selected, tap to pick``
- AttachmentViewer: `Customer signature` header
- Tile/MoreTile/MoreRow/SectionHead/Eyebrow/Avatar/Badge/Button/SegmentedControl: text only via props

## 3. Constants files with user-facing content
- `src/constants/phone.ts` — `+91`, 10-digit length (rendered as leading `+91`)
- `src/features/auth/constants.ts` — OTP length 6; resend 45 s; `BUSINESS_TYPES` (9 options); `INDIA_STATES` (36 labels)
- `src/features/jobDetail/eventLabels.ts` — activity-event label map
- `src/features/onboarding/data.ts` — slide copy
- `src/features/jobs/format.ts`, `scopeFilters.ts`, `urgency.ts` — status vocabulary, chip sets
- `src/features/notifications/*` — `notificationEventRegistry.ts`, `leaveNotificationModel.ts`, `reportNotificationModel.ts`, `notificationBannerModel.ts`, `bellBadge.ts`
- `src/features/reports/reportModel.ts` — report catalog, status labels, error copy
- `src/features/attendance/*` — `dashboardModel.ts` (KPI/flag copy), `dayStatusVisual.ts` + `services/resources/attendanceDayStatus.ts` (DAY_STATUS_LABELS — the day-status vocabulary), `leaveApplyModel.ts` + `leaveStatusModel.ts` + `leaveSplitModel.ts` (leave vocabulary), `attendanceTodayModel.ts` (punch copy), `wizardModel.ts` (wizard copy), `officeFormModel.ts` (form errors), `checkInDialogs.ts` (dialog copy), `useLocateMe.ts` (locate errors)
- `src/features/customers/format.ts`, `technicians/format.ts`, `profile/format.ts` — label formatters
- `src/services/api/apiError.ts` — transport/HTTP fallback copy: `Something went wrong with that request.`, `The request took too long. Check your connection and try again.`, `Request was cancelled.`, `Could not reach the server. Check your connection and try again.`, `Your session has expired. Please log in again.` (401), `You don't have permission to do that.` (403), `That couldn't be found.` (404), `Something went wrong on our end. Please try again.` (5xx)
- `src/services/resources/skills.ts:47` — `Couldn't load the job types. Please try again.` (note: "job types", not "skills" — inconsistent with the rest of the app)

## 4. Date/time formats shown to users (exact)
- `2:00 – 4:00 PM` / `2:00 PM` — jobs format.ts (en-IN toLocaleTimeString)
- `17 Jun 2026` — tech detail dateLine, DateTimeFields, ReportRangeFields
- `12 Aug, 2:14 PM` — ActivityTimeline timestamps (en-IN toLocaleString)
- `12 Jun 25` — customers formatShortDate
- `20 Sep` / `1 Sep – 15 Sep 2026` / `20 Sep, 4:05 PM` — reports (formatIstDay/Range/RequestedAt)
- `14 Sep 2026` / `14–18 Sep 2026` / `28 Dec 2026 – 2 Jan 2027` — leave (formatLeaveDate/Range)
- `Wed, 30 Sept, 2026` — utils/formatLongDate (en-IN; note **"Sept"** here vs "Sep" elsewhere)
- `Monday, 14 September 2026` — dashboard flag rows (full month names)
- `Today, Thursday · 12 Oct` — attendance tab header
- `October` / `September 2026` — month chips
- `Sunday, 4 Oct 2026` — My month holidays
- `Just now` / `Xm ago` / `Xh ago` / `Xd ago` / `Xw ago` — relativeTime (falls back to `formatIstDateLabel` — `29 Sep 2026`)
- `4:06 AM` punch times; `M:SS` countdowns (`9:42`); `N h MM m` durations (`8 h 08 m`, `2 h 05 m`, `11 h 53 m before shift`); `N min` (`Late by 22 min`)
- `09:00 – 18:00`, `09:00–18:00 · late after 15 min · 8 h full day` — office timings (24h)
- `12.938° N, 77.690° E` — office coordinates; `28.12345, 77.12345` — pin coordinates
- `n / 500` reason counters

## 5. Where BACKEND text is displayed verbatim (paths, not wording)
1. **Store error → InlineError/EmptyState/banner**: JobsScreen:329/346, CustomersScreen:141/170, HomeScreen:132, NewJobScreen:439/496/556, SelectTechniciansScreen:254, TodayScreen:146/157, HistoryScreen:80/91, NotificationsScreen:407/417/423, ReportsScreen:340/369, JobDetailScreen:310, TechJobDetailScreen:294, CustomerDetailScreen:294, AddressPicker (useAddressAutosuggest.ts:118/240 → SearchPhaseBody:131), Reports useReports.ts:141/194/222, Customers useCustomers.ts:117, Profile useMyProfile.ts:130, Skills useSkills.ts:107 — all render `ApiError.message` (BE wording) with FE fallbacks.
2. **Auth**: AuthFlow.tsx:42/53/181 — unmapped auth errors show BE `message`.
3. **Attendance punch**: `attendanceTodayModel.ts messageForApiError` default renders the server's `message` verbatim (the PRD copy lives server-side, e.g. distance rejections).
4. **Leave writes**: `useLeaveApply.messageForSubmitError` (BE message verbatim except transport); owner leave writes (OwnerLeaveScreen → `classifyLeaveWriteFailure` carries verbatim BE message); cancel/revoke sheets render host error verbatim; leave preview GET rejections render BE message in the count slot.
5. **Corrections**: `DayDetailSheet` save errors render `saveErrorMessage(err)` (BE message for server rejections; FE lines only for offline).
6. **Job edit/cancel**: EditJobSheet renders `resolveSaveError(...).message` — BE message for unmapped codes; cancel failure Alert shows `flattenApiMessage(apiError.message)` (BE validation strings, array-flattened).
7. **Workflow advance** (technician): `workflowActionBarModel.classifyAdvanceError` `generic`/`offline` branches render BE `err.message` inline.
8. **BE-driven labels rendered verbatim**: workflow template `step.label` (JobDetail WorkflowStatus + stepper + ActivityTimeline + notification banners/cards); BE skill names (JobCard, badges, pickers); BE job numbers (`JB-2026-0001`); BE event types for unknown activity events (`eventLabel` fallback renders raw value); BE actor names in correction attribution (`Regularized by {name}`); BE correction notes (quoted); BE leave reasons (quoted in detail sheet and in `leave.rejected` notification messages); BE payload fields `technician_name`, `job_number`, `employeeName`, `officeName`, `reportLabel`, `errorCode` (fallback `Error (code: {code})`).
9. **Notifications inbox**: generic/attendance card titles/messages are FE registry copy, but interpolate BE payload values; unknown event types fall back through registry rendering payload-derived text; realtime toast banner (`StatusBanner.tsx`) renders BE name · job · step label, fallback `Job status updated`.
10. **OS-generated strings surfaced**: camera/gallery failure `res.errorMessage` (photoPicker.ts:125/153), OS location error text in `useLocateMe` (`message.includes('timed out')` heuristic), reverse-geocoded Google address (`Pinned near: …`).
11. **DEV-only**: OTP screen dev banner shows the real OTP (`OtpScreen.tsx:114`, `__DEV__`-gated).

## 6. Suspicious jargon (for the plain-English audit)
- **Geofence / geofenced**: `Configure geofence & shift hours` (OfficesScreen), `{n} m geofence` (OfficeListRow), `Geofenced check-ins at their assigned office.` (EnrolmentRow), `Outside Geofence` (PunchButton), `Within Office Geofence` / `Outside Office Geofence` (PunchStatusCard), `Radius must be 50–1000 metres` (officeFormModel)
- **Radius**: `geofence radius` (RadiusStepper), `Increase/Decrease radius`, a11y `Radius, N metres`
- **GPS**: `Location verified via GPS` (PunchStatusCard), `Refresh GPS and try again` (:296), `GPS spoofing blocked on N days.` (dashboard), `low GPS accuracy` (ActivityTimeline), `GPS Verified` (OfficeLocationCard)
- **Sync**: `Tap to sync status` (Today empty), `Waiting to sync` (WorkflowStepper), `Live Sync` + `Auto` (PresentCard), `syncing...` (Reports header), `Sync paused — pull to retry` (Reports), `Synced an offline update` (eventLabels)
- **Punch**: `Tap to punch`, `READY TO PUNCH`, `PUNCH DISABLED`, `Try again in 9:42` — "punch" sits beside "Check in/out" with no explanation
- **Bounds**: `Out of Bounds for Check-out` / `LOCKED` (PunchStatusCard)
- **Fake location / spoofing**: `Fake location attempt`, `Fake location`, `GPS spoofing blocked` — three wordings, one concept
- **Short day / Tracked / Not tracked / tracked employees**: dashboard tiles & copy (HR vocabulary)
- **Enrolment / enrolled / Enrolments**: `Team enrolment`, `Enrolled employees · leave empty to include everyone` (British spelling + register)
- **Effective from**: WeeklyOff + Reassign sheets (legal register)
- **Regularized**: `Regularized by {name}` (DayDetailSheet; also US 'z' vs app's otherwise-neutral English)
- **GST / GSTIN**: `That doesn't look like a valid GSTIN.`, `Check your GSTIN and state…`, `GST number`
- **OTP**: `Send OTP`, `Resend OTP` vs "code" in headings — acronym exposure
- **Dispatch**: `Dispatch tip: Tap Overdue (N) to clear or reassign delayed assignments.` (Jobs empty state)
- **Payload/presign/R2**: internal only (not user-visible) — confirmed
- **Workflow / step**: `WORKFLOW STATUS` (uppercase label), `Step 2 of 4` — mild
- **Policy**: `Shift & location policy`, `View leave policy` — bureaucratic for technicians
- **"job types" vs "skills"**: skills resource error says `Couldn't load the job types.` while every other surface says "skills"
- **Hardcoded "Good morning"** on Home/HomeHeader/Today regardless of time of day (copy bug, not jargon)
- **"Sept"** in `formatLongDate` vs "Sep" everywhere else
