import type { Client as dbClient } from "https://deno.land/x/postgres@v0.17.0/mod.ts";
// @deno-types="npm:@types/express@^4.17"
import express from "npm:express@4.18.2";
import { join } from "https://deno.land/std@0.176.0/path/mod.ts";
import { crypto } from "https://deno.land/std@0.176.0/crypto/mod.ts";
import { WEEK } from "https://deno.land/std@0.176.0/datetime/mod.ts";

const sessions: Map<string, { hash: string; expires: number }> = new Map();

const api = (path: TemplateStringsArray) => join("/api", path.toString());

const server = (db: dbClient) => {
  const app = express();

  app.disable("x-powered-by");

  // deno-lint-ignore no-explicit-any
  const removeTrailingSlash = (req: any, res: any, next: any) => {
    if (req.path.substring(req.path.length - 1) == "/" && req.path.length > 1) {
      const query = req.url.slice(req.path.length);
      res.redirect(301, req.path.slice(0, -1) + query);
    } else {
      next();
    }
  };

  app.use(removeTrailingSlash);
  app.use(express.json());

  const getUUID = async (username: string) => {
    const queryRes = await db.queryObject<{
      uuid: string;
      uuidSend: string;
    }>({
      camelcase: true,
      text: `SELECT * FROM get_uuid($1)`,
      args: [username],
    });

    if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

    return queryRes.rows[0];
  };

  app.get(api`status`, (_req, res) =>
    res.status(200).send("Everything works.")
  );

  app.post(api`signup`, async (req, res) => {
    const newUser: Record<string, string> = req.body;

    if (
      Object.entries(newUser).length !== 3 ||
      Object.entries(newUser).some(
        ([k, v]) =>
          k == null ||
          v == null ||
          k.length === 0 ||
          v.length === 0 ||
          (k !== "username" && k !== "email" && k !== "password")
      )
    ) {
      res.status(400).send({ message: `Invalid user data received` });
      return;
    }

    const { username, email, password } = newUser;

    try {
      const queryRes = await db.queryObject(
        `
INSERT INTO
  Users (username, email, password)
VALUES
  ($1,$2,$3);`,
        [username, email, password]
      );

      if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

      res.status(200).send({ message: "Account creation successful" });
    } catch (e) {
      console.error(e);
      res.status(404).send({ error: true });
    }
  });

  app.post(api`signin`, async (req, res) => {
    const user: Record<string, string> = req.body;

    const { username, password, userToken } = user;

    if (username == null || (password == null && userToken == null)) {
      res.status(400).send({ message: `Invalid user data received` });
      return;
    }

    if (password == null && userToken != null) {
      const session = sessions.get(username);

      if (session == null) {
        res.status(400).send({ message: `Token invalid` });
        return;
      }

      const { hash, expires } = session;

      if (expires < Date.now()) {
        sessions.delete(username);

        res.status(400).send({ message: `Token invalid` });

        return;
      }

      const isHashValid = hash === userToken;

      if (isHashValid) {
        sessions.set(username, { hash, expires: Date.now() + WEEK });

        res.status(200).send({
          loggedIn: isHashValid,
          hash: userToken,
          message: isHashValid ? "Signin successful" : "Invalid hash",
        });
        return;
      } else {
        res.status(400).send({ message: `Invalid user data received` });
        return;
      }
    }

    let uuid = "";

    try {
      uuid = (await getUUID(username)).uuid;
    } catch (e) {
      console.error(e);
      res.status(404).send({ error: true, message: "Username not found" });
      return;
    }

    try {
      const queryRes = await db.queryObject<{ success: boolean }>({
        text: `SELECT * FROM validate_sign_in($1, $2)`,
        args: [uuid, password],
        fields: ["success"],
      });

      if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

      const successfulSignin = queryRes.rows[0].success;

      if (successfulSignin) {
        const hash = crypto.randomUUID();
        sessions.set(username, {
          hash,
          expires: Date.now() + WEEK,
        });

        res.status(200).send({
          loggedIn: true,
          hash,
          message: `Signin successful`,
        });
      } else {
        res
          .status(404)
          .send({ error: true, message: "Invalid username or password" });
        return;
      }
    } catch (e) {
      console.error(e);
      res.status(404).send({ error: true });
    }
  });

  // create/delete/renew a token
  app.post(api`token`, async (req, res) => {
    const appName = req.body.appName ?? "";
    const username = req.body.username;
    const providedToken = req.body.token;
    const requestType = req.body.type;

    let processedToken = providedToken;

    if (
      requestType == null ||
      (requestType !== "create" &&
        requestType !== "renew" &&
        requestType !== "delete")
    ) {
      res.status(400).send({ message: `Invalid data received` });
      return;
    }

    if (requestType === "renew" || requestType === "delete") {
      if (providedToken == null || providedToken.length === 0) {
        res.status(400).send({ message: `Invalid data received` });
        return;
      }
    }

    if (requestType === "create") {
      if (providedToken == null || providedToken.length < 4) {
        if (username != null && username.length !== 0) {
          try {
            processedToken = (await getUUID(username)).uuid + ":";
          } catch (e) {
            console.error(e);
            res
              .status(404)
              .send({ error: true, message: "Invalid data received" });
            return;
          }
        } else {
          res
            .status(400)
            .send({ error: true, message: `Invalid data received` });
          return;
        }
      } else {
        processedToken = providedToken;
      }
    }

    interface TokenResponse {
      userID: string;
      message: string;
      token: string;
      renewToken: string;
      deleteToken: string;
      expires: string;
    }

    try {
      const queryRes = await db.queryObject<TokenResponse>({
        camelcase: true,
        text: `SELECT * FROM token_request($1, $2, $3)`,
        args: [processedToken, requestType, appName],
      });

      if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

      res.status(200).send({ result: queryRes.rows[0] });
    } catch (e) {
      console.error(e);
      res
        .status(404)
        .send({ error: true, message: e.fields.message, hint: e.fields.hint });
    }
  });

  // get user trees
  app.get(api`trees`, async (req, res) => {
    const { username, token } = req.query as Record<string, string>;

    if ([username, token].some((v) => v == null || typeof v !== "string")) {
      res.status(404).send({ error: true, message: "Invalid parameters" });
    }

    console.log(req.query);

    let uuid = null;

    try {
      uuid = (await getUUID(username)).uuid;
    } catch (e) {
      console.error(e);
      res.status(404).send({ error: true, message: "Username not found" });
      return;
    }

    const session = sessions.get(username);

    if (session == null) {
      res.status(400).send({ message: `Token invalid` });
      return;
    }

    const { hash, expires } = session;

    if (expires < Date.now()) {
      sessions.delete(username);

      res.status(400).send({ message: `Token invalid` });

      return;
    }

    const isTokenValid = hash === token;

    if (isTokenValid) {
      const queryRes = await db.queryArray({
        text: `SELECT * FROM Trees WHERE ownerID = $1;`,
        args: [uuid],
      });

      if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

      res.status(200).send({
        trees: queryRes.rows,
      });
      return;
    } else {
      res.status(400).send({ message: `Invalid user data received` });
      return;
    }
  });

  // get tree
  app.get(api`tree/:treeID`, async (req, res) => {
    const { username, token } = req.query as Record<string, string>;
    const { treeID } = req.params as Record<string, string>;

    if ([username, token].some((v) => v == null || typeof v !== "string")) {
      res.status(404).send({ error: true, message: "Invalid parameters" });
    }

    if (treeID == null || typeof treeID !== "string") {
      res.status(404).send({ error: true, message: "Invalid parameters" });
    }

    console.log(req.params);
    console.log(req.query);

    let uuid = null;

    try {
      uuid = (await getUUID(username)).uuid;
    } catch (e) {
      console.error(e);
      res.status(404).send({ error: true, message: "Username not found" });
      return;
    }

    const session = sessions.get(username);

    if (session == null) {
      res.status(400).send({ message: `Token invalid` });
      return;
    }

    const { hash, expires } = session;

    if (expires < Date.now()) {
      sessions.delete(username);

      res.status(400).send({ message: `Token invalid` });

      return;
    }

    const isTokenValid = hash === token;

    if (isTokenValid) {
      const queryRes = await db.queryArray({
        text: `SELECT * FROM Trees WHERE ownerID = $1 AND ID = $2;`,
        args: [uuid, treeID],
      });

      if (queryRes.warnings.length !== 0) console.warn(queryRes.warnings);

      res.status(200).send({
        trees: queryRes.rows,
      });
      return;
    } else {
      res.status(400).send({ message: `Invalid user data received` });
      return;
    }
  });

  return app;
};

export default server;
