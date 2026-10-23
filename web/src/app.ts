// The HTTP app: /api/health for the pipeline's smoke test and the hourly
// health check, /api/me for whoever App Service Authentication signed in,
// and the static frontend.
import fastifyStatic from '@fastify/static';
import Fastify, { type FastifyInstance } from 'fastify';
import { sql } from 'kysely';
import type { Db } from './db.js';

export interface AppOptions {
  db?: Db;
  clientRoot?: string;
  logger?: boolean;
}

export async function buildApp({ db, clientRoot, logger = false }: AppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({ logger });

  // Fails when the database is unreachable, including when the free offer
  // has paused it for the rest of the month.
  app.get('/api/health', async (req, reply) => {
    if (!db) return reply.code(503).send({ status: 'error', error: 'Database is not configured' });
    try {
      await sql`SELECT 1 AS ok`.execute(db);
      return { status: 'ok', db: 'ok' };
    } catch (err) {
      req.log.error(err);
      return reply.code(503).send({ status: 'error', error: 'Database is unavailable' });
    }
  });

  // App Service Authentication sets these headers after a sign-in; they
  // can't be forged from outside because it strips them from requests.
  app.get('/api/me', async (req, reply) => {
    const provider = req.headers['x-ms-client-principal-idp'];
    const userId = req.headers['x-ms-client-principal-id'];
    if (typeof provider !== 'string' || typeof userId !== 'string') return reply.code(401).send({ error: 'Not signed in' });
    const name = req.headers['x-ms-client-principal-name'];
    return { provider, userId, name: typeof name === 'string' ? name : null };
  });

  if (clientRoot) await app.register(fastifyStatic, { root: clientRoot });
  return app;
}
