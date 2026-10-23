import assert from 'node:assert/strict';
import { test } from 'node:test';
import { assertSafeIdentifier, checkAppliedMigrations, migrationChecksum, orderMigrations, splitBatches } from './lib.mjs';

test('orders migrations by number and ignores non-sql files', () => {
  assert.deepEqual(
    orderMigrations(['0002_b.sql', 'README.md', '0001_a.sql']),
    ['0001_a.sql', '0002_b.sql'],
  );
});

test('rejects misnamed and duplicate migrations', () => {
  assert.throws(() => orderMigrations(['1_a.sql']), /Bad migration file name/);
  assert.throws(() => orderMigrations(['0001_a.sql', '0001_b.sql']), /Duplicate migration number 0001/);
});

test('splits batches on GO lines only', () => {
  assert.deepEqual(
    splitBatches('CREATE SCHEMA app;\nGO\n  go  \nSELECT 1 AS GOAL;\nGO\n'),
    ['CREATE SCHEMA app;', 'SELECT 1 AS GOAL;'],
  );
});

test('only safe identifiers pass', () => {
  assert.equal(assertSafeIdentifier('id-acme-dev-app-sdc'), 'id-acme-dev-app-sdc');
  assert.throws(() => assertSafeIdentifier('x]; DROP USER y; --'), /Unsafe/);
});

test('a migration checksum ignores line endings only', () => {
  assert.equal(migrationChecksum('SELECT 1;\r\nGO\r\n'), migrationChecksum('SELECT 1;\nGO\n'));
  assert.notEqual(migrationChecksum('SELECT 1;\n'), migrationChecksum('SELECT 2;\n'));
});

test('applied migrations must keep their file and checksum', () => {
  const files = new Map([['0001_a.sql', 'aaa'], ['0002_b.sql', 'bbb'], ['0003_c.sql', 'ccc']]);
  assert.deepEqual(checkAppliedMigrations(new Map([['0001_a.sql', 'aaa'], ['0002_b.sql', null]]), files),
    { problems: [], backfill: ['0002_b.sql'] });
  assert.deepEqual(checkAppliedMigrations(new Map([['0001_a.sql', 'xxx'], ['0009_gone.sql', 'ggg']]), files).problems,
    ['0001_a.sql was edited after it was applied', '0009_gone.sql was applied but its file is gone']);
});
