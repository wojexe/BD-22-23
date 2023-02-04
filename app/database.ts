import { Client } from "https://deno.land/x/postgres@v0.17.0/mod.ts";

const db = new Client({
  applicationName: "backend",
  user: "wojexe",
  database: "genealogy-backend",
  hostname: "localhost",
});

export default db;
