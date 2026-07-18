create table if not exists public.task_nudges (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  task_occurrence_id uuid not null references public.task_occurrences(id) on delete cascade,
  child_id uuid not null references public.child_profiles(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  message text not null,
  status text not null default 'pending',
  delivered_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz not null default now(),
  check (status in ('pending', 'delivered', 'dismissed')),
  check (length(trim(message)) between 1 and 280)
);

create index if not exists task_nudges_family_child_status_idx
  on public.task_nudges (family_id, child_id, status, created_at desc);

create index if not exists task_nudges_occurrence_idx
  on public.task_nudges (task_occurrence_id, created_at desc);

alter table public.task_nudges enable row level security;

drop policy if exists "family members can read nudges" on public.task_nudges;
create policy "family members can read nudges"
on public.task_nudges for select
using (public.is_family_member(family_id));

drop policy if exists "parents can create nudges" on public.task_nudges;
create policy "parents can create nudges"
on public.task_nudges for insert
with check (
  created_by = auth.uid()
  and public.is_family_parent(family_id)
);

drop policy if exists "parents and assigned children can update nudges" on public.task_nudges;
create policy "parents and assigned children can update nudges"
on public.task_nudges for update
using (
  public.is_family_parent(family_id)
  or exists (
    select 1
    from public.child_profiles
    where child_profiles.id = task_nudges.child_id
      and child_profiles.linked_user_id = auth.uid()
  )
)
with check (
  public.is_family_parent(family_id)
  or exists (
    select 1
    from public.child_profiles
    where child_profiles.id = task_nudges.child_id
      and child_profiles.linked_user_id = auth.uid()
  )
);
