"use strict";
// Tableau de suivi (type Trello / Jira) : tickets en colonnes À faire / En cours / Terminé, priorité, retours (commentaires)
// et historique de chaque ticket. Un ticket = un fichier data/tickets/<id>.json ; écriture atomique.
// L'historique et les dates sont produits ICI (jamais fournis par le navigateur) ; tout est revalidé avant écriture et restauration.
const fs = require("node:fs");
const path = require("node:path");

const STATUSES = [{ id: "todo", label: "À faire" }, { id: "doing", label: "En cours" }, { id: "done", label: "Terminé" }];
const PRIORITIES = [{ id: "P0", label: "Critique" }, { id: "P1", label: "Haute" }, { id: "P2", label: "Normale" }, { id: "P3", label: "Basse" }];
const TYPES = [{ id: "tache", label: "Tâche" }, { id: "bug", label: "Bug" }, { id: "idee", label: "Idée" }];
const ids = (list) => list.map((x) => x.id);
const TICKET_ID = /^t[a-z0-9]{6,24}$/;
const COMMENT_ID = /^k[a-z0-9]{6,24}$/;
const MAX_TICKETS = 500, MAX_COMMENTS = 100, MAX_HISTORY = 200;

class BoardError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status || 422;
  }
}
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const text = (v, min, max) => typeof v === "string" && v.length >= min && v.length <= max && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(v);
const labelOf = (list, id) => (list.find((x) => x.id === id) || { label: id }).label;

function atomicWrite(file, content) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = file + "." + process.pid + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
  fs.writeFileSync(tmp, content);
  fs.renameSync(tmp, file);
}
function readJson(file) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); } catch { return null; }
}
const rid = (prefix) => prefix + Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

// Champs modifiables par l'utilisateur.
function cleanFields(raw, partial) {
  if (!isObject(raw)) throw new BoardError("ticket invalide");
  const out = {};
  const has = (k) => raw[k] !== undefined;
  if (!partial || has("title")) { if (!text(raw.title, 3, 120)) throw new BoardError("titre invalide (3 à 120 caractères)"); out.title = raw.title.trim(); if (out.title.length < 3) throw new BoardError("titre invalide (3 à 120 caractères)"); }
  if (!partial || has("description")) { const d = raw.description === undefined ? "" : raw.description; if (!text(d, 0, 4000)) throw new BoardError("description invalide (4000 caractères au plus)"); out.description = d; }
  if (!partial || has("priority")) { const p = raw.priority === undefined ? "P2" : raw.priority; if (!ids(PRIORITIES).includes(p)) throw new BoardError("priorité inconnue"); out.priority = p; }
  if (!partial || has("type")) { const t = raw.type === undefined ? "tache" : raw.type; if (!ids(TYPES).includes(t)) throw new BoardError("type inconnu"); out.type = t; }
  if (!partial || has("module")) { const m = raw.module === undefined ? "" : raw.module; if (!text(m, 0, 60)) throw new BoardError("module invalide (60 caractères au plus)"); out.module = m; }
  return out;
}

function createBoard({ dir, activity, clock }) {
  const now = clock || Date.now;
  const ticketsDir = path.join(dir, "tickets");
  const fileOf = (id) => path.join(ticketsDir, id + ".json");
  const checkId = (id) => { if (typeof id !== "string" || !TICKET_ID.test(id)) throw new BoardError("identifiant invalide", 400); };
  const log = (action, ticket, detail) => { if (activity) activity.add("ticket", action, ticket.title, detail, ticket.id); };

  function validStored(t) {
    return isObject(t) && typeof t.id === "string" && TICKET_ID.test(t.id) && text(t.title, 1, 120) && text(t.description, 0, 4000) && ids(PRIORITIES).includes(t.priority) &&
      ids(TYPES).includes(t.type) && ids(STATUSES).includes(t.status) && text(t.module, 0, 60) && Number.isInteger(t.createdAt) && Number.isInteger(t.updatedAt) && Number.isFinite(t.position) &&
      Array.isArray(t.comments) && t.comments.length <= MAX_COMMENTS && t.comments.every((c) => isObject(c) && COMMENT_ID.test(c.id) && text(c.text, 1, 2000) && Number.isInteger(c.at)) &&
      Array.isArray(t.history) && t.history.length <= MAX_HISTORY && t.history.every((h) => isObject(h) && Number.isInteger(h.at) && text(h.action, 1, 30) && (h.text === undefined || text(h.text, 0, 500)) && (h.from === undefined || text(h.from, 0, 40)) && (h.to === undefined || text(h.to, 0, 40)));
  }
  function readAll() {
    if (!fs.existsSync(ticketsDir)) return [];
    const out = [];
    for (const name of fs.readdirSync(ticketsDir)) {
      if (!/^t[a-z0-9]{6,24}\.json$/.test(name)) continue;
      const t = readJson(path.join(ticketsDir, name));
      if (validStored(t)) out.push(t);
    }
    return out;
  }
  function list() {
    const order = ids(STATUSES);
    return readAll().sort((a, b) => order.indexOf(a.status) - order.indexOf(b.status) || a.position - b.position || a.createdAt - b.createdAt);
  }
  function load(id) {
    checkId(id);
    const t = fs.existsSync(fileOf(id)) ? readJson(fileOf(id)) : null;
    if (!validStored(t)) throw new BoardError("ticket introuvable", 404);
    return t;
  }
  const save = (t) => atomicWrite(fileOf(t.id), JSON.stringify(t, null, 2) + "\n");
  const column = (status, exceptId) => list().filter((t) => t.status === status && t.id !== exceptId);
  function pushHistory(t, entry) {
    t.history.push(Object.assign({ at: now() }, entry));
    if (t.history.length > MAX_HISTORY) t.history = t.history.slice(-MAX_HISTORY);
  }
  // Renumérote une colonne 0..n-1 (sans toucher aux dates des tickets qui ne changent pas de rang... seul le rang est réécrit).
  function renumber(tickets) {
    tickets.forEach((t, i) => { if (t.position !== i) { t.position = i; save(t); } });
  }

  function create(raw) {
    if (readAll().length >= MAX_TICKETS) throw new BoardError("trop de tickets (" + MAX_TICKETS + " au plus)", 429);
    const f = cleanFields(raw, false);
    let status = "todo";
    if (isObject(raw) && raw.status !== undefined) { if (!ids(STATUSES).includes(raw.status)) throw new BoardError("statut inconnu"); status = raw.status; }
    const t = Object.assign({ id: rid("t"), status, position: 0, createdAt: now(), updatedAt: now(), comments: [], history: [] }, f);
    if (status === "done") t.doneAt = now();
    pushHistory(t, { action: "created", to: status });
    renumber([t].concat(column(status))); // un nouveau ticket arrive en haut de sa colonne
    save(t);
    log("ticket_cree", t, labelOf(PRIORITIES, t.priority) + " · " + labelOf(TYPES, t.type));
    return t;
  }

  function update(id, raw) {
    const t = load(id);
    const f = cleanFields(raw, true);
    const changed = [];
    for (const k of Object.keys(f)) {
      if (f[k] === t[k]) continue;
      if (k === "priority") pushHistory(t, { action: "priority", from: t.priority, to: f.priority });
      changed.push(k);
      t[k] = f[k];
    }
    if (!changed.length) return t;
    const others = changed.filter((k) => k !== "priority");
    if (others.length) pushHistory(t, { action: "edited", text: others.join(", ") });
    t.updatedAt = now();
    save(t);
    log(changed.includes("priority") && changed.length === 1 ? "priorite_changee" : "ticket_modifie", t, changed.join(", "));
    return t;
  }

  // Déplace un ticket vers une colonne et une position (index dans la colonne d'arrivée).
  function move(id, raw) {
    if (!isObject(raw) || !ids(STATUSES).includes(raw.status)) throw new BoardError("statut inconnu");
    if (raw.index !== undefined && (!Number.isInteger(raw.index) || raw.index < 0 || raw.index > 10000)) throw new BoardError("position invalide");
    const t = load(id);
    const from = t.status, fromIndex = column(from).findIndex((x) => x.id === id);
    const target = column(raw.status, id);
    const index = Math.min(raw.index === undefined ? target.length : raw.index, target.length);
    if (from === raw.status && fromIndex === index) return t;
    const old = from;
    t.status = raw.status;
    if (raw.status === "done" && old !== "done") t.doneAt = now();
    if (raw.status !== "done") delete t.doneAt;
    target.splice(index, 0, t);
    t.updatedAt = now();
    pushHistory(t, old === raw.status ? { action: "reordered", text: "position " + (fromIndex + 1) + " → " + (index + 1) } : { action: "moved", from: old, to: raw.status });
    renumber(target);
    save(t);
    if (old !== raw.status) renumber(column(old));
    log(old === raw.status ? "ticket_reordonne" : "ticket_deplace", t, old === raw.status ? labelOf(STATUSES, old) : labelOf(STATUSES, old) + " → " + labelOf(STATUSES, raw.status));
    return load(id);
  }

  function addComment(id, raw) {
    if (!isObject(raw) || !text(raw.text, 1, 2000) || !raw.text.trim()) throw new BoardError("retour invalide (1 à 2000 caractères)");
    const t = load(id);
    if (t.comments.length >= MAX_COMMENTS) throw new BoardError("trop de retours sur ce ticket", 429);
    t.comments.push({ id: rid("k"), text: raw.text, at: now() });
    t.updatedAt = now();
    pushHistory(t, { action: "commented", text: raw.text.slice(0, 120) });
    save(t);
    log("retour_ajoute", t, raw.text.slice(0, 120));
    return t;
  }
  function removeComment(id, commentId) {
    if (typeof commentId !== "string" || !COMMENT_ID.test(commentId)) throw new BoardError("identifiant de retour invalide", 400);
    const t = load(id);
    if (!t.comments.some((c) => c.id === commentId)) throw new BoardError("retour introuvable", 404);
    t.comments = t.comments.filter((c) => c.id !== commentId);
    t.updatedAt = now();
    pushHistory(t, { action: "comment_removed" });
    save(t);
    log("retour_supprime", t);
    return t;
  }
  function remove(id) {
    const t = load(id);
    fs.rmSync(fileOf(id), { force: true });
    renumber(column(t.status));
    log("ticket_supprime", t, labelOf(STATUSES, t.status));
  }

  const extra = {
    key: "tickets",
    stats() {
      let bytes = 0, count = 0;
      for (const t of readAll()) { count++; bytes += fs.statSync(fileOf(t.id)).size; }
      return { count, bytes };
    },
    backup() { return list(); },
    restore(items, skip) {
      let n = 0;
      const have = new Map(readAll().map((t) => [t.id, t]));
      for (const raw of Array.isArray(items) ? items : []) {
        if (!validStored(raw)) { skip("ticket", "ticket invalide"); continue; }
        const current = have.get(raw.id);
        if (current && current.updatedAt >= raw.updatedAt) continue;
        if (!current && have.size >= MAX_TICKETS) { skip("ticket", "trop de tickets"); continue; }
        const clean = { id: raw.id, title: raw.title, description: raw.description, priority: raw.priority, type: raw.type, module: raw.module, status: raw.status, position: raw.position, createdAt: raw.createdAt, updatedAt: raw.updatedAt, comments: raw.comments.map((c) => ({ id: c.id, text: c.text, at: c.at })), history: raw.history.map((h) => { const o = { at: h.at, action: h.action }; for (const k of ["text", "from", "to"]) if (h[k] !== undefined) o[k] = h[k]; return o; }) };
        if (Number.isInteger(raw.doneAt)) clean.doneAt = raw.doneAt;
        save(clean);
        have.set(clean.id, clean);
        n++;
      }
      return n;
    },
  };
  return { list, get: load, create, update, move, addComment, removeComment, remove, extra };
}

module.exports = { createBoard, BoardError, STATUSES, PRIORITIES, TYPES, MAX_TICKETS, MAX_COMMENTS, MAX_HISTORY };
