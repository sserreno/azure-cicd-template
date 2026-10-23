# Infrastructure and CI/CD

How this template deploys an app to Azure from GitHub Actions, and how to set it up for a new project.

## What you get

| | free tier | paid tier |
| --- | --- | --- |
| Web | App Service **F1** (Linux, Node 22): 60 CPU-minutes a day, sleeps when idle, no SLA | App Service **B1** by default (`PAID_PLAN_SKU`): Always On; S1/P0v3 add deployment slots |
| Database | Azure SQL **free offer** (serverless, 32 GB): pauses for the rest of the month when its allowance runs out | Azure SQL **Basic** by default (`PAID_SQL_SKU`); S0 or a vCore SKU such as `GP_S_Gen5_1` for more |
| Monitoring | Hourly GitHub health check (`health.yml`) | The same, plus Application Insights and Log Analytics with a 0.5 GB/day cap |
| Guardrails | Policy allows only resource types that cannot charge; budget alert at 1 | Policy also allows monitoring and slots; budget alert at the amount you choose |
| Typical monthly cost | 0 | roughly the plan plus the database: B1 + Basic is about US$15–20 (check the [pricing calculator](https://azure.microsoft.com/pricing/calculator/)) |

The tier is chosen per environment (`DEV_TIER`, `PROD_TIER`). A common setup is free for dev and paid for prod once real people depend on it. The decisions behind all this are in `docs/adr/`.

Both tiers share the rest:
- **Sign-in:** App Service Authentication with Microsoft, GitHub and email sign-in, each optional.
- **Database access:** Entra-only SQL, with the app signing in as its managed identity.
- **Pipeline access:** OIDC, so there are no Azure secrets in GitHub.
- **Migrations:** checksummed and immutable once applied.
- **Releases:** prod deploys only from tagged commits on the `release` branch.

## Layout

```
infra/
  bootstrap/main.bicep     one-time, per subscription: resource group, deploy identity, policies, budget
  main.bicep               per deploy: App Service, SQL, monitoring (paid)
  modules/                 app-service, sql, monitoring
  dev.bicepparam, prod.bicepparam   read their values from environment variables set by the workflows
.github/workflows/
  dev.yml                  checks on every PR (plus infra what-if); deploy dev on merge to main
  prod.yml                 deploy prod from the release branch, only for v* tagged commits
  _checks.yml, _deploy.yml shared steps
  health.yml               hourly check of prod's /api/health
db/                        migrate.mjs and migrations/NNNN_name.sql
web/                       a minimal sample app (Fastify): /api/health, /api/me, a static page; replace with yours
scripts/
  setup-azure.sh           one-time setup wizard
  release.sh               tag and release to prod
  sync-sql-firewall.sh     used by the deploy
  check-migrations-unchanged.sh   used by CI
```

## Set up a new project

1. **Create the repository from this template.** Use "Use this template" on GitHub. To combine it with the agent workflow, also copy in the files from `agent-workflow-template`.
2. **Run the wizard** from a machine with `az`, `gh` and `jq`, signed in as an Owner of the Azure tenant and an admin of the repository:
   ```bash
   scripts/setup-azure.sh
   ```
   It asks for:
   - the app's short name, the region and the tier for each environment;
   - the budget(s) and the address for budget alerts.

   It then creates or records:
   - the dev and prod subscriptions (you create them in the portal; it records their IDs);
   - providers registered in each subscription;
   - per environment: the SQL admin group, the bootstrap deployment (resource group, deploy identity, policies, budget) and, optionally, the Microsoft and GitHub sign-in apps;
   - the GitHub variables and secrets the workflows read.

   Values are also kept in `.env`, which is git-ignored, so a re-run offers them as defaults.
3. **Deploy dev.** Run the dev workflow manually, or merge anything to `main`. Its smoke test calls `/api/health`, which must return `200`.
4. **Release prod:** `scripts/release.sh v0.1.0`. Re-run the wizard's last stage afterwards to set `PROD_URL`, which switches on the hourly health check.

Until step 2 is done, the Azure jobs are skipped, so a fresh repository runs only the checks and stays green.

## GitHub variables and secrets

Set by the wizard; listed here for reference and for manual fixes.

| Name | Kind | What |
| --- | --- | --- |
| `APP_NAME` | variable | Short name used in every resource name |
| `REGION_CODE` | variable | Short region code in names (default `sdc`) |
| `AZURE_TENANT_ID` | variable | Entra tenant |
| `DEV_TIER`, `PROD_TIER` | variable | `free` or `paid` |
| `PAID_PLAN_SKU`, `PAID_SQL_SKU` | variable, optional | Paid-tier SKUs (defaults `B1`, `Basic`) |
| `DEV_AZURE_SUBSCRIPTION_ID`, `DEV_AZURE_CLIENT_ID` (and `PROD_…`) | variable | Subscription and deploy identity |
| `DEV_SQL_ADMIN_GROUP_NAME`, `DEV_SQL_ADMIN_GROUP_ID` (and `PROD_…`) | variable | Entra group that administers SQL |
| `DEV_MICROSOFT_AUTH_CLIENT_ID` (and `PROD_…`) | variable, optional | "Sign in with Microsoft" |
| `DEV_GITHUB_AUTH_CLIENT_ID` / `DEV_GITHUB_AUTH_CLIENT_SECRET` (and `PROD_…`) | variable / secret, optional | "Sign in with GitHub" |
| `DEV_EMAIL_AUTH_CLIENT_ID`, `DEV_EMAIL_AUTH_METADATA_URL` / `DEV_EMAIL_AUTH_CLIENT_SECRET` (and `PROD_…`) | variable / secret, optional | "Sign in with email" |
| `PROD_URL` | variable | Turns on `health.yml` |

## Switching an environment's tier

1. **Re-run the subscription bootstrap with the new tier,** so the policy allows the paid resource types and the budget matches. You can re-run the wizard, or run:
   ```bash
   APP_NAME=… TIER=paid REGION=swedencentral REGION_CODE=sdc GITHUB_OIDC_REPO=… BUDGET_EMAIL=… BUDGET_AMOUNT=30 \
     az deployment sub create --subscription <id> --location swedencentral \
       --name <app>-bootstrap-prod --parameters infra/bootstrap/prod.bicepparam
   ```
2. **Set the tier variable,** for example `gh variable set PROD_TIER --body paid`.
3. **Redeploy:**
   - dev: run the dev workflow manually; manual runs always deploy infrastructure.
   - prod: run `scripts/release.sh` with a new tag.

Going from paid back to free works the same way, in reverse order: switch the tier and redeploy first, then re-run the bootstrap. That order keeps the stricter policy from blocking the monitoring resources that still exist. Delete those monitoring resources by hand afterwards.

## Sign in with email (optional)

Email sign-in uses Microsoft Entra External ID as a custom OpenID Connect provider named `email`. Setting it up takes four steps:
1. Create an External ID tenant.
2. In it, register an app with redirect URI `https://<app host>/.auth/login/email/callback`, and create a sign-up/sign-in user flow that includes the app.
3. Set `<ENV>_EMAIL_AUTH_CLIENT_ID`, `<ENV>_EMAIL_AUTH_METADATA_URL` (the tenant's `…ciamlogin.com/…/v2.0/.well-known/openid-configuration`) and the `<ENV>_EMAIL_AUTH_CLIENT_SECRET` secret.
4. Redeploy.

The External ID tenant's data location (for example `europe`) must be allowed: set `EXTRA_ALLOWED_LOCATIONS=europe` (comma-separated) when running the bootstrap.

## Running the checks locally

```bash
docker run -d --name mssql -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD=Local_Test_1 -p 1433:1433 mcr.microsoft.com/mssql/server:2022-latest
export SQL_SERVER=localhost SQL_DATABASE=app_test SQL_USER=sa SQL_PASSWORD=Local_Test_1 SQL_TRUST_SERVER_CERTIFICATE=true
(cd db && npm ci && npm test && node migrate.mjs)
(cd web && npm ci && npm test)
```

Without `SQL_TRUST_SERVER_CERTIFICATE=true`, the database tests fail with "self-signed certificate". `node db/migrate.mjs --check` only verifies the applied migrations' checksums.
