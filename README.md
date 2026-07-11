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
- Seed family state for Jesse/Zoe with `$15.00` base allowance and `$13.50` current total
- Role-aware parent and child app shells
- Ledger-driven allowance summary
- Idempotent missed-task deductions
- Excuse flow that voids deductions
- Parent bonus flow
- Parent child-profile and invite-link flow with iOS share sheet handoff
- Child dashboard
- Task detail
- Mock camera/evidence capture
- Mock advisory AI review
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

The schema lives in:

```text
supabase/migrations/0001_initial_schema.sql
supabase/migrations/0002_child_profiles_and_invites.sql
```

Evidence files should be stored under paths beginning with the family id:

```text
{familyId}/{taskOccurrenceId}/original.jpg
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

1. Add Supabase auth and route from `family_members.role`.
2. Add the invite-acceptance Edge Function that hashes tokens and links child profiles to child auth users.
3. Replace local seed state with Supabase-backed families, chores, occurrences, and ledger reads.
4. Replace mock capture with real camera capture, EXIF stripping, and Storage upload.
5. Add WidgetKit targets backed by shared App Group state.
6. Add local notification scheduling and Universal Links.
7. Move AI review behind a server-side endpoint with structured JSON output.
