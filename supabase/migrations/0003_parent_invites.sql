create table if not exists public.parent_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  parent_name text not null,
  phone_e164 text,
  created_by_parent_id uuid references auth.users(id) on delete set null,
  token_hash text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'expired', 'revoked')),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_parent_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists parent_invites_family_status_idx
  on public.parent_invites (family_id, status, created_at desc);

drop trigger if exists parent_invites_set_updated_at on public.parent_invites;
create trigger parent_invites_set_updated_at
before update on public.parent_invites
for each row execute function public.set_updated_at();

alter table public.parent_invites enable row level security;

drop policy if exists "parents can manage parent invites" on public.parent_invites;
create policy "parents can manage parent invites"
on public.parent_invites for all
using (public.is_family_parent(family_id))
with check (public.is_family_parent(family_id));
