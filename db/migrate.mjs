// Applies pending db/migrations and makes sure the app's managed identity
// has a database user.
//
// Signs in with an Entra ID access token (the pipeline's deploy identity is in
// the server's admin group). Configuration comes from the environment:
//   SQL_SERVER        server FQDN
//   SQL_DATABASE      database name
//   SQL_ACCESS_TOKEN  token for https://database.windows.net/
//   APP_IDENTITY_NAME       name of the app's user-assigned managed identity
//   APP_IDENTITY_CLIENT_ID  its client ID
//
// For the local SQL Server used by tests, set SQL_USER and SQL_PASSWORD
// instead of SQL_ACCESS_TOKEN and the identity. The database is then created
// if missing, and no managed-identity user is made.
//
// Applied migrations are immutable: each one's checksum is stored, and a
// run stops if a file that already ran was edited or removed. With --check
// it only verifies that and applies nothing.
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sql from 'mssql';
import { connect, connectionConfig, isLocal, required } from './connect.mjs';
import { assertSafeIdentifier, checkAppliedMigrations, migrationChecksum, orderMigrations, splitBatches } from './lib.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

async function applyMigrations(pool) {
  await pool.request().batch(`
    IF OBJECT_ID('dbo.schema_migrations') IS NULL
      CREATE TABLE dbo.schema_migrations (
        name       NVARCHAR(200) PRIMARY KEY,
        applied_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
      );`);

  // Each applied migration's checksum, so an edit after it ran is caught.
  await pool.request().batch(`
    IF COL_LENGTH('dbo.schema_migrations', 'checksum') IS NULL
      ALTER TABLE dbo.schema_migrations ADD checksum CHAR(64) NULL;`);

  const dir = path.join(here, 'migrations');
  const files = orderMigrations(await readdir(dir));
  const texts = new Map();
  for (const file of files) texts.set(file, await readFile(path.join(dir, file), 'utf8'));
  const checksums = new Map([...texts].map(([file, text]) => [file, migrationChecksum(text)]));

  const applied = new Map(
    (await pool.request().query('SELECT name, checksum FROM dbo.schema_migrations')).recordset
      .map((r) => [r.name, r.checksum ? r.checksum.trim() : null]),
  );
  const { problems, backfill } = checkAppliedMigrations(applied, checksums);
  if (problems.length) {
    throw new Error(`Applied migrations changed:\n  ${problems.join('\n  ')}\nNever edit or remove a migration that has run; add a new one instead.`);
  }
  // Rows recorded before checksums existed take today's file as their checksum.
  for (const file of backfill) {
    await pool.request().input('name', sql.NVarChar, file).input('checksum', sql.Char(64), checksums.get(file))
      .query('UPDATE dbo.schema_migrations SET checksum = @checksum WHERE name = @name AND checksum IS NULL');
  }
  if (process.argv.includes('--check')) {
    console.log(`checked ${applied.size} applied migrations; ${files.length - applied.size} pending`);
    return;
  }

  for (const file of files.filter((f) => !applied.has(f))) {
    const batches = splitBatches(texts.get(file));
    const tx = new sql.Transaction(pool);
    await tx.begin();
    try {
      for (const batch of batches) await new sql.Request(tx).batch(batch);
      await new sql.Request(tx).input('name', sql.NVarChar, file).input('checksum', sql.Char(64), checksums.get(file))
        .query('INSERT INTO dbo.schema_migrations (name, checksum) VALUES (@name, @checksum)');
      await tx.commit();
      console.log(`applied ${file}`);
    } catch (err) {
      await tx.rollback();
      throw new Error(`Migration ${file} failed: ${err.message}`);
    }
  }
}

// Creates a database user for the app's managed identity, with read/write on
// the app schema. Uses WITH SID ... TYPE = E rather than FROM EXTERNAL
// PROVIDER, which would need the server to have Microsoft Graph read access
// when run by the pipeline's identity (docs/adr/0003-sql-with-managed-identity.md).
async function ensureAppUser(pool, user, clientId) {
  await pool.request()
    .input('user', sql.NVarChar(128), user)
    .input('clientId', sql.UniqueIdentifier, clientId)
    .batch(`
      DECLARE @stmt NVARCHAR(400);
      IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = @user)
      BEGIN
        DECLARE @sid VARBINARY(16) = CAST(@clientId AS VARBINARY(16));
        SET @stmt = N'CREATE USER ' + QUOTENAME(@user) + N' WITH SID = ' + CONVERT(NVARCHAR(34), @sid, 1) + N', TYPE = E';
        EXEC sp_executesql @stmt;
      END
      IF IS_ROLEMEMBER('app_rw', @user) = 0
      BEGIN
        SET @stmt = N'ALTER ROLE app_rw ADD MEMBER ' + QUOTENAME(@user);
        EXEC sp_executesql @stmt;
      END`);
  console.log(`SQL user ${user} is ready`);
}

async function ensureLocalDatabase(database) {
  const pool = await connect(connectionConfig('master'));
  try {
    await pool.request().input('name', sql.NVarChar(128), assertSafeIdentifier(database))
      .batch(`IF DB_ID(@name) IS NULL
        BEGIN
          DECLARE @stmt NVARCHAR(200) = N'CREATE DATABASE ' + QUOTENAME(@name);
          EXEC sp_executesql @stmt;
        END`);
  } finally {
    await pool.close();
  }
}

async function main() {
  const database = required('SQL_DATABASE');
  if (isLocal()) await ensureLocalDatabase(database);
  const pool = await connect(connectionConfig(database));
  try {
    await applyMigrations(pool);
    if (!isLocal() && !process.argv.includes('--check')) {
      const user = assertSafeIdentifier(required('APP_IDENTITY_NAME'));
      await ensureAppUser(pool, user, required('APP_IDENTITY_CLIENT_ID'));
    }
  } finally {
    await pool.close();
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
