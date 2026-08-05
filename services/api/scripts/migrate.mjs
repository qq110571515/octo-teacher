import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";
import postgres from "postgres";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL is required");

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const migrationDir = path.join(root, "migrations");
const sql = postgres(databaseUrl, { max: 1, prepare: false, ssl: "require" });

try {
  await sql`
    create table if not exists octoteacher_schema_migrations (
      name text primary key,
      applied_at timestamptz not null default now()
    )
  `;
  const appliedRows = await sql`select name from octoteacher_schema_migrations`;
  const applied = new Set(appliedRows.map((row) => String(row.name)));
  const files = (await readdir(migrationDir)).filter((name) => name.endsWith(".sql")).sort();

  for (const name of files) {
    if (applied.has(name)) continue;
    const body = await readFile(path.join(migrationDir, name), "utf8");
    await sql.begin(async (transaction) => {
      await transaction.unsafe(body);
      await transaction`insert into octoteacher_schema_migrations (name) values (${name})`;
    });
    console.log(`Applied ${name}`);
  }
} finally {
  await sql.end();
}
