insert into public.families (id, name, weekly_base_allowance_cents)
values ('87d72069-308b-44cb-bbbe-0c27f5665b5b', 'Preview Family', 1500)
on conflict (id) do nothing;

