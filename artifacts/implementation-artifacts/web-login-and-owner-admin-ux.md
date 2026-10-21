# UX pass: website login and admin page

Owner: Sally (UX Designer). Input: `web-login-and-owner-admin-spec.md`, the landing page header, and the web standards (`docs/repos/fenzit-web/standards.md`). Date: 2026-10-21.

## Who this is for

Field-service owners and office staff on a phone, often on a slow mobile connection, who want to get into the company page quickly. Some are not technical. They know their phone number. Email is the second choice, mainly for the owner who set one up.

## Header (landing page)

- "Log in" sits beside "Join early access". It is a plain text link, so the call to action stays the strongest thing in the bar.
- Phone width: the bar holds the logo, "Log in", and the button. The button keeps its full label. The gap between items stays at `--space-3`, and the bar keeps its gutter. The build checks this at 360 px, and if the label does not fit, the button wraps to a second row instead of being shortened.
- Desktop: the same order, with the section links between the logo and the buttons.

## /login

One page, one heading: **Log in to Fenzit**.

1. **One field, "Phone or email".** Helper text under it: "Use the phone number or the email linked to your account."
2. **Phone path** (no "@" in the value): a **Send code** button. On success the page changes to a code step, not a new page:
   - Heading line: "Enter the 4-digit code we sent to +91 98765 43210." The number is shown back so the owner can check it.
   - One code field, numeric keyboard, `autocomplete="one-time-code"`.
   - **Log in** button, and a **Change number** link that returns to step 1 and keeps what was typed.
3. **Email path** (contains "@"): a **Password** field appears below the first field and the button reads **Log in**. The password field is hidden for phone users, so they never see a field that does not apply to them.
4. **Validation on submit, not on each keystroke.** Empty value: "Enter your phone number or email." A phone number that fails the existing rule: "Type the number without the country code, a plus sign, 00 or a leading 0." Email without a valid shape: "Enter a valid email address."
5. **Errors:**
   - Wrong email or password: "That email and password do not match. Check them and try again." The same message covers an unknown email and a disabled account, so the page never reveals which emails exist.
   - Wrong code: "That code is not right. Check it and try again." (existing `INVALID_OTP` copy)
   - Code expired: "That code has expired. Ask for a new one." Plus a **Send new code** button in the same step.
   - Too many attempts: the existing "Too many wrong codes. Wait before you try again." copy.
   - No connection or timeout: the existing connection copy from `messageForError`.
6. **Loading:** the button text changes ("Sending code…", "Logging in…") and the button is disabled while the request runs. The disabled state needs no explanation, because the button text already says what is happening.
7. **After success:** go to `/admin`. The page does not say "Welcome" or show a success banner. The next screen is the answer.
8. **Visual:** the same flat surface and card-free layout as the landing page. One column, `--layout-content-max` wide on phones. Inputs at 48 px tall with 16 px text. Labels always visible above the field, never placeholder-only. Focus ring on every control.

## /admin

Heading **Company admin**. Under it, one line: "This page is a placeholder. Company tools will appear here."

States, in order a person sees them:

1. **Checking your access…** A plain line of text in the page's text colour, not a spinner over a blank page. (The standards ask for a skeleton on data screens; this page has no data to show, so a single line is enough.)
2. **Could not check your access.** "We could not check your access. Check your connection and try again." with a **Try again** button, which reloads the check.
3. **No permission.** "You do not have permission to open this page." with a **Log out** button. This is the page a field technician or viewer sees after logging in. It does not say what their role is.
4. **Admin.** The heading, the placeholder line, the name when the account has one ("Signed in as Ravi Kumar"), and **Log out**.

**Log out** clears the saved sign-in and returns to the home page. It does not ask for confirmation, because nothing is lost.

A signed-out visitor who opens `/admin` is sent to `/login` at once, with no message.

## Copy rules applied

- Sentence case. Button text names the action: "Send code", "Log in", "Log out", "Try again".
- No "Submit". No Hindi words. Indian English is fine.
- Every disabled control says why (in this flow, none are disabled without a visible reason, because the buttons stay enabled until a request is running).

## Open points for the owner

- The spec's login form has two fields. This pass adds the code step for phone users, because a phone login has no password. The spec's list of fields is therefore one field plus the password field that appears for email, and one code step for phone. This matches the spec's intent (existing OTP flow, unchanged).
- The phone path is India-only for now (+91), which matches the early-access form's default. The country picker is not on this page.
