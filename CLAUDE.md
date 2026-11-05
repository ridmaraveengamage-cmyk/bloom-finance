# Bloom Finance: project brief for Claude Code

The owner, **Ridma**, is a beginner in software development and works on legal and administrative matters in Sri Lanka.
- Lead the technical work: make reasonable, reversible decisions yourself, and explain important ones in plain language.
- Ask only when a decision or permission genuinely blocks progress.
- Ridma prefers complete, structured answers and wants things done "in one go", tested, with no visible bugs.

## What this is

Bloom Finance is a personal finance **website and installable phone app (PWA)** built from one codebase.

- **Live site:** https://ridmaraveengamage-cmyk.github.io/bloom-finance. This is also the phone app (Install / Add to Home Screen).
- **Hosting:** GitHub Pages, deploying from the `main` branch root. Every push to `main` goes live in about 1–2 minutes.
  - Netlify (the old host) has builds **stopped**. Don't use it. `netlify.toml` and `pages.yml` are leftovers.
- **The app:** one self-contained file, `index.html` (HTML, CSS and plain JavaScript, no build step), about 245 KB.
- **Other app files:**
  - `supabase-config.js`: public URL and publishable key only.
  - `sw.js`: offline service worker. Bump `VERSION` when icons or the manifest change.
  - `manifest.webmanifest`: name "Bloom Finance".
  - Icons: `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `apple-touch-icon.png` (fintech-style: green bars and a gold trend arrow).
  - `privacy.html`: the privacy policy, required by Google sign-in.
- **Backend:** Supabase, project ref `lljjqsyivqstwcdxkicb` (free plan).
  - Sign-in by email/password and Google.
  - The Google OAuth client lives in Google Cloud project `bloom-finance-513013`. It is published to production.
- **Current version:** v0.22.

## Non-negotiable rules

1. **Secrets:**
   - Never commit, print or log secrets: Supabase access token, database password, service-role key, Google client secret.
   - Never ask Ridma to paste a secret into chat.
2. **Money:**
   - Integer minor units (cents) only.
   - Balances are always derived from opening amounts plus transactions. Never store a running balance.
3. **Financial rules** (tests depend on them):

   | Transaction | Effect |
   |---|---|
   | Expense from bank or cash | Reduces that account |
   | Credit-card purchase | Increases card debt only. *Not* in Total expenses or cash flow, but *is* in spending-by-category, budgets and emergency cover |
   | Card repayment | Bank down, card debt down. Not an expense |
   | Loan payment | Principal reduces the loan. Only the interest is an expense |
   | Own transfer, cash withdrawal, cash deposit | Never income or expense |
   | Transfer to family or external | Expense, category "Transfers" |
   | Transfer from family or external | Income, source "Transfers" |
   | Savings goals | Earmarks only. They never change balances or net worth |

   Two identities must always hold:
   - Cash flow balance = income − expenses − card repayments − loan principal = the change in cash and bank balances.
   - Net worth = (cash and bank + other assets) − (card debt + loans).
4. **Privacy and security:**
   - Row Level Security stays on for every table with personal data.
   - Shared group figures are totals only. Never publish account names or individual transactions to a group.
   - Store only the last 4 digits of cards.
5. **Never fake success.** Don't claim something works without running it. Sign-in must never pretend to work when Supabase is unreachable.
6. **No browser pop-ups.** Don't use `alert()`, `confirm()` or `prompt()`; use the in-app `ask(msg, yes, label, no)` and `tell(msg)` dialogs.
7. **No developer text in the UI.** Users must never see version numbers or words like "localStorage", "Supabase", "preview", "next stage" or "this view". Use plain, friendly wording.
8. **Apple sign-in was dropped** by the owner (it costs US$99 a year). Don't add it back.

## Design: "Midnight" (approved by the owner)

- **One style only**, called Midnight, with Light, Dark and Match device modes (More › Appearance).
  - Font: Manrope. Accent: `#0B7A53` in light mode and `#3DDC97` in dark mode. Cards have 18px corners.
  - The approved design canvas has 30 screens. The app should keep matching it.
- **Phone:**
  - Floating bottom bar: Overview, Transactions, a green **+**, Accounts, More.
  - Header: logo, greeting and name, and a profile circle that opens More.
  - The More page is the hub for every other section.
  - Dialogs open as bottom sheets.
- **Computer (≥1024px):**
  - Sidebar with icons, with the user and Log out at the bottom.
  - Top bar with the page title, the period selector and **+ Add transaction**.
- **Add transaction:**
  - Type tabs, "Paid with" chips, a category grid with icons and subcategory chips.
  - The original `<select>` fields stay underneath (hidden) as the source of truth. Each chip sets its select and fires `change`.
- **QA standard before every release:** every tab (`ov tx ac al an bu gr dc mo`) at **360px, 412px and 1440px**, in **light and dark**. Check for:
  - nothing wider than the screen,
  - nothing cut off in the nav,
  - text contrast of at least 4.5:1,
  - no script errors,
  - no developer text.
  - Ridma's phones are an Infinix Hot 40i (~360px) and a Pixel 10 Pro (~412px).
- **Demo mode:** `?demo` loads sample data in memory (never saved or synced). Use it for testing and screenshots.

## Architecture inside `index.html`

- **State:** `S` (accounts, cards, assets, liabs, tx, budgets, custom, goals, groups, docs, base).
  - Saved per account in `localStorage[KEY]`, where `KEY = "bloom-v1-u-"+userId`.
  - `save()` writes the data and re-renders.
  - Core functions: `calc(asOf)`, `flows(range)`, `range()`, `series(n)`, `contrib(level, items, range)`.
- **Personal cloud sync** (table `user_app_state`, one JSON row per user, version-guarded):
  - The functions are `syncStart`, `pushNow`, `queuePush` and `adoptRemote`.
  - `fp()` is a content fingerprint built with sorted keys. **Only real data changes** count as "dirty".
  - Shared groups (those with `g.cloud`) are excluded from personal sync via `personalOf()`.
  - When both devices genuinely changed, Bloom asks "Use account copy / Keep this device's copy".
  - v0.22 fixed false conflict prompts. Don't reintroduce re-saves on open.
- **Shared groups** (tables `bloom_groups`, `bloom_group_members` and `bloom_group_invites`, plus RPC functions):
  - Invite links: `?join=CODE`. The code is kept in `localStorage` for up to a day so it survives sign-up.
  - Personal links work once (member_ref). Open links let anyone join. All links expire after 7 days.
  - Group functions: `gPull`, `gPush`, `gPack`, `gUnpack`, `gInvite`, `gJoin`, `gContent`.
  - `m.me` is never stored on the server; `m.uid` identifies real members.
  - Each member publishes their chosen sharing totals in `data.shares[uid]` (`gMySnap`). `groupOverview()` sums everyone who shares.
  - Your own sharing level is never overwritten by others' edits.
  - Conflicts: latest version wins and the user is told.
- **Documents:**
  - Signed in on the site, files go to the private Supabase Storage bucket `documents`, in folder `<userId>/`. The adapter is `SBDOC`, and asset ids look like `sb:<path>`.
  - Files open via signed URLs that expire after 120 seconds. The limit is 20 MB.
  - **Statement reading with AI** is not available on the site (it needs a paid API and a server-side key). Ask Ridma before adding cost.
- **Startup:**
  - `boot()` → `afterSignIn()` → `enterApp(user)`, which is wrapped to start group sync, invite handling and document storage.
  - On phones, a splash animation shows while the app loads.

## Database

- **Migrations** are in `supabase/migrations/`, applied in order:
  - core and groups,
  - group access and goals,
  - transaction tags,
  - profile sign-up,
  - `app_state_sync`,
  - `shared_groups_invites`,
  - `group_shares_privacy`,
  - `document_storage`.
- **All of them are already applied to the live project.** They were run through the Supabase SQL editor.
- **The `supabase.yml` workflow is not set up**, because its secrets were never added. To apply a new migration, ask Ridma to run it in the Supabase SQL editor, or help them set up the secrets.
- Supabase puts pgcrypto in the `extensions` schema. Functions use `set search_path = public`, so use built-ins like `gen_random_uuid()`, not `gen_random_bytes()`.
- `document_storage` needs Supabase Storage. The Checks workflow skips migrations that touch `storage.` because plain PostgreSQL has no storage schema.

## How to check your work

**Database tests** (local PostgreSQL 16 or Docker; never against the real project):
```
createdb bloomtest
psql -v ON_ERROR_STOP=1 -d bloomtest -f supabase/tests/local_auth_stub.sql
for f in $(ls supabase/migrations/*.sql | sort); do grep -q "storage\." "$f" && continue; psql -v ON_ERROR_STOP=1 -d bloomtest -f "$f"; done
for t in security_and_ledger_test group_access_and_goals_test transaction_group_tags_test profile_signup_test app_state_sync_test shared_groups_test; do
  psql -d bloomtest -f supabase/tests/$t.sql | grep -q "ALL TESTS PASSED" || echo "FAILED: $t"; done
```
The last run passed 56 + 28 + 11 + 11 + 8 + 32 checks.

**App:**
- Extract the inline `<script>` from `index.html` and run `node --check` on it, as `validate.yml` does.
- For logic changes, write a Node harness that stubs `document`, `localStorage` and dialogs and calls the app's functions.
- For sync and groups, simulate the server with the same rules as the database: the version guard, membership, and RPC behaviour.
- For layout, test the live or local page in iframes at 360, 412 and 1440px, in both modes, using `?demo`.

## Known limits and possible next steps

- Group overviews show other members' figures for the current month as last synced, not for any selected past period.
- Statement reading with AI is not available on the site (it would add cost).
- **Card refunds** as their own transaction type.
- **Multi-currency conversion** with recorded rates. Today currencies are shown separately and never summed.
- Ridma plans further **phone app UI improvements**. Ask for screenshots and follow the QA standard above.
- **Repo housekeeping:**
  - `DEPLOY.md` was updated for GitHub Pages.
  - `netlify.toml` and `.github/workflows/pages.yml` can be removed once Ridma agrees.
