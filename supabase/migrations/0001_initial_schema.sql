create extension if not exists "pgcrypto";

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  weekly_base_allowance_cents integer not null default 1500 check (weekly_base_allowance_cents >= 0),
  timezone text not null default 'America/Los_Angeles',
  week_starts_on integer not null default 0 check (week_starts_on between 0 and 6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('parent', 'child')),
  display_name text not null,
  created_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

create table if not exists public.weeks (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  base_allowance_cents integer not null check (base_allowance_cents >= 0),
  archived_at timestamptz,
  final_balance_cents integer check (final_balance_cents >= 0),
  created_at timestamptz not null default now(),
  unique (family_id, child_id, starts_at)
);

create table if not exists public.chore_definitions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  short_title text not null,
  description text,
  instructions text,
  expected_evidence text,
  example_image_path text,
  deduction_cents integer not null check (deduction_cents >= 0),
  verification_mode text not null default 'photo_required'
    check (verification_mode in ('photo_required', 'photo_optional', 'parent_only', 'no_verification')),
  recurrence jsonb not null,
  due_window_minutes integer not null default 90 check (due_window_minutes > 0),
  reminder_offsets_minutes integer[] not null default array[15, 0],
  is_paused boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_occurrences (
  id uuid primary key default gen_random_uuid(),
  chore_definition_id uuid not null references public.chore_definitions(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  week_id uuid not null references public.weeks(id) on delete cascade,
  scheduled_at timestamptz not null,
  due_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'upcoming'
    check (status in ('upcoming', 'due', 'submitted', 'ai_reviewed', 'approved', 'rejected', 'missed', 'excused')),
  submission_id uuid,
  deduction_ledger_entry_id uuid,
  excused_by_parent_id uuid references auth.users(id),
  excuse_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (chore_definition_id, child_id, scheduled_at)
);

create table if not exists public.chore_submissions (
  id uuid primary key default gen_random_uuid(),
  task_occurrence_id uuid not null references public.task_occurrences(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  image_path text not null,
  thumbnail_path text,
  submitted_at timestamptz not null default now(),
  ai_result jsonb,
  parent_decision jsonb,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'task_occurrences_submission_id_fkey'
  ) then
    alter table public.task_occurrences
      add constraint task_occurrences_submission_id_fkey
      foreign key (submission_id) references public.chore_submissions(id)
      deferrable initially deferred;
  end if;
end;
$$;

create table if not exists public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  week_id uuid not null references public.weeks(id) on delete cascade,
  child_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id),
  entry_type text not null check (entry_type in ('weekly_base', 'deduction', 'bonus', 'adjustment')),
  title text not null,
  amount_cents integer not null check (amount_cents >= 0),
  related_occurrence_id uuid references public.task_occurrences(id),
  note text,
  is_voided boolean not null default false,
  created_at timestamptz not null default now()
);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'task_occurrences_deduction_ledger_entry_id_fkey'
  ) then
    alter table public.task_occurrences
      add constraint task_occurrences_deduction_ledger_entry_id_fkey
      foreign key (deduction_ledger_entry_id) references public.ledger_entries(id)
      deferrable initially deferred;
  end if;
end;
$$;

create unique index if not exists ledger_entries_one_active_deduction_per_occurrence
  on public.ledger_entries (related_occurrence_id)
  where entry_type = 'deduction' and is_voided = false and related_occurrence_id is not null;

create index if not exists chore_definitions_family_child_idx on public.chore_definitions (family_id, child_id);
create index if not exists task_occurrences_week_child_idx on public.task_occurrences (week_id, child_id, due_at);
create index if not exists ledger_entries_week_child_idx on public.ledger_entries (week_id, child_id, created_at desc);
create index if not exists submissions_occurrence_idx on public.chore_submissions (task_occurrence_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists families_set_updated_at on public.families;
create trigger families_set_updated_at
before update on public.families
for each row execute function public.set_updated_at();

drop trigger if exists chore_definitions_set_updated_at on public.chore_definitions;
create trigger chore_definitions_set_updated_at
before update on public.chore_definitions
for each row execute function public.set_updated_at();

drop trigger if exists task_occurrences_set_updated_at on public.task_occurrences;
create trigger task_occurrences_set_updated_at
before update on public.task_occurrences
for each row execute function public.set_updated_at();

create or replace function public.is_family_member(target_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.is_family_parent(target_family_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.family_members
    where family_id = target_family_id
      and user_id = auth.uid()
      and role = 'parent'
  );
$$;

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.weeks enable row level security;
alter table public.chore_definitions enable row level security;
alter table public.task_occurrences enable row level security;
alter table public.chore_submissions enable row level security;
alter table public.ledger_entries enable row level security;

drop policy if exists "family members can read families" on public.families;
create policy "family members can read families"
on public.families for select
using (public.is_family_member(id));

drop policy if exists "parents can update families" on public.families;
create policy "parents can update families"
on public.families for update
using (public.is_family_parent(id))
with check (public.is_family_parent(id));

drop policy if exists "members can read family memberships" on public.family_members;
create policy "members can read family memberships"
on public.family_members for select
using (public.is_family_member(family_id));

drop policy if exists "parents can manage family memberships" on public.family_members;
create policy "parents can manage family memberships"
on public.family_members for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop policy if exists "family members can read weeks" on public.weeks;
create policy "family members can read weeks"
on public.weeks for select
using (public.is_family_member(family_id));

drop policy if exists "parents can manage weeks" on public.weeks;
create policy "parents can manage weeks"
on public.weeks for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop policy if exists "family members can read chores" on public.chore_definitions;
create policy "family members can read chores"
on public.chore_definitions for select
using (public.is_family_member(family_id));

drop policy if exists "parents can manage chores" on public.chore_definitions;
create policy "parents can manage chores"
on public.chore_definitions for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop policy if exists "family members can read occurrences" on public.task_occurrences;
create policy "family members can read occurrences"
on public.task_occurrences for select
using (
  exists (
    select 1
    from public.weeks
    where weeks.id = task_occurrences.week_id
      and public.is_family_member(weeks.family_id)
  )
);

drop policy if exists "parents can manage occurrences" on public.task_occurrences;
create policy "parents can manage occurrences"
on public.task_occurrences for all
using (
  exists (
    select 1
    from public.weeks
    where weeks.id = task_occurrences.week_id
      and public.is_family_parent(weeks.family_id)
  )
)
with check (
  exists (
    select 1
    from public.weeks
    where weeks.id = task_occurrences.week_id
      and public.is_family_parent(weeks.family_id)
  )
);

drop policy if exists "family members can read submissions" on public.chore_submissions;
create policy "family members can read submissions"
on public.chore_submissions for select
using (
  exists (
    select 1
    from public.task_occurrences
    join public.weeks on weeks.id = task_occurrences.week_id
    where task_occurrences.id = chore_submissions.task_occurrence_id
      and public.is_family_member(weeks.family_id)
  )
);

drop policy if exists "children can create own submissions" on public.chore_submissions;
create policy "children can create own submissions"
on public.chore_submissions for insert
with check (child_id = auth.uid());

drop policy if exists "parents can update submissions" on public.chore_submissions;
create policy "parents can update submissions"
on public.chore_submissions for update
using (
  exists (
    select 1
    from public.task_occurrences
    join public.weeks on weeks.id = task_occurrences.week_id
    where task_occurrences.id = chore_submissions.task_occurrence_id
      and public.is_family_parent(weeks.family_id)
  )
)
with check (
  exists (
    select 1
    from public.task_occurrences
    join public.weeks on weeks.id = task_occurrences.week_id
    where task_occurrences.id = chore_submissions.task_occurrence_id
      and public.is_family_parent(weeks.family_id)
  )
);

drop policy if exists "family members can read ledger" on public.ledger_entries;
create policy "family members can read ledger"
on public.ledger_entries for select
using (
  exists (
    select 1
    from public.weeks
    where weeks.id = ledger_entries.week_id
      and public.is_family_member(weeks.family_id)
  )
);

drop policy if exists "parents can manage ledger" on public.ledger_entries;
create policy "parents can manage ledger"
on public.ledger_entries for all
using (
  exists (
    select 1
    from public.weeks
    where weeks.id = ledger_entries.week_id
      and public.is_family_parent(weeks.family_id)
  )
)
with check (
  exists (
    select 1
    from public.weeks
    where weeks.id = ledger_entries.week_id
      and public.is_family_parent(weeks.family_id)
  )
);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chore-evidence',
  'chore-evidence',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do nothing;

drop policy if exists "family members can read chore evidence" on storage.objects;
create policy "family members can read chore evidence"
on storage.objects for select
using (
  bucket_id = 'chore-evidence'
  and public.is_family_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "family members can upload chore evidence" on storage.objects;
create policy "family members can upload chore evidence"
on storage.objects for insert
with check (
  bucket_id = 'chore-evidence'
  and public.is_family_member(((storage.foldername(name))[1])::uuid)
);

drop policy if exists "parents can manage chore evidence" on storage.objects;
create policy "parents can manage chore evidence"
on storage.objects for all
using (
  bucket_id = 'chore-evidence'
  and public.is_family_parent(((storage.foldername(name))[1])::uuid)
)
with check (
  bucket_id = 'chore-evidence'
  and public.is_family_parent(((storage.foldername(name))[1])::uuid)
);
