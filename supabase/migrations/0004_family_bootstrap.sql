create or replace function public.insert_preview_chore(
  target_family_id uuid,
  target_child_profile_id uuid,
  target_week_id uuid,
  chore_title text,
  chore_short_title text,
  chore_description text,
  chore_instructions text,
  chore_expected_evidence text,
  chore_deduction_cents integer,
  due_time_label text,
  due_time_value time
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  created_chore_id uuid;
  due_at_value timestamptz := (current_date + due_time_value)::timestamptz;
  expires_at_value timestamptz := (current_date + due_time_value)::timestamptz + interval '90 minutes';
  status_value text := case
    when (current_date + due_time_value)::timestamptz <= now() then 'due'
    else 'upcoming'
  end;
begin
  insert into public.chore_definitions (
    family_id,
    child_id,
    title,
    short_title,
    description,
    instructions,
    expected_evidence,
    deduction_cents,
    verification_mode,
    recurrence,
    due_window_minutes,
    reminder_offsets_minutes
  )
  values (
    target_family_id,
    target_child_profile_id,
    chore_title,
    chore_short_title,
    chore_description,
    chore_instructions,
    chore_expected_evidence,
    chore_deduction_cents,
    'photo_required',
    jsonb_build_object('type', 'daily', 'times', jsonb_build_array(due_time_label)),
    90,
    array[15, 0]
  )
  returning id into created_chore_id;

  insert into public.task_occurrences (
    chore_definition_id,
    child_id,
    week_id,
    scheduled_at,
    due_at,
    expires_at,
    status
  )
  values (
    created_chore_id,
    target_child_profile_id,
    target_week_id,
    due_at_value,
    due_at_value,
    expires_at_value,
    status_value
  );
end;
$$;

revoke all on function public.insert_preview_chore(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  integer,
  text,
  time
) from public, anon, authenticated;

create or replace function public.bootstrap_preview_family(
  parent_display_name text default 'Daddy',
  child_display_name text default 'Zoe',
  family_display_name text default null
)
returns table (
  family_id uuid,
  child_profile_id uuid,
  week_id uuid
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  base_allowance integer := 1500;
  week_start timestamptz := date_trunc('week', now());
  week_end timestamptz := date_trunc('week', now()) + interval '7 days';
begin
  if current_user_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select fm.family_id, cp.id, w.id
  into family_id, child_profile_id, week_id
  from public.family_members fm
  left join public.child_profiles cp on cp.family_id = fm.family_id
  left join public.weeks w on w.family_id = fm.family_id and w.child_id = cp.id
  where fm.user_id = current_user_id
    and fm.role = 'parent'
  order by fm.created_at desc, w.starts_at desc
  limit 1;

  if family_id is not null then
    return next;
    return;
  end if;

  insert into public.families (name, weekly_base_allowance_cents)
  values (
    coalesce(nullif(family_display_name, ''), child_display_name || '''s Family'),
    base_allowance
  )
  returning id into family_id;

  insert into public.family_members (family_id, user_id, role, display_name)
  values (
    family_id,
    current_user_id,
    'parent',
    coalesce(nullif(parent_display_name, ''), 'Parent')
  );

  insert into public.child_profiles (
    family_id,
    display_name,
    created_by_parent_id
  )
  values (
    family_id,
    coalesce(nullif(child_display_name, ''), 'Child'),
    current_user_id
  )
  returning id into child_profile_id;

  insert into public.weeks (
    family_id,
    child_id,
    starts_at,
    ends_at,
    base_allowance_cents
  )
  values (
    family_id,
    child_profile_id,
    week_start,
    week_end,
    base_allowance
  )
  returning id into week_id;

  insert into public.ledger_entries (
    week_id,
    child_id,
    created_by,
    entry_type,
    title,
    amount_cents
  )
  values (
    week_id,
    child_profile_id,
    current_user_id,
    'weekly_base',
    'Starting allowance',
    base_allowance
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Feed Dog (AM)',
    'Feed dog',
    'One full bowl of food in the morning.',
    'Give the dog one full bowl of food. Make sure the bowl is full and the area is clean.',
    'A full dog bowl and the surrounding floor area.',
    100,
    '7:30 AM',
    time '07:30'
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Feed Dog (Evening)',
    'Feed dog',
    'One full bowl of food in the evening.',
    'Give the dog one full bowl of food. Show the full bowl and a clean area around it.',
    'A full dog bowl and nearby floor.',
    100,
    '6:00 PM',
    time '18:00'
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Take Dog Out (AM)',
    'Dog outing',
    'Morning dog outing.',
    'Take the dog outside and make sure the door is secure when you come back.',
    'Dog leash or door area after the outing.',
    50,
    '8:00 AM',
    time '08:00'
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Take Dog Out (PM)',
    'Dog outing',
    'Evening dog outing.',
    'Take the dog outside before the evening gets late.',
    'Dog leash or door area after the outing.',
    50,
    '8:00 PM',
    time '20:00'
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Keep Bedroom Floor Clean',
    'Bedroom floor',
    'Daily bedroom floor check.',
    'Pick up trash, clothes, and anything that blocks the floor.',
    'A clear bedroom floor.',
    100,
    '8:30 PM',
    time '20:30'
  );

  perform public.insert_preview_chore(
    family_id,
    child_profile_id,
    week_id,
    'Keep Bathroom Neat',
    'Bathroom neat',
    'Daily bathroom check.',
    'Clear the sink, hang towels, and make sure the counter is tidy.',
    'A tidy bathroom sink and counter.',
    100,
    '8:30 PM',
    time '20:30'
  );

  return next;
end;
$$;

revoke all on function public.bootstrap_preview_family(text, text, text) from public, anon;
grant execute on function public.bootstrap_preview_family(text, text, text) to authenticated;
