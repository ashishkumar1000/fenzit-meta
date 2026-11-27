# Fenzit console – user-facing copy, extracted verbatim (2026-11-25)

Every string below is copied exactly as it appears in the code — punctuation, dashes and ellipses included. Context labels say where each string shows. Dynamic strings keep their `${...}` placeholders with a plain-language note. Routes, intent names and other internal identifiers are listed at the end of each section and must not be changed.

---

## Console shell & navigation (sidebar, landing index, company picker)

`src/features/admin/adminLoader.ts`

- Sidebar link (staff role): "Inspect"
- Sidebar link (staff role): "Account"
- Sidebar link (staff role): "Reports"
- Sidebar link (staff role): "Deletion requests"
- Sidebar link (staff role): "Config"
- Sidebar link (owner role): "Overview"
- Sidebar link (owner role): "Customers"
- Sidebar link (owner role): "Employees"
- Sidebar link (owner role): "Salary"
- Sidebar link (owner role): "Jobs"
- Sidebar link (owner role): "Holidays"
- Sidebar link (owner role): "Leave"
- Sidebar link (owner role): "Attendance"
- Sidebar link (member role): "Me"
- Sidebar link (member role): "Jobs"
- Sidebar group caption: "Business"
- Sidebar group caption: "Team"
- Sidebar group caption: "Money"

`src/pages/AdminPage.tsx`

- Access-check screen: "Checking your access…"
- Access-check failure (role="alert"): "We could not check your access. Check your connection and try again."
- Retry button (idle): "Try again"
- Retry button (busy): "Checking…"
- Console page heading: "Console"
- Role chip caption (staff): "Fenzit staff"
- Role chip caption (owner): "Company owner"
- Role chip caption (member): "Team member"
- User chip fallback when the name is missing: "Signed in"
- Sidebar nav aria-label (aria): "Console sections"
- Leave sidebar link aria-label when it has pending requests (aria, dynamic): `Leave, ${pendingBadge} pending` — pendingBadge = the tenant's pending leave count
- Brand link aria-label (aria): "Fenzit home"
- Brand wordmark: "Fenzit"
- Brand plan pill (static brand copy): "PRO"
- Sidebar footer button: "Log out"
- Greeting heading when the name is missing: "Hello"
- Greeting heading (dynamic): `Hello, ${data.name}` — data.name = the signed-in user's name
- Landing lede (staff): "The whole system, one console."
- Landing lede (owner): "Your whole business, one console."
- Landing "Loading your console…" (role="status")
- Landing failure (role="alert"): "We could not load your console. Check your connection and try again."
- Staff landing footnote (with shield glyph): "This console cannot delete anything."
- Landing index blurbs, one per section:
  - Inspect: "Everything the system knows about one person, on one page."
  - Account: "Flip someone's staff and sign-in flags."
  - Reports: "Job photos people flagged, ready to hide or dismiss."
  - Deletion requests: "People asking us to erase their data, and what we did."
  - Config: "App-wide settings — the force-update rule and the support contact."
  - Overview: "Today's pulse, the job report and every list in your company."
  - Customers: "The people you serve, and the jobs booked for them."
  - Employees: "Your team, their details and their offices."
  - Salary: "Salary structures, deductions and the statutory switches."
  - Jobs: "Create jobs, assign them and follow them to the finish."
  - Holidays: "The days your team is off."
  - Leave: "Leave types and time off requests."
  - Attendance: "Who checked in, where and when."

`src/features/admin/components/CompanyPicker.tsx` (staff tools)

- Card title: "Work on a company"
- Card meta when no company is active: "None picked"
- Status line when a company is active (dynamic): `You are working on ${active.company}.` — active.company = the company's name
- Status line when none is active: "No company picked. Pick one below before you act for a company."
- Empty list: "This person has no companies to pick."
- Unavailable company hint: "Choosing this company is not available here yet."
- Row hint for the active company: "Picked"
- Row hint for other companies: "Pick this company"

---

## Customers

### Customers page — top bar and greeting   (src/pages/AdminCustomersPage.tsx)
- Breadcrumb nav aria-label (aria): "Breadcrumb"
- Breadcrumb root link: "Console"
- Breadcrumb separator (decorative, aria-hidden): "›"
- Breadcrumb current page: "Customers"
- Greeting (dynamic): `Hello, ${selfName}` — selfName = the signed-in owner's display name
- Greeting when the owner's name is unavailable: "Hello"
- Role pill beside the greeting: "Owner"
- Lede: "Your customer book — contacts, addresses and the jobs booked for them, all in one place."

### Customers page — stat tiles   (src/pages/AdminCustomersPage.tsx)
- Tile label: "Total customers"
- Tile sub-line: "Everyone in your company's book" (straight apostrophe in company's)
- Tile label: "New leads"
- Tile pill: "No jobs yet"
- Tile sub-line: "Waiting for their first job"
- Tile label: "Single job"
- Tile sub-line: "Exactly one job so far"
- Tile label: "Repeat customers"
- Tile pill: "2+ jobs"
- Tile sub-line: "They come back — 10+ jobs wear a VIP badge"

### Customers page — filter bar   (src/features/admin/components/CustomersFilterBar.tsx)
- Bucket chip group aria-label (aria): "Filter customers by jobs"
- Bucket chip: "All" (followed by the whole-company count, a plain number)
- Bucket chip: "New" (followed by count)
- Bucket chip: "Single job" (followed by count)
- Bucket chip: "Repeat" (followed by count)
- Button, shown only when a filter/search is set: "Clear all"
- Search placeholder: "Search name or phone…" (single-character ellipsis)
- Search aria-label (aria): "Search customers"
- Keyboard shortcut badge beside search (decorative, aria-hidden): "⌘K"

### Customers page — sort dropdown   (src/pages/AdminCustomersPage.tsx)
- Trigger label: "Sort" — the dropdown shell renders it with a trailing colon, as `Sort:`
- Option: "Added (newest)"
- Option: "Added (oldest)"
- Option: "Name (A–Z)" (en dash in A–Z)
- Option: "Name (Z–A)" (en dash in Z–A)
- Option: "Recent activity"
- Note: these five words are defined a second time in src/features/admin/customersLabels.ts (`CUSTOMER_SORT_WORDS`), which supplies the trigger's current-value label — the two copies must stay identical.

### Customers page — table   (src/features/admin/components/CustomersTable.tsx)
- Column header, sortable link: "Customer name"
- Column header: "Phone"
- Column header: "Address"
- Column header: "Jobs"
- Column header, sortable link: "Last job activity"
- Sort arrows beside the sortable headers (decorative, aria-hidden): "↑↓"
- Badge beside the name of a customer with 10 or more jobs: "VIP"
- Copy button on the phone cell: "Copy"
- Copy button after a successful copy: "Copied"
- Copy button aria-label (aria, dynamic): `Copy phone number ${full}` — full = the row's dial code plus number, e.g. "+91 9876543210"
- Address cell when the customer has no address: "—" (em dash)
- Last-activity cell when the customer has no jobs: "—" (em dash)
- Jobs chip (dynamic): `${c.jobCount} ${c.jobCount === 1 ? "job" : "jobs"}` — e.g. "1 job" or "3 jobs"

### Customers page — results line and empty states   (src/pages/AdminCustomersPage.tsx)
- Results caption (dynamic): `Showing ${from}–${to} of ${total} ${total === 1 ? "customer" : "customers"}` — from/to = the page window, total = the filtered count; en dash between from and to; singular "customer" when total is 1
- Busy suffix appended to the results caption during a refetch (dynamic): ` — updating…` (em dash, single-character ellipsis)
- Empty when the company has no customers at all: "No customers yet. Add the first one, or book a job and we'll save them." (straight apostrophe in we'll)
- Empty when filters match nothing (or the page is past the end): "No customers match these filters, or this page is past the last one."

### Customers page — load failure   (src/pages/AdminCustomersPage.tsx)
- Alert replacing the whole card: "The customer list could not load. Try opening this page again from the menu."

### Customers page — pager   (src/features/admin/components/CustomersPager.tsx)
- Rows-per-page trigger label: "Rows per page" — the shell renders it with a trailing colon, as `Rows per page:`; the current value and the options are plain numbers (10, 25, 50)
- Pager nav aria-label (aria): "Pages"
- First-page step aria-label (aria): "First page"; visible glyph: "«"
- Previous-page step aria-label (aria): "Previous page"; visible glyph: "‹"
- Next-page step aria-label (aria): "Next page"; visible glyph: "›"
- Last-page step aria-label (aria): "Last page"; visible glyph: "»"
- Gap marker between page numbers (decorative): "…"
- Go-to form label: "Go to page:"
- Go-to input aria-label (aria): "Go to page"
- Go-to input placeholder: the current page number (plain number, dynamic)
- Go-to validation error (dynamic): `Enter a page from 1 to ${pages}.` — pages = the last page number

### Customers page — export button   (src/features/admin/components/CustomersExport.tsx)
- Button, idle: "Download list"
- Button, busy before any progress reports: "Preparing…" (single-character ellipsis)
- Button, busy with progress (dynamic): `${done} fetched…` — done = rows fetched so far; single-character ellipsis
- Error alert under the button: "The file could not be created. Try again."

### Exported CSV   (src/features/admin/components/CustomersExport.tsx)
- Header row of the downloaded file, one cell each: "Name", "Phone", "Code", "Address", "City", "Jobs", "Last job activity"
- Download filename: "customers.csv"

### Add customer dialog   (src/features/admin/components/AddCustomerDialog.tsx)
- Header action button: "Add customer"
- Dialog aria-label (aria): "Add customer"
- Dialog title, form state: "Add customer"
- Hint under the title: "A phone number identifies a customer — one number per customer per company."
- Field label: "Name"
- Field label: "Phone number"
- Hint under the phone field: "Numbers only, 6 to 15 digits."
- Field label: "Address (optional)"
- Field label: "City (optional)"
- Reason the save button is off, name empty: "Enter the customer's name to save them." (straight apostrophe in customer's)
- Reason the save button is off, phone too short: "Enter a phone number of 6 to 15 digits to save the customer."
- Buttons: "Cancel" and "Save customer"
- Save button busy text: "Saving…" (single-character ellipsis)
- Saved dialog title: "Customer saved"
- Saved status line: "Customer saved."
- Saved detail (dynamic): `Their customer code is ${saved.customerCode}.` — customerCode = the code minted by the backend
- Saved dialog button: "Close"

### Add customer dialog — dial-code select   (src/components/ui/DialCodeSelect.tsx)
- Visually hidden field label (aria, screen readers only): "Country code"
- Option label (dynamic): `${country.countryName} (${country.dialCode})` — e.g. "India (+91)"; countryName comes from the console's country list, the parentheses and dial code are this component's format. The same string is the option's native tooltip (title attribute).

### Filter dropdown shell (shared; renders the Sort and Rows per page triggers)   (src/features/admin/components/ConsoleFilterDropdown.tsx)
- Trigger renders the caller's label with a trailing colon (dynamic): `${label}:` — on this page `Sort:` and `Rows per page:`
- Chevron in the trigger (decorative, aria-hidden): "^"
- Check mark on the selected option row (decorative, aria-hidden): "✓"
- Panel footer buttons: "Reset" and "Apply"
- Empty option list: "No options match." — not reachable on this page (this page's dropdowns open without a search box)

### Shared label maps   (src/features/admin/customersLabels.ts)
- BUCKET_WORDS, key "all": "All" (same word as the bucket chip)
- BUCKET_WORDS, key "new": "New" (same word as the bucket chip)
- BUCKET_WORDS, key "single": "Single job" (same word as the bucket chip)
- BUCKET_WORDS, key "repeat": "Repeat" (same word as the bucket chip)
- CUSTOMER_SORT_WORDS, key "created_new": "Added (newest)"
- CUSTOMER_SORT_WORDS, key "created_old": "Added (oldest)"
- CUSTOMER_SORT_WORDS, key "name_az": "Name (A–Z)" (en dash)
- CUSTOMER_SORT_WORDS, key "name_za": "Name (Z–A)" (en dash)
- CUSTOMER_SORT_WORDS, key "recent_activity": "Recent activity"

### Save-action messages surfaced in the Add customer dialog   (src/features/admin/adminBrowseLoaders.ts)
- Submit refused (unknown or missing intent): "That save could not be sent. Try again."
- Validation failure (name or phone malformed): "Enter a name and a phone number (6–15 digits) to save the customer." (en dash in 6–15)
- Duplicate phone (backend 409): "That phone number is already a customer of your company."
- Note: any other error text shown in the dialog comes from the shared error-message utility (messageForError in src/utils/errorMessages.ts), which is outside the files listed for this brief.

### Internal identifiers — do not touch
- Route: /admin/company/customers (CUSTOMERS_PATH); breadcrumb link target /admin
- Query params: q, bucket, sort, pageSize, page
- bucket values: all, new, single, repeat
- sort values: created_new, created_old, name_az, name_za, recent_activity
- Hidden form intent: create; form field names: name, phoneNumber, countryCode, address, city
- Backend error code branched on: DUPLICATE_RESOURCE
- Thrown but never displayed: "No session" (Error inside CustomersExport; the button shows "The file could not be created. Try again." instead)
- aria-sort attribute values (standard ARIA, not copy): ascending, descending, none

---

## Jobs

### Jobs page — top bar, tabs and greeting   (src/pages/AdminJobsPage.tsx)
- Breadcrumb nav (aria): "Breadcrumb"
- Breadcrumb root link: "Console"
- Breadcrumb separator (aria-hidden glyph): "›"
- Breadcrumb current page: "Jobs"
- Tab strip nav (aria): "Page sections" — from src/features/admin/components/Tabs.tsx
- Owner tab labels: "Jobs", "Approval", "Activity", "Report"
- Member tab labels: "Jobs", "My report", "Rejected", "Activity"
- Owner greeting: "Hello" / dynamic `Hello, ${selfName}` — selfName = the signed-in owner's name
- Owner role pill: "Owner"
- Owner lede: "Every job your company runs — create, assign and follow them to the finish."
- Owner action link: "Create a job"
- Member greeting: "Hello" / dynamic `Hello, ${selfName}`
- Member lede: "Your jobs — what is scheduled for you and what you have finished."
- Whole-page failure: "The job list could not load." (with SectionCard title "Jobs")
- Retry button idle: "Try again" / busy: "Retrying…"

### Jobs page — owner tiles   (src/pages/AdminJobsPage.tsx)
- Tile label: "Total jobs" / sub: "Every job your company has run"
- Tile label: "In progress" / sub: "Started, waiting to be finished"
- Tile label: "Job approvals" / sub: "Employee-created, waiting on you"
- Tile label: "Completed (30 days)" / sub: "Finished work this month"

### Jobs page — filter bar   (src/features/admin/components/JobsFilterBar.tsx)
- Clear-filters button: "Clear all"
- Search input placeholder: "Search job, customer, employee, skill, place…"
- Search input (aria): "Search jobs"
- Keyboard hint (aria-hidden glyph): "⌘K"
- Status chips group (aria): "Filter jobs by status"
- Chip labels + counts: "All", "Scheduled", "In progress", "Pending approval", "Completed", "Cancelled", "Rejected" (from src/features/admin/jobsLabels.ts, counts are whole-company numbers)
- Dropdown trigger label: "Skill" — fallback value word: "Chosen skill" / "All"
- Skill search placeholder (also its aria-label): "Search skills…"
- Dropdown trigger label: "Priority" — value word fallback: "All"
- Priority options: "Normal", "Urgent"
- Dropdown trigger label: "Sort"
- Sort options: "Latest", "Soonest"
- Shared dropdown chrome (src/features/admin/components/ConsoleFilterDropdown.tsx): trigger renders `${label}:` then the chosen word; chevron glyph (aria-hidden): "^"; selected check mark (aria-hidden): "✓"; panel aria-label = the dropdown label; empty list: "No options match."; footer buttons: "Reset", "Apply"

### Jobs page — table   (src/features/admin/components/JobsTable.tsx)
- Column headers: "Job", "Customer", "Status", "Step", "Skill", "Employee", "Priority", "Scheduled"
- Job cell title: description or the job number (data)
- Job cell subtitle: the job number, or the service location when there is no description
- Rejected job subtitle (dynamic): `${job.rejectionReason ?? "No reason given"} · ${job.jobNumber}` — the reject reason, then the job number; without a description just the reason, or "No reason given"
- Step cell (dynamic): `Step ${job.currentStepIndex + 1} of ${job.workflowTemplate.steps.length}` — e.g. "Step 2 of 5"; otherwise the current step's words; empty state: "—"
- Status cell: status badge word, humanised from the wire value (see "Shared status vocabulary")
- Skill/employee/customer empty: "—"
- Priority cell: "Urgent" pill, otherwise "—"
- Scheduled cell: formatted time (data)

### Jobs page — table footer, empty states and pager   (src/pages/AdminJobsPage.tsx + src/features/admin/components/JobsPager.tsx)
- Empty, no jobs at all: "No jobs yet. Create the first one and assign it to an employee."
- Empty, filtered: "No jobs match these filters, or this page is past the last one."
- Showing line (dynamic): `Showing ${from}–${to} of ${result.total} ${result.total === 1 ? "job" : "jobs"}` — en dash between the numbers; suffix while busy: ` — updating…`
- Rows-per-page dropdown label: "Rows per page" (options are bare numbers)
- Pager nav (aria): "Pages"
- Pager step aria-labels (aria): "First page", "Previous page", "Next page", "Last page"
- Pager glyphs: "«", "‹", "›", "»", and window ellipsis "…"
- Go-to field label: "Go to page:"
- Go-to input (aria): "Go to page" — placeholder is the current page number
- Go-to error (dynamic): `Enter a page from 1 to ${pages}.`

### Jobs page — export   (src/features/admin/components/JobsExport.tsx)
- Button idle: "Download list"
- Button busy (dynamic): `${done} fetched…` — rows fetched so far; default busy: "Preparing…"
- Export failure: "The file could not be created. Try again."
- CSV first-row headers (visible in the downloaded file): "Job number", "Description", "Customer", "Employee", "Skill", "Status", "Priority", "Place", "Scheduled", "Completed"

### Jobs page — create banner   (src/features/admin/components/JobsCreateBanner.tsx)
- Section (aria): "Create a job"
- Banner title: "Send the next job out"
- Banner lede: "Create a job for a customer, assign it to any employee, and follow it step by step until it is done."
- Banner CTA: "Create a job"

### Jobs page — member jobs tab   (src/pages/AdminJobsPage.tsx)
- Section card title: "Jobs"
- Card meta (dynamic): `${ordered.length} jobs` / `${ordered.length} of ${rows.length} jobs` — the second when a search narrows the rows
- Status chip nav (aria): "Filter jobs by status"
- Chip labels (fallback for an unknown value): "All", "Scheduled", "In progress", "Pending approval", "Completed", "Cancelled", "Rejected"
- Search input placeholder: "Search job, customer, employee, skill, place…"
- Search input (aria): "Search jobs"
- Sort chip nav (aria): "Sort jobs"
- Sort chips: "Latest first", "Soonest first"
- Column headers: "Job", "Customer", "Status", "Step", "Skill", "Employee", "Priority", "Scheduled"
- Job cell subtitle: the job number, or the service location; rejected (dynamic): `${job.rejectionReason ?? "No reason given"} · ${job.jobNumber}`
- Step cell (dynamic): `Step ${job.currentStepIndex + 1} of ${job.workflowTemplate.steps.length}`; otherwise the step's words; "—"
- Priority cell: "Urgent" pill, otherwise "—"
- Empty, searching: "No job matches that search."
- Empty, no jobs: "No jobs yet."
- Empty, filtered (dynamic): `No ${chipLabel.toLowerCase()} jobs.` — the chip word lower-cased, e.g. "No pending approval jobs."

### Jobs page — member report tab   (src/features/admin/MeJobActivity.tsx)
- Card title: "My job activity" — meta is the range (dynamic): `${fmtDay(from)} – ${fmtDay(to)}` (en dash)
- Range nav (aria): "Activity period"
- Range links: "Today", "Last 7 days", "Last 30 days", "This month", "Last month"
- Loading line: "Loading the activity…"
- Load failure: "Your job activity could not load for this period."
- Stat labels: "I created", "Approved", "Auto-approved", "Rejected", "Waiting"
- Fact labels: "Approval rate", "Average wait", "Median wait", "Assigned to me now", "I completed in this period"
- Fact values (dynamic): percent "N%"; waits `${Math.round(minutes)} min`, `${hours} h`, `${days} d`; "—" when unknown
- Rejections title: "Rejection reasons I received, newest first"
- Reason fallback: "No reason given"
- More line (dynamic): `Showing the ${shown} newest of ${total} rejections in this period — the full history is on the Rejected tab.`

### Jobs page — member rejected tab   (src/features/admin/MeJobActivity.tsx)
- Card title: "My rejected jobs" — meta is the count (dynamic): `${n}+` when more pages follow, else the count
- Empty state: "Nothing of yours was rejected. Newer decisions appear here."
- Column headers: "Job", "Task", "Reason", "Decided", "Was scheduled"
- Reason fallback: "No reason given"
- More link: "Load older rejections"
- Load failure: "Your rejected jobs could not load."

### Jobs page — activity tab   (src/features/admin/LatestJobActivity.tsx)
- Card title: "Latest job activity" — meta is the entry count (number)
- Load failure: "The activity feed could not load." / retry: "Try again"
- Empty state: "No job activity yet. Alerts appear here as they happen."
- Alert sentences (dynamic): `${employeeName ?? "An employee"} submitted ${job}${customerName ? ` for ${customerName}` : ""}`
- `${job}${forWhom} was approved`
- `${job}${forWhom} was rejected${reason ? ` — ${reason}` : ""}`
- `${job}${forWhom} was edited${changedFields ? ` (${fields})` : ""}`
- `${job}${forWhom} was cancelled`
- `${job}${forWhom} was assigned`
- Fallback for unknown events (dynamic): `${job} — ${humanize(eventType)}`
- Fallback words inside sentences: "A job", "An employee"

### Jobs page — report tab   (src/pages/AdminJobsPage.tsx + src/features/admin/ReportExportCard.tsx + ReportHistoryList.tsx + jobExportApi.ts + components/Dropdown.tsx)
- Card title: "Job activity report"
- Date field labels: "From", "To"
- Employee dropdown label: "Employee" — first option: "All employees"
- Dropdown search placeholder (dynamic, derived): `Search ${label.toLowerCase()}…` → "Search employee…" (and its matching aria-label without the ellipsis)
- Dropdown no-match (dynamic, curly quotes): `No match for “${query}”.`
- Employee list failure: "The employee list could not load — the report will cover all employees." / retry: "Try again"
- Generate button: "Download report"
- Date alerts: "The start date must be on or before the end date." / "Pick both dates to generate the report."
- Working line: "Building the report — this takes a few seconds…"
- Ready line: "Report downloaded." / link: "Open it again"
- Idle hints: "A PDF of the chosen employees' job work over the chosen dates." / "A PDF of attendance for all offices over the chosen dates."
- Generation failures: "The report is taking unusually long. Try again in a minute." / "The report could not be built. Try again."
- Download failure: "That report is not ready to download. Generate a new one."
- Retry-while-building: "Still building — give it a minute, then try downloading."
- History heading (dynamic): `Previous ${label} reports` — label is the report type word: "Job activity" or "Attendance"
- History load failure: "The report history could not load." / retry: "Try again"
- History empty: "Nothing generated yet. Reports you build are listed here to download again."
- History row meta (dynamic): `All employees` or `${count} employee${count === 1 ? "" : "s"}`, then " · " and the created time
- Row actions: "Download" (busy "Preparing…"), aria-label (dynamic): `Download the ${range} ${label} report`; "Try again" (busy "Retrying…"), aria-label (dynamic): `Retry the ${range} ${label} report`
- Report type words (src/features/admin/jobExportApi.ts): "Job activity", "Attendance"
- API client validation messages surfaced as errors: "The report service did not acknowledge the request." / "The report history did not look as expected."

### Jobs page — approval queue, filter card   (src/features/admin/ApprovalQueueSection.tsx)
- Queue load failure: "The approval queue could not load." / retry link: "Try again"
- Card title: "Filter"
- Field labels: "Employee", "Age of submission"
- Employee options: "All employees", employee names, fallback "(no name)", stale-id fallback "(this employee)"
- Age options: "Any age", "Older than 24 hours", "Older than 3 days", "Older than 7 days"
- Filter load failure: "The employee filter could not load." — optional second sentence: " The employee filter already in the address still applies."

### Jobs page — approval queue, list   (src/features/admin/ApprovalQueueSection.tsx)
- Card title: "Approval queue"
- Card meta (dynamic): `${rows.length} waiting` / `${rows.length}+ waiting` when more pages exist
- Updating line: "Updating the list…"
- Empty state: "Nothing is waiting for approval." — with a filter set: "Nothing is waiting for approval for these filters."
- Row title: the description or the job number, then (dynamic) ` · ${row.jobNumber}`, ` · ${row.customerName}`, and while open for edit the mark ` · being edited`
- Row meta (dynamic): `${employeeName ?? "(no name)"} · submitted ${day} · waiting ${waitLabel(ageHours)}`, plus ` · scheduled ${fmtWhen(scheduledStart)}` when scheduled — wait reads "<1 h", "N h" or "N d"
- Row actions: link "Edit"; button "Approve" (busy "Working…"); button "Reject"
- Older-page line: link "Older submissions", then text " continue on the next page of the queue — the oldest always lead."

### Approval queue — edit form   (src/features/admin/components/PendingJobEditForm.tsx)
- Card title: "Edit pending job" / form heading (dynamic): `Edit ${job.jobNumber}`
- Edit-load failure: "That job could not load for editing." / link "Back to the queue"
- No-longer-pending: "That job is no longer waiting for approval." / link "Back to the queue"
- Form hint: "The employee is told about every change you save. Your edits stay visible on the job."
- Saved line: "Changes saved."
- Picker warnings: "The skill list could not load — the job keeps its current skill unless you pick another." / "The customer list could not load — the job keeps its current customer."
- Field labels: "What needs doing", "Starts", "Ends (optional)", "Assign to", "Priority", "Where", "Skill", "Customer", "Notes for the employee (optional)"
- Select options: "Unassigned" (empty assignee), "No skill" (empty skill), "Normal", "Urgent" — plus, when a stray priority value exists, the raw value shown as-is
- Fallback option name: "(the job's current value)"
- Save button idle: "Save changes" / busy: "Saving…"
- Back link: "Back to the queue"

### Approval queue — action error messages   (src/features/admin/approvalLoaders.ts)
- Bad decision request: "That action could not be sent. Try again."
- Bad save request: "That save could not be sent. Try again."
- Bad start time: "That start time did not read as a real time. Check it and try again."
- Bad end time: "That end time did not read as a real time. Check it and try again."
- End before start: "The end time must come after the start time."
- Unmatched action: "That action could not be sent. Try again."
- (Any other failure renders the shared error-message helper's text — supplied by src/utils/errorMessages.ts, not extracted here.)

### Reject job dialog   (src/features/admin/components/RejectDialog.tsx)
- Trigger button: "Reject"
- Dialog title: "Reject this job?"
- Dialog body: "The employee is told the job was rejected, with your reason if you give one. This cannot be undone."
- Field label: "Reason (optional)"
- Buttons: "Cancel"; submit idle "Reject job" / busy "Working…"
- Error line: the action's message (see "Approval queue — action error messages")

### Job settings dialog   (src/features/admin/components/JobSettingsDialog.tsx)
- Chip labels: "Off", "Create + approval", "Creates jobs"
- Dialog title: "Job settings"
- Dialog hint: "Changes apply to the next job this employee creates. Jobs already waiting stay as they are."
- Checkbox 1: "Can create jobs" / helper: "They record their own visits and tasks."
- Checkbox 2: "Approval needed" / helper (dynamic): "New jobs wait for your approval first." — disabled state: "Turn on Can create jobs first."
- Saved mark: "Job settings saved."
- Buttons: "Close"; "Cancel"; submit idle "Save" / busy "Saving…"
- Error line: the employees action's message (supplied by src/features/admin/adminBrowseLoaders.ts, not extracted here)

### New job page   (src/pages/AdminMeNewJobPage.tsx)
- Card title (all states): "New job"
- Load failure: "The new-job form could not load." / retry idle "Retry" / busy "Retrying…"
- Refusal (no permission): "You are not allowed to create jobs. Ask your owner to turn this on for you."
- Back link: "Back"
- Outcome lines (dynamic): owner awaiting approval `${jobNumber} created — waiting for approval.`; owner assigned `${jobNumber} created and assigned.`; member awaiting approval `${jobNumber} created — waiting for your owner's approval.`; member assigned `${jobNumber} created and assigned to you.`
- Outcome links: "Back", "Create another job"
- Form hint, owner: "The employee you assign sees the job in their app at once."
- Form hint, member: "Your owner sees every job you create — the approval rule they set for you decides whether it waits for them first."
- Form error line: the create action's message (supplied by src/features/admin/meCreateJobLoaders.ts, not extracted here)
- Field labels: "What needs doing", "Who is it for", "Customer", "Customer name", "Phone number (India)", "Address (optional)", "City (optional)", "Assign to", "What needs doing (skill)", "Starts", "Ends (optional)", "Priority", "Where", "Notes for the employee (optional)" (owner) / "Notes for your owner (optional)" (member)
- Select options: "An existing customer", "A new customer", "Normal", "Urgent"
- Placeholder options: "Pick a customer", "Pick an employee", "Pick a skill"
- List-load failures: "The customer list could not load. Refresh the page to retry." / "The employee list could not load. Refresh the page to retry." / "The skill list could not load. Refresh the page to retry."
- Empty roster: "No active employees to assign yet. Add employees first."
- Held-submit note: "The Create button is held until the lists above load. Refresh the page to retry."
- Submit button idle: "Create job" / busy: "Creating…"
- Phone tooltip (title attribute): "6 to 15 digits, no spaces"

### Job detail page — header and facts   (src/pages/AdminJobDetailPage.tsx)
- Crumb link: "All jobs" / separator " / " (aria-hidden) / the job number
- Card title: the job number
- Urgent pill: "Urgent"
- Status badge: humanised status word (see "Shared status vocabulary")
- Fact labels: "Customer", "Employee", "Skill", "Location", "Description", "Notes for the employee", "Rejected", "Completed", "Scheduled"
- Employee fallback: "(no name)"
- Rejected fact value (dynamic): `${job.rejectionReason ?? "No reason given"}${decidedAt ? ` — decided ${fmtWhen(decidedAt)}` : ""}`
- Scheduled value (dynamic): start time, plus ` – ${fmtWhen(scheduledEnd)}` (en dash) when an end exists
- Load failure card title: "Job"
- Failure, member: "This job is not available to you. You can open only the jobs assigned to you."
- Failure, owner: "This job is not available. It may be mistyped, or outside your company."
- Failure, other: "The job could not load."
- Retry idle: "Try again" / busy: "Retrying…"
- Back link: "Back to all jobs"

### Job detail page — workflow, activity, photos   (src/pages/AdminJobDetailPage.tsx)
- Card title: "Workflow"
- Workflow empty: "This job has no workflow steps."
- Step requirement words: "Photo", "Signature", separator " · ", done suffix " · done", current suffix " · current step"
- Card title: "Activity"
- Activity empty: "Nothing has happened on this job yet."
- Event labels: humanised from the wire event type ("step_arrived" → "Arrived", "job_submitted" → "Submitted"); the actor line (dynamic): `${actorName} · ` then the time
- Card title: "Photos and signatures" — meta is the attachment count (number)
- Photos empty: "Nothing uploaded yet. The employee adds photos from the job in their app."
- Broken/missing image tile: "Unavailable"
- Shot caption (dynamic): `${one.type === "signature" ? "Signature" : "Photo"} · ${fmtWhen(one.createdAt)}`
- Image alt (alt, dynamic): `${job.jobNumber} ${one.type} from ${fmtWhen(one.createdAt)}`

### Dossier — overview   (src/features/admin/DossierView.tsx)
- Name fallback: "(no name)"
- Badges: "Fenzit staff", "Disabled", "Regular account", "Founder"
- Facts: "no email"; dynamic `joined ${date}`; dynamic `last sign-in ${date}` / "unknown" when never signed in
- Stat tile labels: "Jobs", "Attendance", "Attempts", "Leave", "Invites sent", "Notifications", "Audit rows", "Activity"

### Dossier — company picker   (src/features/admin/components/CompanyPicker.tsx)
- Card title: "Work on a company" — meta: the active company's name, or "None picked"
- Status lines: dynamic `You are working on ${company}.` / "No company picked. Pick one below before you act for a company."
- Empty: "This person has no companies to pick."
- Unpickable hint: "Choosing this company is not available here yet."
- Link hints: "Picked" / "Pick this company"
- Clear link: "Stop working on this company"

### Dossier — subscription   (src/features/admin/SubscriptionSection.tsx)
- Card title: "Subscription" — meta (dynamic): `Valid until ${date}` / "No end date"
- Field label: "Valid until (India time)"
- Save button idle: "Save date" / busy: "Saving…"
- Notes: "Change the date to save it." / "The subscription ends at the end of this day."
- Saved: "Saved."
- Session ended: "Your session has ended. Sign in again to save."

### Dossier — companies cards   (src/features/admin/DossierSections.tsx)
- "Companies" card — columns: "Company", "Role", "Status", "Code", "Invited by", "Joined"; empty: "No company memberships."; founder suffix (dynamic): ` (founder)`
- "Company" card — columns: "Members", "Customers", "Jobs", "Attendance", "GSTIN", "UPI", "State"; empty: "No company."

### Dossier — jobs card   (src/features/admin/DossierSections.tsx)
- Card title: "Jobs" — meta: the total (number); footer (dynamic): `and ${n} more jobs`
- Columns: "Job", "Status", "Step", "Skill", "Customer", "Scheduled", "Photos"
- Empty: "No jobs as technician."

### Dossier — attendance cards   (src/features/admin/DossierSections.tsx)
- Card title: "Attendance" — meta (dynamic): `${records} records · recent 5`
- Footer chips (dynamic): `attempts ${n}`, `corrections ${n}`, `overrides ${n} (authored ${n})`, `weekly-off ${n}`, `enrolments ${n}`
- Recent table columns: "Day", "Check-in", "Check-out", "In dist.", "Out dist.", "GPS"; empty: "No attendance records."; GPS cell: "mocked" / "ok"
- Attempts table columns: "Attempt kind", "Outcome", "Provider", "Distance", "When"
- Distance values (dynamic): `${metres} m` / `${km} km`, "—" when unknown
- "Attendance moderations" card — columns: "Day", "Employee", "Note"; empty: "No corrections authored."

### Dossier — leave cards   (src/features/admin/DossierSections.tsx)
- "Leave" card — columns: "From", "To", "Part", "State", "Reason"; empty: "No leave requests."; footer (dynamic): `and ${n} more requests`
- Caption: "Graded leave days"
- Leave-day chip (dynamic): `${day} · ${humanize(state)}`
- "Leave timeline" card — columns: "Event", "Actor", "Dates", "When"; empty: "No leave events."

### Dossier — skills, invites, moderations   (src/features/admin/DossierSections.tsx)
- "Skills" card — empty: "No skills enrolled." (skills otherwise render as chips)
- "Invites sent" card — columns: "Person", "Phone", "Company", "Role", "Status"; empty: "Nobody invited by this person."; name fallback "(no name)"; footer (dynamic): `invited by ${name}` or `and ${n} more invites`

### Dossier — notifications, audit, activity, reports, offices   (src/features/admin/DossierSections.tsx)
- "Notifications" card — columns: "Event", "Summary", "Read", "When"; empty: "No notifications."; unread cell: "unread"; footer (dynamic): `and ${n} more notifications`
- "Audit trail" card — columns: "Action", "Direction", "When"; empty: "No audit rows."; direction cells: "as actor" / "as target"; footer (dynamic): `and ${n} more rows`
- "Activity" card — columns: "Event", "Job", "When"; empty: "No activity events."; footer (dynamic): `and ${n} more events`
- "Reports" card — columns: "Type", "Status", "When"; empty: "No report requests."; footer (dynamic): `and ${n} more requests`
- "Offices" card — columns: "Office", "Address", "Radius", "Validity"; empty: "No office assignments."

### Shared status vocabulary   (src/features/admin/jobsLabels.ts + src/features/admin/status.ts + src/features/admin/components/Badge.tsx)
- Job status words: "All", "Scheduled", "In progress", "Pending approval", "Completed", "Cancelled", "Rejected"
- Priority words: "All", "Normal", "Urgent"
- Sort words: "Latest", "Soonest"
- Status badges render any wire status via humanize (backend-supplied values, snake_case → "In progress" style); the colour vocabulary pairs with words like "Active", "Approved", "Ready", "Generating", "Failed", "Revoked", "Mocked", etc. — backend values, not fixed copy
- Job-detail validation message: "The job detail did not look as expected." (src/features/admin/jobDetailApi.ts) / report validation: "The report response did not look as expected." (src/features/admin/jobReportsApi.ts)

### Shared display helpers   (src/features/admin/format.ts + src/features/admin/MeJobActivity.tsx)
- Wait suffixes (dynamic): "`<1 h`", "`${hours} h`", "`${days} d`" — used after the words "waiting" in the queue
- Wait suffixes on the member report (dynamic): "`${minutes} min`", "`${hours} h`", "`${days} d`"; unknown: "—"
- Distance suffixes (dynamic): "`${metres} m`", "`${km} km`"; unknown: "—"
- Unknown-value placeholder everywhere: "—"

### Internal identifiers — do not touch
- Route segments: `/admin`, `/admin/company/jobs`, `/admin/company/jobs/new`, `/admin/me`, `/admin/me/new-job`, `/login`
- Query params: `tab`, `status`, `sort`, `q`, `skill`, `priority`, `pageSize`, `page`, `employeeId`, `olderThan`, `edit`, `cursor`, `range`, `rejectedCursor`, `company`
- Intent names: `decide`, `edit-save`, `job-settings`
- Form field names: `jobId`, `decision`, `reason`, `description`, `scheduledStart`, `scheduledEnd`, `technicianId`, `customerId`, `skillId`, `priority`, `serviceLocation`, `notesForTechnician`, `newCustomerName`, `newCustomerPhone`, `newCustomerAddress`, `newCustomerCity`, `idempotencyKey`, `userId`, `canCreateJobs`, `jobApprovalRequired`
- Wire status/priority/sort values: `scheduled`, `in_progress`, `pending_approval`, `completed`, `cancelled`, `rejected`, `normal`, `urgent`, `latest`, `soonest`, `ready`, `failed`, `generating`, `queued`
- Report type ids: `technician_job_activity`, `attendance_report`
- API paths: `/api/v1/jobs/:id`, `/api/v1/job-reports/owner`, `/api/v1/job-reports/employee`, `/api/v1/reports`, `/api/v1/reports/:id`, `/api/v1/reports/:id/retry`, `/api/v1/admin/tenants/:id/validity`
- Download filenames: `jobs.csv`, `fenzit-report.pdf`
- Notification payload keys / event types (backend): `job_number`, `customer_name`, `employee_name`, `reason`, `changed_fields`; `job.submitted`, `job.approved`, `job.rejected`, `job.edited`, `job.cancelled`, `job.assigned`; `step_*` / `job_*` activity prefixes

---

## Employees

### Shared rendering conventions — used across the whole section   (src/features/admin/format.ts, src/features/admin/status.ts, src/features/admin/components/Badge.tsx, src/features/admin/components/ConsoleFilterDropdown.tsx)
- Empty-cell / unknown-value marker: "—" (em dash, used as cell text in many tables)
- Word-unit formatters (units only, no sentence copy): "<1 h", `${hours} h`, `${days} d` (waitLabel); `${m} m`, `${km} km` (fmtDistance); " min" and " h" suffixes on shift-rule values
- Status badge rule: a raw backend status like `in_progress` is humanized to "In progress" (first letter capitalized, underscores to spaces) and shown as a badge — e.g. member statuses render as "Active", "Invited", "Deactivated"; job statuses as "In progress", "Scheduled", "Completed"; punch and leave-request statuses come from the backend and pass through the same rule
- Leave-part rule: empty part renders as "Full day"; `first_half` → "First Half" (same humanize rule)
- Dropdown trigger renders its label plus a colon: `${label}:` — e.g. "Role:", "Job settings:", "Sort:", "Rows per page:"
- Dropdown footer buttons: "Reset", "Apply"
- Dropdown empty state: "No options match."
- Country dial-code select, screen-reader-only field label (aria-style, hidden label): "Country code"
- Country dial-code select option (dynamic): `${country.countryName} (${country.dialCode})` — country name comes from a data list

### Employees page — top bar and breadcrumb   (src/pages/AdminEmployeesPage.tsx)
- aria (nav label): "Breadcrumb"
- Crumb link: "Console"
- Crumb separator (visible glyph, aria-hidden): "›"
- Crumb current page: "Employees"

### Employees page — greeting block   (src/pages/AdminEmployeesPage.tsx)
- Heading (dynamic): `Hello, ${selfName}` — selfName = the signed-in owner's name; when unknown, just "Hello"
- Role pill in the heading: "Owner"
- Ledes/subtitle: "Your team directory, their invites and their job approvals — all in one place."
- Button (opens the invite dialog): "Invite employee"

### Employees page — stat tiles   (src/pages/AdminEmployeesPage.tsx)
- Tile label: "Total employees"
- Tile sub (dynamic): `${result.stats.active} active, ${result.stats.invited} invited, ${result.stats.deactivated} deactivated` — the three counts
- Tile label: "Active employees"
- Tile sub (dynamic): `${activePct}% of all employees` — activePct = rounded share of active employees
- aria (progress bar label, same wording as the sub, dynamic): `${activePct}% of all employees`
- Tile label: "Pending invites"
- Tile pill: "Invited"
- Tile sub: "Waiting for their first sign-in"
- Tile label: "Needs approval"
- Tile pill: "Approval pending"
- Tile sub: "Their new jobs need your approval"

### Employees page — filter bar   (src/features/admin/components/EmployeesFilterBar.tsx)
- Button (shown only when a filter is set): "Clear all"
- Search input placeholder: "Search name, code or phone…"
- aria (search input label): "Search employees"
- Visible keyboard hint (aria-hidden): "⌘K"
- Status chip group aria: "Filter by status"
- Status chips (each followed by a count): "All", "Active", "Invited", "Deactivated"
- Dropdown trigger label: "Role"
- aria (option panel label, same word): "Role"
- Search placeholder inside the dropdown: "Filter roles…"
- Dropdown options: "All roles", "Owner", "Employee", "Viewer"
- Dropdown trigger label: "Job settings"
- aria (option panel label, same words): "Job settings"
- Search placeholder inside the dropdown: "Filter job settings…"
- Dropdown options: "All settings"; option with chip "Off" and text "Cannot create jobs"; option with chip "Creates jobs" (chip only, no text); option with chip "Create + approval" (chip only, no text)
- Dropdown trigger label: "Sort"
- Dropdown options: "Joined (newest)", "Joined (oldest)", "Name (A–Z)", "Name (Z–A)", "Code (A–Z)", "Code (Z–A)"

### Employees page — table   (src/features/admin/components/MembersTable.tsx)
- Column header (sortable link): "Name"
- Column header: "Phone"
- Column header (sortable link): "Code"
- Column header: "Role"
- Column header: "Status"
- Column header: "Job settings"
- Column header: "Employment"
- Column header (sortable link): "Joined on"
- Sort-arrow glyph inside sortable headers (visible, aria-hidden): "↑↓"
- Name fallback (dynamic — shown when the row has no name): "(no name)"
- Self pill beside your own row's name: "You"
- Role pill labels: "Owner", "Employee", "Viewer"
- Status pill text: humanized backend status (see shared conventions: "Active", "Invited", "Deactivated")
- Joined date: formatted "Nov 07, 2026" (en-US short month, 2-digit day, 4-digit year, India time) — numbers only, no words
- Empty-cell marker in Job settings / Employment columns for rows without a control: "—"

### Employees page — table, resend-invite cell   (src/features/admin/components/MembersTable.tsx)
- Button (idle): "Resend invite"
- Button (busy): "Sending…"
- Success note (dynamic, per SMS outcome): "Invite resent." / "Resent, but too many messages went to this number. Try again after some time." / "Resent, but the SMS could not be sent just now." / "Resent. SMS sending is switched off, so no SMS went out."
- Error line (dynamic): `${mine.message}` — passthrough of the action's error copy (see the action-messages group)

### Employees page — pager and rows-per-page   (src/features/admin/components/EmployeesPager.tsx)
- Dropdown trigger label: "Rows per page"
- Rows-per-page options: pure numbers only (the accepted page sizes, e.g. 10, 20…)
- aria (pager nav label): "Pages"
- aria (first-step link): "First page" — visible glyph "«"
- aria (previous-step link): "Previous page" — visible glyph "‹"
- aria (next-step link): "Next page" — visible glyph "›"
- aria (last-step link): "Last page" — visible glyph "»"
- Ellipsis glyph between page numbers (visible, decorative): "…"
- Form label: "Go to page:"
- aria (go-to input label): "Go to page"
- Go-to input placeholder: the current page number (dynamic number, not copy)
- Inline error (dynamic): `Enter a page from 1 to ${pages}.` — pages = total page count

### Employees page — empty, showing and failure states   (src/pages/AdminEmployeesPage.tsx)
- Failure alert: "The team list could not load. Try opening this page again from the menu."
- Empty state (company has nobody): "Nobody on the team yet."
- Empty state (filters exclude everyone or page is out of range): "No employees match these filters, or this page is past the last one."
- Showing caption (dynamic): `Showing ${from}–${to} of ${result.total} ${result.total === 1 ? "employee" : "employees"}` — en dash between the numbers; noun flips between "employee" and "employees"
- Busy suffix on the showing caption (dynamic): ` — updating…` — em dash + single-character ellipsis, appended while the list refetches

### Employees page — action error messages   (src/features/admin/adminBrowseLoaders.ts — the employees route's action; shown in the dialog and on table rows)
- Invite validation error: "Enter a name and a phone number (6–15 digits) before sending the invite."
- Resend failure error: "That resend could not be sent. Try again."
- Job-settings failure error: "That save could not be sent. Try again."

### Invite employee dialog   (src/features/admin/components/AddEmployeeDialog.tsx)
- aria (dialog label): "Invite employee"
- Dialog title: "Invite employee"
- Hint: "We'll send an invite SMS to their phone. They appear in the team list as Invited until they sign in."
- Form field label: "Name"
- Form field label: "Phone number"
- Hint under the phone field: "Numbers only, 6 to 15 digits."
- Inline readiness hint (dynamic — the send button's disabled reason): "Enter the employee's name to send the invite." / "Enter a phone number of 6 to 15 digits to send the invite."
- Error line (dynamic): `${error}` — passthrough of the invite action's error copy
- Success title: "Invite saved."
- Success body (dynamic composite): `Their employee code is ${saved.employeeCode}. ${smsOutcome(saved.smsStatus)} They appear in the team list below.` — the code sentence is omitted when no code; the SMS sentence is one of the four below
- SMS outcome sentences (dynamic, chosen by backend status): "The invite SMS went out to their phone." / "The invite is saved, but too many messages went to this number in a short time. Try again after some time." / "The invite is saved, but the SMS could not be sent just now." / "The invite is saved. SMS sending is switched off, so no SMS went out."
- Button (idle): "Send invite"
- Button (busy): "Sending…"
- Button: "Cancel"
- Button (after save): "Close"

### Job settings dialog (per employee row)   (src/features/admin/components/JobSettingsDialog.tsx)
- Trigger chip labels: "Off", "Creates jobs", "Create + approval"
- Dialog title: "Job settings"
- Hint: "Changes apply to the next job this employee creates. Jobs already waiting stay as they are."
- Checkbox label: "Can create jobs"
- Checkbox helper text: "They record their own visits and tasks."
- Checkbox label: "Approval needed"
- Checkbox helper text (dynamic, depends on the first switch): "New jobs wait for your approval first." / "Turn on Can create jobs first."
- Error line (dynamic): `${error}` — passthrough of the job-settings action's error copy
- Saved mark: "Job settings saved."
- Button (idle): "Save"
- Button (busy): "Saving…"
- Button: "Cancel"
- Button (after save): "Close"

### Export CSV button   (src/features/admin/components/EmployeesExport.tsx)
- Button (idle): "Download list"
- Button (busy): "Preparing…"
- Error alert: "The file could not be created. Try again."
- Downloaded file name: "employees.csv"
- CSV header row (visible inside the exported spreadsheet): "Name", "Email", "Phone", "Code", "Role", "Status", "Joined"

### Profile page — breadcrumb   (src/pages/AdminEmployeeProfilePage.tsx)
- aria (nav label): "Breadcrumb"
- Crumb link: "Console"
- Crumb separator (visible glyph, aria-hidden): "›"
- Crumb link: "Employees"
- Crumb separator (visible glyph, aria-hidden): "›"
- Crumb current page (dynamic): "Profile" — falls back to "Employee" when no userId is in the address

### Profile page — not-found and failed states   (src/pages/AdminEmployeeProfilePage.tsx)
- Heading: "Employee"
- Not-found alert: "This person is not on the team — they may have been removed, or the link is stale."
- Button link (not-found): "Back to all employees"
- Failed alert: "This page could not load. Check your connection and try again."
- Button (idle): "Try again"
- Button (busy): "Loading…"

### Profile page — header card and deactivate/reinstate actions   (src/pages/AdminEmployeeProfilePage.tsx)
- Heading fallback (dynamic — when the member has no name): "(no name)"
- Meta line (dynamic): `Joined ${fmtIstDay(member.createdAt)} · ${fmtPhone(...)}` — date in "19 Oct 2026" shape, then a middle dot, then the phone in "+91 98765 43210" shape
- Quiet button in the meta line: "+ Add designation"
- Identity badges: "Can create jobs", "Job approval required", "Owner", "Viewer"
- Status badge beside the name: humanized backend status ("Active", "Invited", "Deactivated")
- Button: "Assign Job"
- Button (opens the employment dialog): "Edit Profile"
- Button (step 1 of parking a member): "Deactivate"
- Button (step 2, confirming): "Confirm deactivate"
- Button (busy, both steps): "Working…"
- Button (cancel the confirm): "Cancel"
- Button (bring a parked member back): "Reinstate"
- Button (busy): "Working…"
- Action error line (dynamic): `${activateError}` — passthrough of the action's error copy (backend refusal text or the shared error copy below)
- aria (employment dialog label, dynamic): `Employment details for ${member.name ?? "employee"}` — falls back to the word "employee" when the member has no name

### Profile page — tabs   (src/features/admin/employeeProfileLabels.ts)
- aria (tab strip nav label, from Tabs.tsx): "Page sections"
- Tab labels, in order: "Master Record", "Jobs", "Attendance", "Leave", "Salary"

### Profile page — Master Record tab   (src/features/admin/components/employee/MasterRecordPanel.tsx)
- Card title: "Workforce master record"
- Card meta: "Legal and payroll identifiers"
- Setup banner (dynamic): `Statutory profile incomplete for automated EPF filing — ${missingStatutory.map((f) => f.label).join(", ")} still missing.` — em dash; the list is the missing fields' labels joined with commas
- Banner button: "Complete master setup"
- Field labels, in display order: "Date of Birth", "Father's Name", "Mother's Name", "Spouse Name", "PAN", "PF Account Number", "UAN", "Bank Name", "IFSC Code", "Bank Account", "Department"
- Per-field add affordance (shown in place of an empty value): "+ Add"
- Load-failure alert: "The employment record could not load."
- Failure-recovery button inside the alert: "Open it anyway"
- Card title: "Skills & certifications"
- Card meta: "Job dispatch matches on these"
- Empty state: "No skills yet — the employee picks them in their app."

### Profile page — Jobs tab   (src/features/admin/components/employee/ProfileJobsPanel.tsx)
- Load-failure alert: "The job history could not load. Try opening this page again from the menu."
- Summary chip labels: "Total jobs", "In progress", "Scheduled", "Completed"
- Card title: "Job history"
- Column headers: "Job", "Service", "Location", "Date", "Status"
- Empty state: "No jobs yet — assign one from the Assign Job button above."
- Overflow caption (dynamic): `Showing the newest ${data.data.length} of ${data.total} — open the Jobs page for everything.` — the words "open the Jobs page" are the link text; em dash before the link
- Cell fallbacks: "—" for skill and date columns; job status via humanize

### Profile page — Attendance tab   (src/features/admin/components/employee/ProfileAttendancePanel.tsx)
- Card title: "Office assignment"
- Card meta: "Tracked office & geofence"
- Load-failure alert: "The enrolment could not load — retry the page from the menu."
- Empty state: "Not enrolled in attendance yet."
- Address fallback (dynamic, when the office has none): "Address not set"
- Radius chip (dynamic): `${office.data.radiusM} m geofence radius` — radiusM = the geofence radius in metres
- Assignment date (dynamic): `Assigned since ${fmtDay(assigned.attendanceStartDate)}` — d = the enrolment's start date
- Assignment-date fallback: "Assignment date not recorded"
- Card title: "Shift rules"
- Card meta: "How the day is graded"
- Rule labels: "Start", "End", "Late cutoff", "Full day", "Half day"
- Rule value suffixes (dynamic): `${rules.lateCutoffMinutes} min`, `${rules.fullDayHours} h`, `${rules.halfDayHours} h`
- Empty state (settled, person genuinely not enrolled): "No shift rules — the person is not enrolled."
- Empty state (fetch failed): "The shift rules could not load."
- Card title: "Punch history"
- Card meta (dynamic): the month name and year, e.g. "November 2026" — Intl long month + year, no other words
- Month nav aria: "Month"
- Month nav links: "‹ Previous", "Next ›"
- Load-failure alert: "The punch history could not load — retry the page from the menu."
- Column headers: "Date", "Check-in", "Check-out", "In distance", "Out distance", "Status"
- Empty state (dynamic): `Punches appear here once ${memberName} checks in${assigned?.officeName != null ? ` at ${assigned.officeName}` : ""}.` — memberName defaults to "this employee"; the " at ${officeName}" tail is omitted when no office is assigned
- Cell fallbacks: "—" for missing check-in/check-out; distance cells via the m/km formatter; status via humanize

### Profile page — Leave tab   (src/features/admin/components/employee/ProfileLeavePanel.tsx)
- Load-failure alert (balances): "The leave balances could not load — retry the page from the menu."
- Empty state (balances): "No accrual leave types are set up for this company yet."
- Balance card name: the leave type's name (backend value)
- Balance value (dynamic): `${balance.remaining} days left` — the number, then the words " days left"
- Accrual captions (dynamic): "Accrues 1 day / month" / `Accrues ${days} days / month` / `Annual grant of ${days} days` / "Credited by the owner"
- Disabled suffix on the caption (dynamic): ` · Type disabled` — appended after a middle dot separator
- Card title: "Leave requests"
- Card meta: "Newest first"
- Truncation note in the footer (dynamic): `Only the newest ${requests.data.data.length} show here — older requests are not listed in the console yet.`
- Load-failure alert (requests): "The leave requests could not load — retry the page from the menu."
- Column headers: "Dates", "Part", "Working days", "Reason", "Status"
- Empty state: "No leave requests yet — requests appear here with type, dates and approval status."
- Date-range cell (dynamic): `${fmtDay(row.startDate)} – ${fmtDay(row.endDate)}` — en dash with spaces
- Part fallback: "Full day"; otherwise the humanized backend part ("First Half" etc.)
- Reason fallback: "—"; status via humanize

### Member job cards (member's own view, above the jobs table)   (src/features/admin/MemberJobsCards.tsx)
- Card title: "New job"
- Card body (dynamic, depends on the approval switch): "Create a job for a customer — it waits for your owner's approval first." / "Create a job for a customer — it is assigned to you at once."
- Card link: "Create a job"
- Card title: "Waiting for approval"
- Card meta (dynamic): `${pending.data.length} waiting` / `${pending.data.length}+ waiting` — n = number waiting, "+" when more follow
- Pending item line (dynamic composite): `· ${p.jobNumber} · ${p.customerName} · waiting ${waitLabel(p.ageHours)}` — middle-dot separators; when the customer is unknown the middle becomes " · (no customer)"; waitLabel renders "<1 h", "42 h" or "2 d"
- Truncation note: "Older submissions follow on the next pages."
- Footer note: "Your owner decides these — you get a notification on your phone, and the outcome shows in My report." — "My report" is the link text
- Card title (failure state): "Waiting for approval"
- Load-failure alert: "Your waiting-for-approval list could not load. Retry from the sidebar."

### Shared error copy surfaced by this section's failures   (src/utils/errorMessages.ts — console-wide map; reached from the employees and profile actions via messageForError)
- Generic failure: "Something went wrong. Try again."
- Server failure: "Something went wrong on our side. Try again in a moment."
- No company selected: "Pick a company first. Search for the person, then choose the company you want to work on."
- Session error: "Your session has ended. Sign in again to continue."
- Permission error: "You do not have permission to do this."
- Validation error: "Check the highlighted fields and try again."
- Not found: "We could not find that. It may have been removed."
- Duplicate: "That already exists."
- Already on team: "That person is already on your team."
- Rate limit: "Too many attempts. Wait a few minutes and try again."

### Profile action message   (src/features/admin/employeeProfileLoaders.ts)
- Error for an unrecognized action post: "Nothing to do — unknown action."
- Note: a backend 4xx refusal (wrong state, last owner, etc.) is passed through to the screen verbatim — backend-supplied, not in this dump

### Internal identifiers — do not touch
- Route segments: /admin, /admin/company/employees, /admin/company/employees/:userId, /admin/company/jobs, /admin/company/jobs/new, /admin/me/new-job, /login
- Query params: tab, month, q, status, role, jobSetting, sort, pageSize, page, userId, technician (on the Assign Job link); tab value report on the My report link
- Tab values: master, jobs, attendance, leave, payroll
- Sort values: joined_new, joined_old, name_az, name_za, code_az, code_za
- Filter values: all, active, invited, deactivated, off, create_only, approval, company_admin, employee, viewer
- Form intents and fields: invite, resend, job-settings, activate; fields name, phoneNumber, countryCode, userId, canCreateJobs, jobApprovalRequired, active, q
- Wire statuses (backend-supplied, humanized for display): active, invited, deactivated, in_progress, scheduled, completed, sent, refused_cap, failed, not_configured, plus punch and leave statuses
- Tone vocabulary (colour mapping keys, never rendered): done, progress, scheduled, cancelled, neutral, primary, violet, gray, sky, green
- aria keywords/attributes: aria-sort ascending/descending/none, aria-current, aria-haspopup, aria-live, aria-hidden
- Internal error string never rendered: "No session"
- Emoji/glyph decorations to leave as-is: ›, ‹, «, », …, ↑↓, ✓, ⌘K, —, ·

---
