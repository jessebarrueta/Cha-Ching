create or replace function public.decide_chore_submission(
  target_occurrence_id uuid,
  target_decision text,
  target_note text default null
)
returns table (
  occurrence_id uuid,
  submission_id uuid,
  ledger_entry_id uuid,
  decision text,
  status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  normalized_decision text := lower(target_decision);
  decided_at_value timestamptz := now();
  occurrence_record public.task_occurrences%rowtype;
  chore_record public.chore_definitions%rowtype;
  active_deduction_id uuid;
  updated_status text;
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if normalized_decision is null or normalized_decision not in ('approved', 'rejected', 'excused', 'retake_requested') then
    raise exception 'invalid_decision' using errcode = '22023';
  end if;

  select task_occurrences.*
  into occurrence_record
  from public.task_occurrences
  where task_occurrences.id = target_occurrence_id
  for update;

  if occurrence_record.id is null then
    raise exception 'occurrence_not_found' using errcode = 'P0002';
  end if;

  select chore_definitions.*
  into chore_record
  from public.chore_definitions
  where chore_definitions.id = occurrence_record.chore_definition_id;

  if chore_record.id is null then
    raise exception 'chore_not_found' using errcode = 'P0002';
  end if;

  if not public.is_family_parent(chore_record.family_id) then
    raise exception 'not_family_parent' using errcode = '42501';
  end if;

  if normalized_decision in ('approved', 'excused') then
    update public.ledger_entries
    set is_voided = true
    where related_occurrence_id = occurrence_record.id
      and entry_type = 'deduction'
      and is_voided = false;
  elsif normalized_decision = 'rejected' then
    select id
    into active_deduction_id
    from public.ledger_entries
    where related_occurrence_id = occurrence_record.id
      and entry_type = 'deduction'
      and is_voided = false
    limit 1;

    if active_deduction_id is null then
      insert into public.ledger_entries (
        week_id,
        child_id,
        created_by,
        entry_type,
        title,
        amount_cents,
        related_occurrence_id
      )
      values (
        occurrence_record.week_id,
        occurrence_record.child_id,
        current_user_id,
        'deduction',
        'Missed: ' || chore_record.title,
        chore_record.deduction_cents,
        occurrence_record.id
      )
      returning id into active_deduction_id;
    end if;
  end if;

  updated_status := case normalized_decision
    when 'approved' then 'approved'
    when 'rejected' then 'rejected'
    when 'excused' then 'excused'
    when 'retake_requested' then 'due'
  end;

  update public.task_occurrences
  set
    status = updated_status,
    deduction_ledger_entry_id = case
      when normalized_decision = 'rejected' then active_deduction_id
      else deduction_ledger_entry_id
    end,
    excuse_reason = case
      when normalized_decision = 'excused' then target_note
      else excuse_reason
    end
  where id = occurrence_record.id;

  if occurrence_record.submission_id is not null then
    update public.chore_submissions
    set parent_decision = jsonb_build_object(
      'decision', normalized_decision,
      'note', target_note,
      'decided_at', to_char(decided_at_value at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'parent_id', current_user_id
    )
    where id = occurrence_record.submission_id;
  end if;

  occurrence_id := occurrence_record.id;
  submission_id := occurrence_record.submission_id;
  ledger_entry_id := active_deduction_id;
  decision := normalized_decision;
  status := updated_status;
  return next;
end;
$$;

revoke all on function public.decide_chore_submission(uuid, text, text) from public, anon;
grant execute on function public.decide_chore_submission(uuid, text, text) to authenticated;
