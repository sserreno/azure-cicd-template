import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.js';
import { createDb, isDbConfigured } from '../src/db.js';

test('health is 503 without a database', async () => {
  const app = await buildApp();
  const res = await app.inject({ method: 'GET', url: '/api/health' });
  assert.equal(res.statusCode, 503);
  assert.equal(res.json().error, 'Database is not configured');
});

test('health is ok with the migrated test database', { skip: !isDbConfigured() && 'set SQL_* for the test database' }, async () => {
  const db = createDb();
  try {
    const app = await buildApp({ db });
    const res = await app.inject({ method: 'GET', url: '/api/health' });
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.json(), { status: 'ok', db: 'ok' });
  } finally {
    await db.destroy();
  }
});

test('/api/me reads the App Service Authentication headers', async () => {
  const app = await buildApp();
  assert.equal((await app.inject({ method: 'GET', url: '/api/me' })).statusCode, 401);
  const res = await app.inject({
    method: 'GET', url: '/api/me',
    headers: { 'x-ms-client-principal-idp': 'github', 'x-ms-client-principal-id': '42', 'x-ms-client-principal-name': 'ada' },
  });
  assert.deepEqual(res.json(), { provider: 'github', userId: '42', name: 'ada' });
});
