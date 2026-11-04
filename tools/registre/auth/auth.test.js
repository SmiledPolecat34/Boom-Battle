"use strict";
// Comptes et rôles : catalogue de permissions, mots de passe, stockage (fichiers ET PostgreSQL simulé en mémoire), connexion, sessions, garde-fous.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const P = require("./permissions");
const { hashPassword, verifyPassword, checkNewPassword } = require("./passwords");
const { createFileStore } = require("./store-file");
const { createPgStore } = require("./store-pg");
const { createAuth, AuthError } = require("./service");

// ----- permissions -----------------------------------------------------------------------------------------------------
test("permissions : identifiants uniques, catégories complètes, une série de droits par rubrique de journal", () => {
  assert.equal(new Set(P.ALL_IDS).size, P.ALL_IDS.length);
  assert.ok(P.PERMISSIONS.every((x) => x.id && x.label && x.description && x.category));
  const { SCHEMAS } = require("../journal");
  for (const s of SCHEMAS) for (const a of ["view", "create", "edit", "delete"]) assert.ok(P.isPermission("journal." + s.id + "." + a), s.id + "." + a);
  for (const id of ["projects.add", "projects.remove", "roles.manage", "security.settings", "users.delete", "storage.export", "storage.import"]) assert.equal(P.isAdminOnly(id), true, id);
  assert.equal(P.isAdminOnly("tickets.view"), false);
  assert.equal(P.adminRole().permissions.length, P.ALL_IDS.length);
});

test("permissions : un rôle personnalisé refuse l'inconnu, les doublons, les droits réservés aux admins et les mauvais types", () => {
  assert.equal(P.checkRolePermissions(["tickets.view", "tickets.move"]).ok, true);
  for (const bad of [null, "x", {}, [1], [null], ["inconnue.permission"], ["tickets.view", "tickets.view"], ["projects.add"], ["roles.manage"], ["__proto__"], ["constructor"], [["tickets.view"]]]) assert.equal(P.checkRolePermissions(bad).ok, false, JSON.stringify(bad));
  assert.deepEqual(P.checkRolePermissions(["tickets.move", "tickets.view"]).clean, ["tickets.view", "tickets.move"], "ordre du catalogue");
  for (const r of P.STARTER_ROLES) assert.equal(P.checkRolePermissions(r.permissions).ok, true, r.id);
});

// ----- mots de passe -----------------------------------------------------------------------------------------------------
test("mots de passe : haché avec sel (deux hachages différents), vérifié, jamais en clair", async () => {
  const a = await hashPassword("monSecret2026"), b = await hashPassword("monSecret2026");
  assert.notEqual(a, b);
  assert.ok(!a.includes("monSecret2026"));
  assert.match(a, /^scrypt\$16384\$8\$1\$/);
  assert.equal(await verifyPassword("monSecret2026", a), true);
  assert.equal(await verifyPassword("monSecret2027", a), false);
  assert.equal(await verifyPassword("", a), false);
  for (const stored of [null, undefined, "", "x", "scrypt$1$2", "bcrypt$1$1$1$a$b", "scrypt$0$8$1$QQ==$QQ==", "scrypt$16384$8$1$QQ==$QQ==", "scrypt$99999999$8$1$QQ==" + "$" + "A".repeat(100)]) assert.equal(await verifyPassword("monSecret2026", stored), false, String(stored));
  for (const pw of [null, undefined, 5, {}, "x".repeat(200)]) assert.equal(await verifyPassword(pw, a), false);
  await assert.rejects(hashPassword(""), /invalide/);
  await assert.rejects(hashPassword("x".repeat(200)), /invalide/);
});

test("mots de passe : règles d'un nouveau mot de passe", () => {
  const ctx = { username: "steph-mss", defaultPassword: "qwerty1234", current: "ancien1234" };
  assert.equal(checkNewPassword("Solide2026ok", ctx), null);
  const bad = ["court1", "seulementdeslettres", "12345678901", "qwerty1234", "Qwerty1234", "motdepasse", "steph-mss2026", "ancien1234", "a\u0000bcdefg1", "x".repeat(129) + "1", 5, null];
  for (const pw of bad) assert.notEqual(checkNewPassword(pw, ctx), null, String(pw));
});

// ----- contrat commun des stockages -----------------------------------------------------------------------------------
async function makeStores() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-auth-"));
  const { newDb } = require("pg-mem");
  const { Pool } = newDb().adapters.createPg();
  const out = [
    { name: "fichiers", store: createFileStore({ dir }), cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) },
    { name: "postgresql (simulé)", store: createPgStore({ pool: new Pool() }), cleanup: () => {} },
  ];
  for (const s of out) await s.store.init();
  return out;
}
const user = (o) => Object.assign({ id: "u1", username: "alice", displayName: "Alice", passwordHash: "h", roleId: "admin", mustChangePassword: false, disabled: false, failedLogins: 0, lockedUntil: 0, lastLoginAt: null, createdAt: 1000, updatedAt: 1000, createdBy: "installation" }, o);

test("stockage (fichiers et PostgreSQL) : comptes — créer, lire, modifier, doublon, supprimer en cascade", async () => {
  for (const { name, store, cleanup } of await makeStores()) {
    try {
      const m = (s) => name + " : " + s;
      await store.users.insert(user());
      await store.users.insert(user({ id: "u2", username: "bob", createdAt: 2000 }));
      assert.deepEqual((await store.users.list()).map((u) => u.username), ["alice", "bob"], m("tri par création"));
      assert.equal((await store.users.getByUsername("bob")).id, "u2", m("par nom"));
      assert.equal(await store.users.getById("nope"), null, m("inconnu"));
      await assert.rejects(store.users.insert(user({ id: "u3", username: "alice" })), (e) => e.code === "duplicate", m("nom en double"));
      await assert.rejects(store.users.insert(user({ id: "u1", username: "autre" })), (e) => e.code === "duplicate", m("id en double"));
      const upd = await store.users.update("u1", { displayName: "Alice B", failedLogins: 3, lockedUntil: 99, lastLoginAt: 5, mustChangePassword: true, disabled: true });
      assert.deepEqual([upd.displayName, upd.failedLogins, upd.lockedUntil, upd.lastLoginAt, upd.mustChangePassword, upd.disabled], ["Alice B", 3, 99, 5, true, true], m("modification"));
      assert.equal((await store.users.getById("u1")).passwordHash, "h", m("le reste est intact"));
      await assert.rejects(store.users.update("u1", { username: "bob" }), (e) => e.code === "duplicate", m("renommage en double"));
      assert.equal(await store.users.update("absent", { displayName: "x" }), null, m("modifier un absent"));
      await assert.rejects(store.users.update("u1", { motDePasse: "x" }), m("champ inconnu refusé"));
      await store.sessions.insert({ hash: "s1", userId: "u2", createdAt: 1, lastSeenAt: 1, expiresAt: 10, ip: "1.1.1.1", userAgent: "x" });
      assert.equal(await store.users.delete("u2"), true, m("suppression"));
      assert.equal(await store.sessions.getByHash("s1"), null, m("sessions supprimées avec le compte"));
      assert.equal(await store.users.delete("u2"), false, m("déjà supprimé"));
      assert.equal(await store.users.count(), 1, m("compte"));
    } finally {
      cleanup();
    }
  }
});

test("stockage (fichiers et PostgreSQL) : rôles, sessions, journal de sécurité, réglages", async () => {
  for (const { name, store, cleanup } of await makeStores()) {
    try {
      const m = (s) => name + " : " + s;
      await store.roles.insert({ id: "lecteur", name: "Lecteur", description: "d", permissions: ["tickets.view"], createdAt: 1, updatedAt: 1 });
      await assert.rejects(store.roles.insert({ id: "lecteur2", name: "Lecteur", description: "", permissions: [], createdAt: 2, updatedAt: 2 }), (e) => e.code === "duplicate", m("nom de rôle en double"));
      const r = await store.roles.update("lecteur", { permissions: ["tickets.view", "tickets.move"], name: "Lecteur+", updatedAt: 5 });
      assert.deepEqual(r.permissions, ["tickets.view", "tickets.move"], m("permissions relues en tableau"));
      assert.equal((await store.roles.get("lecteur")).name, "Lecteur+", m("nom"));
      await store.users.insert(user({ roleId: "lecteur" }));
      assert.equal(await store.roles.countUsers("lecteur"), 1, m("nombre d'utilisateurs du rôle"));
      assert.equal(await store.roles.delete("lecteur"), true, m("suppression du rôle"));
      assert.equal(await store.roles.get("lecteur"), null, m("rôle supprimé"));

      await store.sessions.insert({ hash: "a", userId: "u1", createdAt: 1, lastSeenAt: 10, expiresAt: 100, ip: "", userAgent: "" });
      await store.sessions.insert({ hash: "b", userId: "u1", createdAt: 2, lastSeenAt: 20, expiresAt: 5, ip: "", userAgent: "" });
      assert.deepEqual((await store.sessions.listByUser("u1")).map((s) => s.hash), ["b", "a"], m("tri par dernière activité"));
      assert.equal((await store.sessions.update("a", { lastSeenAt: 50, expiresAt: 200 })).expiresAt, 200, m("mise à jour de session"));
      assert.equal(await store.sessions.purgeExpired(10), 1, m("purge des sessions expirées"));
      assert.equal(await store.sessions.deleteByUser("u1", "a"), 0, m("on garde la session indiquée"));
      assert.equal(await store.sessions.deleteByUser("u1"), 1, m("on ferme le reste"));

      for (let i = 1; i <= 3; i++) await store.audit.add({ at: i, actor: "alice", action: "a" + i, target: null, detail: null, ip: null });
      assert.deepEqual((await store.audit.list(2)).map((e) => e.action), ["a3", "a2"], m("le plus récent d'abord, limité"));
      assert.equal((await store.audit.list()).length, 3, m("liste complète"));

      assert.deepEqual(await store.settings.get(), {}, m("réglages vides"));
      await store.settings.put({ sessionHours: 8 });
      await store.settings.put({ lockMinutes: 30 });
      assert.deepEqual(await store.settings.get(), { sessionHours: 8, lockMinutes: 30 }, m("les réglages se complètent"));
    } finally {
      cleanup();
    }
  }
});

test("stockage PostgreSQL : les migrations sont rejouables sans erreur ni doublon", async () => {
  const { newDb } = require("pg-mem");
  const { Pool } = newDb().adapters.createPg();
  const store = createPgStore({ pool: new Pool() });
  await store.init();
  await store.init();
  await store.users.insert(user());
  assert.equal(await store.users.count(), 1);
});

// ----- service -----------------------------------------------------------------------------------------------------------
async function setup(opts) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-svc-"));
  let t = 1800000000000;
  const clock = () => t;
  const store = createFileStore({ dir });
  const auth = createAuth({ store, clock });
  await auth.init();
  await auth.ensureAdmins([{ username: "steph-mss", displayName: "steph-mss" }, { username: "SmiledPolecat34", displayName: "SmiledPolecat34" }], "2903");
  const tick = (ms) => { t += ms; };
  const ctx = { ip: "10.0.0.1", userAgent: "test" };
  async function actorOf(username, password) {
    const r = await auth.login(username, password, ctx);
    return Object.assign(await auth.resolve(r.token), { token: r.token });
  }
  void opts;
  return { auth, store, tick, ctx, actorOf, now: clock, cleanup: () => fs.rmSync(dir, { recursive: true, force: true }) };
}
const rejects = (promise, status, pattern) => assert.rejects(promise, (e) => e instanceof AuthError && e.status === status && (!pattern || pattern.test(e.message)), "attendu : " + status + " " + (pattern || ""));

test("installation : les deux administrateurs sont créés une seule fois, avec le rôle admin et sans changement de mot de passe imposé", async () => {
  const s = await setup();
  try {
    const users = await s.store.users.list();
    assert.deepEqual(users.map((u) => u.username).sort(), ["smiledpolecat34", "steph-mss"]);
    assert.ok(users.every((u) => u.roleId === "admin" && u.mustChangePassword === false && u.passwordHash.startsWith("scrypt$") && !u.passwordHash.includes("2903")));
    assert.deepEqual(await s.auth.ensureAdmins([{ username: "steph-mss" }], "autre"), [], "idempotent");
    const roles = await s.store.roles.list();
    assert.deepEqual(roles.map((r) => r.id).sort(), ["contributeur", "lecteur", "testeur"], "rôles de départ");
    await s.auth.init();
    assert.equal((await s.store.roles.list()).length, 3, "les rôles de départ ne reviennent pas après suppression ni doublon");
    await assert.rejects(s.auth.ensureAdmins([{ username: "x" }], "2903"), AuthError);
  } finally { s.cleanup(); }
});

test("connexion : réussie (insensible à la casse), session valide, droits d'administrateur complets", async () => {
  const s = await setup();
  try {
    const r = await s.auth.login("  SMILEDPOLECAT34 ", "2903", s.ctx);
    assert.match(r.token, /^[A-Za-z0-9_-]{40,}$/);
    assert.equal(r.mustChangePassword, false);
    assert.equal(r.user.roleId, "admin");
    assert.ok(!JSON.stringify(r).includes("passwordHash"));
    const actor = await s.auth.resolve(r.token);
    assert.equal(actor.permissions.size, P.ALL_IDS.length);
    const me = await s.auth.me(actor);
    assert.equal(me.admin, true);
    assert.ok(me.permissions.includes("projects.add"));
    const stored = await s.store.sessions.getByHash(require("node:crypto").createHash("sha256").update(r.token).digest("hex"));
    assert.ok(stored, "seule l'empreinte du jeton est stockée");
    assert.equal(await s.store.sessions.getByHash(r.token), null);
  } finally { s.cleanup(); }
});

test("connexion : erreurs identiques pour mot de passe faux, compte inconnu et compte désactivé ; saisies hostiles refusées", async () => {
  const s = await setup();
  try {
    const messages = new Set();
    for (const [u, p] of [["steph-mss", "mauvais"], ["personne", "2903"], ["", ""], [null, "x"], ["steph-mss", null], [{}, []], ["x".repeat(500), "x"], ["steph-mss", "x".repeat(500)]]) {
      try { await s.auth.login(u, p, s.ctx); assert.fail("devait échouer"); } catch (e) { assert.ok(e instanceof AuthError); messages.add(e.status + e.message); }
    }
    assert.deepEqual([...messages], ["401Identifiant ou mot de passe incorrect."]);
    const admin = await s.actorOf("steph-mss", "2903");
    const other = await s.store.users.getByUsername("smiledpolecat34");
    await s.auth.updateUser(admin, other.id, { disabled: true });
    await rejects(s.auth.login("smiledpolecat34", "2903", { ip: "10.9.9.9" }), 401, /incorrect/);
    const entries = (await s.store.audit.list()).filter((e) => e.action === "connexion_refusee");
    assert.ok(entries.length >= 6);
    assert.ok(entries.every((e) => !JSON.stringify(e).includes("mauvais")), "aucun mot de passe dans le journal");
  } finally { s.cleanup(); }
});

test("connexion : verrouillage après 5 échecs (même message pour un nom inconnu), puis déblocage après le délai", async () => {
  const s = await setup();
  try {
    for (let i = 0; i < 5; i++) await assert.rejects(s.auth.login("steph-mss", "faux" + i, s.ctx), (e) => e.status === 401);
    await rejects(s.auth.login("steph-mss", "2903", s.ctx), 429, /Trop d'essais/);
    for (let i = 0; i < 5; i++) await assert.rejects(s.auth.login("inconnu", "faux", { ip: "10.1.1.1" }), (e) => e.status === 401);
    await rejects(s.auth.login("inconnu", "faux", { ip: "10.1.1.1" }), 429, /Trop d'essais/);
    await rejects(s.auth.login("steph-mss", "2903", { ip: "10.2.2.2" }), 401, /incorrect/); // autre adresse : le compte lui-même est verrouillé
    s.tick(16 * 60000);
    const ok = await s.auth.login("steph-mss", "2903", s.ctx);
    assert.ok(ok.token);
    assert.equal((await s.store.users.getByUsername("steph-mss")).failedLogins, 0);
  } finally { s.cleanup(); }
});

test("sessions : expiration, prolongation glissante, plafond absolu, compte désactivé, déconnexion, jetons falsifiés", async () => {
  const s = await setup();
  try {
    const r = await s.auth.login("steph-mss", "2903", s.ctx);
    assert.ok(await s.auth.resolve(r.token));
    s.tick(11 * 3600000);
    assert.ok(await s.auth.resolve(r.token), "toujours valide, et prolongée");
    s.tick(11 * 3600000);
    assert.ok(await s.auth.resolve(r.token), "prolongée par l'activité");
    s.tick(13 * 3600000);
    assert.equal(await s.auth.resolve(r.token), null, "inactive plus de 12 h");
    const r2 = await s.auth.login("steph-mss", "2903", s.ctx);
    for (let i = 0; i < 8; i++) { s.tick(10 * 3600000); await s.auth.resolve(r2.token); }
    s.tick(10 * 3600000 * 12);
    assert.equal(await s.auth.resolve(r2.token), null, "plafond absolu de 7 jours");
    const r3 = await s.auth.login("steph-mss", "2903", s.ctx);
    await s.auth.logout(r3.token, s.ctx);
    assert.equal(await s.auth.resolve(r3.token), null, "déconnecté");
    for (const bad of [null, undefined, "", "x", "a".repeat(200), {}, 5, "../../etc"]) assert.equal(await s.auth.resolve(bad), null, String(bad));
    await s.auth.logout("inconnu-token-inconnu-token-inconnu", s.ctx); // sans effet, sans erreur
  } finally { s.cleanup(); }
});

test("mot de passe : changement avec contrôles, fermeture des autres sessions, journal ; le mot de passe de départ impose un changement", async () => {
  const s = await setup();
  try {
    const admin = await s.actorOf("steph-mss", "2903");
    const created = await s.auth.createUser(admin, { username: "Camille", roleId: "lecteur" }, s.ctx);
    assert.equal(created.username, "camille");
    assert.equal(created.mustChangePassword, true);
    const login = await s.auth.login("camille", "qwerty1234", s.ctx);
    assert.equal(login.mustChangePassword, true);
    const me = await s.auth.resolve(login.token);
    const other = await s.auth.login("camille", "qwerty1234", s.ctx);
    await rejects(s.auth.changePassword(me, { current: "faux", next: "NouveauSolide26" }, s.ctx), 403, /ancien/);
    for (const next of ["court1", "lettresseulement", "qwerty1234", "camille12345", "Qwerty1234"]) await rejects(s.auth.changePassword(me, { current: "qwerty1234", next }, s.ctx), 422);
    for (const body of [null, {}, { current: "qwerty1234" }, { current: 5, next: "x" }]) await rejects(s.auth.changePassword(me, body, s.ctx), 422);
    await s.auth.changePassword(me, { current: "qwerty1234", next: "NouveauSolide26" }, s.ctx);
    assert.equal((await s.auth.login("camille", "NouveauSolide26", s.ctx)).mustChangePassword, false);
    await rejects(s.auth.login("camille", "qwerty1234", s.ctx), 401);
    assert.ok(await s.auth.resolve(login.token), "la session qui a changé le mot de passe reste ouverte");
    assert.equal(await s.auth.resolve(other.token), null, "les autres sessions sont fermées");
    const actions = (await s.store.audit.list()).map((e) => e.action);
    assert.ok(actions.includes("mdp_change") && actions.includes("changement_mdp_refuse"));
    assert.ok(!JSON.stringify(await s.store.audit.list()).includes("NouveauSolide26"));
  } finally { s.cleanup(); }
});

test("profil : changer son nom affiché (2 à 40 caractères), rien d'autre", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    assert.equal((await s.auth.updateProfile(a, { displayName: "  Stéphane " })).displayName, "Stéphane");
    for (const bad of [null, {}, { displayName: "" }, { displayName: "x" }, { displayName: "x".repeat(41) }, { displayName: "   " }, { displayName: 5 }, { displayName: "a\u0000b" }]) await rejects(s.auth.updateProfile(a, bad), 422);
    assert.equal((await s.store.users.getById(a.user.id)).username, "steph-mss", "le nom d'utilisateur ne change pas");
  } finally { s.cleanup(); }
});

test("comptes : création (validation, doublon, mot de passe de départ), liste, modification, réinitialisation, suppression", async () => {
  const s = await setup();
  try {
    const admin = await s.actorOf("steph-mss", "2903");
    for (const bad of [null, {}, { username: "ab", roleId: "lecteur" }, { username: "Bad Name", roleId: "lecteur" }, { username: "-x-x", roleId: "lecteur" }, { username: "ok-name", roleId: "inconnu" }, { username: "ok-name" }, { username: "ok-name", roleId: "lecteur", displayName: "x" }, { username: "ok-name", roleId: "lecteur", password: "court" }, { username: "ok-name", roleId: "lecteur", password: 5 }, { username: "x".repeat(40), roleId: "lecteur" }]) await rejects(s.auth.createUser(admin, bad, s.ctx), 422);
    const ok = await s.auth.createUser(admin, { username: "lea", displayName: "Léa", roleId: "testeur", password: "MotDePasseUnique1", mustChangePassword: false }, s.ctx);
    assert.equal(ok.mustChangePassword, false);
    await rejects(s.auth.createUser(admin, { username: "LEA", roleId: "lecteur" }, s.ctx), 409);
    const forced = await s.auth.createUser(admin, { username: "marc", roleId: "lecteur", password: "qwerty1234", mustChangePassword: false }, s.ctx);
    assert.equal(forced.mustChangePassword, true, "le mot de passe de départ impose toujours un changement");
    const list = await s.auth.listUsers(admin);
    assert.equal(list.length, 4);
    assert.ok(list.every((u) => !("passwordHash" in u)));
    const renamed = await s.auth.updateUser(admin, ok.id, { displayName: "Léa M." });
    assert.equal(renamed.displayName, "Léa M.");
    const moved = await s.auth.updateUser(admin, ok.id, { roleId: "contributeur" });
    assert.equal(moved.roleName, "Contributeur");
    await rejects(s.auth.updateUser(admin, "inconnu", { displayName: "xx" }), 404);
    await rejects(s.auth.updateUser(admin, ok.id, { disabled: "oui" }), 422);
    await rejects(s.auth.updateUser(admin, ok.id, null), 422);
    const reset = await s.auth.resetPassword(admin, ok.id, {}, s.ctx);
    assert.equal(reset.usedDefault, true);
    assert.equal((await s.auth.login("lea", "qwerty1234", s.ctx)).mustChangePassword, true);
    await rejects(s.auth.resetPassword(admin, admin.user.id, {}, s.ctx), 403);
    await rejects(s.auth.resetPassword(admin, ok.id, { password: "court" }, s.ctx), 422);
    await s.auth.deleteUser(admin, forced.id, s.ctx);
    await rejects(s.auth.deleteUser(admin, forced.id, s.ctx), 404);
    assert.equal((await s.auth.listUsers(admin)).length, 3);
  } finally { s.cleanup(); }
});

test("comptes : garde-fous (soi-même, dernier administrateur, administrateur protégé)", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    const b = await s.store.users.getByUsername("smiledpolecat34");
    await rejects(s.auth.updateUser(a, a.user.id, { disabled: true }), 403, /propre compte/);
    await rejects(s.auth.updateUser(a, a.user.id, { roleId: "lecteur" }), 403, /propre rôle/);
    await rejects(s.auth.deleteUser(a, a.user.id, s.ctx), 403);
    await s.auth.updateUser(a, b.id, { disabled: true });
    await rejects(s.auth.updateUser(a, a.user.id, { roleId: "lecteur" }), 403);
    // b est désactivé : a est le dernier administrateur actif ; un autre administrateur ne peut pas le retirer non plus
    await s.auth.updateUser(a, b.id, { disabled: false });
    const lecteur = await s.auth.createUser(a, { username: "viewer", roleId: "lecteur" }, s.ctx);
    await s.auth.updateUser(a, b.id, { roleId: "lecteur" }); // possible : a reste administrateur actif
    await rejects(s.auth.updateUser(a, a.user.id, { roleId: "lecteur" }), 403);
    await s.auth.updateUser(a, b.id, { roleId: "admin" });
    await s.auth.updateUser(a, b.id, { disabled: true });
    const bAdmin = await s.store.users.update(b.id, { disabled: false });
    void bAdmin; void lecteur;
    await s.auth.deleteUser(a, b.id, s.ctx);
    const only = await s.store.users.list();
    assert.equal(only.filter((u) => u.roleId === "admin").length, 1);
    await rejects(s.auth.deleteUser(a, only.find((u) => u.roleId === "admin").id, s.ctx), 403);
  } finally { s.cleanup(); }
});

test("rôles : créer, modifier, supprimer ; nom unique ; admin intouchable ; droits réservés refusés ; rôle utilisé non supprimable", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    const role = await s.auth.createRole(a, { name: "Modérateur", description: "Gère les tickets", permissions: ["tickets.view", "tickets.move", "tickets.edit"] }, s.ctx);
    assert.match(role.id, /^[a-z0-9][a-z0-9_-]+$/);
    await rejects(s.auth.createRole(a, { name: "modérateur", permissions: [] }, s.ctx), 409);
    for (const bad of [null, {}, { name: "x", permissions: [] }, { name: "Admin", permissions: [] }, { name: "Administrateur", permissions: [] }, { name: "Ok role", permissions: ["projects.add"] }, { name: "Ok role", permissions: ["inconnue"] }, { name: "Ok role", permissions: "tickets.view" }, { name: "Ok role", permissions: [], description: "x".repeat(201) }]) await rejects(s.auth.createRole(a, bad, s.ctx), bad && bad.name === "modérateur" ? 409 : 422);
    const edited = await s.auth.updateRole(a, role.id, { name: "Modérateur senior", description: "", permissions: ["tickets.view"] }, s.ctx);
    assert.deepEqual(edited.permissions, ["tickets.view"]);
    await rejects(s.auth.updateRole(a, "admin", { name: "Autre", permissions: [] }, s.ctx), 403);
    await rejects(s.auth.updateRole(a, "inconnu", { name: "Autre role", permissions: [] }, s.ctx), 404);
    await rejects(s.auth.updateRole(a, role.id, { name: "Lecteur", permissions: [] }, s.ctx), 409);
    await rejects(s.auth.deleteRole(a, "admin", s.ctx), 403);
    await s.auth.createUser(a, { username: "modo", roleId: role.id }, s.ctx);
    await rejects(s.auth.deleteRole(a, role.id, s.ctx), 409, /1 compte/);
    const list = await s.auth.listRoles(a);
    assert.equal(list.find((r) => r.id === role.id).userCount, 1);
    assert.equal(list[0].id, "admin");
    assert.equal(list[0].builtin, true);
    await s.auth.updateUser(a, (await s.store.users.getByUsername("modo")).id, { roleId: "lecteur" });
    await s.auth.deleteRole(a, role.id, s.ctx);
    await rejects(s.auth.deleteRole(a, role.id, s.ctx), 404);
    const cat = await s.auth.catalog(a);
    assert.ok(cat.some((c) => c.id === "journal" && c.permissions.length > 30));
  } finally { s.cleanup(); }
});

test("droits : un rôle modifié s'applique tout de suite ; un rôle falsifié dans la base ne donne jamais un droit réservé aux admins", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    await s.auth.createUser(a, { username: "zoe", roleId: "lecteur" }, s.ctx);
    const zoe = await s.actorOf("zoe", "qwerty1234");
    assert.equal(s.auth.can(zoe, "tickets.view"), true);
    assert.equal(s.auth.can(zoe, "tickets.create"), false);
    assert.throws(() => s.auth.need(zoe, "tickets.create"), (e) => e.status === 403 && /Créer un ticket/.test(e.message));
    await s.auth.updateRole(a, "lecteur", { name: "Lecteur", description: "", permissions: ["tickets.view", "tickets.create"] }, s.ctx);
    const again = await s.auth.resolve(zoe.token);
    assert.equal(s.auth.can(again, "tickets.create"), true, "effet immédiat, sans reconnexion");
    await s.store.roles.update("lecteur", { permissions: ["tickets.view", "projects.add", "roles.manage", "inconnue"] });
    const tampered = await s.auth.resolve(zoe.token);
    assert.deepEqual([...tampered.permissions], ["tickets.view"]);
    await s.store.roles.delete("lecteur");
    const orphan = await s.auth.resolve(zoe.token);
    assert.equal(orphan.permissions.size, 0, "rôle supprimé = aucun droit");
  } finally { s.cleanup(); }
});

test("droits : sans « modifier un compte » ou « créer un compte », rien n'est possible ; pas d'escalade vers un rôle plus puissant", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    const gest = await s.auth.createRole(a, { name: "Gestionnaire", description: "", permissions: P.STARTER_ROLES[0].permissions.concat(["users.view", "users.create", "users.edit", "users.disable", "users.reset_password", "roles.view"]) }, s.ctx);
    await s.auth.createUser(a, { username: "gestion", roleId: gest.id, password: "MotDePasse123x", mustChangePassword: false }, s.ctx);
    await s.auth.createUser(a, { username: "simple", roleId: "lecteur", password: "MotDePasse123y", mustChangePassword: false }, s.ctx);
    const g = await s.actorOf("gestion", "MotDePasse123x");
    const simple = await s.actorOf("simple", "MotDePasse123y");
    await rejects(s.auth.listUsers(simple), 403);
    await rejects(s.auth.createUser(simple, { username: "nouveau", roleId: "lecteur" }, s.ctx), 403);
    await rejects(s.auth.createUser(g, { username: "pirate", roleId: "admin" }, s.ctx), 403, /administrateur/);
    await rejects(s.auth.createUser(g, { username: "pirate", roleId: "contributeur" }, s.ctx), 403, /plus de droits/);
    const okUser = await s.auth.createUser(g, { username: "petit", roleId: "lecteur" }, s.ctx);
    assert.equal(okUser.roleId, "lecteur");
    await rejects(s.auth.updateUser(g, (await s.store.users.getByUsername("steph-mss")).id, { displayName: "Piraté" }), 403, /administrateur/);
    await rejects(s.auth.updateUser(g, okUser.id, { roleId: "admin" }), 403);
    await rejects(s.auth.resetPassword(g, (await s.store.users.getByUsername("steph-mss")).id, {}, s.ctx), 403);
    await rejects(s.auth.deleteUser(g, okUser.id, s.ctx), 403, /Droit manquant/);
    await rejects(s.auth.createRole(g, { name: "Nouveau rôle", permissions: [] }, s.ctx), 403);
    await rejects(s.auth.getSettings(g), 403);
    await rejects(s.auth.listAudit(g, 10), 403);
    await rejects(s.auth.listSessions(g, okUser.id), 403);
    assert.equal((await s.auth.listRoles(g)).length >= 5, true);
  } finally { s.cleanup(); }
});

test("sécurité : réglages validés (mot de passe de départ, durées, verrouillage) et appliqués ; sessions d'un compte consultables et fermables", async () => {
  const s = await setup();
  try {
    const a = await s.actorOf("steph-mss", "2903");
    assert.equal((await s.auth.getSettings(a)).defaultPassword, "qwerty1234");
    for (const bad of [null, { inconnu: 1 }, { defaultPassword: "court" }, { defaultPassword: 5 }, { sessionHours: 0 }, { sessionHours: 1.5 }, { sessionHours: 999 }, { maxFailedLogins: 1 }, { lockMinutes: "5" }]) await rejects(s.auth.updateSettings(a, bad, s.ctx), 422);
    const next = await s.auth.updateSettings(a, { defaultPassword: "Depart2026xx", maxFailedLogins: 3, lockMinutes: 2 }, s.ctx);
    assert.deepEqual([next.defaultPassword, next.maxFailedLogins, next.lockMinutes], ["Depart2026xx", 3, 2]);
    const u = await s.auth.createUser(a, { username: "neo", roleId: "lecteur" }, s.ctx);
    assert.equal((await s.auth.login("neo", "Depart2026xx", s.ctx)).mustChangePassword, true);
    for (let i = 0; i < 3; i++) await assert.rejects(s.auth.login("neo", "faux", { ip: "10.3.3.3" }), (e) => e.status === 401);
    await rejects(s.auth.login("neo", "Depart2026xx", { ip: "10.3.3.3" }), 429);
    const sessions = await s.auth.listSessions(a, u.id);
    assert.equal(sessions.length, 1);
    assert.ok(!("hash" in sessions[0]), "le jeton ou son empreinte ne sont jamais exposés");
    assert.deepEqual(await s.auth.revokeSessions(a, u.id, s.ctx), { closed: 1 });
    assert.equal((await s.auth.listSessions(a, u.id)).length, 0);
    const audit = await s.auth.listAudit(a, 500);
    assert.ok(audit.some((e) => e.action === "securite_modifiee") && audit.some((e) => e.action === "sessions_fermees"));
  } finally { s.cleanup(); }
});

test("service : le même scénario de connexion fonctionne sur PostgreSQL (simulé en mémoire)", async () => {
  const { newDb } = require("pg-mem");
  const { Pool } = newDb().adapters.createPg();
  const store = createPgStore({ pool: new Pool() });
  const auth = createAuth({ store });
  await auth.init();
  await auth.ensureAdmins([{ username: "steph-mss" }], "2903");
  const r = await auth.login("steph-mss", "2903", { ip: "1.1.1.1" });
  const actor = await auth.resolve(r.token);
  assert.equal(actor.permissions.size, P.ALL_IDS.length);
  const role = await auth.createRole(actor, { name: "Testeur Pg", permissions: ["tests.view"] });
  const u = await auth.createUser(actor, { username: "pgtest", roleId: role.id });
  assert.equal(u.mustChangePassword, true);
  await assert.rejects(auth.deleteRole(actor, role.id), (e) => e.status === 409);
  await auth.logout(r.token);
  assert.equal(await auth.resolve(r.token), null);
});
