insert into public.families (id, name, weekly_base_allowance_cents)
values ('87d72069-308b-44cb-bbbe-0c27f5665b5b', 'Preview Family', 1500)
on conflict (id) do nothing;

insert into public.child_profiles (id, family_id, display_name)
values (
  'a14615dd-424e-44fb-b2e6-c61da3ce680c',
  '87d72069-308b-44cb-bbbe-0c27f5665b5b',
  'Zoe'
)
on conflict (id) do nothing;
