drop function if exists public.admin_list_scores();

create function public.admin_list_scores()
returns table(user_id uuid, username text, points numeric, launch_multiplier numeric, force_level integer, tank_level integer)
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
         end,
         case
           when s.data ->> 'launchMultiplier' ~ '^[0-9]+([.][0-9]+)?$'
             then least(10::numeric, greatest(0.1::numeric, (s.data ->> 'launchMultiplier')::numeric))
           else 1::numeric
         end,
         case
           when s.data #>> '{upgrades,force}' ~ '^[0-9]+$'
             then least(30, (s.data #>> '{upgrades,force}')::integer)
           else 0
         end,
         case
           when s.data #>> '{upgrades,tank}' ~ '^[0-9]+$'
             then least(20, (s.data #>> '{upgrades,tank}')::integer)
           else 0
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

create or replace function public.admin_set_launch_multiplier(p_user_id uuid, p_multiplier numeric)
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

  if p_user_id is null or p_multiplier is null or p_multiplier < 0.1 or p_multiplier > 10 then
    raise exception using errcode = '22023', message = 'Launch multiplier must be between 0.1 and 10';
  end if;

  update public.saves s
  set data = jsonb_set(
        case when jsonb_typeof(s.data) = 'object' then s.data else '{}'::jsonb end,
        '{launchMultiplier}', to_jsonb(p_multiplier), true
      ),
      updated_at = now()
  where s.user_id = p_user_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Player save not found';
  end if;
end;
$$;

create or replace function public.admin_set_launch_upgrades(p_user_id uuid, p_force_level integer, p_tank_level integer)
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

  if p_user_id is null or p_force_level is null or p_force_level < 0 or p_force_level > 30
     or p_tank_level is null or p_tank_level < 0 or p_tank_level > 20 then
    raise exception using errcode = '22023', message = 'Invalid launch upgrade level';
  end if;

  update public.saves s
  set data = jsonb_set(
        jsonb_set(
          case
            when jsonb_typeof(s.data -> 'upgrades') = 'object' then s.data
            else jsonb_set(case when jsonb_typeof(s.data) = 'object' then s.data else '{}'::jsonb end, '{upgrades}', '{}'::jsonb, true)
          end,
          '{upgrades,force}', to_jsonb(p_force_level), true
        ),
        '{upgrades,tank}', to_jsonb(p_tank_level), true
      ),
      updated_at = now()
  where s.user_id = p_user_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Player save not found';
  end if;
end;
$$;

revoke all on function public.admin_set_launch_multiplier(uuid, numeric) from public, anon;
revoke all on function public.admin_set_launch_upgrades(uuid, integer, integer) from public, anon;
grant execute on function public.admin_set_launch_multiplier(uuid, numeric) to authenticated;
grant execute on function public.admin_set_launch_upgrades(uuid, integer, integer) to authenticated;
