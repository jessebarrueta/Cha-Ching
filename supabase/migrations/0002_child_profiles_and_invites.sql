create table if not exists public.child_profiles (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  display_name text not null,
  phone_e164 text,
  linked_user_id uuid unique references auth.users(id) on delete set null,
  created_by_parent_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.child_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  child_profile_id uuid not null references public.child_profiles(id) on delete cascade,
  child_name text not null,
  phone_e164 text,
  created_by_parent_id uuid references auth.users(id) on delete set null,
  token_hash text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_child_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.weeks
  drop constraint if exists weeks_child_id_fkey,
  add constraint weeks_child_id_fkey
    foreign key (child_id) references public.child_profiles(id) on delete cascade;

alter table public.chore_definitions
  drop constraint if exists chore_definitions_child_id_fkey,
  add constraint chore_definitions_child_id_fkey
    foreign key (child_id) references public.child_profiles(id) on delete cascade;

alter table public.task_occurrences
  drop constraint if exists task_occurrences_child_id_fkey,
  add constraint task_occurrences_child_id_fkey
    foreign key (child_id) references public.child_profiles(id) on delete cascade;

alter table public.chore_submissions
  drop constraint if exists chore_submissions_child_id_fkey,
  add constraint chore_submissions_child_id_fkey
    foreign key (child_id) references public.child_profiles(id) on delete cascade;

alter table public.ledger_entries
  drop constraint if exists ledger_entries_child_id_fkey,
  add constraint ledger_entries_child_id_fkey
    foreign key (child_id) references public.child_profiles(id) on delete cascade;

create index if not exists child_profiles_family_idx on public.child_profiles (family_id);
create index if not exists child_invites_family_status_idx on public.child_invites (family_id, status, created_at desc);

drop trigger if exists child_profiles_set_updated_at on public.child_profiles;
create trigger child_profiles_set_updated_at
before update on public.child_profiles
for each row execute function public.set_updated_at();

drop trigger if exists child_invites_set_updated_at on public.child_invites;
create trigger child_invites_set_updated_at
before update on public.child_invites
for each row execute function public.set_updated_at();

create or replace function public.is_linked_child_profile(target_child_profile_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.child_profiles
    where id = target_child_profile_id
      and linked_user_id = auth.uid()
  );
$$;

alter table public.child_profiles enable row level security;
alter table public.child_invites enable row level security;

drop policy if exists "family members can read child profiles" on public.child_profiles;
create policy "family members can read child profiles"
on public.child_profiles for select
using (public.is_family_member(family_id));

drop policy if exists "parents can manage child profiles" on public.child_profiles;
create policy "parents can manage child profiles"
on public.child_profiles for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop policy if exists "parents can manage child invites" on public.child_invites;
create policy "parents can manage child invites"
on public.child_invites for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop policy if exists "children can create own submissions" on public.chore_submissions;
create policy "children can create own submissions"
on public.chore_submissions for insert
with check (public.is_linked_child_profile(child_id));
