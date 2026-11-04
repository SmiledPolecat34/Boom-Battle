"use strict";
// Serveur avec comptes : page de connexion, cookie de session, droits par route, administration, portée des conversations, hôtes autorisés.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createServer } = require("../serve");
const { createFileStore } = require("./store-file");
const { createAuth } = require("./service");
const { requiredPermission, parseCookies, sessionCookie } = require("./http");
const { sampleData } = require("../page-helpers");
const P = require("./permissions");

const H = { "X-Registre": "1", "Content-Type": "application/json" };

function request(port, method, url, { headers = {}, body, cookie, host } = {}) {
  return new Promise((resolve, reject) => {
    const h = Object.assign({}, headers);
    if (cookie) h.Cookie = cookie;
    if (host) h.Host = host;
    const req = http.request({ host: "127.0.0.1", port, method, path: url, headers: h }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        resolve({ status: res.statusCode, headers: res.headers, text: buffer.toString("utf8"), json: () => JSON.parse(buffer.toString("utf8")) });
      });
    });
    req.on("error", reject);
    if (body !== undefined) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}
const cookieOf = (res) => (res.headers["set-cookie"] || [])[0] || "";
const pair = (setCookie) => setCookie.split(";")[0];

async function withServer(fn, serverOptions) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), "registre-http-"));
  const store = createFileStore({ dir: path.join(base, "auth") });
  const auth = createAuth({ store });
  await auth.init();
  await auth.ensureAdmins([{ username: "steph-mss" }, { username: "smiledpolecat34" }], "2903");
  const server = createServer(Object.assign({ dir: path.join(base, "c"), runsDir: path.join(base, "r"), dataDir: path.join(base, "data"), initialData: sampleData(), collect: async () => sampleData(), auth }, serverOptions));
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;
  async function login(username, password) {
    const res = await request(port, "POST", "/api/auth/login", { headers: H, body: { username, password } });
    return { res, cookie: pair(cookieOf(res)) };
  }
  try {
    await fn({ port, auth, store, base, login, as: async (u, p) => (await login(u, p)).cookie });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(base, { recursive: true, force: true });
  }
}

test("sans connexion : la page ne montre que la connexion (aucune donnée du projet), l'API répond 401", async () => {
  await withServer(async ({ port }) => {
    const page = await request(port, "GET", "/");
    assert.equal(page.status, 200);
    assert.match(page.text, /Connexion/);
    assert.ok(!page.text.includes("Premiers pas") && !page.text.includes('id="data"'), "aucune donnée du projet");
    for (const [m, u] of [["GET", "/api/tickets"], ["GET", "/api/journal/playtests"], ["GET", "/api/projects"], ["GET", "/api/backup"], ["GET", "/api/chats"], ["POST", "/api/tests/run"], ["GET", "/api/admin/users"], ["GET", "/api/auth/me"], ["GET", "/api/inconnue"]]) {
      const res = await request(port, m, u, { headers: H, body: m === "POST" ? "{}" : undefined });
      assert.equal(res.status, 401, m + " " + u);
      assert.equal(res.json().code, "login_required");
    }
    assert.equal((await request(port, "GET", "/sounds/s123456.wav")).status, 401);
    assert.equal((await request(port, "GET", "/img/autre.png")).status, 401);
    assert.notEqual((await request(port, "GET", "/img/logo.png")).status, 401, "le logo de la page de connexion reste public");
    const garbage = await request(port, "GET", "/", { cookie: "registre_session=" + "a".repeat(43) });
    assert.match(garbage.text, /Connexion/);
  });
});

test("connexion : cookie HttpOnly + SameSite=Strict, en-tête de protection exigé, erreurs sans fuite, déconnexion", async () => {
  await withServer(async ({ port, login }) => {
    assert.equal((await request(port, "POST", "/api/auth/login", { headers: { "Content-Type": "application/json" }, body: { username: "steph-mss", password: "2903" } })).status, 403, "en-tête manquant");
    const bad = await request(port, "POST", "/api/auth/login", { headers: H, body: { username: "steph-mss", password: "faux" } });
    assert.equal(bad.status, 401);
    assert.equal(bad.json().error, "Identifiant ou mot de passe incorrect.");
    assert.ok(!cookieOf(bad));
    assert.equal((await request(port, "POST", "/api/auth/login", { headers: H, body: "{cassé" })).status, 400);
    assert.equal((await request(port, "POST", "/api/auth/login", { headers: H, body: { username: 5, password: [] } })).status, 401);
    const { res, cookie } = await login("steph-mss", "2903");
    assert.equal(res.status, 200);
    const raw = cookieOf(res);
    assert.match(raw, /^registre_session=[A-Za-z0-9_-]{40,};/);
    assert.match(raw, /HttpOnly/);
    assert.match(raw, /SameSite=Strict/);
    assert.match(raw, /Path=\//);
    assert.match(raw, /Max-Age=43200/);
    assert.ok(!/Secure/.test(raw), "pas de Secure en local");
    assert.ok(!res.text.includes("passwordHash") && !res.text.includes(cookie.split("=")[1]), "le jeton n'est pas dans le corps");
    const page = await request(port, "GET", "/", { cookie });
    assert.match(page.text, /"me":\{/);
    assert.match(page.headers["content-security-policy"], /form-action 'self'/);
    assert.equal(page.headers["x-frame-options"], "DENY");
    const out = await request(port, "POST", "/api/auth/logout", { headers: H, cookie });
    assert.match(cookieOf(out), /Max-Age=0/);
    assert.equal((await request(port, "GET", "/api/auth/me", { headers: H, cookie })).status, 401, "session fermée côté serveur");
  });
});

test("connexion : le cookie reçoit Secure en production", async () => {
  await withServer(async ({ port, login }) => {
    assert.match(cookieOf((await login("steph-mss", "2903")).res), /; Secure/);
  }, { secureCookies: true });
  assert.equal(sessionCookie("t", 5, true), "registre_session=t; Path=/; HttpOnly; SameSite=Strict; Max-Age=5; Secure");
  assert.deepEqual(parseCookies("a=1; registre_session=xyz; a=2; b"), { a: "1", registre_session: "xyz" });
});

test("hôtes : un autre nom d'hôte est refusé sauf s'il est autorisé ; l'adresse IP du proxy n'est lue que si on lui fait confiance", async () => {
  await withServer(async ({ port }) => {
    assert.equal((await request(port, "GET", "/", { host: "evil.example.com" })).status, 403);
    assert.equal((await request(port, "GET", "/", { host: "registre.onrender.com" })).status, 200);
    assert.equal((await request(port, "GET", "/", { host: "REGISTRE.onrender.com:443" })).status, 200);
  }, { allowedHosts: ["registre.onrender.com"] });
  await withServer(async ({ port, store, auth }) => {
    for (let i = 0; i < 5; i++) await request(port, "POST", "/api/auth/login", { headers: Object.assign({ "X-Forwarded-For": "203.0.113." + i }, H), body: { username: "steph-mss", password: "faux" } });
    const audit = await store.audit.list();
    assert.ok(audit.some((e) => e.ip && e.ip.startsWith("203.0.113.")), "adresse du proxy enregistrée");
    void auth;
  }, { trustProxy: true });
  await withServer(async ({ port, store }) => {
    await request(port, "POST", "/api/auth/login", { headers: Object.assign({ "X-Forwarded-For": "203.0.113.9" }, H), body: { username: "steph-mss", password: "faux" } });
    assert.ok(!(await store.audit.list()).some((e) => e.ip === "203.0.113.9"), "en-tête usurpable ignoré sans proxy");
  });
});

test("première connexion : mot de passe de départ => page de changement, API bloquée, puis accès normal", async () => {
  await withServer(async ({ port, login, as }) => {
    const admin = await as("steph-mss", "2903");
    const created = await request(port, "POST", "/api/admin/users", { headers: H, cookie: admin, body: { username: "camille", roleId: "lecteur" } });
    assert.equal(created.status, 201);
    const { res, cookie } = await login("camille", "qwerty1234");
    assert.equal(res.json().mustChangePassword, true);
    assert.match((await request(port, "GET", "/", { cookie })).text, /Choisis ton mot de passe|change-form/);
    assert.ok(!(await request(port, "GET", "/", { cookie })).text.includes('"me"'));
    const blocked = await request(port, "GET", "/api/tickets", { headers: H, cookie });
    assert.equal(blocked.status, 403);
    assert.equal(blocked.json().code, "must_change_password");
    assert.equal((await request(port, "GET", "/api/admin/users", { headers: H, cookie })).status, 403);
    assert.equal((await request(port, "GET", "/api/auth/me", { headers: H, cookie })).status, 200);
    const weak = await request(port, "POST", "/api/auth/password", { headers: H, cookie, body: { current: "qwerty1234", next: "qwerty1234" } });
    assert.equal(weak.status, 422);
    const ok = await request(port, "POST", "/api/auth/password", { headers: H, cookie, body: { current: "qwerty1234", next: "MonNouveauMdp26" } });
    assert.equal(ok.status, 200);
    assert.equal((await request(port, "GET", "/api/tickets", { headers: H, cookie })).status, 200);
    assert.match((await request(port, "GET", "/", { cookie })).text, /"me":\{/);
  });
});

test("droits : chaque route exige sa permission (lecteur, rôle sur mesure, administrateur) ; routes inconnues = 404", async () => {
  await withServer(async ({ port, auth, as, store }) => {
    const admin = await as("steph-mss", "2903");
    const mk = async (username, roleId) => {
      await request(port, "POST", "/api/admin/users", { headers: H, cookie: admin, body: { username, roleId, password: "MotDePasse2026a", mustChangePassword: false } });
      return as(username, "MotDePasse2026a");
    };
    const lecteur = await mk("lecteur1", "lecteur");
    const roleRes = await request(port, "POST", "/api/admin/roles", { headers: H, cookie: admin, body: { name: "Trieur", permissions: ["tickets.view", "tickets.move", "journal.playtests.view", "journal.playtests.create"] } });
    assert.equal(roleRes.status, 201);
    const trieur = await mk("trieur1", roleRes.json().id);
    const ticket = await request(port, "POST", "/api/tickets", { headers: H, cookie: admin, body: { title: "Un ticket de test" } });
    const id = ticket.json().id;

    const expect = async (cookie, method, url, status, body) => {
      const res = await request(port, method, url, { headers: H, cookie, body: body === undefined ? (method === "GET" || method === "DELETE" ? undefined : "{}") : body });
      assert.equal(res.status, status, method + " " + url + " attendu " + status + " obtenu " + res.status + " " + res.text.slice(0, 100));
      return res;
    };
    await expect(lecteur, "GET", "/api/tickets", 200);
    await expect(lecteur, "POST", "/api/tickets", 403, { title: "interdit" });
    await expect(lecteur, "PATCH", "/api/tickets/" + id, 403, { title: "interdit" });
    await expect(lecteur, "POST", "/api/tickets/" + id + "/move", 403, { status: "done" });
    await expect(lecteur, "POST", "/api/tickets/" + id + "/comments", 403, { text: "non" });
    await expect(lecteur, "DELETE", "/api/tickets/" + id, 403);
    await expect(lecteur, "GET", "/api/journal/playtests", 200);
    await expect(lecteur, "POST", "/api/journal/playtests", 403, {});
    await expect(lecteur, "GET", "/api/projects", 200);
    await expect(lecteur, "POST", "/api/projects", 403, { source: "github", url: "https://github.com/a/b" });
    await expect(lecteur, "POST", "/api/projects/pick-folder", 403);
    await expect(lecteur, "DELETE", "/api/projects/p0123456789abcdef", 403);
    await expect(lecteur, "GET", "/api/backup", 403);
    await expect(lecteur, "POST", "/api/backup", 403, {});
    await expect(lecteur, "POST", "/api/tests/run", 403, {});
    await expect(lecteur, "GET", "/api/admin/users", 403);
    await expect(lecteur, "GET", "/api/admin/roles", 403);
    await expect(lecteur, "GET", "/api/admin/audit", 403);
    await expect(lecteur, "PUT", "/api/admin/settings", 403, {});
    await expect(lecteur, "GET", "/api/schema", 200);

    await expect(trieur, "POST", "/api/tickets/" + id + "/move", 200, { status: "doing" });
    await expect(trieur, "PATCH", "/api/tickets/" + id, 403, { title: "non" });
    await expect(trieur, "POST", "/api/journal/playtests", 201, { date: "2026-11-04", scenario: "2 clients", result: "ok" });
    await expect(trieur, "PUT", "/api/journal/playtests/jabcdef01", 403, {});
    await expect(trieur, "GET", "/api/journal/decisions", 403);
    await expect(trieur, "GET", "/api/activity", 403);
    await expect(trieur, "GET", "/api/sounds", 403);

    await expect(admin, "GET", "/api/inconnue", 404);
    await expect(admin, "GET", "/api/journal/inconnue", 404);
    await expect(admin, "DELETE", "/api/tickets", 404);
    await expect(admin, "GET", "/api/backup", 200);
    await expect(admin, "GET", "/api/activity", 200);
    assert.equal((await expect(trieur, "GET", "/api/tests/latest", 403)).json().code, "forbidden");
    void auth; void store;
  });
});

test("table des droits : chaque route connue de l'application a une permission valide ou « toute personne connectée »", () => {
  const routes = [["GET", "/api/projects"], ["POST", "/api/projects"], ["GET", "/api/projects/boom"], ["PATCH", "/api/projects/boom"], ["DELETE", "/api/projects/luma"], ["POST", "/api/projects/p0123456789abcdef/refresh"], ["GET", "/api/storage"], ["GET", "/api/settings"], ["PUT", "/api/settings"],
    ["GET", "/api/chats"], ["DELETE", "/api/chats"], ["PUT", "/api/chats/cabcdef12"], ["GET", "/api/sounds"], ["POST", "/api/sounds"], ["PUT", "/api/sounds/sabcdef12"], ["DELETE", "/api/sounds/sabcdef12"], ["GET", "/api/schema"], ["GET", "/api/activity"],
    ["GET", "/api/tickets"], ["POST", "/api/tickets"], ["GET", "/api/tickets/tabc"], ["PATCH", "/api/tickets/tabc"], ["DELETE", "/api/tickets/tabc"], ["POST", "/api/tickets/tabc/move"], ["POST", "/api/tickets/tabc/comments"], ["DELETE", "/api/tickets/tabc/comments/kabc"],
    ["GET", "/api/journal/seeds"], ["POST", "/api/journal/seeds"], ["PUT", "/api/journal/seeds/jabc"], ["DELETE", "/api/journal/seeds/jabc"], ["GET", "/api/backup"], ["POST", "/api/backup"], ["GET", "/api/contributions"], ["POST", "/api/contributions"], ["DELETE", "/api/contributions/123"],
    ["POST", "/api/refresh"], ["GET", "/api/tests/latest"], ["POST", "/api/tests/run"]];
  for (const [m, u] of routes) {
    const perm = requiredPermission(m, u);
    assert.notEqual(perm, undefined, m + " " + u);
    for (const x of Array.isArray(perm) ? perm : perm === null ? [] : [perm]) assert.ok(P.isPermission(x), x);
  }
  for (const [m, u] of [["PATCH", "/api/tickets"], ["GET", "/api/tickets/tabc/move"], ["DELETE", "/api/settings"], ["GET", "/api/n-importe-quoi"], ["GET", "/api/journal/inconnue"], ["POST", "/api/tickets/tabc/comments/kabc"], ["PUT", "/api/projects"]]) assert.equal(requiredPermission(m, u), undefined, m + " " + u);
  assert.equal(requiredPermission("POST", "/api/projects"), "projects.add");
  assert.equal(P.isAdminOnly("projects.add"), true);
});

test("projets : seuls les administrateurs peuvent en ajouter, même avec un rôle qui contient tous les autres droits", async () => {
  await withServer(async ({ port, as, store }) => {
    const admin = await as("steph-mss", "2903");
    // Un rôle qui tente de contenir « projects.add » est refusé à la création ; un rôle falsifié dans la base est neutralisé à l'usage.
    const refused = await request(port, "POST", "/api/admin/roles", { headers: H, cookie: admin, body: { name: "Chef", permissions: ["projects.add", "projects.view"] } });
    assert.equal(refused.status, 422);
    assert.match(refused.json().error, /réservée aux administrateurs/);
    const ok = await request(port, "POST", "/api/admin/roles", { headers: H, cookie: admin, body: { name: "Chef", permissions: P.GRANTABLE_IDS } });
    assert.equal(ok.status, 201);
    await request(port, "POST", "/api/admin/users", { headers: H, cookie: admin, body: { username: "chef", roleId: ok.json().id, password: "MotDePasse2026c", mustChangePassword: false } });
    await store.roles.update(ok.json().id, { permissions: P.ALL_IDS });
    const chef = await as("chef", "MotDePasse2026c");
    for (const [m, u, b] of [["POST", "/api/projects", { source: "github", url: "https://github.com/a/b" }], ["POST", "/api/projects/pick-folder", {}], ["DELETE", "/api/projects/p0123456789abcdef"], ["POST", "/api/admin/roles", { name: "Autre", permissions: [] }], ["GET", "/api/backup"]]) {
      assert.equal((await request(port, m, u, { headers: H, cookie: chef, body: b === undefined ? undefined : JSON.stringify(b) })).status, 403, m + " " + u);
    }
    assert.equal((await request(port, "GET", "/api/projects", { headers: H, cookie: chef })).status, 200);
  });
});

test("conversations et réglages : propres à chaque personne ; la sauvegarde n'exporte que les siens", async () => {
  await withServer(async ({ port, as }) => {
    const a = await as("steph-mss", "2903");
    const b = await as("smiledpolecat34", "2903");
    const chat = (id, title) => ({ id, title, createdAt: 1, updatedAt: 2, messages: [{ role: "user", content: "Bonjour" }] });
    assert.equal((await request(port, "PUT", "/api/chats/cabcdef01", { headers: H, cookie: a, body: chat("cabcdef01", "À Stéph") })).status, 200);
    assert.equal((await request(port, "PUT", "/api/chats/cabcdef02", { headers: H, cookie: b, body: chat("cabcdef02", "À Smiled") })).status, 200);
    assert.deepEqual((await request(port, "GET", "/api/chats", { headers: H, cookie: a })).json().map((c) => c.title), ["À Stéph"]);
    assert.deepEqual((await request(port, "GET", "/api/chats", { headers: H, cookie: b })).json().map((c) => c.title), ["À Smiled"]);
    assert.equal((await request(port, "DELETE", "/api/chats/cabcdef01", { headers: H, cookie: b })).status, 404, "impossible de supprimer la conversation d'un autre");
    await request(port, "PUT", "/api/settings", { headers: H, cookie: a, body: { tab: "sons" } });
    assert.deepEqual((await request(port, "GET", "/api/settings", { headers: H, cookie: b })).json(), {});
    assert.deepEqual((await request(port, "GET", "/api/settings", { headers: H, cookie: a })).json(), { tab: "sons" });
    const backup = (await request(port, "GET", "/api/backup", { headers: H, cookie: a })).json();
    assert.deepEqual(backup.chats.map((c) => c.title), ["À Stéph"]);
    assert.ok(!JSON.stringify(backup).includes("À Smiled"));
    assert.equal((await request(port, "DELETE", "/api/chats", { headers: H, cookie: a })).json().removed, 1);
    assert.equal((await request(port, "GET", "/api/chats", { headers: H, cookie: b })).json().length, 1, "tout effacer ne touche que ses propres conversations");
  });
});

test("administration par l'API : comptes, rôles, réglages, sessions, journal de sécurité ; identifiants et corps hostiles", async () => {
  await withServer(async ({ port, as }) => {
    const admin = await as("steph-mss", "2903");
    const call = (m, u, b, cookie) => request(port, m, u, { headers: H, cookie: cookie || admin, body: b === undefined ? undefined : b });
    const list = (await call("GET", "/api/admin/users")).json();
    assert.deepEqual(list.map((u) => u.username).sort(), ["smiledpolecat34", "steph-mss"]);
    assert.ok(list.every((u) => !("passwordHash" in u) && u.roleId === "admin"));
    const created = (await call("POST", "/api/admin/users", { username: "Nouvelle-Personne", displayName: "Nouvelle", roleId: "contributeur" })).json();
    assert.equal(created.username, "nouvelle-personne");
    assert.equal(created.mustChangePassword, true);
    assert.equal((await call("POST", "/api/admin/users", { username: "nouvelle-personne", roleId: "lecteur" })).status, 409);
    assert.equal((await call("PATCH", "/api/admin/users/" + created.id, { displayName: "Nouvelle P." })).json().displayName, "Nouvelle P.");
    assert.equal((await call("PATCH", "/api/admin/users/" + created.id, { disabled: true })).json().disabled, true);
    assert.equal((await call("POST", "/api/admin/users/" + created.id + "/reset-password", {})).json().usedDefault, true);
    assert.equal((await call("GET", "/api/admin/users/" + created.id + "/sessions")).status, 200);
    assert.equal((await call("DELETE", "/api/admin/users/" + created.id + "/sessions")).json().closed, 0);
    const roles = (await call("GET", "/api/admin/roles")).json();
    assert.equal(roles[0].id, "admin");
    const catalog = (await call("GET", "/api/admin/permissions")).json();
    assert.ok(catalog.length >= 10 && catalog.every((c) => c.permissions.length > 0));
    assert.equal((await call("GET", "/api/admin/settings")).json().defaultPassword, "qwerty1234");
    assert.equal((await call("PUT", "/api/admin/settings", { lockMinutes: 5 })).json().lockMinutes, 5);
    assert.ok((await call("GET", "/api/admin/audit?limit=50")).json().some((e) => e.action === "compte_cree"));
    assert.equal((await call("DELETE", "/api/admin/users/" + created.id)).status, 200);
    // hostile
    for (const [m, u] of [["PATCH", "/api/admin/users/..%2f..%2fx"], ["DELETE", "/api/admin/users/x"], ["PUT", "/api/admin/roles/Admin"], ["DELETE", "/api/admin/roles/..%2fx"], ["GET", "/api/admin/inconnue"], ["POST", "/api/admin/users/u0123456789abcdef/inconnu"]]) {
      const res = await call(m, u, m === "GET" || m === "DELETE" ? undefined : "{}");
      assert.ok([404, 400].includes(res.status), m + " " + u + " → " + res.status);
    }
    assert.equal((await call("POST", "/api/admin/users", "{cassé")).status, 400);
    assert.equal((await call("POST", "/api/admin/users", "x".repeat(10000))).status, 413);
    assert.equal((await call("POST", "/api/admin/users", { username: "ok-nom", roleId: "admin__proto__" })).status, 422);
    assert.equal((await call("PATCH", "/api/admin/users/u0123456789abcdef", { displayName: "xx" })).status, 404);
  });
});

test("sécurité : un compte désactivé est expulsé tout de suite ; un mot de passe changé ferme les autres connexions ; un rôle supprimé retire les droits", async () => {
  await withServer(async ({ port, as, login }) => {
    const admin = await as("steph-mss", "2903");
    const call = (m, u, b, cookie) => request(port, m, u, { headers: H, cookie: cookie || admin, body: b });
    const u = (await call("POST", "/api/admin/users", { username: "tempo", roleId: "lecteur", password: "MotDePasse2026d", mustChangePassword: false })).json();
    const tempo = await as("tempo", "MotDePasse2026d");
    assert.equal((await call("GET", "/api/tickets", undefined, tempo)).status, 200);
    await call("PATCH", "/api/admin/users/" + u.id, { disabled: true });
    assert.equal((await call("GET", "/api/tickets", undefined, tempo)).status, 401);
    assert.equal((await login("tempo", "MotDePasse2026d")).res.status, 401);
    await call("PATCH", "/api/admin/users/" + u.id, { disabled: false });
    const again = await as("tempo", "MotDePasse2026d");
    const second = await as("tempo", "MotDePasse2026d");
    assert.equal((await call("POST", "/api/auth/password", { current: "MotDePasse2026d", next: "AutreSolide2026" }, again)).status, 200);
    assert.equal((await call("GET", "/api/tickets", undefined, second)).status, 401, "l'autre session est fermée");
    assert.equal((await call("GET", "/api/tickets", undefined, again)).status, 200);
    assert.equal((await call("PATCH", "/api/auth/profile", { displayName: "Tempo Test" }, again)).json().displayName, "Tempo Test");
    assert.equal((await call("PATCH", "/api/auth/profile", { displayName: "x" }, again)).status, 422);
  });
});
