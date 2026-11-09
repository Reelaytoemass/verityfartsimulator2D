drop function if exists public.admin_list_scores();

create function public.admin_list_scores()
returns table(user_id uuid, username text, points numeric)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and split_part(coalesce(u.email, ''), '@', 1) = 'admin'
      and u.raw_app_meta_data ->> 'role' = 'admin'
  ) then
    raise exception using errcode = '42501', message = 'Admin access required';
  end if;

  return query
  select s.user_id,
         coalesce(nullif(split_part(u.email, '@', 1), ''), 'player'),
         case
           when s.data ->> 'coins' ~ '^[0-9]+$' then (s.data ->> 'coins')::numeric
           else 0::numeric
         end
  from public.saves s
  left join auth.users u on u.id = s.user_id
  order by 2;
end;
$$;

create or replace function public.admin_set_points(p_user_id uuid, p_points bigint)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and split_part(coalesce(u.email, ''), '@', 1) = 'admin'
      and u.raw_app_meta_data ->> 'role' = 'admin'
  ) then
    raise exception using errcode = '42501', message = 'Admin access required';
  end if;

  if p_user_id is null or p_points is null or p_points < 0 then
    raise exception using errcode = '22023', message = 'Invalid points value';
  end if;

  update public.saves s
  set data = jsonb_set(
        case when jsonb_typeof(s.data) = 'object' then s.data else '{}'::jsonb end,
        '{coins}',
        to_jsonb(p_points),
        true
      ),
      updated_at = now()
  where s.user_id = p_user_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Player save not found';
  end if;
end;
$$;

revoke all on function public.admin_list_scores() from public, anon;
revoke all on function public.admin_set_points(uuid, bigint) from public, anon;
grant execute on function public.admin_list_scores() to authenticated;
grant execute on function public.admin_set_points(uuid, bigint) to authenticated;

drop function if exists public.admin_set_launch_multiplier(uuid, numeric);
drop function if exists public.admin_set_launch_upgrades(uuid, integer, integer);

create table if not exists public.game_settings (
  id boolean primary key default true check (id),
  launch_speed_multiplier numeric not null default 1 check (launch_speed_multiplier between 0.1 and 10),
  gravity_multiplier numeric not null default 1 check (gravity_multiplier between 0.1 and 5),
  points_multiplier numeric not null default 1 check (points_multiplier between 0.1 and 10),
  updated_at timestamptz not null default now()
);

insert into public.game_settings (id) values (true) on conflict (id) do nothing;
alter table public.game_settings enable row level security;

create or replace function public.get_game_settings()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'launchSpeedMultiplier', launch_speed_multiplier,
    'gravityMultiplier', gravity_multiplier,
    'pointsMultiplier', points_multiplier
  )
  from public.game_settings
  where id
$$;

create or replace function public.admin_update_game_settings(
  p_launch_speed_multiplier numeric,
  p_gravity_multiplier numeric,
  p_points_multiplier numeric
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1
    from auth.users u
    where u.id = auth.uid()
      and split_part(coalesce(u.email, ''), '@', 1) = 'admin'
      and u.raw_app_meta_data ->> 'role' = 'admin'
  ) then
    raise exception using errcode = '42501', message = 'Admin access required';
  end if;

  if p_launch_speed_multiplier is null or p_launch_speed_multiplier not between 0.1 and 10
     or p_gravity_multiplier is null or p_gravity_multiplier not between 0.1 and 5
     or p_points_multiplier is null or p_points_multiplier not between 0.1 and 10 then
    raise exception using errcode = '22023', message = 'Game settings are outside allowed limits';
  end if;

  update public.game_settings
  set launch_speed_multiplier = p_launch_speed_multiplier,
      gravity_multiplier = p_gravity_multiplier,
      points_multiplier = p_points_multiplier,
      updated_at = now()
  where id;
end;
$$;

revoke all on function public.get_game_settings() from public, anon;
revoke all on function public.admin_update_game_settings(numeric, numeric, numeric) from public, anon;
grant execute on function public.get_game_settings() to authenticated;
grant execute on function public.admin_update_game_settings(numeric, numeric, numeric) to authenticated;
