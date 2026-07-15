create table if not exists public.family_evidence_policies (
  family_id uuid primary key references public.families(id) on delete cascade,
  photo_evidence_enabled boolean not null default true,
  default_verification_mode text not null default 'photo_optional',
  block_people_in_photos boolean not null default true,
  evidence_retention_mode text not null default 'after_parent_review',
  delete_grace_minutes integer not null default 10,
  delete_after_period_close_days integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (default_verification_mode in ('photo_required', 'photo_optional', 'parent_only', 'no_verification')),
  check (evidence_retention_mode in ('after_parent_review', 'after_period_close', 'manual_only')),
  check (delete_grace_minutes between 0 and 1440),
  check (delete_after_period_close_days between 0 and 30)
);

insert into public.family_evidence_policies (family_id)
select families.id
from public.families
on conflict (family_id) do nothing;

alter table public.family_evidence_policies enable row level security;

drop policy if exists "family members can read evidence policies" on public.family_evidence_policies;
create policy "family members can read evidence policies"
on public.family_evidence_policies for select
using (public.is_family_member(family_id));

drop policy if exists "parents can manage evidence policies" on public.family_evidence_policies;
create policy "parents can manage evidence policies"
on public.family_evidence_policies for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));

drop trigger if exists family_evidence_policies_set_updated_at on public.family_evidence_policies;
create trigger family_evidence_policies_set_updated_at
before update on public.family_evidence_policies
for each row execute function public.set_updated_at();

alter table public.chore_definitions
  add column if not exists block_people_in_photos boolean,
  add column if not exists evidence_retention_mode text,
  add column if not exists evidence_delete_grace_minutes integer;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chore_definitions_evidence_retention_mode_check'
  ) then
    alter table public.chore_definitions
      add constraint chore_definitions_evidence_retention_mode_check
      check (
        evidence_retention_mode is null
        or evidence_retention_mode in ('after_parent_review', 'after_period_close', 'manual_only')
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'chore_definitions_evidence_delete_grace_minutes_check'
  ) then
    alter table public.chore_definitions
      add constraint chore_definitions_evidence_delete_grace_minutes_check
      check (
        evidence_delete_grace_minutes is null
        or evidence_delete_grace_minutes between 0 and 1440
      );
  end if;
end;
$$;

alter table public.chore_submissions
  alter column image_path drop not null;

create or replace function public.submit_chore_without_photo(target_occurrence_id uuid)
returns table (
  submission_id uuid,
  task_occurrence_id uuid,
  status text,
  submitted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  occurrence_record public.task_occurrences%rowtype;
  chore_record public.chore_definitions%rowtype;
  policy_record public.family_evidence_policies%rowtype;
  submission_record public.chore_submissions%rowtype;
begin
  select *
  into occurrence_record
  from public.task_occurrences
  where id = target_occurrence_id
  for update;

  if not found then
    raise exception 'Task occurrence not found';
  end if;

  if occurrence_record.child_id <> auth.uid() then
    raise exception 'Only the assigned child can submit this task';
  end if;

  select *
  into chore_record
  from public.chore_definitions
  where id = occurrence_record.chore_definition_id;

  select *
  into policy_record
  from public.family_evidence_policies
  where family_id = chore_record.family_id;

  if coalesce(policy_record.photo_evidence_enabled, true)
     and chore_record.verification_mode = 'photo_required' then
    raise exception 'This task requires photo evidence';
  end if;

  if occurrence_record.submission_id is not null then
    select *
    into submission_record
    from public.chore_submissions
    where id = occurrence_record.submission_id;

    submission_id := submission_record.id;
    task_occurrence_id := occurrence_record.id;
    status := occurrence_record.status;
    submitted_at := submission_record.submitted_at;
    return next;
    return;
  end if;

  insert into public.chore_submissions (
    task_occurrence_id,
    child_id,
    image_path
  )
  values (
    occurrence_record.id,
    occurrence_record.child_id,
    null
  )
  returning *
  into submission_record;

  update public.task_occurrences
  set
    submission_id = submission_record.id,
    status = 'submitted',
    updated_at = now()
  where id = occurrence_record.id
  returning *
  into occurrence_record;

  submission_id := submission_record.id;
  task_occurrence_id := occurrence_record.id;
  status := occurrence_record.status;
  submitted_at := submission_record.submitted_at;
  return next;
end;
$$;

revoke all on function public.submit_chore_without_photo(uuid) from public;
grant execute on function public.submit_chore_without_photo(uuid) to authenticated;
