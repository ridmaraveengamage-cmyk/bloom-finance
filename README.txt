BLOOM FINANCE — LOGIN + ANALYTICS VERSION

WHAT'S INCLUDED
- Sign in and Sign up screens for a local demo profile.
- Overview, Analytics, Transactions, Accounts, Assets & Liabilities, Goals, Backup & Settings.
- Analytics period selector: weekly, monthly, quarterly, 6 months, annual.
- Income and expense category pie charts.
- Income/expense trend bars for the selected period.
- Goal achievement progress charts.
- Rule-based insights and money advice.
- Choosing an asset/liability category automatically sets the main type (Asset or Liability); changing the main type filters the category.
- Net worth estimate linked to Overview.
- Green selected tabs and very light green hover effect.
- JSON backup/restore.
- GitHub Pages workflow for automatic deployment after setup.

HOW TO RUN LOCALLY
1. Extract the ZIP.
2. Open index.html in a modern browser.
3. Choose Sign up to create a local demo profile, then sign in on later visits.

IMPORTANT AUTHENTICATION LIMITATION
The sign-in/sign-up is a local prototype using browser storage and a client-side password hash. It is NOT production-grade authentication, and all finance data is stored locally in the browser. It does not securely isolate multiple users on the same device and it does not synchronize between devices. Never reuse a real password. Do not enter sensitive banking credentials or real confidential financial data. For a public finance app, replace this with server-side authentication and a protected database before launch.

AUTOMATED HOSTING WITH GITHUB PAGES
1. Sign in or create an account at https://github.com/
2. Create a repository named bloom-finance. Public is the simplest route for free GitHub Pages.
3. Upload all contents of this package to the repository root, including the hidden .github/workflows/pages.yml file.
4. Open repository Settings -> Pages and set Source to GitHub Actions.
5. Open Actions and wait for the Deploy Bloom Finance workflow to succeed.
6. Find the published website URL under Settings -> Pages.
After this one-time setup, every push to the main branch automatically redeploys the website.

NETLIFY ALTERNATIVE
1. Connect the GitHub repository at https://app.netlify.com/
2. Choose Add new site -> Import an existing project and select the repository.
3. Set the publish directory to "." and leave the build command blank.
4. Deploy. Future pushes to the connected branch redeploy automatically.

SECURITY NOTES
- This is a prototype, not a secure financial platform.
- The site is public to anyone with its URL unless you add access controls.
- Use fictional data only until server-side authentication, per-user data isolation, a secure backend and privacy/security review are implemented.
- Never enter bank passwords, PINs, CVVs, OTPs or full bank account numbers.
- Analytics advice is basic rules, not professional financial advice.
