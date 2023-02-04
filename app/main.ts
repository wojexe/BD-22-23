import "https://deno.land/x/dotenv@v3.2.0/load.ts";

import db from "./database.ts";
import server from "./server.ts";

if (import.meta.main) {
  await db.connect();
}

const app = server(db);

app.listen(8080);

console.log(`🫡 Listening on http://localhost:8080`);
