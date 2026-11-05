# Bloom Finance: how it's deployed

- **Website and phone app:** GitHub Pages serves this repository's `main` branch at
  https://ridmaraveengamage-cmyk.github.io/bloom-finance. Any change pushed to `main` goes live in about 1–2 minutes.
- **Checks:** the "Checks" workflow runs on every push. It checks the app's code and runs the database security tests.
- **Database and sign-in:** Supabase project `lljjqsyivqstwcdxkicb`.
  - All migrations in `supabase/migrations/` are already applied.
  - Apply a new migration by pasting it into the Supabase SQL editor (Dashboard → SQL Editor) and pressing Run.
- **Google sign-in:**
  - The Google Cloud project is `bloom-finance-513013`, with OAuth client "Bloom Finance Web". It is published to production.
  - Supabase Authentication → URL Configuration: the Site URL is the GitHub Pages address above.
- **Netlify:** no longer used. Builds are stopped.
- **Costs:** GitHub, GitHub Pages, Supabase (free plan) and Google sign-in are all free. Nothing can charge you unless you upgrade a plan.
