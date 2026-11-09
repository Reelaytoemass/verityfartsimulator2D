create or replace function public.admin_list_scores()
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
