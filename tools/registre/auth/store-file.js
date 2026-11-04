"use strict";
// Stockage des comptes dans des fichiers (développement local et tests). Même interface que le stockage PostgreSQL (store-pg.js).
// Les opérations sont sérialisées dans le processus et les écritures sont atomiques. Les mots de passe sont déjà hachés quand ils arrivent ici.
const fs = require("node:fs");
const path = require("node:path");

const MAX_AUDIT = 5000;

function createFileStore({ dir }) {
  let chain = Promise.resolve();
  const exclusive = (fn) => {
    const run = chain.then(fn, fn);
    chain = run.catch(() => {});
    return run;
  };
  const file = (name) => path.join(dir, name + ".json");
  function read(name, fallback) {
    try {
      return JSON.parse(fs.readFileSync(file(name), "utf8"));
    } catch {
      return fallback;
    }
  }
  function write(name, value) {
    fs.mkdirSync(dir, { recursive: true });
    const tmp = file(name) + "." + process.pid + "." + Math.random().toString(36).slice(2, 8) + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(value, null, 1));
    fs.renameSync(tmp, file(name));
  }
  const clone = (v) => (v === undefined ? v : JSON.parse(JSON.stringify(v)));
  // Mêmes champs modifiables que dans PostgreSQL : un champ inconnu est une erreur, jamais une écriture silencieuse.
  const KEYS = { users: ["username", "displayName", "passwordHash", "roleId", "mustChangePassword", "disabled", "failedLogins", "lockedUntil", "lastLoginAt", "updatedAt", "createdBy"], roles: ["name", "description", "permissions", "updatedAt"], sessions: ["lastSeenAt", "expiresAt"] };
  const onlyKnown = (kind, patch) => { for (const k of Object.keys(patch)) if (!KEYS[kind].includes(k)) throw new Error("champ inconnu : " + k); };

  const store = {
    kind: "file",
    async init() {},
    async close() {},

    users: {
      getById: (id) => exclusive(() => clone(read("users", []).find((u) => u.id === id) || null)),
      getByUsername: (name) => exclusive(() => clone(read("users", []).find((u) => u.username === name) || null)),
      list: () => exclusive(() => clone(read("users", []).sort((a, b) => a.createdAt - b.createdAt))),
      insert: (user) => exclusive(() => {
        const list = read("users", []);
        if (list.some((u) => u.id === user.id || u.username === user.username)) { const e = new Error("compte déjà existant"); e.code = "duplicate"; throw e; }
        list.push(clone(user));
        write("users", list);
        return clone(user);
      }),
      update: (id, patch) => exclusive(() => {
        onlyKnown("users", patch);
        const list = read("users", []);
        const i = list.findIndex((u) => u.id === id);
        if (i < 0) return null;
        if (patch.username && list.some((u) => u.username === patch.username && u.id !== id)) { const e = new Error("nom d'utilisateur déjà pris"); e.code = "duplicate"; throw e; }
        list[i] = Object.assign({}, list[i], clone(patch));
        write("users", list);
        return clone(list[i]);
      }),
      delete: (id) => exclusive(() => {
        const list = read("users", []);
        const next = list.filter((u) => u.id !== id);
        if (next.length === list.length) return false;
        write("users", next);
        write("sessions", read("sessions", []).filter((s) => s.userId !== id));
        return true;
      }),
      count: () => exclusive(() => read("users", []).length),
    },

    roles: {
      list: () => exclusive(() => clone(read("roles", []).sort((a, b) => a.createdAt - b.createdAt))),
      get: (id) => exclusive(() => clone(read("roles", []).find((r) => r.id === id) || null)),
      insert: (role) => exclusive(() => {
        const list = read("roles", []);
        if (list.some((r) => r.id === role.id || r.name.toLowerCase() === role.name.toLowerCase())) { const e = new Error("rôle déjà existant"); e.code = "duplicate"; throw e; }
        list.push(clone(role));
        write("roles", list);
        return clone(role);
      }),
      update: (id, patch) => exclusive(() => {
        onlyKnown("roles", patch);
        const list = read("roles", []);
        const i = list.findIndex((r) => r.id === id);
        if (i < 0) return null;
        if (patch.name && list.some((r) => r.id !== id && r.name.toLowerCase() === patch.name.toLowerCase())) { const e = new Error("nom de rôle déjà pris"); e.code = "duplicate"; throw e; }
        list[i] = Object.assign({}, list[i], clone(patch));
        write("roles", list);
        return clone(list[i]);
      }),
      delete: (id) => exclusive(() => {
        const list = read("roles", []);
        const next = list.filter((r) => r.id !== id);
        if (next.length === list.length) return false;
        write("roles", next);
        return true;
      }),
      countUsers: (id) => exclusive(() => read("users", []).filter((u) => u.roleId === id).length),
    },

    sessions: {
      insert: (s) => exclusive(() => { const list = read("sessions", []); list.push(clone(s)); write("sessions", list); return clone(s); }),
      getByHash: (hash) => exclusive(() => clone(read("sessions", []).find((s) => s.hash === hash) || null)),
      update: (hash, patch) => exclusive(() => {
        onlyKnown("sessions", patch);
        const list = read("sessions", []);
        const i = list.findIndex((s) => s.hash === hash);
        if (i < 0) return null;
        list[i] = Object.assign({}, list[i], clone(patch));
        write("sessions", list);
        return clone(list[i]);
      }),
      deleteByHash: (hash) => exclusive(() => { const list = read("sessions", []); const next = list.filter((s) => s.hash !== hash); write("sessions", next); return list.length - next.length; }),
      deleteByUser: (userId, exceptHash) => exclusive(() => { const list = read("sessions", []); const next = list.filter((s) => s.userId !== userId || s.hash === exceptHash); write("sessions", next); return list.length - next.length; }),
      listByUser: (userId) => exclusive(() => clone(read("sessions", []).filter((s) => s.userId === userId).sort((a, b) => b.lastSeenAt - a.lastSeenAt))),
      purgeExpired: (now) => exclusive(() => { const list = read("sessions", []); const next = list.filter((s) => s.expiresAt > now); if (next.length !== list.length) write("sessions", next); return list.length - next.length; }),
    },

    audit: {
      add: (event) => exclusive(() => {
        const list = read("audit", []);
        const id = (list.length ? list[0].id : 0) + 1;
        list.unshift(Object.assign({ id }, clone(event)));
        write("audit", list.slice(0, MAX_AUDIT));
        return id;
      }),
      list: (limit) => exclusive(() => clone(read("audit", []).slice(0, Number.isInteger(limit) && limit > 0 ? Math.min(limit, MAX_AUDIT) : 200))),
    },

    settings: {
      get: () => exclusive(() => clone(read("settings", {}))),
      put: (value) => exclusive(() => { const merged = Object.assign({}, read("settings", {}), clone(value)); write("settings", merged); return clone(value); }),
    },
  };
  return store;
}

module.exports = { createFileStore };
