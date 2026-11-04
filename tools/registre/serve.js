#!/usr/bin/env node
"use strict";
// Registre BOOM BATTLE (version locale) : tableau de bord des tests, des données du jeu et des assets, avec un assistant
// Groq et un formulaire dont les contributions sont ÉCRITES dans le dépôt (tools/registre/contributions/*.json).
//
//   node tools/registre/serve.js [port]     puis ouvrir l'adresse affichée (http://127.0.0.1:4173 par défaut)
//
// Sécurité : le serveur n'écoute QUE sur 127.0.0.1 ; les écritures exigent un en-tête personnalisé (bloque l'envoi depuis un autre
// site) et passent par la même validation stricte que apply.js ; il ne sert que les images de assets/ui. La clé Groq n'est jamais
// transmise au serveur ni écrite sur disque : le navigateur l'envoie directement à api.groq.com.
// Ensuite : « node tools/registre/apply.js » applique les contributions en attente aux fichiers de src/shared (avec les tests).

const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { validate } = require("./validate");
const { createProjects, ProjectError } = require("./projects");
const { createActivity } = require("./activity");
const { createBoard, BoardError, STATUSES, PRIORITIES, TYPES } = require("./board");
const { createJournal, JournalError, SCHEMAS } = require("./journal");
const { createStore, StoreError, SOUND_EVENTS, SOUND_CATEGORIES, MAX_SOUND_BYTES, MAX_SOUNDS, MAX_CHATS } = require("./store");

const ROOT = path.resolve(__dirname, "..", "..");
const DEFAULT_DIR = path.join(__dirname, "contributions");
const MAX_BODY = 20000;
const MAX_CONTRIBUTIONS = 500;
const ID_PATTERN = /^[0-9]{10,16}-[a-z0-9]{6}$/;
const DEFAULT_RUNS_DIR = path.join(__dirname, "runs");
const DEFAULT_DATA_DIR = path.join(__dirname, "data");
const BACKUP_MAX_BODY = 100000000;
const RUN_TIMEOUT_MS = 180000;
const MAX_RUNS = 100;
// Filtre de suite : lettres, chiffres, _ / . - et espace ; jamais de tiret en tête (aucune option ne peut être injectée).
const FILTER_PATTERN = /^[A-Za-z0-9_][A-Za-z0-9_/. -]{0,59}$/;

function findLune() {
  const candidates = ["lune"];
  if (process.env.LOCALAPPDATA) candidates.push(path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Links", "lune.exe"));
  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
    if (!probe.error && probe.status === 0) return candidate;
  }
  return null;
}

// Historique des exécutions de tests : un petit fichier JSON par exécution (date, durée, bilan, échecs), les ${MAX_RUNS} plus récents.
function saveRun(dir, run) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, run.startedAt + ".json"), JSON.stringify(run, null, 2) + "\n");
  const files = fs.readdirSync(dir).filter((n) => /^[0-9]{10,16}\.json$/.test(n)).sort();
  for (const old of files.slice(0, Math.max(0, files.length - MAX_RUNS))) fs.unlinkSync(path.join(dir, old));
}

function listRuns(dir) {
  if (!fs.existsSync(dir)) return [];
  const runs = [];
  for (const name of fs.readdirSync(dir)) {
    if (!/^[0-9]{10,16}\.json$/.test(name)) continue;
    try {
      const run = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));
      if (typeof run.startedAt === "number" && typeof run.passed === "number") runs.push(run);
    } catch {
      /* fichier illisible : ignoré */
    }
  }
  return runs.sort((a, b) => b.startedAt - a.startedAt).slice(0, MAX_RUNS);
}

function summarize(report, meta) {
  const failures = (report.results || []).filter((r) => !r.ok).slice(0, 20).map((r) => ({ suite: r.suite, name: r.name, message: String(r.message || "").slice(0, 300) }));
  return {
    startedAt: meta.startedAt,
    finishedAt: meta.finishedAt,
    durationMs: meta.finishedAt - meta.startedAt,
    passed: report.passed,
    failed: report.failed,
    suites: report.suites,
    filter: meta.filter || "",
    trigger: meta.trigger,
    ok: report.failed === 0,
    failures,
  };
}

// Lance les tests Lune SANS bloquer le serveur. Le rapport est écrit même quand des tests échouent (code de sortie 1).
// Retourne { report, run } ; lève une erreur lisible si les tests n'ont pas pu tourner (Lune absent, filtre sans résultat, délai).
function runLune({ filter, trigger }) {
  return new Promise((resolve, reject) => {
    const lune = findLune();
    if (!lune) return reject(new Error("Lune est introuvable : installe-le (winget install Lune.Lune)."));
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "registre-"));
    const reportFile = path.join(tmp, "tests.json");
    const args = ["run", "tests/run", "--", "--json", reportFile];
    if (filter) args.push(filter); // argument séparé (jamais de shell) : le filtre est déjà validé
    const startedAt = Date.now();
    const child = spawn(lune, args, { cwd: ROOT, stdio: "ignore" });
    let settled = false;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      try {
        if (error) return reject(error);
        if (!fs.existsSync(reportFile)) return reject(new Error(filter ? `Aucune suite ne correspond à « ${filter} ».` : "Le rapport de tests n'a pas pu être produit."));
        const report = Object.assign({ error: "" }, JSON.parse(fs.readFileSync(reportFile, "utf8")));
        resolve({ report, run: summarize(report, { startedAt, finishedAt: Date.now(), filter, trigger }) });
      } catch (e) {
        reject(e);
      } finally {
        fs.rmSync(tmp, { recursive: true, force: true });
      }
    };
    const timer = setTimeout(() => {
      child.kill();
      finish(new Error("Les tests ont dépassé le délai de " + RUN_TIMEOUT_MS / 1000 + " s : interrompus."));
    }, RUN_TIMEOUT_MS);
    child.on("error", (e) => finish(e));
    child.on("close", () => finish(null));
  });
}

// Rassemble les données affichées : tests (exécutés maintenant), données du jeu (export Luau), modules sans suite, manifeste.
async function collectData(options) {
  const opts = options || {};
  const runsDir = opts.runsDir || DEFAULT_RUNS_DIR;
  const data = {
    generatedAt: new Date().toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" }),
    tests: { passed: 0, failed: 0, suites: 0, results: [], error: "" },
    runs: [],
    game: null,
    untested: JSON.parse(fs.readFileSync(path.join(ROOT, "tests", "untested.json"), "utf8")),
    manifest: JSON.parse(fs.readFileSync(path.join(ROOT, "assets", "manifest.json"), "utf8")),
  };
  try {
    const { report, run } = await (opts.runTests || runLune)({ filter: "", trigger: opts.trigger || "demarrage" });
    data.tests = report;
    saveRun(runsDir, run);
    const lune = findLune();
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "registre-"));
    try {
      const gameFile = path.join(tmp, "game.json");
      const exported = spawnSync(lune, ["run", "tools/export_game_data", "--", gameFile], { cwd: ROOT, encoding: "utf8" });
      if (exported.status !== 0 || !fs.existsSync(gameFile)) throw new Error("L'export des données du jeu a échoué.");
      data.game = JSON.parse(fs.readFileSync(gameFile, "utf8"));
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  } catch (error) {
    data.tests.error = String(error.message || error);
  }
  data.runs = listRuns(runsDir);
  if (!data.game) data.game = emptyGame();
  return data;
}

function emptyGame() {
  return {
    version: "?", cosmetics: { bomb: [], effect: [] }, cosmeticDefaults: {}, quests: [],
    map: { cellSize: 4, defaultSize: "", defaultTheme: "", crateDensity: 0, spawnSafeDistance: 0, sizes: [], themes: [] },
    powerups: [], emotes: { maxLoopSeconds: 0, list: [] }, quickChat: { bubbleSeconds: 0, maxRecents: 0, maxFavorites: 0, defaultFavorites: [], phrases: [] },
    settings: { round: {}, bomb: {}, movement: {}, powerupDrops: { DropChancePerCrate: 0 }, remoteLimits: {}, rewards: {}, data: {} },
  };
}

function buildHtml(data) {
  const template = fs.readFileSync(path.join(__dirname, "template.html"), "utf8");
  const backend = fs.readFileSync(path.join(__dirname, "adapter-local.js"), "utf8");
  const core = ["core.js", "journal-suggestions.js", "board-ui.js", "projects-ui.js"].map(name => fs.readFileSync(path.join(__dirname, name), "utf8")).join("\n");
  const json = JSON.stringify(data).replace(/</g, "\\u003c");
  return template
    .replace("/*__BACKEND__*/", () => backend)
    .replace("/*__EXTRA__*/", () => core)
    .replace("__DATA__", () => json);
}

function send(res, status, body, type) {
  const payload = typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": type || "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; media-src 'self'; connect-src 'self' https://api.groq.com; frame-ancestors 'none'",
  });
  res.end(payload);
}

function readBody(req, limit) {
  const max = limit || MAX_BODY;
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > Math.max(5000000, max * 2)) {
        req.destroy(); // abus manifeste : on coupe la connexion
        return;
      }
      if (size <= max) chunks.push(chunk); // au-delà de la limite on jette la suite, la réponse 413 part à la fin
    });
    req.on("end", () => (size > max ? reject(Object.assign(new Error("corps trop gros"), { status: 413 })) : resolve(Buffer.concat(chunks).toString("utf8"))));
    req.on("error", reject);
  });
}

function listContributions(dir) {
  if (!fs.existsSync(dir)) return [];
  const items = [];
  for (const name of fs.readdirSync(dir)) {
    const id = name.replace(/\.json$/, "");
    if (!name.endsWith(".json") || !ID_PATTERN.test(id)) continue;
    try {
      const doc = JSON.parse(fs.readFileSync(path.join(dir, name), "utf8"));
      items.push(Object.assign({}, doc, { _id: id }));
    } catch {
      /* fichier illisible : ignoré, jamais bloquant */
    }
  }
  return items.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)).slice(0, 200);
}

function createServer(options) {
  const dir = options.dir || DEFAULT_DIR;
  const runsDir = options.runsDir || DEFAULT_RUNS_DIR;
  const runTests = options.runTests || runLune;
  const dataDir = options.dataDir || DEFAULT_DATA_DIR;
  const projects = createProjects({ dir: dataDir, ...(options.projectOptions || {}) });
  const activity = createActivity(path.join(dataDir, "activity.json"));
  const board = createBoard({ dir: dataDir, activity });
  const journal = createJournal({ dir: dataDir, activity });
  const store = createStore({ dir: dataDir, contributionsDir: dir, runsDir, extras: [board.extra, journal.extra, activity.extra] });

  async function jsonBody(req, limit) {
    let raw;
    try {
      raw = await readBody(req, limit);
    } catch (error) {
      throw new StoreError(error.status === 413 ? "données trop volumineuses" : "demande invalide", error.status || 400);
    }
    try {
      return raw ? JSON.parse(raw) : {};
    } catch {
      throw new StoreError("JSON invalide", 400);
    }
  }

  // Routes de stockage durable : conversations, réglages, sons, vue d'ensemble, sauvegarde. Retourne true si la route a répondu.
  async function storageRoutes(req, res, url) {
    const method = req.method;
    const p = url.pathname;
    try {
      if (p === "/api/projects") {
        if (method === "GET") return send(res, 200, projects.list()), true;
        if (method === "POST") return send(res, 201, await projects.add(await jsonBody(req, 8000))), true;
      }
      if (method === "POST" && p === "/api/projects/pick-folder") return send(res, 200, await projects.pick()), true;
      const projectRefresh = /^\/api\/projects\/(p[a-f0-9]{16})\/refresh$/.exec(p);
      if (method === "POST" && projectRefresh) return send(res, 200, projects.refresh(projectRefresh[1])), true;
      const profile = /^\/api\/projects\/(boom|luma|p[a-f0-9]{16})$/.exec(p);
      if (profile) {
        if (method === "GET") return send(res, 200, projects.get(profile[1])), true;
        if (method === "PATCH") return send(res, 200, projects.update(profile[1], await jsonBody(req, 12000))), true;
        if (method === "DELETE") return send(res, 200, projects.remove(profile[1])), true;
      }
      if (method === "GET" && p === "/api/storage") return send(res, 200, Object.assign(store.stats(), { limits: { soundEvents: SOUND_EVENTS, soundCategories: SOUND_CATEGORIES, maxSoundBytes: MAX_SOUND_BYTES, maxSounds: MAX_SOUNDS, maxChats: MAX_CHATS } })), true;

      if (p === "/api/settings") {
        if (method === "GET") return send(res, 200, store.getSettings()), true;
        if (method === "PUT") return send(res, 200, store.putSettings(await jsonBody(req, 4000))), true;
      }

      if (p === "/api/chats") {
        if (method === "GET") return send(res, 200, store.listChats()), true;
        if (method === "DELETE") return send(res, 200, { removed: store.clearChats() }), true;
      }
      const chat = /^\/api\/chats\/([^/]+)$/.exec(p);
      if (chat) {
        const id = decodeURIComponent(chat[1]);
        if (method === "PUT") {
          const body = await jsonBody(req, 700000);
          if (!body || body.id !== id) throw new StoreError("identifiant incohérent", 400);
          return send(res, 200, { id: store.putChat(body).id }), true;
        }
        if (method === "DELETE") return store.removeChat(id), send(res, 200, { ok: true }), true;
      }

      if (p === "/api/sounds") {
        if (method === "GET") return send(res, 200, store.listSounds()), true;
        if (method === "POST") {
          const body = await jsonBody(req, 2400000);
          return send(res, 201, store.putSound(body.sound, body.file)), true;
        }
      }
      const sound = /^\/api\/sounds\/([^/]+)$/.exec(p);
      if (sound) {
        const id = decodeURIComponent(sound[1]);
        if (method === "PUT") {
          const body = await jsonBody(req, 2400000);
          if (!/^s[a-z0-9]{6,24}$/.test(id)) throw new StoreError("identifiant invalide", 400);
          return send(res, 200, store.putSound(body.sound, body.file, id)), true;
        }
        if (method === "DELETE") return store.removeSound(id), send(res, 200, { ok: true }), true;
      }

      if (method === "GET" && p === "/api/schema") return send(res, 200, { journal: SCHEMAS, board: { statuses: STATUSES, priorities: PRIORITIES, types: TYPES } }), true;
      if (method === "GET" && p === "/api/activity") return send(res, 200, activity.list(Number(url.searchParams.get("limit")) || 200)), true;

      if (p === "/api/tickets") {
        if (method === "GET") return send(res, 200, board.list()), true;
        if (method === "POST") return send(res, 201, board.create(await jsonBody(req, 20000))), true;
      }
      const ticket = new RegExp("^/api/tickets/([^/]+)(?:/(move|comments)(?:/([^/]+))?)?$").exec(p);
      if (ticket) {
        const id = decodeURIComponent(ticket[1]), sub = ticket[2], extraId = ticket[3] && decodeURIComponent(ticket[3]);
        if (!sub) {
          if (method === "GET") return send(res, 200, board.get(id)), true;
          if (method === "PATCH") return send(res, 200, board.update(id, await jsonBody(req, 20000))), true;
          if (method === "DELETE") return board.remove(id), send(res, 200, { ok: true }), true;
        } else if (sub === "move" && !extraId && method === "POST") {
          return send(res, 200, board.move(id, await jsonBody(req, 2000))), true;
        } else if (sub === "comments") {
          if (!extraId && method === "POST") return send(res, 201, board.addComment(id, await jsonBody(req, 8000))), true;
          if (extraId && method === "DELETE") return send(res, 200, board.removeComment(id, extraId)), true;
        }
      }

      const entries = new RegExp("^/api/journal/([a-z]+)(?:/([^/]+))?$").exec(p);
      if (entries) {
        const coll = entries[1], id = entries[2] && decodeURIComponent(entries[2]);
        if (!id && method === "GET") return send(res, 200, journal.list(coll)), true;
        if (!id && method === "POST") return send(res, 201, journal.put(coll, await jsonBody(req, 20000))), true;
        if (id && method === "PUT") return send(res, 200, journal.put(coll, await jsonBody(req, 20000), id)), true;
        if (id && method === "DELETE") return journal.remove(coll, id), send(res, 200, { ok: true }), true;
      }

      if (p === "/api/backup") {
        if (method === "GET") return send(res, 200, store.backup()), true;
        if (method === "POST") return send(res, 200, store.restore(await jsonBody(req, BACKUP_MAX_BODY))), true;
      }
    } catch (error) {
      if (error instanceof StoreError || error instanceof BoardError || error instanceof JournalError || error instanceof ProjectError) return send(res, error.status, { error: error.message }), true;
      throw error;
    }
    return false;
  }
  let data = options.initialData;
  let running = false; // une seule exécution de tests à la fois

  async function handle(req, res) {
    const url = new URL(req.url, "http://localhost");
    const hostName = String(req.headers.host || "").replace(/:\d+$/, "");
    if (hostName !== "127.0.0.1" && hostName !== "localhost") return send(res, 403, { error: "hôte refusé" });

    // L'historique des exécutions est relu à chaque chargement : un rechargement montre aussi les lancements faits entre-temps.
    if (req.method === "GET" && url.pathname === "/") return send(res, 200, buildHtml(Object.assign({}, data, { runs: listRuns(runsDir), projects: projects.list(), projectProfiles: projects.builtins() })), "text/html; charset=utf-8");

    const image = /^\/img\/([a-z0-9_]+\.png)$/.exec(url.pathname);
    if (req.method === "GET" && image) {
      const file = path.join(ROOT, "assets", "ui", image[1]);
      if (!fs.existsSync(file)) return send(res, 404, { error: "introuvable" });
      return send(res, 200, fs.readFileSync(file), "image/png");
    }

    const audio = /^\/sounds\/([a-z0-9.]+)$/.exec(url.pathname);
    if (req.method === "GET" && audio) {
      const found = store.readSoundFile(audio[1]);
      if (!found) return send(res, 404, { error: "introuvable" });
      return send(res, 200, found.buffer, found.mime);
    }

    if (!url.pathname.startsWith("/api/")) return send(res, 404, { error: "introuvable" });
    if (req.headers["x-registre"] !== "1") return send(res, 403, { error: "en-tête manquant" });

    if (await storageRoutes(req, res, url)) return;

    if (req.method === "GET" && url.pathname === "/api/contributions") return send(res, 200, listContributions(dir));

    if (req.method === "POST" && url.pathname === "/api/contributions") {
      let parsed;
      try {
        parsed = JSON.parse(await readBody(req));
      } catch (error) {
        return send(res, error.status || 400, { error: error.status === 413 ? "contribution trop volumineuse" : "JSON invalide" });
      }
      const check = validate(parsed);
      if (!check.ok) return send(res, 422, { error: check.errors.join(" ; ") });
      fs.mkdirSync(dir, { recursive: true });
      if (fs.readdirSync(dir).length >= MAX_CONTRIBUTIONS) return send(res, 429, { error: "trop de contributions en attente : applique-les ou retire-en" });
      const createdAt = Date.now();
      const id = `${createdAt}-${Math.random().toString(36).slice(2, 8).padEnd(6, "0")}`;
      const doc = { type: check.clean.type, fields: check.clean.fields, note: check.clean.note, status: "pending", createdAt };
      fs.writeFileSync(path.join(dir, id + ".json"), JSON.stringify(doc, null, 2) + "\n", { flag: "wx" });
      return send(res, 201, { id });
    }

    const one = /^\/api\/contributions\/([^/]+)$/.exec(url.pathname);
    if (req.method === "DELETE" && one) {
      const id = decodeURIComponent(one[1]);
      if (!ID_PATTERN.test(id)) return send(res, 400, { error: "identifiant invalide" });
      const file = path.join(dir, id + ".json");
      if (!fs.existsSync(file)) return send(res, 404, { error: "introuvable" });
      let doc;
      try {
        doc = JSON.parse(fs.readFileSync(file, "utf8"));
      } catch {
        doc = {};
      }
      if ((doc.status || "pending") !== "pending") return send(res, 409, { error: "seule une contribution en attente peut être retirée" });
      fs.unlinkSync(file);
      return send(res, 200, { ok: true });
    }

    if (req.method === "POST" && url.pathname === "/api/refresh") {
      if (running) return send(res, 409, { error: "Des tests sont déjà en cours." });
      running = true;
      try {
        data = await (options.collect || collectData)({ trigger: "site", runsDir });
      } finally {
        running = false;
      }
      return send(res, 200, { ok: true });
    }

    if (req.method === "GET" && url.pathname === "/api/tests/latest") {
      return send(res, 200, { report: data.tests, runs: listRuns(runsDir), running });
    }

    if (req.method === "POST" && url.pathname === "/api/tests/run") {
      let filter = "";
      try {
        const raw = await readBody(req);
        const body = raw ? JSON.parse(raw) : {};
        filter = body && body.filter !== undefined ? body.filter : "";
      } catch (error) {
        return send(res, error.status || 400, { error: "demande invalide" });
      }
      if (typeof filter !== "string" || (filter !== "" && !FILTER_PATTERN.test(filter))) return send(res, 422, { error: "filtre invalide (lettres, chiffres, _ / . - et espace ; 60 caractères au plus)" });
      if (running) return send(res, 409, { error: "Des tests sont déjà en cours." });
      running = true;
      try {
        const { report, run } = await runTests({ filter, trigger: "site" });
        saveRun(runsDir, run);
        data.tests = report;
        return send(res, 200, { report, runs: listRuns(runsDir) });
      } catch (error) {
        return send(res, 500, { error: String((error && error.message) || error) });
      } finally {
        running = false;
      }
    }
    return send(res, 404, { error: "introuvable" });
  }

  return http.createServer((req, res) => {
    handle(req, res).catch((error) => {
      if (!res.headersSent) send(res, 500, { error: "erreur interne" });
      else res.end();
      if (process.env.REGISTRE_DEBUG) console.error(error);
    });
  });
}

module.exports = { createServer, collectData, buildHtml, listContributions, listRuns, saveRun, summarize, FILTER_PATTERN, DEFAULT_DATA_DIR };

if (require.main === module) {
  const port = Number(process.argv[2]) || 4173;
  console.log("Collecte des données (tests et export du jeu)…");
  collectData().then((initialData) => {
    const server = createServer({ initialData });
    server.listen(port, "127.0.0.1", () => {
      console.log("Registre BOOM BATTLE : http://127.0.0.1:" + port);
      console.log("Contributions enregistrées dans tools/registre/contributions/ — applique-les avec : node tools/registre/apply.js");
    });
  });
}
