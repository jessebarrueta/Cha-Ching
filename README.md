# Family Chore Allowance Prototype

Phase 1 local prototype for the PRD in `/Users/jessebarrueta/Downloads/do-good-chore-allowance-prd.md`.

## App Name

The user-facing app name is intentionally centralized:

```text
Configuration/AppBrand.xcconfig
```

Change `APP_DISPLAY_NAME` there when the final name is decided. The SwiftUI app reads `CFBundleDisplayName` from the bundle, so UI copy should not hard-code the product name.

## What Is Built

- SwiftUI iPhone app project: `ChaChing.xcodeproj`
- Foundation-only core package for deterministic allowance logic
- Supabase Swift package linked through the Xcode project
- Supabase client configuration using the publishable project key
- Initial Supabase SQL migrations for families, child profiles, child invites, chores, occurrences, submissions, ledger entries, RLS, and private evidence storage
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
- Parent review queue actions
- Local chore editing
- Earnings/ledger overview
- Static lock-screen and home-screen widget previews

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
```

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
```

## Next Slices

1. Apply `0003_parent_invites.sql`, then deploy `accept-child-invite` and `accept-parent-invite`.
2. Add Supabase auth bootstrapping and route from `family_members.role`.
3. Replace local seed state with Supabase-backed families, chores, occurrences, and ledger reads.
4. Smoke-test auth-backed evidence upload and AI review on a physical phone.
5. Replace the native camera sheet with a custom camera preview if the MVP needs guided framing controls.
6. Add WidgetKit targets backed by shared App Group state.
7. Add local notification scheduling and Universal Links.
