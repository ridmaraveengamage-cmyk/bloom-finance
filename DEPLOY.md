# Putting Bloom Finance online, with Google sign-in

**Where it runs (all free):**
- **Netlify** hosts the website.
- **Supabase** handles sign-in and the database.
- **GitHub** stores the code and runs the automation.

**Cost:** everything here is free, including Google sign-in.

**What happens automatically after setup:**
- Every time you change something on GitHub, the app and database are checked.
- If the checks pass, Netlify publishes the site.
- The Supabase database and sign-in settings are updated.

**What you do once, by hand (about 25 minutes):**
- Create the Google login credentials.
- Paste a few values into GitHub.

Google only issues these credentials to a signed-in account owner. Never paste any of these values into a chat, an email or a file in the repository. They go only into GitHub's **Secrets** page.

---

## Step 1: Upload these files to GitHub (5 min)

1. Open **github.com/ridmaraveengamage-cmyk/bloom-finance**.
2. Click **Add file → Upload files**.
3. Drag in **everything inside this folder**, including the hidden `.github` folder.
   - On a Mac, press **Cmd + Shift + .** in Finder to show hidden folders.
   - On Windows, turn on View → Hidden items.
4. Write a short message such as "New Bloom app with sign-in", then click **Commit changes**.

What this changes:
- **Replaced:** `index.html`, `netlify.toml`, `.github/workflows/validate.yml` and `.github/workflows/pages.yml`.
- **Added:** the `supabase` folder and `.github/workflows/supabase.yml`.
- **Left alone:** your existing `supabase-config.js`. The app reads it automatically.

## Step 2: Make sure Netlify publishes from GitHub (3 min)

1. Open **app.netlify.com → bloom-finance-test → Site configuration → Build & deploy**.
2. Under **Continuous deployment**, check that the repository is **bloom-finance** and the branch is **main**.
   - If no repository is linked, click **Link repository**, choose GitHub, and select bloom-finance.
3. Leave **Build command** empty. Set **Publish directory** to `.` (a single dot).

From now on, every change on `main` goes live by itself within about a minute.

## Step 3: Get two Supabase values (5 min)

1. **Access token:** go to **supabase.com/dashboard/account/tokens → Generate new token**. Name it "GitHub" and copy it.
2. **Database password:** open your project, then **Project Settings → Database**. If you don't know the password, click **Reset database password** and copy the new one.
3. **Project ref:** this is `lljjqsyivqstwcdxkicb`, the part before `.supabase.co`.

## Step 4: Google sign-in (10 min, free)

1. Go to **console.cloud.google.com**. Create a project named "Bloom Finance", or pick an existing one.
2. Open **APIs & Services → OAuth consent screen** (it may be called **Google Auth Platform**):
   - Choose **External**.
   - App name: **Bloom Finance**. Add your support email.
   - Save.
   - Under **Audience**, click **Publish app**. While it's in "Testing", only test users you list can sign in. Basic sign-in (name and email) needs no Google review.
3. Open **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Web application**. Name: "Bloom Finance web".
   - **Authorized JavaScript origins:** `https://bloom-finance-test.netlify.app`
   - **Authorized redirect URIs:** `https://lljjqsyivqstwcdxkicb.supabase.co/auth/v1/callback`
   - Click **Create**, then copy the **Client ID** and **Client secret**.

## Step 5: Put the values into GitHub (5 min)

Go to **GitHub → your repo → Settings → Secrets and variables → Actions**.

**Variables tab → New repository variable:**

| Name | Value |
|---|---|
| `SUPABASE_PROJECT_REF` | `lljjqsyivqstwcdxkicb` |
| `SITE_URL` | `https://bloom-finance-test.netlify.app` |

**Secrets tab → New repository secret:**

| Name | Value |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | the token from Step 3 |
| `SUPABASE_DB_PASSWORD` | the database password from Step 3 |
| `GOOGLE_CLIENT_ID` | from Step 4 |
| `GOOGLE_CLIENT_SECRET` | from Step 4 |

## Step 6: Run the automation (2 min)

1. Go to **GitHub → Actions → Supabase setup → Run workflow**.
2. Wait for the green tick. The run:
   - applies the four database files,
   - sets the website address as the allowed sign-in return address, and
   - switches on Google sign-in.
3. If it shows a red cross, open the failed step and read the message. A missing value is named exactly. Send me the error text, never the secret values.

## Step 7: Try it

Open **https://bloom-finance-test.netlify.app**, then:
- Sign up with email. Check your inbox for the confirmation link.
- Log out, then try **Continue with Google**.

---

## Good to know

- **Confirmation emails:** Supabase's built-in email sender only sends a few emails per hour. That's fine for testing. Before inviting many people, add your own email service in Supabase under **Authentication → Emails → SMTP settings**. Brevo and Resend both have free tiers.
- **Data is still kept in each person's browser,** separately per account. Syncing to the Supabase database is the next build step.
- **Documents on your own site:** in this version, the Documents tab can store document details, but it can't store the files themselves or read statements. Inside the Claude preview, Claude provided both. On your own site they'll need Supabase Storage, which has a free tier, and an AI service to read statements, which is paid. That's a later step.
- **Old GitHub Pages copy:** `pages.yml` now only runs if you start it by hand, so Netlify is the one live site.
