// Pure helpers for migrate.mjs, kept separate so they can be unit-tested
// without a database.
import { createHash } from 'node:crypto';
const MIGRATION_FILE = /^(\d{4})_[a-z0-9_]+\.sql$/;

// Returns migration file names in apply order; rejects anything misnamed so a
// typo can't silently skip a migration.
export function orderMigrations(fileNames) {
  const sql = fileNames.filter((f) => f.endsWith('.sql'));
  for (const f of sql) {
    if (!MIGRATION_FILE.test(f)) {
      throw new Error(`Bad migration file name "${f}": expected NNNN_snake_case.sql`);
    }
  }
  const sorted = [...sql].sort();
  const seen = new Set();
  for (const f of sorted) {
    const n = f.slice(0, 4);
    if (seen.has(n)) throw new Error(`Duplicate migration number ${n}`);
    seen.add(n);
  }
  return sorted;
}

// Splits a script into batches on lines containing only GO, like sqlcmd.
export function splitBatches(script) {
  return script
    .split(/^\s*GO\s*$/im)
    .map((b) => b.trim())
    .filter((b) => b.length > 0);
}

// Defence in depth: user names are also QUOTENAME()d in T-SQL.
export function assertSafeIdentifier(name) {
  if (!/^[A-Za-z][A-Za-z0-9_-]{0,127}$/.test(name)) {
    throw new Error(`Unsafe SQL identifier "${name}"`);
  }
  return name;
}

// A migration's fingerprint. Line endings are normalised so a checkout on
// Windows doesn't change it.
export function migrationChecksum(text) {
  return createHash('sha256').update(text.replace(/\r\n?/g, '\n')).digest('hex');
}

// Compares what the database has applied (name -> checksum, null for rows
// recorded before checksums existed) with the files (name -> checksum).
// Applied migrations are immutable: an edited or missing file is a problem;
// fix forward with a new migration instead.
export function checkAppliedMigrations(applied, files) {
  const problems = [];
  const backfill = [];
  for (const [name, checksum] of applied) {
    if (!files.has(name)) problems.push(`${name} was applied but its file is gone`);
    else if (checksum === null) backfill.push(name);
    else if (checksum !== files.get(name)) problems.push(`${name} was edited after it was applied`);
  }
  return { problems, backfill };
}
