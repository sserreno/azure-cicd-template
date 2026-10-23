// Entry point on App Service (appCommandLine in infra/modules/app-service.bicep).
// App Service sets PORT.
import path from 'node:path';
import { buildApp } from './app.js';
import { createDb, isDbConfigured } from './db.js';

async function main() {
  const app = await buildApp({
    db: isDbConfigured() ? createDb() : undefined,
    clientRoot: path.resolve(import.meta.dirname, '../client'),
    logger: true,
  });
  await app.listen({ host: '0.0.0.0', port: Number(process.env.PORT ?? 8080) });
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
