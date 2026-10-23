// The database connection. In Azure the app signs in to SQL with its
// user-assigned managed identity, so there is no password anywhere
// (docs/adr/0003-sql-with-managed-identity.md). SQL_USER and SQL_PASSWORD
// exist only for the local SQL Server used in tests.
import { Kysely, MssqlDialect } from 'kysely';
import * as Tarn from 'tarn';
import * as Tedious from 'tedious';

// Add a table interface per table as the schema grows.
export interface Database {}

export type Db = Kysely<Database>;

export function isDbConfigured(env: NodeJS.ProcessEnv = process.env): boolean {
  return Boolean(env.SQL_SERVER && env.SQL_DATABASE);
}

function authentication(env: NodeJS.ProcessEnv): Tedious.ConnectionAuthentication {
  if (env.SQL_USER) {
    return { type: 'default', options: { userName: env.SQL_USER, password: env.SQL_PASSWORD ?? '' } };
  }
  return { type: 'azure-active-directory-msi-app-service', options: { clientId: env.AZURE_CLIENT_ID } };
}

export function createDb(env: NodeJS.ProcessEnv = process.env): Db {
  if (!isDbConfigured(env)) throw new Error('Database settings are missing');
  const config: Tedious.ConnectionConfiguration = {
    server: env.SQL_SERVER!,
    authentication: authentication(env),
    options: {
      database: env.SQL_DATABASE,
      encrypt: true,
      trustServerCertificate: env.SQL_TRUST_SERVER_CERTIFICATE === 'true',
      // A paused free-offer database takes a while to resume.
      connectTimeout: 60_000,
      requestTimeout: 30_000,
    },
  };
  return new Kysely<Database>({
    dialect: new MssqlDialect({
      tarn: { ...Tarn, options: { min: 0, max: 5 } },
      tedious: { ...Tedious, connectionFactory: () => new Tedious.Connection(config) },
    }),
  });
}
