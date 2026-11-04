"use strict";
// Journal d'activité du registre : une ligne par action (ticket créé, déplacé, commenté, supprimé, entrée de journal…).
// Fichier unique data/activity.json, plafonné ; écriture atomique. Les événements sont produits par le serveur, jamais par le navigateur.
const fs = require("node:fs");
const path = require("node:path");

const MAX_EVENTS = 2000;

function createActivity(file, clock) {
  const now = clock || Date.now;
  function read() {
    try {
      const list = JSON.parse(fs.readFileSync(file, "utf8"));
      return Array.isArray(list) ? list.filter(valid) : [];
    } catch {
      return [];
    }
  }
  function valid(e) {
    return !!e && typeof e === "object" && Number.isInteger(e.at) && typeof e.action === "string" && e.action.length <= 40 &&
      typeof e.kind === "string" && e.kind.length <= 20 && typeof e.title === "string" && e.title.length <= 200 && (e.detail === undefined || (typeof e.detail === "string" && e.detail.length <= 500));
  }
  function write(list) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = file + "." + process.pid + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(list));
    fs.renameSync(tmp, file);
  }
  // Le plus récent en premier.
  function add(kind, action, title, detail, ref) {
    const event = { at: now(), kind, action, title: String(title).slice(0, 200) };
    if (detail) event.detail = String(detail).slice(0, 500);
    if (ref && /^[a-z0-9]{3,30}$/.test(ref)) event.ref = ref;
    write([event].concat(read()).slice(0, MAX_EVENTS));
    return event;
  }
  function list(limit) {
    const n = Number.isInteger(limit) && limit > 0 ? Math.min(limit, MAX_EVENTS) : 200;
    return read().slice(0, n);
  }
  const key = (e) => e.at + "|" + e.kind + "|" + e.action + "|" + e.title;
  const extra = {
    key: "activity",
    stats() { const l = read(); return { count: l.length, bytes: fs.existsSync(file) ? fs.statSync(file).size : 0 }; },
    backup() { return read(); },
    restore(items, skip) {
      const have = new Set(read().map(key));
      const fresh = [];
      for (const e of Array.isArray(items) ? items : []) {
        if (!valid(e)) { skip("activité", "événement invalide"); continue; }
        if (have.has(key(e))) continue;
        have.add(key(e));
        const clean = { at: e.at, kind: e.kind, action: e.action, title: e.title };
        if (e.detail) clean.detail = e.detail;
        if (typeof e.ref === "string" && /^[a-z0-9]{3,30}$/.test(e.ref)) clean.ref = e.ref;
        fresh.push(clean);
      }
      if (fresh.length) write(read().concat(fresh).sort((a, b) => b.at - a.at).slice(0, MAX_EVENTS));
      return fresh.length;
    },
  };
  return { add, list, extra };
}

module.exports = { createActivity, MAX_EVENTS };
