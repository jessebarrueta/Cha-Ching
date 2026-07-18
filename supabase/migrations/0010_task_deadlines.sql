alter table public.families
  add column if not exists task_deadlines_enabled_at timestamptz;

update public.families
set task_deadlines_enabled_at = now()
where task_deadlines_enabled_at is null;

update public.task_occurrences occurrence
set
  status = 'excused',
  excuse_reason = 'Grandfathered when automatic task deadlines were enabled.',
  updated_at = now()
from public.chore_definitions chore, public.families family
where occurrence.chore_definition_id = chore.id
  and family.id = chore.family_id
  and occurrence.status in ('upcoming', 'due')
  and occurrence.expires_at <= family.task_deadlines_enabled_at;

alter table public.families
  alter column task_deadlines_enabled_at set default now(),
  alter column task_deadlines_enabled_at set not null;

create or replace function public.process_task_occurrence_deadlines(
  target_family_id uuid,
  target_child_profile_id uuid
)
returns table (
  marked_due_count integer,
  marked_missed_count integer,
  deduction_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  due_rows integer := 0;
  missed_rows integer := 0;
  deduction_rows integer := 0;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not public.is_family_member(target_family_id) then
    raise exception 'not_a_family_member' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.child_profiles
    where id = target_child_profile_id
      and family_id = target_family_id
  ) then
    raise exception 'child_profile_not_in_family' using errcode = '22023';
  end if;

  update public.task_occurrences occurrence
  set
    status = 'due',
    updated_at = now()
  from public.chore_definitions chore
  where occurrence.chore_definition_id = chore.id
    and chore.family_id = target_family_id
    and occurrence.child_id = target_child_profile_id
    and occurrence.status = 'upcoming'
    and occurrence.due_at <= now()
    and occurrence.expires_at > now();

  get diagnostics due_rows = row_count;

  with missed_occurrences as (
    update public.task_occurrences occurrence
    set
      status = 'missed',
      updated_at = now()
    from public.chore_definitions chore
    where occurrence.chore_definition_id = chore.id
      and chore.family_id = target_family_id
      and occurrence.child_id = target_child_profile_id
      and occurrence.status in ('upcoming', 'due')
      and occurrence.expires_at <= now()
    returning
      occurrence.id,
      occurrence.week_id,
      occurrence.child_id,
      chore.title,
      chore.deduction_cents
  ), inserted_deductions as (
    insert into public.ledger_entries (
      week_id,
      child_id,
      entry_type,
      title,
      amount_cents,
      related_occurrence_id,
      note
    )
    select
      missed_occurrences.week_id,
      missed_occurrences.child_id,
      'deduction',
      'Missed: ' || missed_occurrences.title,
      missed_occurrences.deduction_cents,
      missed_occurrences.id,
      'Automatically applied after the chore window closed.'
    from missed_occurrences
    on conflict do nothing
    returning id
  )
  select
    (select count(*) from missed_occurrences)::integer,
    (select count(*) from inserted_deductions)::integer
  into missed_rows, deduction_rows;

  update public.task_occurrences occurrence
  set deduction_ledger_entry_id = ledger.id
  from public.ledger_entries ledger, public.chore_definitions chore
  where occurrence.child_id = target_child_profile_id
    and chore.id = occurrence.chore_definition_id
    and chore.family_id = target_family_id
    and occurrence.status = 'missed'
    and ledger.related_occurrence_id = occurrence.id
    and ledger.entry_type = 'deduction'
    and ledger.is_voided = false
    and occurrence.deduction_ledger_entry_id is distinct from ledger.id;

  return query select due_rows, missed_rows, deduction_rows;
end;
$$;

revoke all on function public.process_task_occurrence_deadlines(uuid, uuid) from public, anon;
grant execute on function public.process_task_occurrence_deadlines(uuid, uuid) to authenticated;
