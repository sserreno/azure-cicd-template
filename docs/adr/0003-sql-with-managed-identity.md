# SQL with Entra ID only: managed identity for the app, OIDC for the pipeline

The SQL server allows Entra ID authentication only; there is no SQL password anywhere in Azure.
- The app signs in with its user-assigned managed identity.
- The pipeline signs in as its deploy identity, which is a member of the Entra ID group that administers the server.

`db/migrate.mjs` applies the migrations. It also creates the app's database user with `CREATE USER … WITH SID = <client id>, TYPE = E` and adds it to the `app_rw` role, which can read and write the `app` schema only.

The SQL firewall allows exactly the web app's possible outbound addresses (`scripts/sync-sql-firewall.sh`, run on every deploy). A deploy also adds the runner's own address while the migrations run, then removes it.

Applied migrations are immutable:
- `db/migrate.mjs` stores each migration's checksum and refuses to run if a file that already ran was edited or removed.
- CI fails a pull request that changes a migration already on its base branch.

## Consequences

- `WITH SID … TYPE = E` avoids giving the SQL server Microsoft Graph read access, which `FROM EXTERNAL PROVIDER` would need when run by a service principal.
- Fix a bad migration by adding a new one, never by editing the old one.
