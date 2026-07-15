alter table public.families
  add column if not exists allowance_cadence text not null default 'weekly',
  add column if not exists allowance_weekday integer not null default 6,
  add column if not exists next_allowance_at timestamptz not null default (
    date_trunc('day', now()) + (((5 - extract(dow from now())::integer + 7) % 7) * interval '1 day')
  );

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'families_allowance_cadence_check'
  ) then
    alter table public.families
      add constraint families_allowance_cadence_check
      check (allowance_cadence in ('weekly', 'every_two_weeks'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'families_allowance_weekday_check'
  ) then
    alter table public.families
      add constraint families_allowance_weekday_check
      check (allowance_weekday between 1 and 7);
  end if;
end;
$$;
