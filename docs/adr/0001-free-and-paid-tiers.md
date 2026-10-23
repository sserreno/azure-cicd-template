# Two tiers: free, and paid when there's a budget

Each environment (`dev`, `prod`) is deployed on one of two tiers, chosen per environment with the `DEV_TIER` and `PROD_TIER` GitHub variables.

**free** reads "free" strictly. It uses only plans with hard limits that stop instead of billing, and features that are always free:
- plans that stop: App Service F1, and the Azure SQL Database free offer set to auto-pause;
- always-free features: managed identities, Entra ID Free, Azure Policy and budgets.

Metered services with a monthly free allowance, such as Log Analytics, Application Insights and Container Apps, are excluded, because Azure can't hard-stop them once the allowance runs out.

**paid** keeps the same design and changes the SKUs:
- an always-on App Service plan (B1 by default);
- a SQL database that never pauses (Basic by default);
- Application Insights on a Log Analytics workspace with a daily ingestion cap.

The same Bicep deploys both tiers. Moving an environment between tiers means changing its variable and re-running its deployment, not rewriting infrastructure.

## Consequences

- Each subscription gets an "allowed resource types" policy, an "allowed locations" policy and a budget alert.
  - On free, the allowed types exclude everything that can charge, and the budget is 1, so any charge at all alerts.
  - On paid, the allowed types add monitoring and deployment slots, and the budget is whatever the setup wizard was given.
- Neither App Service F1 nor the SQL free offer has an SLA. F1 has a daily CPU quota and sleeps when idle, and the free database pauses for the rest of the month when its allowance runs out. Use paid for anything people depend on.
- Neither tier includes a Container Registry, Key Vault, private networking or Azure DNS. Each is a deliberate gap to add when a project needs it.
- Moving an environment between tiers changes its SKUs in place. Check the pull request's what-if first, and take a backup before switching prod.
