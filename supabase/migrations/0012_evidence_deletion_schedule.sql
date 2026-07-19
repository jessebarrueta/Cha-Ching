alter table public.chore_submissions
  add column if not exists evidence_status text not null default 'available',
  add column if not exists evidence_delete_after timestamptz,
  add column if not exists evidence_deleted_at timestamptz,
  add column if not exists evidence_delete_reason text,
  add column if not exists people_block_result jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chore_submissions_evidence_status_check'
  ) then
    alter table public.chore_submissions
      add constraint chore_submissions_evidence_status_check
      check (evidence_status in ('available', 'pending_delete', 'deleted', 'blocked_before_upload'));
  end if;
end;
$$;

create index if not exists chore_submissions_pending_evidence_delete_idx
  on public.chore_submissions (evidence_delete_after)
  where evidence_status = 'pending_delete' and evidence_delete_after is not null;

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
  week_record public.weeks%rowtype;
  policy_record public.family_evidence_policies%rowtype;
  active_deduction_id uuid;
  updated_status text;
  effective_retention_mode text;
  effective_grace_minutes integer;
  period_close_days integer;
  scheduled_delete_after timestamptz;
  scheduled_delete_reason text;
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

  select weeks.*
  into week_record
  from public.weeks
  where weeks.id = occurrence_record.week_id;

  select family_evidence_policies.*
  into policy_record
  from public.family_evidence_policies
  where family_evidence_policies.family_id = chore_record.family_id;

  effective_retention_mode := coalesce(
    chore_record.evidence_retention_mode,
    policy_record.evidence_retention_mode,
    'after_parent_review'
  );
  effective_grace_minutes := greatest(
    0,
    coalesce(
      chore_record.evidence_delete_grace_minutes,
      policy_record.delete_grace_minutes,
      10
    )
  );
  period_close_days := greatest(0, coalesce(policy_record.delete_after_period_close_days, 1));

  if effective_retention_mode = 'after_parent_review' then
    scheduled_delete_after := decided_at_value + make_interval(mins => effective_grace_minutes);
    scheduled_delete_reason := 'parent_review_complete';
  elsif effective_retention_mode = 'after_period_close' then
    scheduled_delete_after := greatest(
      week_record.ends_at + make_interval(days => period_close_days),
      decided_at_value + make_interval(mins => effective_grace_minutes)
    );
    scheduled_delete_reason := 'allowance_period_closed';
  else
    scheduled_delete_after := null;
    scheduled_delete_reason := null;
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
    set
      parent_decision = jsonb_build_object(
        'decision', normalized_decision,
        'note', target_note,
        'decided_at', to_char(decided_at_value at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
        'parent_id', current_user_id
      ),
      evidence_status = case
        when image_path is null or evidence_status = 'deleted' then evidence_status
        when scheduled_delete_after is null then 'available'
        else 'pending_delete'
      end,
      evidence_delete_after = case
        when image_path is null or evidence_status = 'deleted' then evidence_delete_after
        else scheduled_delete_after
      end,
      evidence_delete_reason = case
        when image_path is null or evidence_status = 'deleted' then evidence_delete_reason
        else scheduled_delete_reason
      end
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
