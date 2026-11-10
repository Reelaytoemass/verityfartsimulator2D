# verityfartsimulator2D

## Admin score panel

The admin panel edits player points and shared game settings for launch speed,
gravity, and points earned. In the Supabase SQL Editor, run `admin.sql` again to
install the global game settings controls.

In the upgrade shop, max every upgrade in the current set, then pay the displayed
point cost to unlock five more levels per upgrade. Each set also increases the
strength of purchased upgrades.
Create the `admin` game account, verify that it is the account you control, then
grant its protected app metadata role in the SQL Editor:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
where email = 'admin@verity-players.com';
```

The admin panel appears after that account signs in again. The database functions
also check this role on every request; a username check in the browser is not
used as authorization.