# Bloom Finance: project brief for Claude Code

The owner, Ridma, is a beginner in software development.
- Lead the technical work, make reasonable reversible decisions yourself, and explain important ones in plain language.
- Ask only when a decision or permission truly blocks progress.

## What this is

Bloom Finance is a personal finance web app.

- **The app:** one self-contained file, `index.html` (HTML, CSS and plain JavaScript, no build step).
- **Hosting:** Netlify publishes the repository root from the `main` branch. The site is https://bloom-finance-test.netlify.app.
- **Sign-in and database:** Supabase, project ref `lljjqsyivqstwcdxkicb`. The app reads `supabase-config.js`, which holds only the public URL and publishable key.
- **Database schema:** `supabase/migrations/`. Security tests are in `supabase/tests/`.
- **Automation (GitHub Actions):**
  - `validate.yml`: app checks plus database tests on every push.
  - `supabase.yml`: applies migrations and sign-in settings.
  - `pages.yml`: manual backup only.
- **Setup guide for the owner:** `DEPLOY.md`.

## Non-negotiable rules

1. **Secrets:**
   - Never commit, print or log secrets: Supabase access token, database password, service-role key, Google client secret.
   - Secrets live only in GitHub Actions secrets or provider dashboards.
   - Never ask the owner to paste a secret into chat.
2. **Money:**
   - Money is stored as integer minor units (cents), never floats.
   - All balances are derived from opening amounts plus transactions. Never store a running balance.
3. **Financial rules.** Keep them exactly; tests depend on them.

   | Transaction | Effect |
   |---|---|
   | Expense from bank or cash | Reduces that account |
   | Credit-card purchase | Increases card debt only. It is *not* in "Total expenses" or cash flow, but it *is* in spending-by-category, budgets and emergency cover |
   | Card repayment | Bank down, card debt down. Not an expense |
   | Loan payment | Principal reduces the loan. Only the interest is an expense |
   | Transfer between my own accounts, cash withdrawal, cash deposit | Never income or expense |
   | Transfer to family or external parties | An expense, category "Transfers" |
   | Transfer from family or external parties | Income, source "Transfers" |
   | Savings goals | Earmarks only. They never move money or change balances or net worth |

   Two identities that must always hold:
   - Cash flow balance = income − expenses − card repayments − loan principal = the change in cash and bank balances over the period.
   - Net worth = (cash and bank + other assets) − (card debt + loans).
4. **Privacy and security:**
   - Row Level Security must stay on for every table holding personal data.
   - People see others' data only through a group they are both active in, at the level the data owner chose: none, overview, selected or full. Shared data is read-only.
   - Tagging a transaction to a group shares that one transaction only.
   - Store only the last 4 digits of cards.
5. **Never fake success.**
   - Don't claim something works without running it.
   - The sign-in screens must never pretend to sign someone in when Supabase is unreachable.
6. **No browser pop-ups.** Don't use `confirm()` or `alert()`; use the in-app `ask()` and `tell()` dialogs.
7. **Keep changes small and tested:**
   - Work on a branch, run the checks, and open a pull request with a plain-language summary.
   - Don't rewrite the whole app without a demonstrated reason.

## How to check your work

Run the database tests locally with Docker or a local PostgreSQL 16:
```
createdb bloomtest
psql -v ON_ERROR_STOP=1 -d bloomtest -f supabase/tests/local_auth_stub.sql
for f in $(ls supabase/migrations/*.sql | sort); do psql -v ON_ERROR_STOP=1 -d bloomtest -f "$f"; done
for t in security_and_ledger_test group_access_and_goals_test transaction_group_tags_test profile_signup_test; do
  psql -d bloomtest -f supabase/tests/$t.sql | grep -q "ALL TESTS PASSED" || echo "FAILED: $t"; done
```
- **Never** run `local_auth_stub.sql` or the test files against the real Supabase project.
- To check the app, extract the inline `<script>` from `index.html` and run `node --check` on it, as `validate.yml` does.
- For any logic change, add tests. A small Node test harness that stubs the page (`document`, `localStorage`, dialogs) and calls the app's functions works well.

## Current state (v0.13)

**Built and tested:**
- Accounts, cards, assets and liabilities, and transactions (all types above).
- Categories and custom categories, budgets, goals, analysis and text reports.
- Groups with access modes, settle-up and group tags.
- Documents: details only on the own site; statement reading worked only inside the Claude preview.
- Email and Google sign-in and sign-up, with username, mobile and country. Apple sign-in was dropped by the owner because it costs US$99 a year. Don't add it back unless asked.
- Backup and restore.
- Logo "rising petals" (option C).

**Not done yet, in priority order:**
1. **Owner confirms deployment:**
   - Help the owner finish `DEPLOY.md`.
   - Check the **Checks** and **Supabase setup** workflow runs.
   - Fix anything that fails.
2. **Cloud sync:**
   - Today, data lives in each browser (`localStorage`, per account).
   - Move it to the Supabase tables in `supabase/migrations` (accounts, cards, assets, liabilities, transactions, budgets, custom categories, goals, groups and so on).
   - Keep offline use working. Migrate existing browser data on first sign-in, after the user confirms.
3. **Real groups:**
   - Invitations by email (Supabase Edge Function plus an email provider), accept or decline in the app, and sharing levels backed by the database.
4. **Documents on the own site:**
   - Use Supabase Storage with a private bucket and owner-only policies.
   - Reading statements needs an AI API called from a Supabase Edge Function. The API key must stay server-side, and the owner must agree to the cost.
   - CSV statements could be parsed locally for free.
5. **Card refunds** as their own transaction type, so statement checks can fix them automatically.
6. **Multi-currency conversion** with recorded exchange rates. Today currencies are shown separately and never summed.
