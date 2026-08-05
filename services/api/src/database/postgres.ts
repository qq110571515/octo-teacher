import postgres, { type Sql } from "postgres";

let sharedClient: Sql | undefined;

export function platformDatabase(): Sql {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("platform_database_unavailable");
  sharedClient ??= postgres(url, {
    max: 1,
    prepare: false,
    ssl: "require",
    connect_timeout: 10,
    idle_timeout: 20,
  });
  return sharedClient;
}
