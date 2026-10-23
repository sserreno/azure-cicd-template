# One App Service and one Azure SQL database per environment

The app is one Node 22 process on a Linux App Service that serves both the frontend and the API. Data lives in one Azure SQL database. This is the smallest setup that has a free tier (F1 and the SQL free offer) and a straightforward paid upgrade path (B1/S1/P0v3 and Basic/S0/vCore) without changing the architecture.

App Service Authentication ("Easy Auth") handles sign-in with Microsoft, GitHub or any email address (Entra External ID). Each provider is optional: one is turned on when its client ID is set, and with none set, authentication is off. The app reads the signed-in person from the `X-MS-CLIENT-PRINCIPAL-*` headers and decides access per route.

## Consequences

- F1 has no deployment slots, so dev has no per-pull-request preview sites. Paid plans from S1 up support slots, and the paid tier's policy already allows them.
- Static Web Apps and Container Apps were not chosen. Static Web Apps' free tier can't host a long-running API with a SQL connection pool. Container Apps bills by usage and has no free tier that stops at a limit.
