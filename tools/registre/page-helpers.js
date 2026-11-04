"use strict";
// Outils communs aux tests de la page générée : faux navigateur (éléments, stockage, fetch) et jeu de données minimal.
const vm = require("node:vm");
const { buildHtml } = require("./serve");

const FAKE_KEY = "gsk_" + "B".repeat(40);
const T0 = 1793800000000; // 4 novembre 2026

function sampleRuns() {
  return [{ startedAt: T0, finishedAt: T0 + 2000, durationMs: 2000, passed: 2, failed: 0, suites: 1, filter: "", trigger: "demarrage", ok: true, failures: [] }];
}

function sampleData(error) {
  const results = [
    { suite: "server/Demo", name: "premier test", ok: true, seconds: 0 },
    { suite: "server/Demo", name: "second test", ok: true, seconds: 0 },
  ];
  return {
    generatedAt: "aujourd'hui",
    tests: { passed: 2, failed: 0, suites: 1, results, error: error || "" },
    runs: sampleRuns(),
    game: {
      version: "t",
      cosmetics: {
        bomb: [
          { id: "bomb_classic", name: "Classique", price: 0, color: "#23232d", material: "SmoothPlastic", description: "Standard.", kind: "bomb" },
          { id: "bomb_red", name: "Rouge", price: 250, color: "#c82828", material: "SmoothPlastic", description: "Rouge.", kind: "bomb" },
        ],
        effect: [
          { id: "effect_classic", name: "Classique", price: 0, color: "#ff961e", description: "Standard.", kind: "effect" },
          { id: "effect_red", name: "Rouge", price: 250, color: "#f03228", description: "Rouge.", kind: "effect" },
        ],
      },
      cosmeticDefaults: { bomb: "bomb_classic", effect: "effect_classic" },
      quests: [{ id: "play3", name: "Premiers pas", description: "Jouer 3 manches", event: "round_played", goal: 3, reward: 30 }],
      map: {
        cellSize: 4, defaultSize: "Medium", defaultTheme: "Classic", crateDensity: 0.55, spawnSafeDistance: 2,
        sizes: [{ id: "Medium", size: 16, enabled: true, pillarAxis: [3, 5], minPlayers: 4, maxPlayers: 6, spawns: [{ x: 1, y: 1 }] }],
        themes: [{ id: "Classic", displayName: "Classique", modular: true, lighting: { clockTime: 14, brightness: 2, ambient: "#000000", outdoorAmbient: "#000000" }, decorKinds: ["Tree"], floorColorA: "#111111", floorColorB: "#222222", floorAccentColor: "#333333", pillarColor: "#444444", crateColor: "#555555", borderColor: "#666666", groundColor: "#777777", decorPrimary: "#888888" }],
      },
      powerups: [{ id: "BombPlus", displayName: "Bomb+", description: "Une bombe de plus.", stat: "bombCapacity", amount: 1 }],
      emotes: { maxLoopSeconds: 8, list: [{ id: "wave", name: "Salut", animationId: "rbxassetid://1", looped: false }] },
      quickChat: { bubbleSeconds: 3.5, maxRecents: 5, maxFavorites: 8, defaultFavorites: ["gg"], phrases: [{ id: "gg", text: "GG !" }] },
      settings: { round: { RoundDuration: 150, QuickCountdown: 6, ResultDuration: 8 }, bomb: { FuseTime: 2, ExplosionDuration: 0.5, MaxCapacity: 5, MaxBlastRange: 6 }, movement: { MaxSpeedPickups: 3, SpeedBonusPerPickup: 2 }, powerupDrops: { DropChancePerCrate: 0.25, MaxShield: 1 }, remoteLimits: {}, rewards: { ParticipationCoins: 10, WinCoins: 50, DrawCoins: 20 }, data: {} },
    },
    untested: { untested: { Types: "Déclarations de types uniquement." } },
    manifest: { createur: "test", assets: [{ fichier: "assets/ui/logo.png", sha256: "a".repeat(64), dimensions: "10x10", assetId: "rbxassetid://1", type: "Image", importeLe: "2026-10-31", utilisePar: "AssetIds : Logo" }] },
  };
}

function storage(initial) {
  const m = new Map(Object.entries(initial || {}));
  return { getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k), m };
}

// Lance le vrai script de la page dans un faux navigateur. `local` / `session` : contenu initial des stockages.
function boot({ session, local, fetchImpl, error, data }) {
  const els = {};
  const asideHandlers = {};
  const mk = (id) => ({
    id, innerHTML: "", hidden: false, value: "", checked: false, textContent: "", attrs: {}, handlers: {}, disabled: false, scrollTop: 0, scrollHeight: 0,
    setAttribute(k, v) { this.attrs[k] = v; }, getAttribute(k) { return this.attrs[k]; },
    addEventListener(t, f) { this.handlers[t] = f; }, appendChild() {}, closest() { return null; },
    querySelectorAll() { return []; },
    querySelector(sel) {
      if (sel === "aside") return { addEventListener: (t, f) => { asideHandlers[t] = f; } };
      return mk("child:" + sel);
    },
  });
  const html = buildHtml(data || sampleData(error));
  const scripts = [...html.matchAll(/<script( id="data" type="application\/json")?>([\s\S]*?)<\/script>/g)];
  const dataText = scripts[0][2];
  const sandbox = {
    document: {
      getElementById: (id) => { const e = els[id] || (els[id] = mk(id)); if (id === "data") e.textContent = dataText; return e; },
      querySelectorAll: () => [], createElement: () => mk("created"), createTextNode: () => ({}), visibilityState: "visible",
      body: { appendChild() {} },
    },
    location: { hash: "", reload() {} },
    navigator: {},
    btoa: (x) => Buffer.from(x, "binary").toString("base64"), Uint8Array, Blob, URL: { createObjectURL: () => "blob:test" },
    AbortController, setTimeout, clearTimeout, setInterval: () => 0, console, JSON, Promise, Date,
    fetch: fetchImpl,
  };
  sandbox.window = { addEventListener() {}, localStorage: storage(local), sessionStorage: storage(session) };
  vm.createContext(sandbox);
  vm.runInContext(scripts[1][2], sandbox);
  return { els, asideHandlers, sandbox, localStorage: sandbox.window.localStorage };
}

const wait = (ms = 15) => new Promise((resolve) => setTimeout(resolve, ms));
const ok = (body) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(body) });
const failure = (status, error) => Promise.resolve({ ok: false, status, json: () => Promise.resolve({ error }) });

// Faux serveur local : contributions en mémoire, lancement de tests simulé, Groq programmable (calls.groq).
function fakeServer() {
  const items = [];
  const calls = [];
  const state = { runs: sampleRuns(), runError: "", runBodies: [], chats: new Map(), settings: {}, sounds: [], storageDown: false, backup: null, restored: [], downloads: 0, now: T0 };
  const LIMITS = { soundEvents: ["bomb_place", "explosion", "menu_music", "custom"], soundCategories: ["sfx", "music", "ui"], maxSoundBytes: 1500000, maxSounds: 40, maxChats: 200 };
  function storageRoute(url, init) {
    const method = init.method || "GET";
    const body = init.body ? JSON.parse(init.body) : undefined;
    if (url === "/api/chats" && method === "GET") return ok([...state.chats.values()]);
    if (url === "/api/chats" && method === "DELETE") { const n = state.chats.size; state.chats.clear(); return ok({ removed: n }); }
    let m = new RegExp("^/api/chats/([^/]+)$").exec(url);
    if (m && method === "PUT") { state.chats.set(m[1], body); return ok(body); }
    if (m && method === "DELETE") return state.chats.delete(m[1]) ? ok({ removed: m[1] }) : failure(404, "introuvable");
    if (url === "/api/settings" && method === "GET") return ok(state.settings);
    if (url === "/api/settings" && method === "PUT") { state.settings = body; return ok(body); }
    if (url === "/api/storage") {
      const bytes = (n) => ({ count: n, bytes: n * 100 });
      return ok({ dir: "tools/registre/data", chats: bytes(state.chats.size), contributions: bytes(items.length), runs: bytes(state.runs.length), sounds: bytes(state.sounds.length), settings: { exists: Object.keys(state.settings).length > 0 }, limits: LIMITS });
    }
    if (url === "/api/sounds" && method === "GET") return ok(state.sounds.slice());
    if (url === "/api/sounds" && method === "POST") {
      const sound = Object.assign({ id: "s" + (100000 + state.sounds.length), createdAt: state.now, updatedAt: state.now }, body.sound);
      if (sound.source.type === "file") sound.source = { type: "file", file: sound.id + ".wav", originalName: body.file.name, mime: "audio/wav", bytes: 40 };
      state.sounds.push(sound); state.lastSoundBody = body;
      return ok(sound);
    }
    m = new RegExp("^/api/sounds/([^/]+)$").exec(url);
    if (m && method === "PUT") {
      const i = state.sounds.findIndex((x) => x.id === m[1]);
      if (i < 0) return failure(404, "son introuvable");
      const old = state.sounds[i];
      const next = Object.assign({}, old, body.sound, { id: old.id });
      if (body.sound.source.type === "file") next.source = body.file ? { type: "file", file: old.id + ".wav", originalName: body.file.name, mime: "audio/wav", bytes: 40 } : old.source;
      state.sounds[i] = next; state.lastSoundBody = body;
      return ok(next);
    }
    if (m && method === "DELETE") { state.sounds = state.sounds.filter((x) => x.id !== m[1]); return ok({ removed: m[1] }); }
    if (url === "/api/backup" && method === "GET") { state.downloads++; return ok(state.backup || { format: "registre-backup", version: 1, chats: [...state.chats.values()] }); }
    if (url === "/api/backup" && method === "POST") {
      if (body.format !== "registre-backup") return failure(422, "fichier de sauvegarde non reconnu");
      state.restored.push(body);
      (body.chats || []).forEach((c) => state.chats.set(c.id, c));
      return ok({ chats: (body.chats || []).length, contributions: 0, runs: 0, sounds: 0, settings: false, ignored: body.ignored || [] });
    }
    return null;
  }
  const fetchImpl = (url, init) => {
    init = init || {};
    calls.push({ url, method: init.method || "GET", headers: init.headers || {}, body: init.body });
    if (new RegExp("^/api/(chats|settings|storage|sounds|backup)").test(url)) return state.storageDown ? Promise.reject(new TypeError("serveur arrêté")) : (storageRoute(url, init) || ok({}));
    if (url === "/api/contributions" && (init.method || "GET") === "GET") return ok(items.slice());
    if (url === "/api/contributions" && init.method === "POST") {
      const doc = JSON.parse(init.body);
      items.unshift(Object.assign({}, doc, { _id: "17000000000" + items.length + "-abcdef" }));
      return ok({ id: "x" });
    }
    if (url === "/api/tests/run" && init.method === "POST") {
      const body = JSON.parse(init.body);
      state.runBodies.push(body);
      if (state.runError) return failure(500, state.runError);
      const startedAt = T0 + 60000 * (state.runs.length + 1);
      state.runs.unshift({ startedAt, finishedAt: startedAt + 1500, durationMs: 1500, passed: 3, failed: 0, suites: 1, filter: body.filter || "", trigger: "site", ok: true, failures: [] });
      const report = { passed: 3, failed: 0, suites: 1, results: [{ suite: "server/Demo", name: "test relancé", ok: true, seconds: 0 }], error: "" };
      return ok({ report, runs: state.runs.slice() });
    }
    if (url.startsWith("https://api.groq.com/")) return calls.groq ? calls.groq(url, init) : Promise.reject(new TypeError("réseau"));
    return ok({});
  };
  return { fetchImpl, items, calls, state };
}

function fillQuestForm(els, values) {
  for (const [k, v] of Object.entries(values)) {
    els["f-" + k] = els["f-" + k] || { value: "", checked: false, attrs: {}, handlers: {}, setAttribute() {}, getAttribute() { return null; }, addEventListener() {} };
    els["f-" + k].value = String(v);
  }
  for (const k of ["name", "description", "goal", "reward", "event"]) els["e-" + k] = { textContent: "" };
  els["auto-id"] = { textContent: "" };
  els["send-msg"] = { textContent: "" };
  els["send-btn"] = { disabled: false };
}

module.exports = { FAKE_KEY, T0, sampleData, sampleRuns, boot, wait, ok, failure, fakeServer, fillQuestForm, storage };
