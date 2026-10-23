# Azure CI/CD template

GitHub Actions CI/CD and Azure infrastructure for a Node web app with an Azure SQL database. Each environment can be on a **free** tier, which cannot charge, or a **paid** tier, which is always on, has a database that never pauses, and adds monitoring.

- **Bicep** (`infra/`):
  - one-time subscription bootstrap with policies and a budget;
  - App Service, Azure SQL, and Application Insights on the paid tier.
- **Workflows** (`.github/workflows/`):
  - checks on every pull request, with an infrastructure what-if;
  - dev deploys on merge to `main`;
  - prod deploys from tagged releases;
  - an hourly health check.
- **No Azure secrets in GitHub:** the pipeline signs in with OIDC, and the app reaches SQL with a managed identity.
- **Migrations** (`db/`): checksummed, and immutable once applied.
- **A minimal sample app** (`web/`) proves the pipeline end to end. Replace it with yours.
- **One-time setup wizard:** `scripts/setup-azure.sh`.

Start with [docs/infrastructure.md](docs/infrastructure.md). The reasons behind each choice are in [docs/adr/](docs/adr/).

For the agent workflow (AGENTS.md, specs and tickets, verify-before-done, guardrails), use it together with [`agent-workflow-template`](https://github.com/sserreno/agent-workflow-template).

Extracted from the Tumeno project, where all of this runs in production.
