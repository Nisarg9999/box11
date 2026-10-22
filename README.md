# Box 11 Trade Manager

```
index.html            the app (login + business app + Users & Access admin tab)
config.js             your Supabase URL + anon key  ← edit this
preview.html          offline demo with fake data (optional, can delete)
api/admin-users.js    Vercel function: create / edit / delete users (admin only)
package.json          dependency for the function
supabase/schema.sql   database setup
.env.example          the 2 secrets to add in Vercel
```

## 1. Supabase (free project at supabase.com)
1. **SQL Editor** → paste `supabase/schema.sql` → Run.
2. **Authentication → Providers → Email**: turn **off** "Allow new users to sign up" and **off** "Confirm email".
3. **Authentication → Users → Add user** → create YOUR admin login (email + password, tick auto-confirm). The first account created automatically becomes admin.
4. **Project Settings → API**: copy the Project URL, the `anon` key and the `service_role` key.

## 2. Edit `config.js`
Paste the Project URL and the **anon** key. (Never the service_role key.)

## 3. GitHub
Create a new repository, then upload everything in this folder (drag-and-drop on github.com → "Add file → Upload files", or `git push`). Make the repository **Private**.

## 4. Vercel
1. vercel.com → **Add New → Project** → import the GitHub repo. Framework preset: **Other**; leave build settings empty.
2. Before deploying, open **Environment Variables** and add `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (the secret key).
3. Deploy. Every later `git push` redeploys automatically.

## 5. Use it
Sign in with your admin email + password → **Users & Access** → **Create new user**. Staff sign in with just their username + password.

Notes: disabling a user blocks them at once; deleting is permanent. You cannot change/delete your own account from the screen. Back up regularly with Backup / Restore.
