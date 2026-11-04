"use strict";
// Stockage des comptes dans PostgreSQL (Render). Même interface que store-file.js.
// `pool` est un objet avec query(texte, paramètres) : le Pool de « pg » en production, un double en mémoire dans les tests.
// Toutes les requêtes sont paramétrées ($1, $2…) : aucune valeur n'est jamais collée dans le texte SQL.

const MIGRATIONS = [
  {
    version: 1,
    statements: [
      "CREATE TABLE IF NOT EXISTS roles (id text PRIMARY KEY, name text NOT NULL, description text NOT NULL DEFAULT '', permissions jsonb NOT NULL DEFAULT '[]', created_at bigint NOT NULL, updated_at bigint NOT NULL)",
      "CREATE UNIQUE INDEX IF NOT EXISTS roles_name ON roles (name)",
      "CREATE TABLE IF NOT EXISTS users (id text PRIMARY KEY, username text NOT NULL UNIQUE, display_name text NOT NULL, password_hash text NOT NULL, role_id text NOT NULL, must_change_password boolean NOT NULL DEFAULT false, disabled boolean NOT NULL DEFAULT false, failed_logins integer NOT NULL DEFAULT 0, locked_until bigint NOT NULL DEFAULT 0, last_login_at bigint, created_at bigint NOT NULL, updated_at bigint NOT NULL, created_by text)",
      "CREATE TABLE IF NOT EXISTS sessions (hash text PRIMARY KEY, user_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE, created_at bigint NOT NULL, last_seen_at bigint NOT NULL, expires_at bigint NOT NULL, ip text, user_agent text)",
      "CREATE INDEX IF NOT EXISTS sessions_user ON sessions (user_id)",
      "CREATE TABLE IF NOT EXISTS audit_log (id bigserial PRIMARY KEY, at bigint NOT NULL, actor text, action text NOT NULL, target text, detail text, ip text)",
      "CREATE INDEX IF NOT EXISTS audit_at ON audit_log (at)",
      "CREATE TABLE IF NOT EXISTS settings (key text PRIMARY KEY, value jsonb NOT NULL)",
    ],
  },
];

const num = (v) => (v === null || v === undefined ? v : Number(v));
const userOf = (r) => r && { id: r.id, username: r.username, displayName: r.display_name, passwordHash: r.password_hash, roleId: r.role_id, mustChangePassword: !!r.must_change_password, disabled: !!r.disabled, failedLogins: num(r.failed_logins), lockedUntil: num(r.locked_until), lastLoginAt: r.last_login_at === null ? null : num(r.last_login_at), createdAt: num(r.created_at), updatedAt: num(r.updated_at), createdBy: r.created_by === null ? null : r.created_by };
const roleOf = (r) => r && { id: r.id, name: r.name, description: r.description, permissions: typeof r.permissions === "string" ? JSON.parse(r.permissions) : r.permissions, createdAt: num(r.created_at), updatedAt: num(r.updated_at) };
const sessionOf = (r) => r && { hash: r.hash, userId: r.user_id, createdAt: num(r.created_at), lastSeenAt: num(r.last_seen_at), expiresAt: num(r.expires_at), ip: r.ip || "", userAgent: r.user_agent || "" };
const auditOf = (r) => ({ id: num(r.id), at: num(r.at), actor: r.actor, action: r.action, target: r.target, detail: r.detail, ip: r.ip });

const USER_COLUMNS = { username: "username", displayName: "display_name", passwordHash: "password_hash", roleId: "role_id", mustChangePassword: "must_change_password", disabled: "disabled", failedLogins: "failed_logins", lockedUntil: "locked_until", lastLoginAt: "last_login_at", updatedAt: "updated_at", createdBy: "created_by" };
const ROLE_COLUMNS = { name: "name", description: "description", permissions: "permissions", updatedAt: "updated_at" };
const SESSION_COLUMNS = { lastSeenAt: "last_seen_at", expiresAt: "expires_at" };

function duplicate(error, message) {
  if (error && (error.code === "23505" || /duplicate key|unique constraint/i.test(String(error.message)))) {
    const e = new Error(message);
    e.code = "duplicate";
    return e;
  }
  return error;
}

// Construit « SET col = $n, … » à partir d'un correctif, en n'acceptant que les colonnes connues.
function setClause(patch, columns, startAt) {
  const sets = [], values = [];
  for (const key of Object.keys(patch)) {
    if (!columns[key]) throw new Error("champ inconnu : " + key);
    values.push(key === "permissions" ? JSON.stringify(patch[key]) : patch[key]);
    sets.push(columns[key] + " = $" + (startAt + values.length - 1) + (key === "permissions" ? "::jsonb" : ""));
  }
  return { sql: sets.join(", "), values };
}

function createPgStore({ pool }) {
  const q = (text, params) => pool.query(text, params || []);
  const one = async (text, params) => (await q(text, params)).rows[0] || null;

  return {
    kind: "postgres",
    async init() {
      let applied;
      try {
        applied = (await q("SELECT version FROM schema_migrations")).rows;
      } catch {
        await q("CREATE TABLE IF NOT EXISTS schema_migrations (version integer PRIMARY KEY, applied_at bigint NOT NULL)");
        applied = [];
      }
      const done = new Set(applied.map((r) => Number(r.version)));
      for (const m of MIGRATIONS) {
        if (done.has(m.version)) continue;
        for (const sql of m.statements) await q(sql);
        await q("INSERT INTO schema_migrations (version, applied_at) VALUES ($1, $2)", [m.version, Date.now()]);
      }
    },
    async close() {
      if (typeof pool.end === "function") await pool.end();
    },

    users: {
      getById: async (id) => userOf(await one("SELECT * FROM users WHERE id = $1", [id])),
      getByUsername: async (name) => userOf(await one("SELECT * FROM users WHERE username = $1", [name])),
      list: async () => (await q("SELECT * FROM users ORDER BY created_at ASC, id ASC")).rows.map(userOf),
      async insert(u) {
        try {
          await q("INSERT INTO users (id, username, display_name, password_hash, role_id, must_change_password, disabled, failed_logins, locked_until, last_login_at, created_at, updated_at, created_by) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)",
            [u.id, u.username, u.displayName, u.passwordHash, u.roleId, !!u.mustChangePassword, !!u.disabled, u.failedLogins || 0, u.lockedUntil || 0, u.lastLoginAt === undefined ? null : u.lastLoginAt, u.createdAt, u.updatedAt, u.createdBy === undefined ? null : u.createdBy]);
        } catch (e) { throw duplicate(e, "compte déjà existant"); }
        return u;
      },
      async update(id, patch) {
        const keys = Object.keys(patch);
        if (!keys.length) return userOf(await one("SELECT * FROM users WHERE id = $1", [id]));
        const { sql, values } = setClause(patch, USER_COLUMNS, 2);
        try {
          return userOf(await one("UPDATE users SET " + sql + " WHERE id = $1 RETURNING *", [id].concat(values)));
        } catch (e) { throw duplicate(e, "nom d'utilisateur déjà pris"); }
      },
      async delete(id) {
        await q("DELETE FROM sessions WHERE user_id = $1", [id]);
        return (await q("DELETE FROM users WHERE id = $1 RETURNING id", [id])).rows.length > 0;
      },
      count: async () => Number((await one("SELECT COUNT(*) AS n FROM users")).n),
    },

    roles: {
      list: async () => (await q("SELECT * FROM roles ORDER BY created_at ASC, id ASC")).rows.map(roleOf),
      get: async (id) => roleOf(await one("SELECT * FROM roles WHERE id = $1", [id])),
      async insert(r) {
        try {
          await q("INSERT INTO roles (id, name, description, permissions, created_at, updated_at) VALUES ($1,$2,$3,$4::jsonb,$5,$6)", [r.id, r.name, r.description || "", JSON.stringify(r.permissions), r.createdAt, r.updatedAt]);
        } catch (e) { throw duplicate(e, "rôle déjà existant"); }
        return r;
      },
      async update(id, patch) {
        if (!Object.keys(patch).length) return roleOf(await one("SELECT * FROM roles WHERE id = $1", [id]));
        const { sql, values } = setClause(patch, ROLE_COLUMNS, 2);
        try {
          return roleOf(await one("UPDATE roles SET " + sql + " WHERE id = $1 RETURNING *", [id].concat(values)));
        } catch (e) { throw duplicate(e, "nom de rôle déjà pris"); }
      },
      delete: async (id) => (await q("DELETE FROM roles WHERE id = $1 RETURNING id", [id])).rows.length > 0,
      countUsers: async (id) => Number((await one("SELECT COUNT(*) AS n FROM users WHERE role_id = $1", [id])).n),
    },

    sessions: {
      async insert(s) {
        await q("INSERT INTO sessions (hash, user_id, created_at, last_seen_at, expires_at, ip, user_agent) VALUES ($1,$2,$3,$4,$5,$6,$7)", [s.hash, s.userId, s.createdAt, s.lastSeenAt, s.expiresAt, s.ip || "", s.userAgent || ""]);
        return s;
      },
      getByHash: async (hash) => sessionOf(await one("SELECT * FROM sessions WHERE hash = $1", [hash])),
      async update(hash, patch) {
        if (!Object.keys(patch).length) return sessionOf(await one("SELECT * FROM sessions WHERE hash = $1", [hash]));
        const { sql, values } = setClause(patch, SESSION_COLUMNS, 2);
        return sessionOf(await one("UPDATE sessions SET " + sql + " WHERE hash = $1 RETURNING *", [hash].concat(values)));
      },
      deleteByHash: async (hash) => (await q("DELETE FROM sessions WHERE hash = $1 RETURNING hash", [hash])).rows.length,
      deleteByUser: async (userId, exceptHash) => (await q("DELETE FROM sessions WHERE user_id = $1 AND hash <> $2 RETURNING hash", [userId, exceptHash || ""])).rows.length,
      listByUser: async (userId) => (await q("SELECT * FROM sessions WHERE user_id = $1 ORDER BY last_seen_at DESC", [userId])).rows.map(sessionOf),
      purgeExpired: async (now) => (await q("DELETE FROM sessions WHERE expires_at <= $1 RETURNING hash", [now])).rows.length,
    },

    audit: {
      async add(e) {
        const row = await one("INSERT INTO audit_log (at, actor, action, target, detail, ip) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id", [e.at, e.actor === undefined ? null : e.actor, e.action, e.target === undefined ? null : e.target, e.detail === undefined ? null : e.detail, e.ip === undefined ? null : e.ip]);
        return num(row.id);
      },
      list: async (limit) => (await q("SELECT * FROM audit_log ORDER BY at DESC, id DESC LIMIT $1", [Number.isInteger(limit) && limit > 0 ? Math.min(limit, 5000) : 200])).rows.map(auditOf),
    },

    settings: {
      async get() {
        const out = {};
        for (const r of (await q("SELECT key, value FROM settings")).rows) out[r.key] = typeof r.value === "string" ? JSON.parse(r.value) : r.value;
        return out;
      },
      async put(value) {
        for (const key of Object.keys(value)) {
          await q("INSERT INTO settings (key, value) VALUES ($1, $2::jsonb) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value", [key, JSON.stringify(value[key])]);
        }
        return value;
      },
    },
  };
}

module.exports = { createPgStore, MIGRATIONS };
