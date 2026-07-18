create unique index if not exists ledger_entries_one_weekly_base_per_week
  on public.ledger_entries (week_id)
  where entry_type = 'weekly_base' and is_voided = false;

create or replace function public.ensure_current_task_occurrences(
  target_family_id uuid,
  target_child_profile_id uuid
)
returns table (
  active_week_id uuid,
  inserted_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  family_timezone text;
  family_cadence text;
  family_base_allowance integer;
  period_days integer;
  local_today date;
  period_start_at timestamptz;
  period_end_at timestamptz;
  latest_period_end timestamptz;
  previous_week_id uuid;
  previous_raw_total integer := 0;
  period_base_allowance integer;
  current_week_id uuid;
  recurrence_type text;
  due_time_value time;
  due_at_value timestamptz;
  should_create boolean;
  weekday_value integer;
  rows_added integer := 0;
  affected_rows integer;
  chore_record public.chore_definitions%rowtype;
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

  select
    families.timezone,
    families.allowance_cadence,
    families.weekly_base_allowance_cents
  into
    family_timezone,
    family_cadence,
    family_base_allowance
  from public.families
  where families.id = target_family_id;

  family_timezone := coalesce(nullif(family_timezone, ''), 'UTC');
  period_days := case when family_cadence = 'every_two_weeks' then 14 else 7 end;
  local_today := (now() at time zone family_timezone)::date;

  select weeks.id
  into current_week_id
  from public.weeks
  where weeks.family_id = target_family_id
    and weeks.child_id = target_child_profile_id
    and weeks.starts_at <= now()
    and weeks.ends_at > now()
  order by weeks.starts_at desc
  limit 1;

  if current_week_id is null then
    select weeks.id, weeks.ends_at
    into previous_week_id, latest_period_end
    from public.weeks
    where weeks.family_id = target_family_id
      and weeks.child_id = target_child_profile_id
    order by weeks.ends_at desc
    limit 1;

    if latest_period_end is null then
      period_start_at := local_today::timestamp at time zone family_timezone;
    else
      period_start_at := latest_period_end;
      while period_start_at + make_interval(days => period_days) <= now() loop
        period_start_at := period_start_at + make_interval(days => period_days);
      end loop;
    end if;

    period_end_at := period_start_at + make_interval(days => period_days);

    if previous_week_id is not null then
      select coalesce(sum(
        case ledger_entries.entry_type
          when 'deduction' then -ledger_entries.amount_cents
          else ledger_entries.amount_cents
        end
      ), 0)::integer
      into previous_raw_total
      from public.ledger_entries
      where ledger_entries.week_id = previous_week_id
        and ledger_entries.child_id = target_child_profile_id
        and ledger_entries.is_voided = false;

      update public.weeks
      set
        archived_at = coalesce(archived_at, now()),
        final_balance_cents = greatest(0, previous_raw_total)
      where id = previous_week_id;
    end if;

    period_base_allowance := greatest(0, family_base_allowance - greatest(0, -previous_raw_total));

    insert into public.weeks (
      family_id,
      child_id,
      starts_at,
      ends_at,
      base_allowance_cents
    )
    values (
      target_family_id,
      target_child_profile_id,
      period_start_at,
      period_end_at,
      period_base_allowance
    )
    on conflict (family_id, child_id, starts_at)
    do update set ends_at = excluded.ends_at
    returning id into current_week_id;

    insert into public.ledger_entries (
      week_id,
      child_id,
      entry_type,
      title,
      amount_cents
    )
    select
      current_week_id,
      target_child_profile_id,
      'weekly_base',
      'Starting allowance',
      period_base_allowance
    where not exists (
      select 1
      from public.ledger_entries
      where ledger_entries.week_id = current_week_id
        and ledger_entries.child_id = target_child_profile_id
        and ledger_entries.entry_type = 'weekly_base'
        and ledger_entries.is_voided = false
    )
    on conflict do nothing;
  end if;

  weekday_value := extract(dow from local_today)::integer + 1;

  for chore_record in
    select chore_definitions.*
    from public.chore_definitions
    where chore_definitions.family_id = target_family_id
      and chore_definitions.child_id = target_child_profile_id
      and chore_definitions.is_paused = false
  loop
    recurrence_type := coalesce(chore_record.recurrence ->> 'type', 'daily');
    should_create := case recurrence_type
      when 'daily' then true
      when 'weekly' then coalesce(
        (chore_record.recurrence -> 'weekdays') @> jsonb_build_array(weekday_value),
        false
      )
      when 'once' then coalesce(
        ((chore_record.recurrence ->> 'due_at')::timestamptz at time zone family_timezone)::date = local_today,
        false
      )
      else false
    end;

    if not should_create then
      continue;
    end if;

    begin
      due_time_value := (chore_record.recurrence -> 'times' ->> 0)::time;
    exception when others then
      continue;
    end;

    due_at_value := (local_today + due_time_value) at time zone family_timezone;

    insert into public.task_occurrences (
      chore_definition_id,
      child_id,
      week_id,
      scheduled_at,
      due_at,
      expires_at,
      status
    )
    select
      chore_record.id,
      target_child_profile_id,
      current_week_id,
      due_at_value,
      due_at_value,
      due_at_value + make_interval(mins => chore_record.due_window_minutes),
      case when due_at_value <= now() then 'due' else 'upcoming' end
    where not exists (
      select 1
      from public.task_occurrences existing_occurrence
      where existing_occurrence.chore_definition_id = chore_record.id
        and existing_occurrence.child_id = target_child_profile_id
        and (existing_occurrence.scheduled_at at time zone family_timezone)::date = local_today
    )
    on conflict (chore_definition_id, child_id, scheduled_at) do nothing;

    get diagnostics affected_rows = row_count;
    rows_added := rows_added + affected_rows;
  end loop;

  return query select current_week_id, rows_added;
end;
$$;

revoke all on function public.ensure_current_task_occurrences(uuid, uuid) from public, anon;
grant execute on function public.ensure_current_task_occurrences(uuid, uuid) to authenticated;
