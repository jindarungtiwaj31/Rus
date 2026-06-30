# Supabase Setup

1. Create a Supabase project.
2. Open SQL Editor.
3. Copy all SQL from `schema.sql` and Run.
4. Open `supabase-config.js`.
5. Fill in your Supabase Project URL and public anon value from Project Settings > API.
6. Commit the file to GitHub.
7. Open the GitHub Pages URL.

Admin login in the web app uses username `admin` and password `9999`.

Users log in with a 4 digit code created by Admin.

The SQL function `issue_receipt` updates `app_state` with row locking, so receipt numbers are issued from the database and are less likely to duplicate when many users work at the same time.
