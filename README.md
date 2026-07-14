# Family Chore Allowance Prototype

Phase 1 local prototype for the PRD in `/Users/jessebarrueta/Downloads/do-good-chore-allowance-prd.md`.

## App Name

The user-facing app name is intentionally centralized:

```text
Configuration/AppBrand.xcconfig
```

Change `APP_DISPLAY_NAME` there when the final name is decided. The SwiftUI app reads `CFBundleDisplayName` from the bundle, so UI copy should not hard-code the product name.

Current display name: `ChaChing`

## What Is Built

- SwiftUI iPhone app project: `ChaChing.xcodeproj`
- Foundation-only core package for deterministic allowance logic
- Supabase Swift package linked through the Xcode project
- Supabase client configuration using the publishable project key
- Initial Supabase SQL migrations for families, child profiles, child/parent invites, remote family bootstrapping, chores, occurrences, submissions, ledger entries, RLS, and private evidence storage
- Seed family state for Daddy/Zoe with `$15.00` base allowance and `$13.50` current total
- Role-aware parent and child app shells
- Ledger-driven allowance summary
- Idempotent missed-task deductions
- Excuse flow that voids deductions
- Parent bonus flow
- Parent child-profile and invite-link flow with iOS share sheet handoff
- Supabase invite creation writes for child and parent links, with local fallback while auth is unfinished
- Invite acceptance service that requests/verifies SMS OTP and calls the `accept-child-invite` Edge Function
- Supabase Edge Function source for hashing invite tokens and linking authenticated child users
- Parent invite flow for a second parent account, with `Daddy` / `Mamma` seed display names
- Supabase schema and Edge Function source for `parent_invites`
- Child dashboard
- Task detail
- Native camera JPEG evidence capture with a simulator-friendly mock fallback
- Supabase Storage evidence upload and `review-evidence` AI review call with local fallback while auth is unfinished
- Parent Family Sync card for phone OTP sign-in, remote family bootstrap, Supabase-backed family loading, and sign-out
- Supabase-backed role routing from `family_members.role`
- Supabase parent review decision RPC and app wiring for approve, reject, excuse, and retake actions
- Remote family refresh on app foreground, toolbar refresh, and pull-to-refresh for parent/child state
- Parent review queue actions
- Local chore editing
- Earnings/ledger overview
- Static lock-screen and home-screen widget previews
- Addable WidgetKit extension with Home Screen and Lock Screen allowance widgets backed by shared App Group state
- Parent allowance schedule controls for weekly or every-two-week cadence
- Local notification permission flow and scheduling for chore due times plus allowance day
- Child allowance-day message handoff using Messages or share-sheet fallback
- Rollover debt calculation when deductions exceed the current allowance period

## Privacy and Evidence Direction

The current app can capture and upload chore evidence photos, but the planned product direction is privacy-first and parent-configurable:

- Photo evidence can be disabled for a family and configured per chore.
- Chores can be `photo_required`, `photo_optional`, `parent_only`, or `no_verification`.
- People/face blocking should run on-device before upload; blocked images never leave the phone.
- Evidence photos should be temporary. MVP default: delete after parent review plus a short undo grace window, with a post-allowance-period cleanup backstop.
- Keep task decisions, allowance history, and lightweight AI/review metadata; do not keep original images or thumbnails after evidence deletion.

See:

```text
docs/privacy-and-evidence-roadmap.md
```

## Widget State

The main app writes the current allowance and next-chore summary to the shared App Group:

```text
group.com.artofsullivan.chaching
```

The widget reads that shared snapshot and falls back to sample data if the group is unavailable. For TestFlight/device archives, make sure App Groups is enabled for both `com.artofsullivan.chaching` and `com.artofsullivan.chaching.widgets` in the Apple team.

## Verified

```sh
swift test
xcodebuild -project ChaChing.xcodeproj -scheme ChaChing \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build
```

The app has also been installed and launched in the iPhone 16 simulator.

## Supabase

Client config lives in:

```text
App/Networking/SupabaseClientProvider.swift
```

The checked-in key is the Supabase publishable key, which is expected to be present in client apps. Do not commit the database password, service-role key, or OpenAI keys.

### Edge Function Secrets

Use Supabase secrets for server-side API keys and model configuration. The checked-in template is:

```text
supabase-secrets.example.env
```

Create your local secrets file, fill in the OpenAI key, then upload it to Supabase:

```sh
cp supabase-secrets.example.env .env.supabase.local
$EDITOR .env.supabase.local
scripts/set-supabase-secrets.sh
```

If the CLI has not been authenticated yet, run `supabase login` first, or set `SUPABASE_ACCESS_TOKEN` for the command.

The script targets project ref `pjvgtmxyxrfhabyuefne` by default. To override it:

```sh
SUPABASE_PROJECT_REF=your-project-ref scripts/set-supabase-secrets.sh
```

Current app secrets:

```text
OPENAI_API_KEY
OPENAI_REVIEW_MODEL
OPENAI_REVIEW_IMAGE_DETAIL
```

Supabase-hosted Edge Functions are expected to provide `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to the invite/review functions. Do not put those values in the iOS app.

The schema lives in:

```text
supabase/migrations/0001_initial_schema.sql
supabase/migrations/0002_child_profiles_and_invites.sql
supabase/migrations/0003_parent_invites.sql
supabase/migrations/0004_family_bootstrap.sql
supabase/migrations/0005_parent_review_decisions.sql
```

`0004_family_bootstrap.sql` adds the `bootstrap_preview_family` RPC used by the parent Family Sync card. A signed-in parent can create the initial remote family, child profile, current week, starting allowance ledger entry, and preview chore schedule from the app.

`0005_parent_review_decisions.sql` adds the `decide_chore_submission` RPC used by parent review actions. It updates the occurrence, parent decision metadata, and any related deduction ledger row in one server-side transaction.

Evidence files should be stored under paths beginning with the family id:

```text
{familyId}/{taskOccurrenceId}/original.jpg
```

Invite acceptance is handled by:

```text
supabase/functions/accept-child-invite/index.ts
```

The function expects an authenticated Supabase user and a raw invite token. It hashes the token with SHA-256, matches it against `child_invites.token_hash`, links the child profile to the authenticated user, upserts the `family_members` child row, and marks the invite accepted.

Second-parent acceptance is handled by:

```text
supabase/functions/accept-parent-invite/index.ts
supabase/migrations/0003_parent_invites.sql
```

The parent function also expects an authenticated Supabase user and raw invite token. It hashes the token, matches `parent_invites.token_hash`, upserts a `family_members` row with `role = 'parent'`, and marks the invite accepted.

AI evidence review is handled by:

```text
supabase/functions/review-evidence/index.ts
```

The function expects an authenticated family member and a `submission_id`. It loads the submission, occurrence, chore definition, and private evidence image server-side, asks OpenAI for structured JSON, stores the advisory result in `chore_submissions.ai_result`, and moves the occurrence to `ai_reviewed` unless a parent has already made a final decision.

Deploy it with:

```sh
supabase functions deploy review-evidence --project-ref pjvgtmxyxrfhabyuefne
```

Invoke it from the app with:

```json
{ "submission_id": "..." }
```

To apply migrations without saving the database password:

```sh
export SUPABASE_DB_PASSWORD='...'
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0001_initial_schema.sql
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0002_child_profiles_and_invites.sql
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0003_parent_invites.sql
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0004_family_bootstrap.sql
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0005_parent_review_decisions.sql
```

## Next Slices

1. Sync bonuses, chore edits, and allowance settings back to Supabase instead of keeping those writes local after remote load.
2. Smoke-test parent review sync across two TestFlight devices: parent reviews a task, child foregrounds or refreshes the app, and widgets update from the refreshed App Group snapshot.
3. Smoke-test auth-backed evidence upload and AI review on a physical phone against the remote family.
4. Add family/chore evidence settings from `docs/privacy-and-evidence-roadmap.md`.
5. Add on-device person/face blocking before evidence upload.
6. Add evidence deletion scheduling after parent review, including the undo grace window and allowance-period cleanup backstop.
7. Add nightly retention cleanup for stale evidence and expired invite tokens.
8. Add realtime or push-triggered refresh so both parent phones and child phones converge without manually tapping Refresh.
9. Persist notification preferences and rollover closeout state in Supabase once remote writes are live.
10. Add a dedicated child allowance-day celebration screen surfaced from push/local notification and dashboard state.
11. Add parent-facing allowance-period closeout review before a child message request is sent.
12. Add Universal Links.
