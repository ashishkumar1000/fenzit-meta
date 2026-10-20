# Database snapshot, 2026-10-20 (source of truth for the working database)

This folder is the **known-good state of the working Supabase database** (`Fenzit-Be`, project `pnlvreaijzslfymlnoti`, Postgres 17) on 2026-10-20, **before** the roles and access work (`../../implementation-artifacts/roles-and-access-spec.md`).

If anything goes wrong later, rebuild a working database from these files. The restore was rehearsed on a second project (`Fenzit-dev`) and verified against the original, so it is known to work.

## Files

| File | What it holds |
|---|---|
| `schema.sql` | Everything in the `public` schema: 35 tables, constraints, indexes, 31 functions, the `attendance_access_state` view, the triggers, 16 policies, the `supabase_realtime` table, and the extensions. |
| `reference-data.sql` | The reference rows only: 87 country codes, 28 skills, 28 workflow templates, 4 app config rows. No customer, company or sign-up data. |
| `cron-jobs.sql` | The six scheduled jobs (`pg_cron`). `pg_dump` leaves these out, so they were exported by hand. |
| `permissions-and-realtime.sql` | Who may run what. `pg_dump` does not carry these over to a fresh Supabase project. Without this file the public API can call every function and read every table. It also holds the realtime policy `notifications_topic_recipient_only`. |

## How to restore

1. Create a new, empty Supabase project (Postgres 17). Turn on `pg_cron` and `btree_gist` if `schema.sql` cannot (it tries).
2. Run the files in this order, with `psql` and the new project's database URL:
   1. `schema.sql`
   2. `reference-data.sql`
   3. `cron-jobs.sql`
   4. `permissions-and-realtime.sql`
3. Point the backend at the new project: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL` and **`SUPABASE_JWT_SECRET`**. The secret must be the new project's legacy JWT secret, because the backend signs its own tokens and the policies read them.
4. Confirm with the checks below, then run the backend tests.

Two harmless errors appear if you also load a full data dump: permission denied on Supabase's own `storage.buckets_vectors` and `storage.vector_indexes`. Ignore them.

## How to check a restore

Run on both databases and compare. These are the values from 2026-10-20:

- 35 tables, 319 columns, 185 constraints, 94 indexes, 16 policies, 26 triggers, 31 functions, 35 tables with row-level security on, 6 cron jobs, realtime table `app_config`.
- Fingerprints (md5 of the ordered definitions): functions `81f8358e128d46ecffa214a36bf57a5a`, policies `cdea86896f359fea3d0a32abb16c332e`, view `ae44a5558f680195222962a64776aed9`.
- Permission fingerprints: function ACLs `3f67cb4a28b4b2239a420ca9056e9f4c`, table ACLs `7df65f1fb035f0080eb776bee60b6e3a`, column ACLs `f426c7e7e3ae7ff2aa5dd889fb03ef88`, default privileges `e05579c6adf6c0c66ca9b4ea08e36266`. Public functions runnable by `anon` or `authenticated`: **0**. Policies on `realtime.messages`: 1.
- The constraints fingerprint can differ because Postgres stores some `AND` brackets differently after a restore. The counts and rules are the same.

## What is not in this folder

- **Customer and account data.** The database held 2 users and 1 company (test data) when this was taken. A full data dump exists only on the owner's machine, because it has phone numbers.
- Supabase's own schemas (`auth`, `storage`, `realtime` tables, `vault`). The app uses none of them: 0 auth users, 0 storage buckets, 0 vault secrets, 0 edge functions.
- Project settings, API keys and the JWT secret. No secrets are stored in these files (scanned).

## Known test baseline on this database

- Unit tests: 104 suites, 1,636 tests, all pass.
- Real-database end-to-end suite: all pass **except two tests that already fail on this database**, before any change, on both the original and the restored copy:
  - `attendance-check-in-out`: "check-out updates the SAME row and reports worked minutes" (expects 0, gets 1).
  - `attendance-reminders`: "the two shifted half-day arms fire at their OWN instants" (a reminder fires one second before its due time; the test calls this bug B-BUG-1).
- Slow connections can also trip the 5-second test timeout. Use `--testTimeout=60000` for a remote database.

If one of these fails after the roles work, it is not caused by the roles work.

## How this was made

`pg_dump` (the script the Supabase CLI generates, run with local `pg_dump` because Docker is not installed) for schema and data. The cron jobs, the permissions and the realtime policy were read from the live database through the Supabase MCP and written by hand. The restore was proven on a separate project and compared with the original object by object.
