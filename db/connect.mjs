// The database connection for the pipeline's scripts. In Azure they sign in
// with the deploy identity's Entra ID access token; against the local test
// server, with SQL_USER and SQL_PASSWORD.
import sql from 'mssql';

export function required(name) {
  const value = process.env[name];
  if (!value) throw new Error(`Missing environment variable ${name}`);
  return value;
}

// Local test server: SQL login, self-signed certificate, no managed identity.
export function isLocal() {
  return Boolean(process.env.SQL_USER);
}

export function connectionConfig(database) {
  const authentication = isLocal()
    ? { type: 'default', options: { userName: required('SQL_USER'), password: required('SQL_PASSWORD') } }
    : { type: 'azure-active-directory-access-token', options: { token: required('SQL_ACCESS_TOKEN') } };
  return {
    server: required('SQL_SERVER'),
    database,
    options: { encrypt: true, trustServerCertificate: isLocal() },
    authentication,
    // A paused free-offer database takes a while to resume.
    connectionTimeout: 120_000,
    requestTimeout: 120_000,
  };
}

// A free-offer database that auto-paused refuses connections with "not
// currently available" (error 40613) for a minute or two while it resumes.
export async function connect(config, attempts = 10, delayMs = 20_000) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await new sql.ConnectionPool(config).connect();
    } catch (err) {
      if (attempt >= attempts) throw err;
      console.log(`connection attempt ${attempt} failed (${err.message}); retrying in ${delayMs / 1000}s`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}
