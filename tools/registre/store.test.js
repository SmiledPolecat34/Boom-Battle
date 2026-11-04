"use strict";
// Stockage durable : conversations, réglages, sons (fichiers audio), sauvegarde et restauration, et leurs routes HTTP.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createStore, StoreError, sniffAudio, MAX_SOUND_BYTES, MAX_SOUNDS, MAX_CHATS } = require("./store");
const { createServer } = require("./serve");
const { sampleData } = require("./page-helpers");

// ----- fabriques -----------------------------------------------------------------------------------------------------------
function tmp() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "registre-store-"));
}
function newStore(root) {
  const base = root || tmp();
  return { store: createStore({ dir: path.join(base, "data"), contributionsDir: path.join(base, "contributions"), runsDir: path.join(base, "runs") }), base };
}
function cleanup(...dirs) {
  for (const d of dirs) fs.rmSync(d, { recursive: true, force: true });
}
const wav = (extra) => Buffer.concat([Buffer.from("RIFF"), Buffer.from([36, 0, 0, 0]), Buffer.from("WAVEfmt "), Buffer.alloc(24, extra || 0)]);
const mp3 = () => Buffer.concat([Buffer.from("ID3"), Buffer.alloc(40, 1)]);
const ogg = () => Buffer.concat([Buffer.from("OggS"), Buffer.alloc(40, 2)]);
const b64 = (buffer) => buffer.toString("base64");

function chat(id, over) {
  return Object.assign({ id, title: "Question " + id, createdAt: 1000, updatedAt: 2000, messages: [{ role: "user", content: "Bonjour" }, { role: "assistant", content: "Salut" }] }, over);
}
function soundMeta(over) {
  return Object.assign({ name: "Explosion douce", event: "explosion", category: "sfx", volume: 0.8, loop: false, enabled: true, note: "", source: { type: "file" } }, over);
}
const withFile = (buffer, name) => ({ name: name || "boom.wav", dataBase64: b64(buffer) });

// ----- conversations ---------------------------------------------------------------------------------------------------------
test("conversations : enregistrées en fichiers, relues triées, supprimées", () => {
  const { store, base } = newStore();
  try {
    store.putChat(chat("caaaaaa1", { updatedAt: 10 }));
    store.putChat(chat("caaaaaa2", { updatedAt: 30 }));
    store.putChat(chat("caaaaaa3", { updatedAt: 20 }));
    assert.deepEqual(store.listChats().map((c) => c.id), ["caaaaaa2", "caaaaaa3", "caaaaaa1"]);
    assert.ok(fs.existsSync(path.join(base, "data", "chats", "caaaaaa1.json")));
    store.putChat(chat("caaaaaa1", { updatedAt: 99, title: "Renommée" })); // mise à jour du même fichier
    assert.equal(store.listChats()[0].title, "Renommée");
    assert.equal(store.listChats().length, 3);
    store.removeChat("caaaaaa2");
    assert.equal(store.listChats().length, 2);
    assert.throws(() => store.removeChat("caaaaaa2"), (e) => e.status === 404);
    assert.equal(store.clearChats(), 2);
    assert.deepEqual(store.listChats(), []);
  } finally {
    cleanup(base);
  }
});

test("conversations : tout ce qui sort du schéma est refusé", () => {
  const { store, base } = newStore();
  try {
    const bad = [
      null, "x", [], chat("../evil"), chat("C12345678"), chat("c1"), chat("caaaaaa1", { title: "" }), chat("caaaaaa1", { title: "x".repeat(121) }),
      chat("caaaaaa1", { createdAt: "hier" }), chat("caaaaaa1", { updatedAt: 1.5 }), chat("caaaaaa1", { messages: [] }), chat("caaaaaa1", { messages: "x" }),
      chat("caaaaaa1", { messages: Array.from({ length: 201 }, () => ({ role: "user", content: "x" })) }),
      chat("caaaaaa1", { messages: [{ role: "system", content: "x" }] }), chat("caaaaaa1", { messages: [{ role: "user", content: 5 }] }),
      chat("caaaaaa1", { messages: [{ role: "user", content: "x".repeat(20001) }] }), chat("caaaaaa1", { messages: [null] }),
    ];
    for (const doc of bad) assert.throws(() => store.putChat(doc), StoreError, JSON.stringify(doc).slice(0, 80));
    assert.deepEqual(store.listChats(), []);
  } finally {
    cleanup(base);
  }
});

test("conversations : les brouillons valides sont conservés, les invalides retirés, les champs inconnus jamais écrits", () => {
  const { store, base } = newStore();
  try {
    const good = { type: "chat", fields: { text: "Bravo !" }, note: "" };
    const doc = chat("caaaaaa1", { extra: "x", messages: [{ role: "assistant", content: "ok", drafts: [good], draftKey: "m2", pirate: 1 }, { role: "assistant", content: "ko", drafts: [{ type: "virus", fields: {} }], draftKey: "m3" }] });
    const saved = store.putChat(doc);
    assert.equal(saved.extra, undefined);
    assert.deepEqual(saved.messages[0].drafts, [good]);
    assert.equal(saved.messages[0].draftKey, "m2");
    assert.equal(saved.messages[0].pirate, undefined);
    assert.equal(saved.messages[1].drafts, undefined);
  } finally {
    cleanup(base);
  }
});

test("conversations : plafond et fichiers abîmés ignorés", () => {
  const { store, base } = newStore();
  try {
    for (let i = 0; i < MAX_CHATS; i++) store.putChat(chat("c" + String(100000 + i)));
    assert.throws(() => store.putChat(chat("cplusdetrop")), (e) => e.status === 429);
    store.putChat(chat("c100000", { title: "modifiable" })); // une conversation existante reste modifiable
    fs.writeFileSync(path.join(base, "data", "chats", "c999999.json"), "{cassé");
    fs.writeFileSync(path.join(base, "data", "chats", "notes.txt"), "x");
    assert.equal(store.listChats().length, MAX_CHATS);
  } finally {
    cleanup(base);
  }
});

// ----- réglages --------------------------------------------------------------------------------------------------------------
test("réglages : enregistrés, relus, champs inconnus écartés, valeurs invalides refusées", () => {
  const { store, base } = newStore();
  try {
    assert.deepEqual(store.getSettings(), {});
    store.putSettings({ model: "openai/gpt-oss-120b", tab: "sons", gameTab: "quetes", runFilter: "GridService", apiKey: "gsk_" + "A".repeat(40) });
    assert.deepEqual(store.getSettings(), { model: "openai/gpt-oss-120b", tab: "sons", gameTab: "quetes", runFilter: "GridService" });
    assert.ok(!fs.readFileSync(path.join(base, "data", "settings.json"), "utf8").includes("gsk_"), "aucune clé dans le fichier de réglages");
    for (const bad of [null, "x", [], { tab: "pirate" }, { gameTab: "x" }, { model: "a b" }, { model: "x".repeat(101) }, { runFilter: "-rf" }, { runFilter: 5 }]) {
      assert.throws(() => store.putSettings(bad), StoreError, JSON.stringify(bad));
    }
    fs.writeFileSync(path.join(base, "data", "settings.json"), "{cassé");
    assert.deepEqual(store.getSettings(), {}, "un fichier abîmé ne bloque pas la page");
  } finally {
    cleanup(base);
  }
});

// ----- sons -------------------------------------------------------------------------------------------------------------------
test("sniffAudio : format reconnu par les octets, jamais par le nom", () => {
  assert.equal(sniffAudio(wav()), "wav");
  assert.equal(sniffAudio(mp3()), "mp3");
  assert.equal(sniffAudio(Buffer.concat([Buffer.from([0xff, 0xfb]), Buffer.alloc(40)])), "mp3");
  assert.equal(sniffAudio(ogg()), "ogg");
  assert.equal(sniffAudio(Buffer.from("MZ" + "x".repeat(40))), null);
  assert.equal(sniffAudio(Buffer.from("<html>" + "x".repeat(40))), null);
  assert.equal(sniffAudio(Buffer.alloc(5)), null);
});

test("sons : création avec fichier, lecture, modification sans nouveau fichier, remplacement, passage à Roblox, suppression", () => {
  const { store, base } = newStore();
  try {
    const created = store.putSound(soundMeta(), withFile(wav(1), "mon son.wav"));
    assert.match(created.id, /^s[a-z0-9]{6,24}$/);
    assert.equal(created.source.type, "file");
    assert.equal(created.source.mime, "audio/wav");
    assert.equal(created.source.file, created.id + ".wav");
    assert.deepEqual(store.readSoundFile(created.source.file).buffer, wav(1));
    assert.equal(store.readSoundFile(created.source.file).mime, "audio/wav");

    const edited = store.putSound(soundMeta({ name: "Renommé", volume: 0.3 }), undefined, created.id); // pas de nouveau fichier : l'ancien reste
    assert.equal(edited.name, "Renommé");
    assert.equal(edited.volume, 0.3);
    assert.equal(edited.source.file, created.source.file);
    assert.equal(edited.createdAt, created.createdAt);

    const replaced = store.putSound(soundMeta(), withFile(mp3(), "autre.mp3"), created.id); // l'ancien .wav est supprimé
    assert.equal(replaced.source.file, created.id + ".mp3");
    assert.equal(store.readSoundFile(created.id + ".wav"), null);
    assert.ok(store.readSoundFile(created.id + ".mp3"));

    const roblox = store.putSound(soundMeta({ source: { type: "roblox", assetId: "rbxassetid://12345" } }), undefined, created.id);
    assert.deepEqual(roblox.source, { type: "roblox", assetId: "rbxassetid://12345" });
    assert.equal(fs.readdirSync(path.join(base, "data", "sounds")).length, 0, "le fichier devenu inutile est supprimé");

    store.removeSound(created.id);
    assert.deepEqual(store.listSounds(), []);
    assert.throws(() => store.removeSound(created.id), (e) => e.status === 404);
  } finally {
    cleanup(base);
  }
});

test("sons : refus des fichiers dangereux ou invalides, du nom de fichier piégé, des métadonnées hors règles", () => {
  const { store, base } = newStore();
  try {
    assert.throws(() => store.putSound(soundMeta(), withFile(Buffer.from("MZ" + "x".repeat(60)), "virus.mp3")), /format audio non reconnu/);
    assert.throws(() => store.putSound(soundMeta(), withFile(Buffer.alloc(MAX_SOUND_BYTES + 1, 1), "gros.wav")), (e) => e.status === 413);
    assert.throws(() => store.putSound(soundMeta(), { name: "x.wav", dataBase64: "pas du base64 !!" }), /illisible/);
    assert.throws(() => store.putSound(soundMeta(), undefined), /fichier audio manquant/);
    const created = store.putSound(soundMeta(), withFile(wav(), "../../../etc/passwd.wav"));
    assert.ok(!created.source.originalName.includes("/") && !created.source.originalName.includes("\\"));
    assert.ok(fs.existsSync(path.join(base, "data", "sounds", created.source.file)));
    const bad = [
      null, soundMeta({ name: "x" }), soundMeta({ name: "x".repeat(41) }), soundMeta({ event: "inconnu" }), soundMeta({ category: "bruit" }),
      soundMeta({ volume: 1.5 }), soundMeta({ volume: -0.1 }), soundMeta({ volume: "fort" }), soundMeta({ loop: "oui" }), soundMeta({ enabled: 1 }),
      soundMeta({ note: "x".repeat(201) }), soundMeta({ source: null }), soundMeta({ source: { type: "url", url: "http://evil" } }),
      soundMeta({ source: { type: "roblox", assetId: "https://evil" } }), soundMeta({ source: { type: "roblox", assetId: "rbxassetid://abc" } }),
    ];
    for (const meta of bad) assert.throws(() => store.putSound(meta, withFile(wav())), StoreError, JSON.stringify(meta).slice(0, 80));
    assert.equal(store.listSounds().length, 1, "aucun son invalide n'a été enregistré");
    assert.throws(() => store.putSound(soundMeta(), withFile(wav()), "sinconnu123"), (e) => e.status === 404);
  } finally {
    cleanup(base);
  }
});

test("sons : une source « aucune » ou Roblox n'exige pas de fichier ; le nombre de sons est plafonné", () => {
  const { store, base } = newStore();
  try {
    assert.equal(store.putSound(soundMeta({ source: { type: "none" } })).source.type, "none");
    for (let i = 1; i < MAX_SOUNDS; i++) store.putSound(soundMeta({ source: { type: "roblox", assetId: "rbxassetid://" + i } }));
    assert.throws(() => store.putSound(soundMeta({ source: { type: "none" } })), (e) => e.status === 429);
  } finally {
    cleanup(base);
  }
});

test("sons : readSoundFile ne sert que des noms au bon format (aucune traversée de dossier)", () => {
  const { store, base } = newStore();
  try {
    store.putSound(soundMeta(), withFile(wav()));
    for (const name of ["../settings.json", "..\\x.wav", "s123456.exe", "sabcdef", "x.wav", "", "s/../../a.wav"]) assert.equal(store.readSoundFile(name), null, name);
  } finally {
    cleanup(base);
  }
});

// ----- vue d'ensemble, sauvegarde, restauration ---------------------------------------------------------------------------
function populate(store, base) {
  store.putChat(chat("caaaaaa1", { updatedAt: 500 }));
  store.putChat(chat("caaaaaa2", { updatedAt: 700, messages: [{ role: "assistant", content: "ok", drafts: [{ type: "chat", fields: { text: "Bravo !" }, note: "" }], draftKey: "m1" }] }));
  store.putSettings({ model: "openai/gpt-oss-20b", tab: "tests" });
  const withAudio = store.putSound(soundMeta({ name: "Boum" }), withFile(ogg(), "boum.ogg"));
  const asset = store.putSound(soundMeta({ name: "Musique", event: "menu_music", category: "music", loop: true, source: { type: "roblox", assetId: "rbxassetid://777" } }));
  fs.mkdirSync(path.join(base, "contributions"), { recursive: true });
  fs.writeFileSync(path.join(base, "contributions", "1700000000000-abc123.json"), JSON.stringify({ type: "chat", fields: { id: "bravo", text: "Bravo !" }, note: "", status: "applied", result: "Ajoutée.", createdAt: 1700000000000 }));
  fs.mkdirSync(path.join(base, "runs"), { recursive: true });
  fs.writeFileSync(path.join(base, "runs", "1700000000500.json"), JSON.stringify({ startedAt: 1700000000500, finishedAt: 1700000002500, durationMs: 2000, passed: 9, failed: 1, suites: 2, filter: "", trigger: "site", ok: false, failures: [] }));
  return { withAudio, asset };
}

test("vue d'ensemble : nombre et taille de chaque type de donnée", () => {
  const { store, base } = newStore();
  try {
    populate(store, base);
    const stats = store.stats();
    assert.equal(stats.chats.count, 2);
    assert.ok(stats.chats.bytes > 0);
    assert.equal(stats.contributions.count, 1);
    assert.equal(stats.runs.count, 1);
    assert.equal(stats.sounds.count, 2);
    assert.ok(stats.sounds.bytes >= ogg().length);
    assert.equal(stats.settings.exists, true);
    assert.equal(stats.dir.endsWith("data"), true);
  } finally {
    cleanup(base);
  }
});

test("sauvegarde puis restauration dans un stockage vide : tout est retrouvé à l'identique, fichiers audio compris", () => {
  const a = newStore();
  const b = newStore();
  try {
    const { withAudio } = populate(a.store, a.base);
    const bundle = JSON.parse(JSON.stringify(a.store.backup())); // passe par JSON comme un vrai fichier
    assert.equal(bundle.format, "registre-backup");
    assert.equal(bundle.chats.length, 2);
    const report = b.store.restore(bundle);
    assert.deepEqual({ chats: report.chats, contributions: report.contributions, runs: report.runs, sounds: report.sounds, settings: report.settings }, { chats: 2, contributions: 1, runs: 1, sounds: 2, settings: true });
    assert.deepEqual(report.ignored, []);
    assert.deepEqual(b.store.listChats(), a.store.listChats());
    assert.deepEqual(b.store.getSettings(), a.store.getSettings());
    assert.deepEqual(b.store.listSounds().map((s) => s.id).sort(), a.store.listSounds().map((s) => s.id).sort());
    assert.deepEqual(b.store.readSoundFile(withAudio.source.file).buffer, ogg(), "les octets audio sont identiques");
    assert.equal(b.store.stats().contributions.count, 1);
    assert.equal(b.store.stats().runs.count, 1);
  } finally {
    cleanup(a.base, b.base);
  }
});

test("restauration : fusion prudente (le plus récent gagne, rien n'est supprimé) et deux restaurations de suite sont inoffensives", () => {
  const a = newStore();
  const b = newStore();
  try {
    populate(a.store, a.base);
    b.store.putChat(chat("caaaaaa1", { updatedAt: 9999, title: "Version plus récente locale" }));
    b.store.putChat(chat("cunique01", { updatedAt: 1 }));
    const bundle = JSON.parse(JSON.stringify(a.store.backup()));
    const first = b.store.restore(bundle);
    assert.equal(first.chats, 1, "seule la conversation absente est ajoutée");
    assert.equal(b.store.listChats().find((c) => c.id === "caaaaaa1").title, "Version plus récente locale");
    assert.ok(b.store.listChats().some((c) => c.id === "cunique01"), "rien n'est supprimé");
    const second = b.store.restore(bundle);
    assert.deepEqual({ chats: second.chats, contributions: second.contributions, runs: second.runs, sounds: second.sounds }, { chats: 0, contributions: 0, runs: 0, sounds: 0 });
    // une conversation plus ancienne dans le fichier ne remplace jamais la locale ; une plus récente oui
    const newer = JSON.parse(JSON.stringify(bundle));
    newer.chats.find((c) => c.id === "caaaaaa2").updatedAt = 99999999;
    newer.chats.find((c) => c.id === "caaaaaa2").title = "Mise à jour importée";
    assert.equal(b.store.restore(newer).chats, 1);
    assert.equal(b.store.listChats().find((c) => c.id === "caaaaaa2").title, "Mise à jour importée");
  } finally {
    cleanup(a.base, b.base);
  }
});

test("restauration : fichier non reconnu refusé ; éléments invalides ignorés avec leur raison, les bons sont gardés", () => {
  const { store, base } = newStore();
  try {
    for (const bad of [null, "x", [], {}, { format: "autre", version: 1 }, { format: "registre-backup", version: 2 }]) assert.throws(() => store.restore(bad), StoreError);
    const report = store.restore({
      format: "registre-backup", version: 1,
      chats: [chat("caaaaaa1"), chat("../evil"), { id: "caaaaaa9" }],
      contributions: [
        { _id: "1700000000000-abc123", type: "chat", fields: { id: "bravo", text: "Bravo !" }, note: "", status: "pending", createdAt: 1700000000000 },
        { _id: "../../evil", type: "chat", fields: { id: "x", text: "y" }, status: "pending" },
        { _id: "1700000000001-abc123", type: "chat", fields: { id: "X", text: "mal formé" }, status: "pending" },
        { _id: "1700000000002-abc123", type: "chat", fields: { id: "ok", text: "ok" }, status: "piraté" },
      ],
      runs: [{ startedAt: 1700000000500, finishedAt: 1700000001500, passed: 1, failed: 0, suites: 1, trigger: "site" }, { startedAt: "x" }, { startedAt: 1, finishedAt: 2, passed: 1, failed: 0, suites: 1, trigger: "t", filter: "-rf" }],
      settings: { tab: "pirate" },
      sounds: [
        { id: "sabcdef01", ...soundMeta({ source: { type: "roblox", assetId: "rbxassetid://5" } }) },
        { id: "../evil", ...soundMeta() },
        { id: "sabcdef02", ...soundMeta(), source: { type: "file", originalName: "x.mp3" }, fileData: b64(Buffer.from("MZ" + "x".repeat(60))) },
      ],
    });
    assert.deepEqual({ chats: report.chats, contributions: report.contributions, runs: report.runs, sounds: report.sounds, settings: report.settings }, { chats: 1, contributions: 1, runs: 1, sounds: 1, settings: false });
    assert.ok(report.ignored.length >= 8);
    assert.ok(report.ignored.some((line) => /format audio non reconnu/.test(line)));
    assert.equal(store.listChats().length, 1);
    assert.equal(store.listSounds().length, 1);
    assert.equal(fs.readdirSync(path.join(base, "contributions")).length, 1);
    assert.ok(!fs.existsSync(path.join(base, "..", "evil")));
  } finally {
    cleanup(base);
  }
});

// ----- routes HTTP ---------------------------------------------------------------------------------------------------------------
const H = { "X-Registre": "1", "Content-Type": "application/json" };
function request(port, method, url, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path: url, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const buffer = Buffer.concat(chunks);
        resolve({ status: res.statusCode, headers: res.headers, buffer, json: () => JSON.parse(buffer.toString("utf8")) });
      });
    });
    req.on("error", reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}
async function withServer(fn) {
  const base = tmp();
  const server = createServer({ dir: path.join(base, "contributions"), runsDir: path.join(base, "runs"), dataDir: path.join(base, "data"), initialData: sampleData(), collect: async () => sampleData() });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await fn(server.address().port, base);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    cleanup(base);
  }
}

test("routes : toutes les routes de stockage exigent l'en-tête de protection", async () => {
  await withServer(async (port) => {
    for (const [method, url] of [["GET", "/api/storage"], ["GET", "/api/settings"], ["PUT", "/api/settings"], ["GET", "/api/chats"], ["DELETE", "/api/chats"], ["PUT", "/api/chats/caaaaaa1"], ["GET", "/api/sounds"], ["POST", "/api/sounds"], ["GET", "/api/backup"], ["POST", "/api/backup"]]) {
      const res = await request(port, method, url, { headers: { "Content-Type": "application/json" }, body: method === "GET" || method === "DELETE" ? undefined : "{}" });
      assert.equal(res.status, 403, method + " " + url);
    }
  });
});

test("routes : conversations (créer, relire, identifiant incohérent, supprimer, tout effacer)", async () => {
  await withServer(async (port) => {
    assert.equal((await request(port, "PUT", "/api/chats/caaaaaa1", { headers: H, body: JSON.stringify(chat("caaaaaa1")) })).status, 200);
    assert.equal((await request(port, "PUT", "/api/chats/caaaaaa2", { headers: H, body: JSON.stringify(chat("caaaaaa1")) })).status, 400);
    assert.equal((await request(port, "PUT", "/api/chats/caaaaaa3", { headers: H, body: JSON.stringify(chat("caaaaaa3", { messages: [] })) })).status, 422);
    assert.equal((await request(port, "PUT", "/api/chats/caaaaaa4", { headers: H, body: "{cassé" })).status, 400);
    assert.equal((await request(port, "PUT", "/api/chats/caaaaaa5", { headers: H, body: JSON.stringify(chat("caaaaaa5", { messages: [{ role: "user", content: "x".repeat(800000) }] })) })).status, 413);
    assert.equal((await request(port, "GET", "/api/chats", { headers: H })).json().length, 1);
    for (const bad of ["..%2f..%2fx", "x", "C1234567"]) assert.notEqual((await request(port, "DELETE", "/api/chats/" + bad, { headers: H })).status, 200, bad);
    assert.equal((await request(port, "DELETE", "/api/chats/caaaaaa1", { headers: H })).status, 200);
    assert.equal((await request(port, "DELETE", "/api/chats/caaaaaa1", { headers: H })).status, 404);
    await request(port, "PUT", "/api/chats/caaaaaa6", { headers: H, body: JSON.stringify(chat("caaaaaa6")) });
    assert.equal((await request(port, "DELETE", "/api/chats", { headers: H })).json().removed, 1);
  });
});

test("routes : réglages (jamais de clé) et vue d'ensemble", async () => {
  await withServer(async (port) => {
    assert.deepEqual((await request(port, "GET", "/api/settings", { headers: H })).json(), {});
    assert.equal((await request(port, "PUT", "/api/settings", { headers: H, body: JSON.stringify({ tab: "pirate" }) })).status, 422);
    const put = await request(port, "PUT", "/api/settings", { headers: H, body: JSON.stringify({ tab: "sons", apiKey: "gsk_" + "A".repeat(40) }) });
    assert.deepEqual(put.json(), { tab: "sons" });
    assert.equal((await request(port, "GET", "/api/storage", { headers: H })).json().settings.exists, true);
  });
});

test("routes : sons (création avec fichier, lecture audio, modification, suppression, refus)", async () => {
  await withServer(async (port) => {
    const created = await request(port, "POST", "/api/sounds", { headers: H, body: JSON.stringify({ sound: soundMeta(), file: withFile(wav(3), "boum.wav") }) });
    assert.equal(created.status, 201);
    const sound = created.json();
    const audio = await request(port, "GET", "/sounds/" + sound.source.file); // sans en-tête : le lecteur audio n'en envoie pas
    assert.equal(audio.status, 200);
    assert.equal(audio.headers["content-type"], "audio/wav");
    assert.equal(audio.headers["x-content-type-options"], "nosniff");
    assert.deepEqual(audio.buffer, wav(3));
    for (const bad of ["/sounds/..%2fsettings.json", "/sounds/s123456.exe", "/sounds/sabcdef0.wav", "/sounds/", "/sounds/..%5c..%5cx.wav"]) assert.notEqual((await request(port, "GET", bad)).status, 200, bad);

    const edited = await request(port, "PUT", "/api/sounds/" + sound.id, { headers: H, body: JSON.stringify({ sound: soundMeta({ name: "Renommé" }) }) });
    assert.equal(edited.status, 200);
    assert.equal(edited.json().name, "Renommé");
    assert.equal((await request(port, "GET", "/api/sounds", { headers: H })).json().length, 1);

    assert.equal((await request(port, "POST", "/api/sounds", { headers: H, body: JSON.stringify({ sound: soundMeta(), file: withFile(Buffer.from("MZ" + "x".repeat(60))) }) })).status, 422);
    assert.equal((await request(port, "POST", "/api/sounds", { headers: H, body: JSON.stringify({ sound: soundMeta({ volume: 7 }), file: withFile(wav()) }) })).status, 422);
    assert.equal((await request(port, "POST", "/api/sounds", { headers: H, body: JSON.stringify({ sound: soundMeta(), file: withFile(Buffer.alloc(MAX_SOUND_BYTES + 5000, 1)) }) })).status, 413);
    assert.equal((await request(port, "PUT", "/api/sounds/pasunid", { headers: H, body: JSON.stringify({ sound: soundMeta() }) })).status, 400);
    assert.equal((await request(port, "PUT", "/api/sounds/sinconnu12", { headers: H, body: JSON.stringify({ sound: soundMeta(), file: withFile(wav()) }) })).status, 404);

    assert.equal((await request(port, "DELETE", "/api/sounds/" + sound.id, { headers: H })).status, 200);
    assert.equal((await request(port, "GET", "/sounds/" + sound.source.file)).status, 404);
    assert.equal((await request(port, "DELETE", "/api/sounds/" + sound.id, { headers: H })).status, 404);
  });
});

test("routes : sauvegarde téléchargée puis restaurée sur un autre serveur", async () => {
  let bundleText;
  await withServer(async (port, base) => {
    const store = createStore({ dir: path.join(base, "data"), contributionsDir: path.join(base, "contributions"), runsDir: path.join(base, "runs") });
    populate(store, base);
    const res = await request(port, "GET", "/api/backup", { headers: H });
    assert.equal(res.status, 200);
    bundleText = res.buffer.toString("utf8");
  });
  await withServer(async (port, base) => {
    const restored = await request(port, "POST", "/api/backup", { headers: H, body: bundleText });
    assert.equal(restored.status, 200);
    const report = restored.json();
    assert.deepEqual({ chats: report.chats, contributions: report.contributions, runs: report.runs, sounds: report.sounds }, { chats: 2, contributions: 1, runs: 1, sounds: 2 });
    assert.equal((await request(port, "GET", "/api/chats", { headers: H })).json().length, 2);
    const stats = (await request(port, "GET", "/api/storage", { headers: H })).json();
    assert.equal(stats.sounds.count, 2);
    assert.equal((await request(port, "POST", "/api/backup", { headers: H, body: JSON.stringify({ format: "autre" }) })).status, 422);
    assert.equal((await request(port, "POST", "/api/backup", { headers: H, body: "{cassé" })).status, 400);
    assert.ok(fs.existsSync(path.join(base, "data", "chats")));
  });
});
