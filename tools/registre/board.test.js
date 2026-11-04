"use strict";
// Tableau de suivi, journaux, journal d'activité : logique, validation hostile, sauvegarde, et routes HTTP.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createActivity, MAX_EVENTS } = require("./activity");
const { createBoard, BoardError, MAX_TICKETS, MAX_COMMENTS } = require("./board");
const { createJournal, JournalError, SCHEMAS, validateEntry } = require("./journal");
const { createStore } = require("./store");
const { createServer } = require("./serve");
const { sampleData } = require("./page-helpers");

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "registre-board-"));
function setup(extra) {
  const base = tmp();
  let t = 1700000000000;
  const clock = () => (t += 1000);
  const activity = createActivity(path.join(base, "activity.json"), clock);
  const board = createBoard({ dir: base, activity, clock });
  const journal = createJournal({ dir: base, activity, clock });
  return Object.assign({ base, activity, board, journal, clock }, extra);
}
const done = (...dirs) => dirs.forEach((d) => fs.rmSync(d, { recursive: true, force: true }));
const ticket = (over) => Object.assign({ title: "Corriger le menu", description: "Le bouton PLAY est coupé", priority: "P1", type: "bug", module: "MainMenu" }, over);

// ----- tickets -------------------------------------------------------------------------------------------------------------------
test("ticket : création avec valeurs par défaut, colonne À faire, historique « créé », trace d'activité", () => {
  const s = setup();
  try {
    const t = s.board.create({ title: "Ajouter le son d'explosion" });
    assert.match(t.id, /^t[a-z0-9]{6,24}$/);
    assert.deepEqual([t.status, t.priority, t.type, t.description, t.module, t.position], ["todo", "P2", "tache", "", "", 0]);
    assert.equal(t.history[0].action, "created");
    assert.deepEqual(t.comments, []);
    assert.equal(s.activity.list()[0].action, "ticket_cree");
    const second = s.board.create({ title: "Deuxième ticket" });
    assert.equal(second.position, 0, "un nouveau ticket arrive en haut de sa colonne");
    assert.deepEqual(s.board.list().filter((x) => x.status === "todo").map((x) => [x.title, x.position]), [["Deuxième ticket", 0], ["Ajouter le son d'explosion", 1]]);
    assert.equal(s.board.create(ticket({ status: "done" })).doneAt > 0, true);
  } finally {
    done(s.base);
  }
});

test("ticket : toute saisie hors règles est refusée (titre, description, priorité, type, statut, module, mauvais types)", () => {
  const s = setup();
  try {
    const bad = [null, "x", [], {}, { title: "ab" }, { title: "   " }, { title: "x".repeat(121) }, { title: 5 }, { title: "ok ok", description: "x".repeat(4001) }, { title: "ok ok", description: 7 },
      { title: "ok ok", priority: "P9" }, { title: "ok ok", priority: 1 }, { title: "ok ok", type: "virus" }, { title: "ok ok", status: "archive" }, { title: "ok ok", module: "x".repeat(61) }, { title: "a\u0000bc" }];
    for (const raw of bad) assert.throws(() => s.board.create(raw), BoardError, JSON.stringify(raw));
    assert.deepEqual(s.board.list(), []);
    assert.equal(s.board.create({ title: "ok ok", extra: "<script>", status: "doing" }).extra, undefined, "champs inconnus jamais écrits");
  } finally {
    done(s.base);
  }
});

test("ticket : modification — seuls les champs fournis changent, l'historique note la priorité et l'édition, rien si identique", () => {
  const s = setup();
  try {
    const t = s.board.create(ticket());
    const same = s.board.update(t.id, { title: t.title, priority: "P1" });
    assert.equal(same.history.length, 1, "aucun changement = aucune ligne d'historique");
    const u = s.board.update(t.id, { priority: "P0", description: "Nouvelle description" });
    assert.equal(u.priority, "P0");
    assert.equal(u.title, t.title);
    assert.deepEqual(u.history.map((h) => h.action), ["created", "priority", "edited"]);
    assert.deepEqual([u.history[1].from, u.history[1].to], ["P1", "P0"]);
    assert.ok(u.updatedAt > t.updatedAt);
    assert.throws(() => s.board.update(t.id, { priority: "P7" }), BoardError);
    assert.throws(() => s.board.update(t.id, { title: "" }), BoardError);
    assert.throws(() => s.board.update("tinconnu123", { title: "valide" }), (e) => e.status === 404);
    assert.throws(() => s.board.update("../evil", { title: "valide" }), (e) => e.status === 400);
  } finally {
    done(s.base);
  }
});

test("déplacement : changement de colonne, position choisie, colonnes renumérotées, historique « déplacé »", () => {
  const s = setup();
  try {
    const c = s.board.create({ title: "Ticket C" }), b = s.board.create({ title: "Ticket B" }), a = s.board.create({ title: "Ticket A" }); // créés à l'envers : A, B, C de haut en bas
    const moved = s.board.move(b.id, { status: "doing" });
    assert.equal(moved.status, "doing");
    assert.equal(moved.position, 0);
    assert.deepEqual(s.board.list().filter((t) => t.status === "todo").map((t) => [t.title, t.position]), [["Ticket A", 0], ["Ticket C", 1]]);
    const last = moved.history[moved.history.length - 1];
    assert.deepEqual([last.action, last.from, last.to], ["moved", "todo", "doing"]);
    s.board.move(a.id, { status: "doing", index: 0 }); // insertion en tête
    assert.deepEqual(s.board.list().filter((t) => t.status === "doing").map((t) => t.title), ["Ticket A", "Ticket B"]);
    assert.equal(s.board.move(c.id, { status: "done" }).doneAt > 0, true);
    assert.equal(s.board.move(c.id, { status: "todo" }).doneAt, undefined, "la date de fin disparaît si on rouvre");
    // index trop grand : placé à la fin
    s.board.move(a.id, { status: "doing", index: 999 });
    assert.deepEqual(s.board.list().filter((t) => t.status === "doing").map((t) => t.title), ["Ticket B", "Ticket A"]);
  } finally {
    done(s.base);
  }
});

test("déplacement : réordonner dans la même colonne est historisé ; ne rien changer ne crée aucun événement ; entrées hostiles refusées", () => {
  const s = setup();
  try {
    s.board.create({ title: "Ticket B" });
    const a = s.board.create({ title: "Ticket A" });
    const before = s.activity.list().length;
    s.board.move(a.id, { status: "todo", index: 0 });
    assert.equal(s.activity.list().length, before, "déplacement sans effet");
    const r = s.board.move(a.id, { status: "todo", index: 1 });
    assert.equal(r.history[r.history.length - 1].action, "reordered");
    assert.deepEqual(s.board.list().map((t) => t.title), ["Ticket B", "Ticket A"]);
    for (const raw of [null, {}, { status: "x" }, { status: "done", index: -1 }, { status: "done", index: 1.5 }, { status: "done", index: "0" }, { status: "done", index: 1e9 }]) assert.throws(() => s.board.move(a.id, raw), BoardError, JSON.stringify(raw));
    assert.throws(() => s.board.move("tinconnu123", { status: "done" }), (e) => e.status === 404);
  } finally {
    done(s.base);
  }
});

test("retours : ajout, suppression, limites, historique et activité", () => {
  const s = setup();
  try {
    const t = s.board.create(ticket());
    const c = s.board.addComment(t.id, { text: "Testé sur mobile : toujours coupé" });
    assert.equal(c.comments.length, 1);
    assert.match(c.comments[0].id, /^k[a-z0-9]{6,24}$/);
    assert.equal(c.history[c.history.length - 1].action, "commented");
    for (const raw of [null, {}, { text: "" }, { text: "   " }, { text: 5 }, { text: "x".repeat(2001) }]) assert.throws(() => s.board.addComment(t.id, raw), BoardError, JSON.stringify(raw));
    assert.throws(() => s.board.removeComment(t.id, "kinconnu123"), (e) => e.status === 404);
    assert.throws(() => s.board.removeComment(t.id, "../x"), (e) => e.status === 400);
    const r = s.board.removeComment(t.id, c.comments[0].id);
    assert.deepEqual(r.comments, []);
    assert.equal(s.activity.list().map((e) => e.action).includes("retour_supprime"), true);
    for (let i = 0; i < MAX_COMMENTS; i++) s.board.addComment(t.id, { text: "retour " + i });
    assert.throws(() => s.board.addComment(t.id, { text: "de trop" }), (e) => e.status === 429);
  } finally {
    done(s.base);
  }
});

test("suppression : le ticket disparaît, la colonne est renumérotée, l'activité garde la trace", () => {
  const s = setup();
  try {
    const a = s.board.create({ title: "Ticket A" }), b = s.board.create({ title: "Ticket B" });
    s.board.remove(a.id);
    assert.deepEqual(s.board.list().map((t) => [t.title, t.position]), [["Ticket B", 0]]);
    assert.equal(s.activity.list()[0].action, "ticket_supprime");
    assert.equal(s.activity.list()[0].title, "Ticket A");
    assert.throws(() => s.board.remove(a.id), (e) => e.status === 404);
    assert.ok(b);
  } finally {
    done(s.base);
  }
});

test("tickets : plafond, fichiers abîmés ou falsifiés ignorés", () => {
  const s = setup();
  try {
    fs.mkdirSync(path.join(s.base, "tickets"), { recursive: true });
    for (let i = 0; i < MAX_TICKETS; i++) {
      const id = "t" + String(100000 + i);
      fs.writeFileSync(path.join(s.base, "tickets", id + ".json"), JSON.stringify({ id, title: "abc", description: "", priority: "P2", type: "tache", status: "todo", module: "", position: i, createdAt: 1, updatedAt: 1, comments: [], history: [] }));
    }
    assert.throws(() => s.board.create({ title: "de trop" }), (e) => e.status === 429);
  } finally {
    done(s.base);
  }
  const s2 = setup();
  try {
    fs.mkdirSync(path.join(s2.base, "tickets"));
    fs.writeFileSync(path.join(s2.base, "tickets", "tabcdef1.json"), "{cassé");
    fs.writeFileSync(path.join(s2.base, "tickets", "tabcdef2.json"), JSON.stringify({ id: "tabcdef2", title: "x", priority: "ZZ" }));
    fs.writeFileSync(path.join(s2.base, "tickets", "notes.txt"), "x");
    assert.deepEqual(s2.board.list(), []);
  } finally {
    done(s2.base);
  }
});

// ----- activité ---------------------------------------------------------------------------------------------------------------------
test("activité : plus récent d'abord, plafonnée, texte borné, fichier abîmé ignoré", () => {
  const s = setup();
  try {
    s.activity.add("ticket", "a", "premier");
    s.activity.add("ticket", "b", "x".repeat(500), "d".repeat(900), "t123456");
    const l = s.activity.list();
    assert.deepEqual(l.map((e) => e.action), ["b", "a"]);
    assert.equal(l[0].title.length, 200);
    assert.equal(l[0].detail.length, 500);
    assert.equal(s.activity.list(1).length, 1);
    assert.equal(s.activity.list(-5).length, 2);
    assert.equal(MAX_EVENTS, 2000);
    fs.writeFileSync(path.join(s.base, "activity.json"), "{cassé");
    assert.deepEqual(s.activity.list(), []);
  } finally {
    done(s.base);
  }
});

// ----- journaux ---------------------------------------------------------------------------------------------------------------------
const VALID = {
  playtests: { date: "2026-11-04", scenario: "2 clients Studio", result: "partiel", device: "PC", players: 2, notes: "Un lag" },
  balance: { name: "Prix bombe rouge", area: "prix", current: "250", proposed: "300", retained: true },
  feedback: { screen: "menu", severity: "moyen", author: "Ami", text: "Le bouton est petit", handled: false },
  images: { file: "logo.png", usage: "Menu", status: "importee", assetId: "rbxassetid://123", sha256: "a".repeat(64) },
  texts: { key: "menu.play", text: "Jouer", reviewed: false },
  seeds: { seed: 4242, theme: "Ice", size: "16", verdict: "aime" },
  decisions: { question: "Quel est le nom du jeu ?", status: "ouverte" },
  perf: { date: "2026-11-04", device: "Téléphone", scenario: "Manche à 8", fps: 45 },
  releases: { date: "2026-11-04", version: "0.1.0" },
};

test("journaux : chaque rubrique accepte une entrée valide, la relit, la modifie et la supprime", () => {
  const s = setup();
  try {
    assert.deepEqual(SCHEMAS.map((x) => x.id).sort(), Object.keys(VALID).sort());
    for (const schema of SCHEMAS) {
      const e = s.journal.put(schema.id, VALID[schema.id]);
      assert.match(e.id, /^j[a-z0-9]{6,24}$/);
      assert.equal(s.journal.list(schema.id).length, 1, schema.id);
      const edited = s.journal.put(schema.id, VALID[schema.id], e.id);
      assert.equal(edited.id, e.id);
      assert.equal(edited.createdAt, e.createdAt);
      assert.ok(edited.updatedAt > e.updatedAt);
      s.journal.remove(schema.id, e.id);
      assert.deepEqual(s.journal.list(schema.id), []);
    }
    const kinds = s.activity.list(100).map((e) => e.action);
    assert.ok(kinds.includes("entree_ajoutee") && kinds.includes("entree_modifiee") && kinds.includes("entree_supprimee"));
  } finally {
    done(s.base);
  }
});

test("journaux : champs obligatoires, types, bornes, formats et valeurs libres invalides refusés pour chaque rubrique", () => {
  const s = setup();
  try {
    for (const schema of SCHEMAS) {
      assert.throws(() => s.journal.put(schema.id, {}), JournalError, schema.id + " vide");
      assert.throws(() => s.journal.put(schema.id, null), JournalError);
      for (const fd of schema.fields) {
        const base = Object.assign({}, VALID[schema.id]);
        if (fd.type === "enum") {
          for (const value of [7, {}, " ", "x".repeat(121), "__custom__", "invalide\u0000"]) {
            base[fd.key] = value; assert.throws(() => s.journal.put(schema.id, base), JournalError, schema.id + "." + fd.key);
          }
        }
        if (fd.type === "int") { for (const v of [fd.min - 1, fd.max + 1, 1.5, "3", NaN, Infinity]) { base[fd.key] = v; assert.throws(() => s.journal.put(schema.id, base), JournalError, schema.id + "." + fd.key + "=" + v); } }
        if (fd.type === "date") { for (const v of ["2026-13-01", "2026-02-30", "demain", "2026-1-1", 20261104]) { base[fd.key] = v; assert.throws(() => s.journal.put(schema.id, base), JournalError, schema.id + "." + fd.key + "=" + v); } }
        if (fd.type === "text" || fd.type === "long") { base[fd.key] = "x".repeat(fd.max + 1); assert.throws(() => s.journal.put(schema.id, base), JournalError, schema.id + "." + fd.key + " trop long"); base[fd.key] = 5; assert.throws(() => s.journal.put(schema.id, base), JournalError); }
        if (fd.type === "bool") { base[fd.key] = "oui"; assert.throws(() => s.journal.put(schema.id, base), JournalError); }
        if (!fd.optional && fd.type !== "bool") { const b2 = Object.assign({}, VALID[schema.id]); delete b2[fd.key]; assert.throws(() => s.journal.put(schema.id, b2), JournalError, schema.id + "." + fd.key + " manquant"); }
      }
    }
    assert.throws(() => s.journal.put("images", Object.assign({}, VALID.images, { assetId: "https://evil" })), JournalError);
    assert.throws(() => s.journal.put("images", Object.assign({}, VALID.images, { sha256: "xyz" })), JournalError);
    assert.throws(() => s.journal.put("inconnue", {}), (e) => e.status === 404);
    assert.throws(() => s.journal.put("playtests", VALID.playtests, "jinconnu123"), (e) => e.status === 404);
    assert.throws(() => s.journal.put("playtests", VALID.playtests, "../x"), (e) => e.status === 400);
    assert.throws(() => s.journal.remove("playtests", "jinconnu123"), (e) => e.status === 404);
    const e = s.journal.put("playtests", Object.assign({}, VALID.playtests, { pirate: "x", notes: "" }));
    assert.equal(e.pirate, undefined);
    assert.equal(e.notes, undefined, "champ facultatif vide : non enregistré");
    assert.deepEqual(validateEntry(SCHEMAS[2], { screen: "menu", severity: "mineur", text: "ok" }).handled, false);
  } finally {
    done(s.base);
  }
});

test("journaux : une valeur personnalisée de sélecteur est sauvegardée, relue et exportée", () => {
  const s = setup();
  try {
    const entry = s.journal.put("feedback", { ...VALID.feedback, screen: "Écran de sélection des bots", severity: "Bloquant sur tablette" });
    assert.equal(s.journal.list("feedback")[0].screen, "Écran de sélection des bots");
    assert.equal(s.journal.extra.backup().feedback[0].severity, "Bloquant sur tablette");
    const updated = s.journal.put("feedback", { ...VALID.feedback, screen: "menu" }, entry.id);
    assert.equal(updated.screen, "menu");
  } finally { done(s.base); }
});

// ----- sauvegarde / restauration -----------------------------------------------------------------------------------------------------
function storeFor(s) {
  return createStore({ dir: path.join(s.base, "data"), contributionsDir: path.join(s.base, "c"), runsDir: path.join(s.base, "r"), extras: [s.board.extra, s.journal.extra, s.activity.extra] });
}
test("sauvegarde et restauration : tickets (retours et historique compris), journaux et activité retrouvés ; fusion sans doublon", () => {
  const a = setup(), b = setup();
  try {
    const t = a.board.create(ticket());
    a.board.addComment(t.id, { text: "Un retour" });
    a.board.move(t.id, { status: "doing" });
    a.journal.put("playtests", VALID.playtests);
    const bundle = JSON.parse(JSON.stringify(storeFor(a).backup()));
    assert.equal(bundle.tickets.length, 1);
    const report = storeFor(b).restore(bundle);
    assert.equal(report.tickets, 1);
    assert.equal(report.journal, 1);
    assert.ok(report.activity >= 3);
    const copy = b.board.get(t.id);
    assert.deepEqual(copy, a.board.get(t.id));
    assert.equal(copy.comments.length, 1);
    assert.equal(b.journal.list("playtests").length, 1);
    const again = storeFor(b).restore(bundle);
    assert.deepEqual([again.tickets, again.journal, again.activity], [0, 0, 0]);
    // un ticket plus récent sur disque n'est jamais écrasé
    for (let i = 0; i < 50; i++) b.clock();
    b.board.update(t.id, { title: "Titre local plus récent" });
    storeFor(b).restore(bundle);
    assert.equal(b.board.get(t.id).title, "Titre local plus récent");
    assert.equal(storeFor(a).stats().tickets.count, 1);
  } finally {
    done(a.base, b.base);
  }
});

test("restauration : éléments falsifiés ignorés avec leur raison, rien d'invalide n'est écrit", () => {
  const s = setup();
  try {
    const good = a_ticket();
    const report = storeFor(s).restore({
      format: "registre-backup", version: 1,
      tickets: [good, Object.assign({}, good, { id: "../evil" }), Object.assign({}, good, { id: "tabcdef99", priority: "P9" }), { id: "tabcdef98" }, Object.assign({}, good, { id: "tabcdef97", comments: [{ id: "x", text: "y", at: 1 }] })],
      journal: { playtests: [Object.assign({ id: "jabcdef01", createdAt: 1, updatedAt: 2 }, VALID.playtests), { id: "jabcdef02", createdAt: 1, updatedAt: 2, scenario: "x" }], inconnue: [{}], perf: "pas une liste" },
      activity: [{ at: 5, kind: "ticket", action: "a", title: "ok" }, { at: "x" }, null],
    });
    assert.equal(report.tickets, 1);
    assert.equal(report.journal, 1);
    assert.equal(report.activity, 1);
    assert.ok(report.ignored.length >= 6);
    assert.equal(s.board.list().length, 1);
    assert.equal(s.journal.list("playtests").length, 1);
  } finally {
    done(s.base);
  }
});
function a_ticket() {
  return { id: "tabcdef01", title: "Importé", description: "", priority: "P2", type: "tache", status: "todo", module: "", position: 0, createdAt: 1, updatedAt: 2, comments: [], history: [{ at: 1, action: "created", to: "todo" }] };
}

// ----- routes HTTP ---------------------------------------------------------------------------------------------------------------------
const H = { "X-Registre": "1", "Content-Type": "application/json" };
function request(port, method, url, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path: url, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, json: () => JSON.parse(Buffer.concat(chunks).toString("utf8")) }));
    });
    req.on("error", reject);
    if (body !== undefined) req.write(typeof body === "string" ? body : JSON.stringify(body));
    req.end();
  });
}
async function withServer(fn) {
  const base = tmp();
  const server = createServer({ dir: path.join(base, "c"), runsDir: path.join(base, "r"), dataDir: path.join(base, "data"), initialData: sampleData(), collect: async () => sampleData() });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await fn(server.address().port);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    done(base);
  }
}

test("routes : en-tête de protection exigé partout, schéma et colonnes exposés", async () => {
  await withServer(async (port) => {
    for (const [m, u] of [["GET", "/api/schema"], ["GET", "/api/tickets"], ["POST", "/api/tickets"], ["PATCH", "/api/tickets/tabcdef01"], ["POST", "/api/tickets/tabcdef01/move"], ["GET", "/api/activity"], ["GET", "/api/journal/playtests"], ["POST", "/api/journal/playtests"]]) {
      assert.equal((await request(port, m, u, { headers: { "Content-Type": "application/json" }, body: m === "GET" ? undefined : "{}" })).status, 403, m + " " + u);
    }
    const schema = (await request(port, "GET", "/api/schema", { headers: H })).json();
    assert.deepEqual(schema.board.statuses.map((s) => s.id), ["todo", "doing", "done"]);
    assert.equal(schema.journal.length, 9);
  });
});

test("routes : cycle complet d'un ticket (créer, modifier, déplacer, commenter, historique, supprimer) et activité", async () => {
  await withServer(async (port) => {
    const created = await request(port, "POST", "/api/tickets", { headers: H, body: ticket() });
    assert.equal(created.status, 201);
    const id = created.json().id;
    assert.equal((await request(port, "PATCH", "/api/tickets/" + id, { headers: H, body: { priority: "P0" } })).json().priority, "P0");
    assert.equal((await request(port, "POST", "/api/tickets/" + id + "/move", { headers: H, body: { status: "doing", index: 0 } })).json().status, "doing");
    const commented = await request(port, "POST", "/api/tickets/" + id + "/comments", { headers: H, body: { text: "Retour du testeur" } });
    assert.equal(commented.status, 201);
    const cid = commented.json().comments[0].id;
    assert.equal((await request(port, "GET", "/api/tickets/" + id, { headers: H })).json().history.length, 4);
    assert.equal((await request(port, "DELETE", "/api/tickets/" + id + "/comments/" + cid, { headers: H })).json().comments.length, 0);
    assert.equal((await request(port, "GET", "/api/tickets", { headers: H })).json().length, 1);
    assert.equal((await request(port, "DELETE", "/api/tickets/" + id, { headers: H })).status, 200);
    assert.equal((await request(port, "GET", "/api/tickets/" + id, { headers: H })).status, 404);
    const feed = (await request(port, "GET", "/api/activity?limit=50", { headers: H })).json().map((e) => e.action);
    for (const a of ["ticket_cree", "priorite_changee", "ticket_deplace", "retour_ajoute", "retour_supprime", "ticket_supprime"]) assert.ok(feed.includes(a), a);
  });
});

test("routes : entrées hostiles refusées avec le bon code", async () => {
  await withServer(async (port) => {
    assert.equal((await request(port, "POST", "/api/tickets", { headers: H, body: { title: "" } })).status, 422);
    assert.equal((await request(port, "POST", "/api/tickets", { headers: H, body: "{cassé" })).status, 400);
    assert.equal((await request(port, "POST", "/api/tickets", { headers: H, body: { title: "ok ok", description: "x".repeat(30000) } })).status, 413);
    assert.equal((await request(port, "PATCH", "/api/tickets/..%2f..%2fx", { headers: H, body: {} })).status, 400);
    assert.equal((await request(port, "PATCH", "/api/tickets/tinconnu123", { headers: H, body: { title: "valide" } })).status, 404);
    assert.equal((await request(port, "POST", "/api/tickets/tinconnu123/move", { headers: H, body: { status: "done" } })).status, 404);
    assert.equal((await request(port, "GET", "/api/tickets/tinconnu123/inconnu", { headers: H })).status, 404);
    assert.equal((await request(port, "GET", "/api/journal/inconnue", { headers: H })).status, 404);
    assert.equal((await request(port, "GET", "/api/journal/..", { headers: H })).status === 200, false);
    assert.equal((await request(port, "POST", "/api/journal/playtests", { headers: H, body: { scenario: "x" } })).status, 422);
  });
});

test("routes : journaux (créer, lister, modifier, supprimer) et sauvegarde complète via l'API", async () => {
  await withServer(async (port) => {
    const e = await request(port, "POST", "/api/journal/playtests", { headers: H, body: VALID.playtests });
    assert.equal(e.status, 201);
    const id = e.json().id;
    assert.equal((await request(port, "PUT", "/api/journal/playtests/" + id, { headers: H, body: Object.assign({}, VALID.playtests, { result: "ok" }) })).json().result, "ok");
    assert.equal((await request(port, "GET", "/api/journal/playtests", { headers: H })).json().length, 1);
    await request(port, "POST", "/api/tickets", { headers: H, body: ticket() });
    const backup = (await request(port, "GET", "/api/backup", { headers: H })).json();
    assert.equal(backup.tickets.length, 1);
    assert.equal(backup.journal.playtests.length, 1);
    assert.ok(backup.activity.length >= 2);
    assert.equal((await request(port, "GET", "/api/storage", { headers: H })).json().tickets.count, 1);
    assert.equal((await request(port, "DELETE", "/api/journal/playtests/" + id, { headers: H })).status, 200);
    assert.equal((await request(port, "DELETE", "/api/journal/playtests/" + id, { headers: H })).status, 404);
  });
});
