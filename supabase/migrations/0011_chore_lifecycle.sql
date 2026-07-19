alter table public.chore_definitions
  add column if not exists archived_at timestamptz;

create index if not exists chore_definitions_active_family_child_idx
  on public.chore_definitions (family_id, child_id, title)
  where archived_at is null;

create or replace function public.set_chore_lifecycle(
  target_chore_id uuid,
  target_is_paused boolean,
  target_archive boolean default false
)
returns table (
  chore_id uuid,
  is_paused boolean,
  archived_at timestamptz,
  excused_occurrence_count integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  chore_record public.chore_definitions%rowtype;
  excused_rows integer := 0;
  lifecycle_reason text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select chore_definitions.*
  into chore_record
  from public.chore_definitions
  where chore_definitions.id = target_chore_id
  for update;

  if chore_record.id is null then
    raise exception 'chore_not_found' using errcode = 'P0002';
  end if;

  if not public.is_family_parent(chore_record.family_id) then
    raise exception 'not_family_parent' using errcode = '42501';
  end if;

  if chore_record.archived_at is not null and not target_archive then
    raise exception 'chore_archived' using errcode = '22023';
  end if;

  update public.chore_definitions
  set
    is_paused = target_is_paused or target_archive,
    archived_at = case
      when target_archive then coalesce(chore_record.archived_at, now())
      else chore_record.archived_at
    end,
    updated_at = now()
  where id = target_chore_id;

  if target_is_paused or target_archive then
    lifecycle_reason := case
      when target_archive then 'Archived by parent.'
      else 'Paused by parent.'
    end;

    update public.task_occurrences
    set
      status = 'excused',
      excuse_reason = lifecycle_reason,
      updated_at = now()
    where chore_definition_id = target_chore_id
      and status in ('upcoming', 'due');

    get diagnostics excused_rows = row_count;
  end if;

  return query
  select
    updated.id,
    updated.is_paused,
    updated.archived_at,
    excused_rows
  from public.chore_definitions updated
  where updated.id = target_chore_id;
end;
$$;

revoke all on function public.set_chore_lifecycle(uuid, boolean, boolean) from public, anon;
grant execute on function public.set_chore_lifecycle(uuid, boolean, boolean) to authenticated;
