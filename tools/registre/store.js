"use strict";
// Stockage durable du registre local, dans des fichiers (aucune dépendance) :
//   data/chats/<id>.json      une conversation par fichier (écriture atomique)
//   data/settings.json        réglages de la page (jamais de clé d'API)
//   data/sounds.json          catalogue des sons ; data/sounds/<id>.<ext> : fichiers audio téléversés
// Les contributions (contributions/) et l'historique des tests (runs/) gardent leurs dossiers : la sauvegarde les inclut.
// Toute donnée est revalidée ICI avant écriture et avant restauration : on ne fait jamais confiance au navigateur ni à un fichier importé.

const fs = require("node:fs");
const path = require("node:path");
const { validate, TYPES } = require("./validate");

const CHAT_ID = /^c[a-z0-9]{6,24}$/;
const SCOPE_ID = /^[a-z0-9]{2,40}$/;
const SOUND_ID = /^s[a-z0-9]{6,24}$/;
const CONTRIBUTION_ID = /^[0-9]{10,16}-[a-z0-9]{6}$/;
const RUN_FILE = /^[0-9]{10,16}\.json$/;
const FILTER = /^[A-Za-z0-9_][A-Za-z0-9_/. -]{0,59}$/;

const MAX_CHATS = 200;
const MAX_MESSAGES = 200;
const MAX_MESSAGE_CHARS = 20000;
const MAX_SOUNDS = 40;
const MAX_SOUND_BYTES = 1500000;
const TABS = ["tests", "donnees", "assets", "contribuer", "assistant", "tableau", "journal", "sons", "stockage", "compte", "admin"];
const GAME_TABS = ["cosmetiques", "quetes", "cartes", "themes", "bonus", "emotes", "chat", "reglages"];
const SOUND_EVENTS = [
  "bomb_place", "bomb_fuse", "explosion", "powerup_pickup", "shield_break", "elimination", "victory", "defeat", "draw",
  "countdown_tick", "round_start", "button_click", "purchase_success", "purchase_fail", "quest_complete",
  "menu_music", "lobby_music", "round_music", "custom",
];
const SOUND_CATEGORIES = ["sfx", "music", "ui"];
const AUDIO_TYPES = { mp3: "audio/mpeg", ogg: "audio/ogg", wav: "audio/wav" };

class StoreError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status || 422;
  }
}

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}
function text(value, min, max) {
  return typeof value === "string" && value.length >= min && value.length <= max && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value);
}
function atomicWrite(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + "." + process.pid + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, file);
}
function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return fallback;
  }
}

// ----- validation -----------------------------------------------------------------------------------------------------------

function validateDraft(d) {
  if (!isObject(d) || !TYPES.includes(d.type) || !isObject(d.fields)) return null;
  if (JSON.stringify(d.fields).length > 3000) return null;
  return { type: d.type, fields: d.fields, note: text(d.note || "", 0, 500) ? d.note || "" : "" };
}

function validateChat(chat) {
  if (!isObject(chat)) throw new StoreError("conversation invalide");
  if (typeof chat.id !== "string" || !CHAT_ID.test(chat.id)) throw new StoreError("identifiant de conversation invalide");
  if (!text(chat.title, 1, 120)) throw new StoreError("titre invalide (1 à 120 caractères)");
  if (!Number.isInteger(chat.createdAt) || !Number.isInteger(chat.updatedAt) || chat.createdAt < 0 || chat.updatedAt < 0) throw new StoreError("dates invalides");
  if (!Array.isArray(chat.messages) || chat.messages.length === 0 || chat.messages.length > MAX_MESSAGES) throw new StoreError("messages invalides (1 à " + MAX_MESSAGES + ")");
  const messages = chat.messages.map((m) => {
    if (!isObject(m) || (m.role !== "user" && m.role !== "assistant")) throw new StoreError("message invalide");
    if (typeof m.content !== "string" || m.content.length > MAX_MESSAGE_CHARS) throw new StoreError("message trop long");
    const out = { role: m.role, content: m.content };
    if (Array.isArray(m.drafts) && m.drafts.length && m.drafts.length <= 5) {
      const drafts = m.drafts.map(validateDraft);
      if (drafts.every(Boolean) && typeof m.draftKey === "string" && /^m[0-9]{1,4}$/.test(m.draftKey)) {
        out.drafts = drafts;
        out.draftKey = m.draftKey;
      }
    }
    return out;
  });
  return { id: chat.id, title: chat.title, createdAt: chat.createdAt, updatedAt: chat.updatedAt, messages };
}

function validateSettings(raw) {
  if (!isObject(raw)) throw new StoreError("réglages invalides");
  const out = {};
  if (raw.model !== undefined && raw.model !== "") {
    if (typeof raw.model !== "string" || raw.model.length > 100 || !/^[A-Za-z0-9._/:-]+$/.test(raw.model)) throw new StoreError("modèle invalide");
    out.model = raw.model;
  }
  if (raw.tab !== undefined) {
    if (!TABS.includes(raw.tab)) throw new StoreError("onglet inconnu");
    out.tab = raw.tab;
  }
  if (raw.gameTab !== undefined) {
    if (!GAME_TABS.includes(raw.gameTab)) throw new StoreError("catégorie inconnue");
    out.gameTab = raw.gameTab;
  }
  if (raw.runFilter !== undefined && raw.runFilter !== "") {
    if (typeof raw.runFilter !== "string" || !FILTER.test(raw.runFilter)) throw new StoreError("filtre invalide");
    out.runFilter = raw.runFilter;
  }
  return out;
}

// Détecte le format réel d'un fichier audio par ses premiers octets (l'extension annoncée ne prouve rien).
function sniffAudio(buffer) {
  if (buffer.length < 12) return null;
  if (buffer.toString("latin1", 0, 4) === "OggS") return "ogg";
  if (buffer.toString("latin1", 0, 4) === "RIFF" && buffer.toString("latin1", 8, 12) === "WAVE") return "wav";
  if (buffer.toString("latin1", 0, 3) === "ID3") return "mp3";
  if (buffer[0] === 0xff && (buffer[1] & 0xe0) === 0xe0) return "mp3";
  return null;
}

// Métadonnées d'un son (sans la partie fichier, gérée à part). `existing` : fichier déjà associé quand on modifie.
function validateSoundMeta(raw, existing) {
  if (!isObject(raw)) throw new StoreError("son invalide");
  if (!text(raw.name, 2, 40)) throw new StoreError("nom invalide (2 à 40 caractères)");
  if (!SOUND_EVENTS.includes(raw.event)) throw new StoreError("événement inconnu");
  if (!SOUND_CATEGORIES.includes(raw.category)) throw new StoreError("catégorie inconnue");
  if (typeof raw.volume !== "number" || !(raw.volume >= 0 && raw.volume <= 1)) throw new StoreError("volume invalide (0 à 1)");
  if (typeof raw.loop !== "boolean" || typeof raw.enabled !== "boolean") throw new StoreError("options invalides");
  if (raw.note !== undefined && raw.note !== "" && !text(raw.note, 0, 200)) throw new StoreError("note invalide (200 caractères au plus)");
  const source = raw.source;
  if (!isObject(source)) throw new StoreError("source manquante");
  let clean;
  if (source.type === "none") clean = { type: "none" };
  else if (source.type === "roblox") {
    if (typeof source.assetId !== "string" || !/^rbxassetid:\/\/\d{1,20}$/.test(source.assetId)) throw new StoreError("identifiant Roblox invalide (rbxassetid://nombre)");
    clean = { type: "roblox", assetId: source.assetId };
  } else if (source.type === "file") {
    clean = { type: "file" }; // les champs fichier sont posés par le serveur
  } else throw new StoreError("type de source inconnu");
  return { name: raw.name, event: raw.event, category: raw.category, volume: raw.volume, loop: raw.loop, enabled: raw.enabled, note: raw.note || "", source: clean, _keepFile: existing };
}

// ----- le stockage ---------------------------------------------------------------------------------------------------------

function createStore(options) {
  const dir = options.dir;
  const contributionsDir = options.contributionsDir;
  const runsDir = options.runsDir;
  const extras = options.extras || []; // modules supplémentaires { key, stats(), backup(), restore(items, skip) }
  const chatsDir = path.join(dir, "chats");
  const soundsDir = path.join(dir, "sounds");
  const settingsFile = path.join(dir, "settings.json");
  // Portée : identifiant d'un compte (conversations et réglages propres à chaque personne). Sans portée : emplacements historiques.
  function scoped(scope) {
    if (scope === undefined || scope === null || scope === "") return { chats: chatsDir, settings: settingsFile };
    if (typeof scope !== "string" || !SCOPE_ID.test(scope)) throw new StoreError("compte invalide", 400);
    return { chats: path.join(chatsDir, "u-" + scope), settings: path.join(dir, "settings-" + scope + ".json") };
  }
  function allChatDirs() {
    const out = [chatsDir];
    if (fs.existsSync(chatsDir)) for (const n of fs.readdirSync(chatsDir)) if (/^u-[a-z0-9]{2,40}$/.test(n)) out.push(path.join(chatsDir, n));
    return out;
  }
  const soundsFile = path.join(dir, "sounds.json");

  // --- conversations
  function listChats(scope) {
    const chatsDir = scoped(scope).chats;
    if (!fs.existsSync(chatsDir)) return [];
    const list = [];
    for (const name of fs.readdirSync(chatsDir)) {
      const id = name.replace(/\.json$/, "");
      if (!name.endsWith(".json") || !CHAT_ID.test(id)) continue;
      try {
        list.push(validateChat(JSON.parse(fs.readFileSync(path.join(chatsDir, name), "utf8"))));
      } catch {
        /* fichier abîmé : ignoré, jamais bloquant */
      }
    }
    return list.sort((a, b) => b.updatedAt - a.updatedAt).slice(0, MAX_CHATS);
  }
  function putChat(raw, scope) {
    const chatsDir = scoped(scope).chats;
    const chat = validateChat(raw);
    const existing = fs.existsSync(chatsDir) ? fs.readdirSync(chatsDir).filter((n) => n.endsWith(".json")) : [];
    if (!existing.includes(chat.id + ".json") && existing.length >= MAX_CHATS) throw new StoreError("trop de conversations enregistrées (" + MAX_CHATS + " au plus)", 429);
    atomicWrite(path.join(chatsDir, chat.id + ".json"), JSON.stringify(chat, null, 2) + "\n");
    return chat;
  }
  function removeChat(id, scope) {
    const chatsDir = scoped(scope).chats;
    if (!CHAT_ID.test(id)) throw new StoreError("identifiant invalide", 400);
    const file = path.join(chatsDir, id + ".json");
    if (!fs.existsSync(file)) throw new StoreError("introuvable", 404);
    fs.unlinkSync(file);
  }
  function clearChats(scope) {
    const chatsDir = scoped(scope).chats;
    if (!fs.existsSync(chatsDir)) return 0;
    let n = 0;
    for (const name of fs.readdirSync(chatsDir)) {
      if (CHAT_ID.test(name.replace(/\.json$/, "")) && name.endsWith(".json")) {
        fs.unlinkSync(path.join(chatsDir, name));
        n++;
      }
    }
    return n;
  }

  // --- réglages
  function getSettings(scope) {
    const raw = readJson(scoped(scope).settings, {});
    try {
      return validateSettings(raw);
    } catch {
      return {};
    }
  }
  function putSettings(raw, scope) {
    const clean = validateSettings(raw);
    atomicWrite(scoped(scope).settings, JSON.stringify(clean, null, 2) + "\n");
    return clean;
  }

  // --- sons
  function readSounds() {
    const list = readJson(soundsFile, []);
    return Array.isArray(list) ? list.filter((s) => isObject(s) && SOUND_ID.test(s.id || "")) : [];
  }
  function writeSounds(list) {
    atomicWrite(soundsFile, JSON.stringify(list, null, 2) + "\n");
  }
  function listSounds() {
    return readSounds().sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
  }
  function decodeAudio(file) {
    if (!isObject(file) || typeof file.dataBase64 !== "string") throw new StoreError("fichier audio manquant");
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(file.dataBase64)) throw new StoreError("fichier audio illisible");
    const buffer = Buffer.from(file.dataBase64, "base64");
    if (buffer.length === 0 || buffer.length > MAX_SOUND_BYTES) throw new StoreError("fichier audio trop gros (" + Math.round(MAX_SOUND_BYTES / 1000) + " Ko au plus)", 413);
    const ext = sniffAudio(buffer);
    if (!ext) throw new StoreError("format audio non reconnu (mp3, ogg ou wav)");
    return { buffer, ext, originalName: text(file.name || "", 1, 120) ? String(file.name).replace(/[\\/]/g, "_") : "audio." + ext };
  }
  function removeFilesOf(id) {
    if (!fs.existsSync(soundsDir)) return;
    for (const name of fs.readdirSync(soundsDir)) if (name.startsWith(id + ".")) fs.unlinkSync(path.join(soundsDir, name));
  }
  // Crée (id absent, ou id fourni avec forceCreate pour une restauration) ou modifie un son. `file` : { name, dataBase64 } pour un fichier nouveau ou remplacé.
  function putSound(raw, file, id, forceCreate) {
    const list = readSounds();
    const current = id ? list.find((s) => s.id === id) : null;
    if (id && !current && !forceCreate) throw new StoreError("son introuvable", 404);
    if (!id && list.length >= MAX_SOUNDS) throw new StoreError("trop de sons (" + MAX_SOUNDS + " au plus)", 429);
    const meta = validateSoundMeta(raw, current && current.source && current.source.type === "file" ? current.source : null);
    const now = Date.now();
    const entry = { id: id || "s" + now.toString(36) + Math.random().toString(36).slice(2, 6).padEnd(4, "0"), name: meta.name, event: meta.event, category: meta.category, volume: meta.volume, loop: meta.loop, enabled: meta.enabled, note: meta.note, source: meta.source, createdAt: current ? current.createdAt : forceCreate && Number.isInteger(raw.createdAt) && raw.createdAt >= 0 ? raw.createdAt : now, updatedAt: now };
    if (entry.source.type === "file") {
      if (file) {
        const audio = decodeAudio(file);
        removeFilesOf(entry.id);
        atomicWrite(path.join(soundsDir, entry.id + "." + audio.ext), audio.buffer);
        entry.source = { type: "file", file: entry.id + "." + audio.ext, mime: AUDIO_TYPES[audio.ext], bytes: audio.buffer.length, originalName: audio.originalName };
      } else if (meta._keepFile) {
        entry.source = meta._keepFile; // modification sans nouveau fichier : on garde l'ancien
      } else throw new StoreError("fichier audio manquant");
    } else {
      removeFilesOf(entry.id); // la source n'est plus un fichier : on libère le disque
    }
    writeSounds(current ? list.map((s) => (s.id === entry.id ? entry : s)) : list.concat([entry]));
    return entry;
  }
  function removeSound(id) {
    if (!SOUND_ID.test(id)) throw new StoreError("identifiant invalide", 400);
    const list = readSounds();
    if (!list.some((s) => s.id === id)) throw new StoreError("introuvable", 404);
    removeFilesOf(id);
    writeSounds(list.filter((s) => s.id !== id));
  }
  function readSoundFile(name) {
    const m = /^(s[a-z0-9]{6,24})\.(mp3|ogg|wav)$/.exec(name);
    if (!m) return null;
    const file = path.join(soundsDir, name);
    if (!fs.existsSync(file)) return null;
    return { buffer: fs.readFileSync(file), mime: AUDIO_TYPES[m[2]] };
  }

  // --- vue d'ensemble, sauvegarde, restauration
  function dirStats(directory, pattern) {
    if (!directory || !fs.existsSync(directory)) return { count: 0, bytes: 0 };
    let count = 0, bytes = 0;
    for (const name of fs.readdirSync(directory)) {
      if (!pattern.test(name)) continue;
      count++;
      bytes += fs.statSync(path.join(directory, name)).size;
    }
    return { count, bytes };
  }
  function stats() {
    const sounds = readSounds();
    const out = {
      dir: path.relative(path.resolve(__dirname, "..", ".."), dir).split(path.sep).join("/"),
      chats: allChatDirs().map((d) => dirStats(d, /^c[a-z0-9]{6,24}\.json$/)).reduce((a, b) => ({ count: a.count + b.count, bytes: a.bytes + b.bytes }), { count: 0, bytes: 0 }),
      contributions: dirStats(contributionsDir, /^[0-9]{10,16}-[a-z0-9]{6}\.json$/),
      runs: dirStats(runsDir, RUN_FILE),
      sounds: { count: sounds.length, bytes: dirStats(soundsDir, /^s[a-z0-9]{6,24}\.(mp3|ogg|wav)$/).bytes },
      settings: { exists: fs.existsSync(settingsFile) },
    };
    for (const x of extras) out[x.key] = x.stats();
    return out;
  }

  function backup(scope) {
    const contributions = [];
    if (contributionsDir && fs.existsSync(contributionsDir)) {
      for (const name of fs.readdirSync(contributionsDir)) {
        const id = name.replace(/\.json$/, "");
        if (!name.endsWith(".json") || !CONTRIBUTION_ID.test(id)) continue;
        const doc = readJson(path.join(contributionsDir, name), null);
        if (isObject(doc)) contributions.push(Object.assign({}, doc, { _id: id }));
      }
    }
    const runs = [];
    if (runsDir && fs.existsSync(runsDir)) {
      for (const name of fs.readdirSync(runsDir)) {
        if (!RUN_FILE.test(name)) continue;
        const run = readJson(path.join(runsDir, name), null);
        if (isObject(run)) runs.push(run);
      }
    }
    const sounds = listSounds().map((s) => {
      const out = Object.assign({}, s);
      if (s.source.type === "file") {
        const f = readSoundFile(s.source.file);
        out.fileData = f ? f.buffer.toString("base64") : null;
      }
      return out;
    });
    const bundle = { format: "registre-backup", version: 1, exportedAt: Date.now(), chats: listChats(scope), contributions, runs, settings: getSettings(scope), sounds };
    for (const x of extras) bundle[x.key] = x.backup();
    return bundle;
  }

  // Restaure une sauvegarde par FUSION : rien n'est supprimé ; une conversation plus récente sur disque est conservée.
  function restore(bundle, scope) {
    if (!isObject(bundle) || bundle.format !== "registre-backup" || bundle.version !== 1) throw new StoreError("fichier de sauvegarde non reconnu");
    const report = { chats: 0, contributions: 0, runs: 0, sounds: 0, settings: false, ignored: [] };
    const skip = (what, error) => {
      if (report.ignored.length < 20) report.ignored.push(what + " : " + (error && error.message ? error.message : error));
    };

    const existingChats = new Map(listChats(scope).map((c) => [c.id, c]));
    for (const raw of Array.isArray(bundle.chats) ? bundle.chats : []) {
      try {
        const chat = validateChat(raw);
        const current = existingChats.get(chat.id);
        if (current && current.updatedAt >= chat.updatedAt) continue;
        putChat(chat, scope);
        report.chats++;
      } catch (e) {
        skip("conversation", e);
      }
    }

    for (const raw of Array.isArray(bundle.contributions) ? bundle.contributions : []) {
      try {
        if (!isObject(raw) || typeof raw._id !== "string" || !CONTRIBUTION_ID.test(raw._id)) throw new StoreError("identifiant invalide");
        if (!["pending", "applied", "rejected"].includes(raw.status)) throw new StoreError("statut invalide");
        const check = validate(raw);
        if (!check.ok) throw new StoreError(check.errors.join(" ; "));
        const file = path.join(contributionsDir, raw._id + ".json");
        if (fs.existsSync(file)) continue;
        const doc = { type: check.clean.type, fields: check.clean.fields, note: check.clean.note, status: raw.status, createdAt: Number.isInteger(raw.createdAt) ? raw.createdAt : Number(raw._id.split("-")[0]) };
        if (typeof raw.result === "string" && raw.result.length <= 300) doc.result = raw.result;
        atomicWrite(file, JSON.stringify(doc, null, 2) + "\n");
        report.contributions++;
      } catch (e) {
        skip("contribution", e);
      }
    }

    for (const raw of Array.isArray(bundle.runs) ? bundle.runs : []) {
      try {
        if (!isObject(raw) || !Number.isInteger(raw.startedAt) || !Number.isInteger(raw.finishedAt) || !Number.isInteger(raw.passed) || !Number.isInteger(raw.failed) || !Number.isInteger(raw.suites)) throw new StoreError("exécution invalide");
        if (typeof raw.trigger !== "string" || raw.trigger.length > 20) throw new StoreError("déclencheur invalide");
        if (raw.filter && !FILTER.test(raw.filter)) throw new StoreError("filtre invalide");
        const file = path.join(runsDir, raw.startedAt + ".json");
        if (fs.existsSync(file)) continue;
        const run = { startedAt: raw.startedAt, finishedAt: raw.finishedAt, durationMs: Math.max(0, raw.finishedAt - raw.startedAt), passed: raw.passed, failed: raw.failed, suites: raw.suites, filter: raw.filter || "", trigger: raw.trigger, ok: raw.failed === 0, failures: [] };
        atomicWrite(file, JSON.stringify(run, null, 2) + "\n");
        report.runs++;
      } catch (e) {
        skip("exécution", e);
      }
    }

    if (bundle.settings !== undefined) {
      try {
        putSettings(bundle.settings, scope);
        report.settings = true;
      } catch (e) {
        skip("réglages", e);
      }
    }

    const known = new Set(readSounds().map((s) => s.id));
    for (const raw of Array.isArray(bundle.sounds) ? bundle.sounds : []) {
      try {
        if (!isObject(raw) || typeof raw.id !== "string" || !SOUND_ID.test(raw.id)) throw new StoreError("identifiant invalide");
        if (known.has(raw.id)) continue;
        const file = raw.source && raw.source.type === "file" ? { name: raw.source.originalName, dataBase64: raw.fileData } : undefined;
        putSound(raw, file, raw.id, true);
        known.add(raw.id);
        report.sounds++;
      } catch (e) {
        skip("son", e);
      }
    }
    for (const x of extras) {
      if (bundle[x.key] === undefined) continue;
      try {
        report[x.key] = x.restore(bundle[x.key], skip);
      } catch (e) {
        skip(x.key, e);
      }
    }
    return report;
  }

  return { listChats, putChat, removeChat, clearChats, getSettings, putSettings, listSounds, putSound, removeSound, readSoundFile, stats, backup, restore };
}

module.exports = {
  createStore, StoreError, validateChat, validateSettings, validateSoundMeta, sniffAudio,
  SOUND_EVENTS, SOUND_CATEGORIES, TABS, GAME_TABS, MAX_SOUND_BYTES, MAX_SOUNDS, MAX_CHATS,
};
