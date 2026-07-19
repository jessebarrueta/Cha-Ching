\set ON_ERROR_STOP on

begin;

do $$
declare
  parent_user_id uuid;
  test_occurrence_id uuid;
  test_chore_id uuid;
  test_child_id uuid;
  test_submission_id uuid := gen_random_uuid();
  test_week_ends_at timestamptz;
  scheduled_at timestamptz;
  lifecycle_status text;
  lifecycle_reason text;
begin
  select
    family_members.user_id,
    task_occurrences.id,
    chore_definitions.id,
    task_occurrences.child_id,
    weeks.ends_at
  into
    parent_user_id,
    test_occurrence_id,
    test_chore_id,
    test_child_id,
    test_week_ends_at
  from public.family_members
  join public.chore_definitions
    on chore_definitions.family_id = family_members.family_id
  join public.task_occurrences
    on task_occurrences.chore_definition_id = chore_definitions.id
  join public.weeks
    on weeks.id = task_occurrences.week_id
  where family_members.role = 'parent'
    and task_occurrences.submission_id is null
  limit 1;

  if parent_user_id is null or test_occurrence_id is null then
    raise exception 'rollback_smoke_fixture_not_found';
  end if;

  perform set_config('request.jwt.claim.sub', parent_user_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);

  update public.family_evidence_policies
  set
    evidence_retention_mode = 'after_parent_review',
    delete_grace_minutes = 10,
    delete_after_period_close_days = 1
  where family_id = (
    select family_id
    from public.chore_definitions
    where id = test_chore_id
  );

  update public.chore_definitions
  set
    evidence_retention_mode = null,
    evidence_delete_grace_minutes = null
  where id = test_chore_id;

  insert into public.chore_submissions (
    id,
    task_occurrence_id,
    child_id,
    image_path
  )
  values (
    test_submission_id,
    test_occurrence_id,
    test_child_id,
    'rollback-smoke-test/evidence.jpg'
  );

  update public.task_occurrences
  set
    submission_id = test_submission_id,
    status = 'submitted'
  where id = test_occurrence_id;

  perform *
  from public.decide_chore_submission(test_occurrence_id, 'approved', 'Rollback smoke test');

  select evidence_status, evidence_delete_after, evidence_delete_reason
  into lifecycle_status, scheduled_at, lifecycle_reason
  from public.chore_submissions
  where id = test_submission_id;

  if lifecycle_status <> 'pending_delete'
     or lifecycle_reason <> 'parent_review_complete'
     or scheduled_at < now() + interval '9 minutes'
     or scheduled_at > now() + interval '11 minutes' then
    raise exception 'after_parent_review_schedule_failed';
  end if;

  update public.chore_definitions
  set
    evidence_retention_mode = 'after_period_close',
    evidence_delete_grace_minutes = 10
  where id = test_chore_id;

  perform *
  from public.decide_chore_submission(test_occurrence_id, 'approved', 'Rollback smoke test');

  select evidence_status, evidence_delete_after, evidence_delete_reason
  into lifecycle_status, scheduled_at, lifecycle_reason
  from public.chore_submissions
  where id = test_submission_id;

  if lifecycle_status <> 'pending_delete'
     or lifecycle_reason <> 'allowance_period_closed'
     or scheduled_at < greatest(
       test_week_ends_at + interval '1 day',
       now() + interval '10 minutes'
     ) then
    raise exception 'after_period_close_schedule_failed';
  end if;

  update public.chore_definitions
  set evidence_retention_mode = 'manual_only'
  where id = test_chore_id;

  perform *
  from public.decide_chore_submission(test_occurrence_id, 'approved', 'Rollback smoke test');

  select evidence_status, evidence_delete_after, evidence_delete_reason
  into lifecycle_status, scheduled_at, lifecycle_reason
  from public.chore_submissions
  where id = test_submission_id;

  if lifecycle_status <> 'available'
     or scheduled_at is not null
     or lifecycle_reason is not null then
    raise exception 'manual_retention_schedule_failed';
  end if;
end;
$$;

select 'evidence_deletion_schedule_smoke_test=ok' as result;

rollback;
