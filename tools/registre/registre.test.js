"use strict";
// Tests des outils du registre : node --test tools/registre
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const http = require("node:http");

const { validate } = require("./validate");
const apply = require("./apply");
const { createServer, buildHtml } = require("./serve");

const ROOT = path.resolve(__dirname, "..", "..");
const read = (file) => fs.readFileSync(path.join(ROOT, file), "utf8");

// --- validation ---------------------------------------------------------------------------------------------------------
const goodChat = { type: "chat", fields: { id: "bravo", text: "Bravo !" }, note: "" };
const goodBomb = { type: "bomb", fields: { id: "bomb_doree", name: "Dorée", price: 400, color: "#d4af37", material: "Metal", description: "Une bombe dorée." } };

test("validate : contributions valides de chaque type", () => {
  assert.equal(validate(goodChat).ok, true);
  assert.equal(validate(goodBomb).ok, true);
  assert.equal(validate({ type: "quest", fields: { id: "bomber5", name: "Bombardier", description: "Poser 5 bombes", event: "round_played", goal: 5, reward: 50 } }).ok, true);
  assert.equal(validate({ type: "effect", fields: { id: "effect_or", name: "Or", price: 0, color: "#ffcc00", description: "Des flammes dorées." } }).ok, true);
  assert.equal(validate({ type: "emote", fields: { id: "salto", name: "Salto", animationId: "rbxassetid://123456", looped: false } }).ok, true);
  assert.equal(validate({ type: "note", fields: { title: "Mode équipe", details: "Deux équipes\nde quatre joueurs." } }).ok, true);
});

test("validate : refuse tout ce qui sort des règles du jeu", () => {
  const bad = [
    null, "x", [], {}, { type: "inconnu", fields: {} }, { type: "chat" }, { type: "chat", fields: [] },
    { type: "chat", fields: { id: "Bravo", text: "x" } }, // majuscule
    { type: "chat", fields: { id: "bravo", text: "x".repeat(31) } }, // 31 caractères
    { type: "chat", fields: { id: "bravo", text: "ligne\nbrisée" } },
    { type: "chat", fields: { id: "bravo", text: "ok", extra: 1 } }, // champ inattendu
    { type: "chat", fields: { id: "bravo" } }, // champ manquant
    { type: "bomb", fields: { ...goodBomb.fields, price: -1 } },
    { type: "bomb", fields: { ...goodBomb.fields, price: 1.5 } },
    { type: "bomb", fields: { ...goodBomb.fields, price: "400" } },
    { type: "bomb", fields: { ...goodBomb.fields, color: "red" } },
    { type: "bomb", fields: { ...goodBomb.fields, material: "Lava" } },
    { type: "bomb", fields: { ...goodBomb.fields, id: "effect_x" } },
    { type: "bomb", fields: { ...goodBomb.fields, id: "bomb_../etc" } },
    { type: "quest", fields: { id: "q1x", name: "Nom", description: "Description", event: "tuer_tout", goal: 1, reward: 1 } },
    { type: "quest", fields: { id: "q1x", name: "Nom", description: "Description", event: "round_won", goal: 0, reward: 1 } },
    { type: "emote", fields: { id: "salto", name: "Salto", animationId: "http://evil", looped: false } },
    { type: "emote", fields: { id: "salto", name: "Salto", animationId: "rbxassetid://12", looped: "oui" } },
    { type: "chat", fields: { id: "bravo", text: "ok" }, note: "x".repeat(501) },
  ];
  for (const doc of bad) assert.equal(validate(doc).ok, false, JSON.stringify(doc));
});

test("validate : le résultat ne contient que les champs attendus", () => {
  const check = validate({ ...goodChat, status: "applied", result: "piraté", createdAt: 1 });
  assert.deepEqual(check.clean, { type: "chat", fields: { id: "bravo", text: "Bravo !" }, note: "" });
});

// --- application dans les fichiers Luau ---------------------------------------------------------------------------------
test("renderLine : même style que les fichiers de configuration", () => {
  assert.equal(apply.renderLine("chat", goodChat.fields), 'table.freeze({ id = "bravo", text = "Bravo !" }),');
  assert.equal(apply.renderLine("bomb", goodBomb.fields), 'bomb("bomb_doree", "Dorée", 400, Color3.fromRGB(212, 175, 55), Enum.Material.Metal, "Une bombe dorée."),');
  assert.equal(
    apply.renderLine("effect", { id: "effect_or", name: "Or", price: 0, color: "#ffcc00", description: "x" }),
    'effect("effect_or", "Or", 0, Color3.fromRGB(255, 204, 0), "x"),'
  );
});

test("renderLine : guillemets et antislash échappés (aucune injection de code Luau)", () => {
  const line = apply.renderLine("chat", { id: "bravo", text: 'a"b\\c' });
  assert.equal(line, 'table.freeze({ id = "bravo", text = "a\\"b\\\\c" }),');
});

test("insertLine : ajoute avant la fermeture de la liste, conserve les fins de ligne, refuse un doublon", () => {
  for (const eol of ["\n", "\r\n"]) {
    const source = read("src/shared/QuickChatConfig.luau").split(/\r?\n/).join(eol);
    const line = apply.renderLine("chat", goodChat.fields);
    const result = apply.insertLine(source, apply.TARGETS.chat, line, "bravo");
    assert.equal(result.done, true);
    assert.ok(result.text.includes("\t" + line + eol + "}) :: { Phrase }"));
    assert.equal(result.text.split(eol).length, source.split(eol).length + 1);
    assert.equal(result.text.includes(eol === "\n" ? "\r\n" : "\n\n\n\n"), false);
    const again = apply.insertLine(result.text, apply.TARGETS.chat, line, "bravo");
    assert.equal(again.done, false);
    assert.match(again.reason, /déjà présent/);
  }
});

test("insertLine : une bombe va après la dernière bombe, un effet après le dernier effet", () => {
  const source = read("src/shared/CosmeticConfig.luau");
  const bomb = apply.insertLine(source, apply.TARGETS.bomb, apply.renderLine("bomb", goodBomb.fields), "bomb_doree");
  const lines = bomb.text.split(/\r?\n/);
  const at = lines.findIndex((l) => l.includes('"bomb_doree"'));
  assert.match(lines[at - 1], /^\tbomb\("bomb_ice"/);
  const effect = apply.insertLine(source, apply.TARGETS.effect, apply.renderLine("effect", { id: "effect_or", name: "Or", price: 0, color: "#ffcc00", description: "x" }), "effect_or");
  const effectLines = effect.text.split(/\r?\n/);
  const e = effectLines.findIndex((l) => l.includes('"effect_or"'));
  assert.match(effectLines[e - 1], /^\teffect\("effect_fire"/);
});

test("insertLine : point d'insertion introuvable => refus clair, fichier intact", () => {
  const result = apply.insertLine("rien ici\n", apply.TARGETS.quest, "x", "x_id");
  assert.equal(result.done, false);
  assert.match(result.reason, /introuvable/);
});

test("plan : applique, ignore les invalides, les notes, les doublons et les déjà traitées", () => {
  const contributions = [
    { name: "a", file: "a", raw: { ...goodChat, status: "pending" } },
    { name: "b", file: "b", raw: { type: "chat", fields: { id: "oops", text: "doublon" }, status: "pending" } }, // id existant dans le jeu
    { name: "c", file: "c", raw: { type: "note", fields: { title: "Idée", details: "détails" }, status: "pending" } },
    { name: "d", file: "d", raw: { type: "chat", fields: { id: "X", text: "mal formé" }, status: "pending" } },
    { name: "e", file: "e", raw: { ...goodChat, fields: { id: "autre", text: "Autre" }, status: "applied" } },
    { name: "f", file: "f", invalid: "JSON illisible" },
  ];
  const { steps } = apply.plan(contributions, read);
  const byName = Object.fromEntries(steps.map((s) => [s.c.name, s]));
  assert.equal(byName.a.status, "apply");
  assert.equal(byName.b.status, "skip");
  assert.match(byName.b.reason, /déjà présent/);
  assert.equal(byName.c.status, "skip");
  assert.match(byName.c.reason, /idée libre/);
  assert.equal(byName.d.status, "skip");
  assert.match(byName.d.reason, /invalide/);
  assert.equal(byName.e, undefined);
  assert.equal(byName.f.status, "skip");
});

test("plan : deux ajouts dans le même fichier se cumulent sans s'écraser", () => {
  const contributions = [
    { name: "a", file: "a", raw: { type: "chat", fields: { id: "un", text: "Un" }, status: "pending" } },
    { name: "b", file: "b", raw: { type: "chat", fields: { id: "deux", text: "Deux" }, status: "pending" } },
  ];
  const { steps, sources } = apply.plan(contributions, read);
  assert.deepEqual(steps.map((s) => s.status), ["apply", "apply"]);
  const text = sources.get("src/shared/QuickChatConfig.luau");
  assert.ok(text.includes('id = "un"') && text.includes('id = "deux"'));
});

// --- serveur local --------------------------------------------------------------------------------------------------------
function emptyData() {
  return {
    generatedAt: "aujourd'hui", tests: { passed: 1, failed: 0, suites: 1, results: [{ suite: "s", name: "t", ok: true, seconds: 0 }], error: "" },
    game: { version: "t", cosmetics: { bomb: [], effect: [] }, cosmeticDefaults: {}, quests: [], map: { cellSize: 4, defaultSize: "", defaultTheme: "", crateDensity: 0, spawnSafeDistance: 0, sizes: [], themes: [] }, powerups: [], emotes: { maxLoopSeconds: 0, list: [] }, quickChat: { bubbleSeconds: 0, maxRecents: 0, maxFavorites: 0, defaultFavorites: [], phrases: [] }, settings: { round: {}, bomb: {}, movement: {}, powerupDrops: { DropChancePerCrate: 0 }, remoteLimits: {}, rewards: {}, data: {} } },
    untested: { untested: {} }, manifest: { assets: [], createur: "t" },
  };
}

function request(port, method, url, { headers = {}, body, host } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path: url, headers: Object.assign({}, host ? { Host: host } : {}, headers) }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, headers: res.headers, text: Buffer.concat(chunks).toString("utf8") }));
    });
    req.on("error", reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

async function withServer(fn) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-test-"));
  const server = createServer({ dir, initialData: emptyData(), collect: emptyData });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await fn(server.address().port, dir);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
const H = { "X-Registre": "1", "Content-Type": "application/json" };

test("serveur : page, en-têtes de sécurité, images limitées à assets/ui", async () => {
  await withServer(async (port) => {
    const page = await request(port, "GET", "/");
    assert.equal(page.status, 200);
    assert.match(page.headers["content-security-policy"], /connect-src 'self' https:\/\/api\.groq\.com/);
    assert.equal(page.headers["x-content-type-options"], "nosniff");
    assert.equal((await request(port, "GET", "/img/logo.png")).status, 200);
    for (const bad of ["/img/../../package.png", "/img/%2e%2e%2fLICENSE", "/img/logo.exe", "/src/server/Bootstrap.server.luau", "/tools/registre/serve.js"]) {
      assert.notEqual((await request(port, "GET", bad)).status, 200, bad);
    }
  });
});

test("serveur : refuse un hôte étranger (protection contre le rebond DNS)", async () => {
  await withServer(async (port) => {
    assert.equal((await request(port, "GET", "/", { host: "evil.example" })).status, 403);
    assert.equal((await request(port, "GET", "/api/contributions", { host: "evil.example", headers: H })).status, 403);
  });
});

test("serveur : l'API exige l'en-tête X-Registre", async () => {
  await withServer(async (port) => {
    assert.equal((await request(port, "GET", "/api/contributions")).status, 403);
    assert.equal((await request(port, "POST", "/api/contributions", { headers: { "Content-Type": "application/json" }, body: JSON.stringify(goodChat) })).status, 403);
    assert.equal((await request(port, "POST", "/api/refresh")).status, 403);
  });
});

test("serveur : cycle complet d'une contribution (créer, lister, retirer)", async () => {
  await withServer(async (port, dir) => {
    const created = await request(port, "POST", "/api/contributions", { headers: H, body: JSON.stringify({ ...goodChat, status: "applied", result: "piraté" }) });
    assert.equal(created.status, 201);
    const id = JSON.parse(created.text).id;
    assert.match(id, /^[0-9]{10,16}-[a-z0-9]{6}$/);
    const onDisk = JSON.parse(fs.readFileSync(path.join(dir, id + ".json"), "utf8"));
    assert.equal(onDisk.status, "pending"); // le client ne choisit jamais le statut
    assert.equal(onDisk.result, undefined);
    const listed = JSON.parse((await request(port, "GET", "/api/contributions", { headers: H })).text);
    assert.equal(listed.length, 1);
    assert.equal(listed[0]._id, id);
    assert.equal((await request(port, "DELETE", "/api/contributions/" + id, { headers: H })).status, 200);
    assert.equal(fs.existsSync(path.join(dir, id + ".json")), false);
    assert.equal((await request(port, "DELETE", "/api/contributions/" + id, { headers: H })).status, 404);
  });
});

test("serveur : charges invalides refusées (JSON cassé, règles du jeu, taille, identifiants piégés)", async () => {
  await withServer(async (port, dir) => {
    assert.equal((await request(port, "POST", "/api/contributions", { headers: H, body: "{pas du json" })).status, 400);
    assert.equal((await request(port, "POST", "/api/contributions", { headers: H, body: JSON.stringify({ type: "chat", fields: { id: "X", text: "x" } }) })).status, 422);
    assert.equal((await request(port, "POST", "/api/contributions", { headers: H, body: JSON.stringify({ type: "note", fields: { title: "Idée", details: "x".repeat(25000) } }) })).status, 413);
    for (const id of ["../../LICENSE", "..%2f..%2fLICENSE", "1234567890-abcdef.json", "x"]) {
      const status = (await request(port, "DELETE", "/api/contributions/" + id, { headers: H })).status;
      assert.ok(status === 400 || status === 404, `${id} -> ${status}`);
    }
    assert.deepEqual(fs.existsSync(dir) ? fs.readdirSync(dir) : [], []);
  });
});

test("serveur : on ne retire pas une contribution déjà appliquée", async () => {
  await withServer(async (port, dir) => {
    const id = "1700000000000-abc123";
    fs.writeFileSync(path.join(dir, id + ".json"), JSON.stringify({ ...goodChat, status: "applied", createdAt: 1700000000000 }));
    assert.equal((await request(port, "DELETE", "/api/contributions/" + id, { headers: H })).status, 409);
    assert.equal(fs.existsSync(path.join(dir, id + ".json")), true);
  });
});

test("serveur : un fichier illisible dans le dossier ne bloque pas la liste", async () => {
  await withServer(async (port, dir) => {
    fs.writeFileSync(path.join(dir, "1700000000000-aaaaaa.json"), "{cassé");
    fs.writeFileSync(path.join(dir, "1700000000001-bbbbbb.json"), JSON.stringify({ ...goodChat, status: "pending", createdAt: 5 }));
    const listed = JSON.parse((await request(port, "GET", "/api/contributions", { headers: H })).text);
    assert.deepEqual(listed.map((x) => x._id), ["1700000000001-bbbbbb"]);
  });
});

// --- page générée ---------------------------------------------------------------------------------------------------------
test("page locale : script valide, données intégrées, aucune clé ni mention d'outil dans le code généré", () => {
  const html = buildHtml(emptyData());
  const scripts = [...html.matchAll(/<script( id="data" type="application\/json")?>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 2);
  assert.doesNotThrow(() => new vm.Script(scripts[1][2]));
  assert.ok(!html.includes("__DATA__") && !html.includes("/*__BACKEND__*/") && !html.includes("/*__EXTRA__*/"));
  assert.ok(!/gsk_[A-Za-z0-9]{20,}/.test(html), "aucune clé ne doit figurer dans la page");
  assert.ok(!new RegExp(["cla", "ude"].join(""), "i").test(html), "aucune mention d'outil dans le code généré");
});

test("page locale : la donnée injectée ne peut pas fermer la balise script", () => {
  const data = emptyData();
  data.tests.error = "</script><script>alert(1)</script>";
  const html = buildHtml(data);
  assert.equal((html.match(/<\/script>/g) || []).length, 2);
});

test("aucune clé d'API dans les fichiers de l'outil", () => {
  for (const file of fs.readdirSync(__dirname)) {
    if (!/\.(js|html)$/.test(file)) continue;
    assert.ok(!/gsk_[A-Za-z0-9]{20,}/.test(fs.readFileSync(path.join(__dirname, file), "utf8")), file);
  }
});
