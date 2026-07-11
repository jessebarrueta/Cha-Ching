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
- Initial Supabase SQL migration for families, chores, occurrences, submissions, ledger entries, RLS, and private evidence storage
- Seed family state for Jesse/Alex with `$15.00` base allowance and `$13.50` current total
- Ledger-driven allowance summary
- Idempotent missed-task deductions
- Excuse flow that voids deductions
- Parent bonus flow
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

The initial schema lives in:

```text
supabase/migrations/0001_initial_schema.sql
```

Evidence files should be stored under paths beginning with the family id:

```text
{familyId}/{taskOccurrenceId}/original.jpg
```

This workspace currently does not have `psql` or the Supabase CLI installed. To apply the migration without saving the database password:

```sh
export SUPABASE_DB_PASSWORD='...'
psql "postgresql://postgres:${SUPABASE_DB_PASSWORD}@db.pjvgtmxyxrfhabyuefne.supabase.co:5432/postgres" \
  -f supabase/migrations/0001_initial_schema.sql
```

## Next Slices

1. Apply the Supabase migration.
2. Add parent/child authentication and role-gated app mode switching.
3. Replace local seed state with Supabase-backed families, chores, occurrences, and ledger reads.
4. Replace mock capture with real camera capture, EXIF stripping, and Storage upload.
5. Add WidgetKit targets backed by shared App Group state.
6. Add local notification scheduling and deep links.
7. Move AI review behind a server-side endpoint with structured JSON output.
