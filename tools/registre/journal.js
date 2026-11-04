"use strict";
// Journaux du projet, pilotés par un schéma : tests réels, équilibrage, retours de playtest, images, textes, cartes, décisions,
// performances, publications. Une entrée = un fichier data/journal/<rubrique>/<id>.json ; tout est revalidé avant écriture et restauration.
const fs = require("node:fs");
const path = require("node:path");

const ENTRY_ID = /^j[a-z0-9]{6,24}$/;
const MAX_ENTRIES = 1000;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

const f = {
  text: (key, label, o) => Object.assign({ key, label, type: "text", min: 1, max: 120 }, o),
  long: (key, label, o) => Object.assign({ key, label, type: "long", max: 4000, optional: true }, o),
  enum: (key, label, values, o) => Object.assign({ key, label, type: "enum", values, allowCustom: true, max: 120 }, o),
  int: (key, label, min, max, o) => Object.assign({ key, label, type: "int", min, max }, o),
  date: (key, label, o) => Object.assign({ key, label, type: "date" }, o),
  bool: (key, label) => ({ key, label, type: "bool" }),
};
const opt = { optional: true };
const E = (list) => list.map(([id, label]) => ({ id, label }));

// values : liste {id, label} ; le serveur n'accepte que les identifiants.
const SCHEMAS = [
  { id: "playtests", label: "Tests réels", description: "Ce que tu testes toi-même dans Studio ou en jeu publié (plusieurs clients, mobile, DataStore, invitations…).", titleField: "scenario",
    fields: [f.date("date", "Date"), f.text("scenario", "Scénario testé"), f.enum("result", "Résultat", E([["ok", "Réussi"], ["partiel", "Partiel"], ["ko", "Échec"], ["non_teste", "Non testé"]])), f.text("device", "Appareil", { optional: true, max: 60 }), f.int("players", "Joueurs", 1, 8, opt), f.long("notes", "Notes")] },
  { id: "balance", label: "Équilibrage", description: "Prix, récompenses, bonus et durées : valeur actuelle, valeur proposée, et celle que tu retiens.", titleField: "name",
    fields: [f.text("name", "Réglage"), f.enum("area", "Domaine", E([["prix", "Prix"], ["recompenses", "Récompenses"], ["bonus", "Bonus"], ["durees", "Durées"], ["carte", "Carte"], ["autre", "Autre"]])), f.text("current", "Valeur actuelle", { optional: true, max: 60 }), f.text("proposed", "Valeur proposée", { max: 60 }), f.bool("retained", "Retenue"), f.long("note", "Raison")] },
  { id: "feedback", label: "Retours de playtest", description: "Ce que disent les testeurs, rattaché à un écran.", titleField: "text",
    fields: [f.enum("screen", "Écran", E([["menu", "Menu"], ["lobby", "Lobby"], ["hud", "HUD de manche"], ["resultats", "Résultats"], ["boutique", "Boutique"], ["quetes", "Quêtes"], ["emotes", "Émotes"], ["chat", "Chat rapide"], ["carte", "Carte"], ["autre", "Autre"]])), f.enum("severity", "Gravité", E([["mineur", "Mineur"], ["moyen", "Moyen"], ["majeur", "Majeur"]])), f.text("author", "Testeur", { optional: true, max: 60 }), f.text("text", "Retour", { max: 500 }), f.bool("handled", "Traité")] },
  { id: "images", label: "Images à importer", description: "PNG de l'interface : empreinte et identifiant Roblox une fois importés (jamais inventé).", titleField: "file",
    fields: [f.text("file", "Fichier", { max: 80 }), f.text("usage", "Utilisation", { max: 120 }), f.text("sha256", "sha256", { optional: true, max: 64, min: 64, pattern: "^[0-9a-f]{64}$" }), f.text("assetId", "Identifiant Roblox", { optional: true, max: 40, pattern: "^rbxassetid://[0-9]{1,20}$" }), f.enum("status", "Statut", E([["a_faire", "À faire"], ["prete", "Prête"], ["importee", "Importée"]]))] },
  { id: "texts", label: "Textes du jeu", description: "Libellés et descriptions à relire au même endroit.", titleField: "key",
    fields: [f.text("key", "Clé", { max: 60 }), f.text("where", "Où", { optional: true, max: 80 }), f.text("text", "Texte", { max: 500 }), f.bool("reviewed", "Relu")] },
  { id: "seeds", label: "Cartes notables", description: "Seeds à rejouer : une carte qui plaît ou qui pose problème.", titleField: "seed",
    fields: [f.int("seed", "Seed", 0, 2147483647), f.enum("theme", "Thème", E([["Classic", "Classique"], ["Desert", "Désert"], ["Ice", "Glace"], ["Volcano", "Volcan"], ["Jungle", "Jungle"]])), f.enum("size", "Taille", E([["10", "10 × 10"], ["16", "16 × 16"], ["24", "24 × 24"]])), f.enum("verdict", "Verdict", E([["aime", "Plaît"], ["neutre", "Neutre"], ["probleme", "Problème"]])), f.long("note", "Note", { max: 500 })] },
  { id: "decisions", label: "Décisions", description: "Questions à trancher (par exemple le nom du jeu) et la décision prise.", titleField: "question",
    fields: [f.text("question", "Question", { max: 200 }), f.long("options", "Options"), f.long("decision", "Décision"), f.enum("status", "Statut", E([["ouverte", "Ouverte"], ["tranchee", "Tranchée"]])), f.date("decidedAt", "Date de décision", opt)] },
  { id: "perf", label: "Performance", description: "Mesures par appareil, pour alimenter docs/PERFORMANCE.md.", titleField: "device",
    fields: [f.date("date", "Date"), f.text("device", "Appareil", { max: 60 }), f.text("scenario", "Scénario", { max: 120 }), f.int("fps", "Images par seconde", 0, 1000), f.int("memoryMb", "Mémoire (Mo)", 0, 100000, opt), f.long("note", "Note", { max: 500 })] },
  { id: "releases", label: "Publications", description: "Versions publiées : date, numéro, tests lancés avant.", titleField: "version",
    fields: [f.date("date", "Date"), f.text("version", "Version", { max: 40 }), f.text("tests", "Tests avant publication", { optional: true, max: 120 }), f.long("notes", "Contenu")] },
];

class JournalError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status || 422;
  }
}
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v, min, max) => typeof v === "string" && v.length >= min && v.length <= max && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(v);

function schemaOf(id) {
  return SCHEMAS.find((s) => s.id === id) || null;
}
function validDate(v) {
  if (typeof v !== "string" || !DATE.test(v)) return false;
  const d = new Date(v + "T00:00:00Z");
  return !isNaN(d) && d.toISOString().slice(0, 10) === v;
}

// Valide et nettoie les champs d'une entrée selon le schéma de sa rubrique. Les champs inconnus sont écartés.
function validateEntry(schema, raw) {
  if (!isObject(raw)) throw new JournalError("entrée invalide");
  const out = {};
  for (const fd of schema.fields) {
    let v = raw[fd.key];
    const empty = v === undefined || v === null || v === "";
    if (fd.type === "bool") {
      if (v !== undefined && typeof v !== "boolean") throw new JournalError(fd.label + " : oui ou non attendu");
      out[fd.key] = v === true;
      continue;
    }
    if (empty) {
      if (fd.optional) continue;
      throw new JournalError(fd.label + " : champ obligatoire");
    }
    if (fd.type === "text" || fd.type === "long") {
      const min = fd.type === "long" ? 0 : fd.min === undefined ? 1 : fd.min;
      if (!text(v, min, fd.max)) throw new JournalError(fd.label + " : texte invalide (" + fd.max + " caractères au plus)");
      if (fd.type === "text" && !v.trim()) throw new JournalError(fd.label + " : champ obligatoire");
      if (fd.pattern && !new RegExp(fd.pattern).test(v)) throw new JournalError(fd.label + " : format invalide");
    } else if (fd.type === "enum") {
      const known = fd.values.some((x) => x.id === v);
      if (!known && (!fd.allowCustom || !text(v, 1, fd.max || 120) || !v.trim() || v === "__custom__")) throw new JournalError(fd.label + " : valeur invalide (120 caractères au plus)");
    } else if (fd.type === "int") {
      if (typeof v !== "number" || !Number.isInteger(v) || v < fd.min || v > fd.max) throw new JournalError(fd.label + " : entier de " + fd.min + " à " + fd.max + " attendu");
    } else if (fd.type === "date") {
      if (!validDate(v)) throw new JournalError(fd.label + " : date invalide (AAAA-MM-JJ)");
    }
    out[fd.key] = v;
  }
  return out;
}

function createJournal({ dir, activity, clock }) {
  const now = clock || Date.now;
  const root = path.join(dir, "journal");
  const dirOf = (id) => path.join(root, id);
  function schemaOrThrow(id) {
    const s = schemaOf(id);
    if (!s) throw new JournalError("rubrique inconnue", 404);
    return s;
  }
  function atomicWrite(file, content) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = file + "." + process.pid + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
    fs.writeFileSync(tmp, content);
    fs.renameSync(tmp, file);
  }
  function readEntry(schema, file) {
    try {
      const e = JSON.parse(fs.readFileSync(file, "utf8"));
      if (!isObject(e) || !ENTRY_ID.test(e.id) || !Number.isInteger(e.createdAt) || !Number.isInteger(e.updatedAt)) return null;
      const fields = validateEntry(schema, e);
      return Object.assign({ id: e.id, createdAt: e.createdAt, updatedAt: e.updatedAt }, fields);
    } catch {
      return null;
    }
  }
  function list(coll) {
    const schema = schemaOrThrow(coll);
    const d = dirOf(coll);
    if (!fs.existsSync(d)) return [];
    const out = [];
    for (const name of fs.readdirSync(d)) {
      if (!/^j[a-z0-9]{6,24}\.json$/.test(name)) continue;
      const e = readEntry(schema, path.join(d, name));
      if (e) out.push(e);
    }
    return out.sort((a, b) => b.updatedAt - a.updatedAt);
  }
  const titleOf = (schema, e) => String(e[schema.titleField]).slice(0, 120);
  function put(coll, raw, id) {
    const schema = schemaOrThrow(coll);
    const fields = validateEntry(schema, raw);
    const entries = list(coll);
    if (id !== undefined) {
      if (typeof id !== "string" || !ENTRY_ID.test(id)) throw new JournalError("identifiant invalide", 400);
      const current = entries.find((e) => e.id === id);
      if (!current) throw new JournalError("entrée introuvable", 404);
      const entry = Object.assign({ id, createdAt: current.createdAt, updatedAt: now() }, fields);
      atomicWrite(path.join(dirOf(coll), id + ".json"), JSON.stringify(entry, null, 2) + "\n");
      if (activity) activity.add("journal", "entree_modifiee", schema.label + " : " + titleOf(schema, entry), "", id);
      return entry;
    }
    if (entries.length >= MAX_ENTRIES) throw new JournalError("trop d'entrées (" + MAX_ENTRIES + " au plus)", 429);
    const entry = Object.assign({ id: "j" + Date.now().toString(36) + Math.random().toString(36).slice(2, 7), createdAt: now(), updatedAt: now() }, fields);
    atomicWrite(path.join(dirOf(coll), entry.id + ".json"), JSON.stringify(entry, null, 2) + "\n");
    if (activity) activity.add("journal", "entree_ajoutee", schema.label + " : " + titleOf(schema, entry), "", entry.id);
    return entry;
  }
  function remove(coll, id) {
    const schema = schemaOrThrow(coll);
    if (typeof id !== "string" || !ENTRY_ID.test(id)) throw new JournalError("identifiant invalide", 400);
    const current = list(coll).find((e) => e.id === id);
    if (!current) throw new JournalError("entrée introuvable", 404);
    fs.rmSync(path.join(dirOf(coll), id + ".json"), { force: true });
    if (activity) activity.add("journal", "entree_supprimee", schema.label + " : " + titleOf(schema, current), "", id);
  }

  const extra = {
    key: "journal",
    stats() {
      let count = 0, bytes = 0;
      for (const s of SCHEMAS) for (const e of list(s.id)) { count++; bytes += fs.statSync(path.join(dirOf(s.id), e.id + ".json")).size; }
      return { count, bytes };
    },
    backup() {
      const out = {};
      for (const s of SCHEMAS) out[s.id] = list(s.id);
      return out;
    },
    restore(items, skip) {
      let n = 0;
      if (!isObject(items)) return 0;
      for (const s of SCHEMAS) {
        if (items[s.id] === undefined) continue;
        if (!Array.isArray(items[s.id])) { skip("journal " + s.id, "liste attendue"); continue; }
        const have = new Map(list(s.id).map((e) => [e.id, e]));
        for (const raw of items[s.id]) {
          try {
            if (!isObject(raw) || typeof raw.id !== "string" || !ENTRY_ID.test(raw.id) || !Number.isInteger(raw.createdAt) || !Number.isInteger(raw.updatedAt)) throw new JournalError("identifiant ou dates invalides");
            const fields = validateEntry(s, raw);
            const current = have.get(raw.id);
            if (current && current.updatedAt >= raw.updatedAt) continue;
            if (!current && have.size >= MAX_ENTRIES) throw new JournalError("trop d'entrées");
            atomicWrite(path.join(dirOf(s.id), raw.id + ".json"), JSON.stringify(Object.assign({ id: raw.id, createdAt: raw.createdAt, updatedAt: raw.updatedAt }, fields), null, 2) + "\n");
            have.set(raw.id, raw);
            n++;
          } catch (e) {
            skip("journal " + s.id, e);
          }
        }
      }
      return n;
    },
  };
  return { list, put, remove, extra };
}

module.exports = { createJournal, JournalError, SCHEMAS, schemaOf, validateEntry, MAX_ENTRIES };
