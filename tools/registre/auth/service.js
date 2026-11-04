"use strict";
// Logique des comptes : connexion, sessions, mots de passe, comptes, rôles, réglages de sécurité et journal de sécurité.
// Indépendante du stockage (fichiers ou PostgreSQL) : tout passe par l'interface de store-file.js / store-pg.js.
const crypto = require("node:crypto");
const { hashPassword, verifyPassword, checkNewPassword } = require("./passwords");
const P = require("./permissions");

class AuthError extends Error {
  constructor(message, status, code) {
    super(message);
    this.status = status || 400;
    this.code = code || "invalid";
  }
}

const USERNAME = /^[a-z0-9][a-z0-9._-]{2,31}$/;
const ROLE_ID = /^[a-z0-9][a-z0-9_-]{1,31}$/;
const DEFAULT_SETTINGS = { defaultPassword: "qwerty1234", sessionHours: 12, sessionMaxDays: 7, maxFailedLogins: 5, lockMinutes: 15 };
const SETTING_LIMITS = { sessionHours: [1, 72], sessionMaxDays: [1, 30], maxFailedLogins: [3, 20], lockMinutes: [1, 1440] };
const TOUCH_EVERY_MS = 60000;
const MS = { hour: 3600000, day: 86400000, minute: 60000 };

const sha256 = (s) => crypto.createHash("sha256").update(s).digest("hex");
const text = (v, min, max) => typeof v === "string" && v.length >= min && v.length <= max && !/[\u0000-\u001f\u007f]/.test(v);
const isObject = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
const normUser = (v) => (typeof v === "string" ? v.trim().toLowerCase() : "");

function createAuth({ store, clock, random }) {
  const now = clock || Date.now;
  const rid = random || ((n) => crypto.randomBytes(n).toString("hex"));
  // Dernières tentatives ratées par « adresse|nom » : protège aussi les noms qui n'existent pas (réponse identique).
  const attempts = new Map();
  let dummyHash = null;

  async function settings() {
    const saved = await store.settings.get();
    const out = Object.assign({}, DEFAULT_SETTINGS);
    for (const k of Object.keys(DEFAULT_SETTINGS)) if (saved[k] !== undefined && typeof saved[k] === typeof DEFAULT_SETTINGS[k]) out[k] = saved[k];
    return out;
  }
  async function record(actor, action, target, detail, ip) {
    try {
      await store.audit.add({ at: now(), actor: actor ? (actor.user ? actor.user.username : String(actor)) : null, action, target: target ? String(target).slice(0, 80) : null, detail: detail ? String(detail).slice(0, 300) : null, ip: ip ? String(ip).slice(0, 60) : null });
    } catch { /* le journal ne doit jamais bloquer l'action */ }
  }

  async function roleById(id) {
    if (id === P.ADMIN_ROLE_ID) return P.adminRole();
    return store.roles.get(id);
  }
  // Permissions effectives : toujours recalculées depuis le rôle courant (un rôle modifié s'applique tout de suite). Les permissions réservées aux admins sont ignorées hors rôle admin.
  function effective(role) {
    if (!role) return new Set();
    if (role.id === P.ADMIN_ROLE_ID) return new Set(P.ALL_IDS);
    return new Set(role.permissions.filter((id) => P.isPermission(id) && !P.isAdminOnly(id)));
  }
  async function publicUser(u, rolesById) {
    const role = rolesById ? rolesById.get(u.roleId) : await roleById(u.roleId);
    return { id: u.id, username: u.username, displayName: u.displayName, roleId: u.roleId, roleName: role ? role.name : "(rôle supprimé)", mustChangePassword: !!u.mustChangePassword, disabled: !!u.disabled, locked: (u.lockedUntil || 0) > now(), lastLoginAt: u.lastLoginAt || null, createdAt: u.createdAt };
  }
  async function rolesMap() {
    const m = new Map([[P.ADMIN_ROLE_ID, P.adminRole()]]);
    for (const r of await store.roles.list()) m.set(r.id, r);
    return m;
  }
  const can = (actor, perm) => !!actor && actor.permissions.has(perm);
  function need(actor, perm) {
    if (!can(actor, perm)) throw new AuthError("Droit manquant : " + ((P.PERMISSIONS.find((x) => x.id === perm) || {}).label || perm), 403, "forbidden");
  }
  const isAdmin = (actor) => !!actor && actor.user.roleId === P.ADMIN_ROLE_ID;

  async function activeAdmins(exceptId) {
    return (await store.users.list()).filter((u) => u.roleId === P.ADMIN_ROLE_ID && !u.disabled && u.id !== exceptId).length;
  }
  // Un rôle ne peut être donné que par un administrateur, ou par quelqu'un qui possède déjà tous ses droits (jamais le rôle admin).
  async function assertAssignable(actor, roleId) {
    const role = await roleById(roleId);
    if (!role) throw new AuthError("Rôle inconnu.", 422);
    if (isAdmin(actor)) return role;
    if (role.id === P.ADMIN_ROLE_ID) throw new AuthError("Seul un administrateur peut donner le rôle administrateur.", 403, "forbidden");
    const mine = actor.permissions;
    if ([...effective(role)].some((id) => !mine.has(id))) throw new AuthError("Tu ne peux pas donner un rôle qui a plus de droits que toi.", 403, "forbidden");
    return role;
  }

  const api = {
    AuthError, DEFAULT_SETTINGS, can, need, isAdmin, settings, effective,

    async init() {
      await store.init();
      const roles = await store.roles.list();
      const saved = await store.settings.get();
      if (!saved.starterRolesSeeded) {
        for (const r of P.STARTER_ROLES) {
          if (!roles.some((x) => x.id === r.id)) await store.roles.insert({ id: r.id, name: r.name, description: r.description, permissions: r.permissions.slice(), createdAt: now(), updatedAt: now() });
        }
        await store.settings.put({ starterRolesSeeded: true });
      }
    },

    // Crée les comptes administrateurs de départ s'ils n'existent pas (idempotent). Le mot de passe fourni n'est jamais affiché ni écrit en clair.
    async ensureAdmins(list, password) {
      const created = [];
      for (const a of list) {
        const username = normUser(a.username);
        if (!USERNAME.test(username)) throw new AuthError("Nom d'utilisateur invalide : " + a.username, 422);
        if (await store.users.getByUsername(username)) continue;
        await store.users.insert({ id: "u" + rid(8), username, displayName: a.displayName || a.username, passwordHash: await hashPassword(password), roleId: P.ADMIN_ROLE_ID, mustChangePassword: !!a.mustChangePassword, disabled: false, failedLogins: 0, lockedUntil: 0, lastLoginAt: null, createdAt: now(), updatedAt: now(), createdBy: "installation" });
        await record("installation", "admin_cree", username, "compte administrateur de départ");
        created.push(username);
      }
      return created;
    },

    // ----- connexion -----
    async login(username, password, ctx) {
      const c = ctx || {};
      const name = normUser(username);
      const key = (c.ip || "?") + "|" + name.slice(0, 40);
      const cfg = await settings();
      const entry = attempts.get(key);
      if (entry && entry.blockedUntil > now()) throw new AuthError("Trop d'essais. Réessaie dans " + Math.max(1, Math.ceil((entry.blockedUntil - now()) / MS.minute)) + " minute(s).", 429, "locked");
      const fail = async (reason, user) => {
        const e = attempts.get(key) || { count: 0, blockedUntil: 0 };
        e.count++;
        if (e.count >= cfg.maxFailedLogins) { e.blockedUntil = now() + cfg.lockMinutes * MS.minute; e.count = 0; }
        attempts.set(key, e);
        if (attempts.size > 5000) attempts.clear();
        if (user) {
          const failed = (user.failedLogins || 0) + 1;
          const lock = failed >= cfg.maxFailedLogins;
          await store.users.update(user.id, { failedLogins: lock ? 0 : failed, lockedUntil: lock ? now() + cfg.lockMinutes * MS.minute : user.lockedUntil || 0 });
        }
        await record(name || null, "connexion_refusee", name, reason, c.ip);
        throw new AuthError("Identifiant ou mot de passe incorrect.", 401, "bad_credentials");
      };
      if (typeof username !== "string" || typeof password !== "string" || !name || name.length > 40 || password.length === 0 || password.length > 128) return fail("saisie invalide");
      const user = await store.users.getByUsername(name);
      if (!dummyHash) dummyHash = await hashPassword("temps-constant");
      const ok = await verifyPassword(password, user ? user.passwordHash : dummyHash);
      if (!user || !ok) return fail(user ? "mot de passe incorrect" : "compte inconnu", user);
      if (user.disabled) return fail("compte désactivé");
      if ((user.lockedUntil || 0) > now()) return fail("compte verrouillé");
      attempts.delete(key);
      const token = crypto.randomBytes(32).toString("base64url");
      await store.users.update(user.id, { failedLogins: 0, lockedUntil: 0, lastLoginAt: now() });
      await store.sessions.insert({ hash: sha256(token), userId: user.id, createdAt: now(), lastSeenAt: now(), expiresAt: now() + cfg.sessionHours * MS.hour, ip: c.ip || "", userAgent: String(c.userAgent || "").slice(0, 200) });
      await store.sessions.purgeExpired(now());
      await record(user.username, "connexion", user.username, null, c.ip);
      return { token, maxAgeSeconds: cfg.sessionHours * 3600, mustChangePassword: !!user.mustChangePassword, user: await publicUser(user) };
    },
    async logout(token, ctx) {
      if (typeof token !== "string" || !token) return;
      const s = await store.sessions.getByHash(sha256(token));
      if (!s) return;
      await store.sessions.deleteByHash(s.hash);
      const u = await store.users.getById(s.userId);
      if (u) await record(u.username, "deconnexion", u.username, null, ctx && ctx.ip);
    },
    // Retrouve la personne connectée d'après le jeton du cookie. Retourne null si absent, expiré, ou compte désactivé.
    async resolve(token) {
      if (typeof token !== "string" || token.length < 20 || token.length > 100) return null;
      const hash = sha256(token);
      const s = await store.sessions.getByHash(hash);
      if (!s) return null;
      const cfg = await settings();
      const t = now();
      if (s.expiresAt <= t || s.createdAt + cfg.sessionMaxDays * MS.day <= t) { await store.sessions.deleteByHash(hash); return null; }
      const user = await store.users.getById(s.userId);
      if (!user || user.disabled) { await store.sessions.deleteByHash(hash); return null; }
      if (t - s.lastSeenAt > TOUCH_EVERY_MS) await store.sessions.update(hash, { lastSeenAt: t, expiresAt: Math.min(t + cfg.sessionHours * MS.hour, s.createdAt + cfg.sessionMaxDays * MS.day) });
      const role = await roleById(user.roleId);
      return { user, role, permissions: effective(role), sessionHash: hash };
    },
    async me(actor) {
      const pu = await publicUser(actor.user);
      return Object.assign(pu, { permissions: [...actor.permissions], admin: isAdmin(actor) });
    },

    // ----- profil personnel -----
    async changePassword(actor, body, ctx) {
      if (!isObject(body) || typeof body.current !== "string" || typeof body.next !== "string") throw new AuthError("Ancien et nouveau mot de passe attendus.", 422);
      const cfg = await settings();
      const user = await store.users.getById(actor.user.id);
      if (!(await verifyPassword(body.current, user.passwordHash))) {
        await record(user.username, "changement_mdp_refuse", user.username, "ancien mot de passe incorrect", ctx && ctx.ip);
        throw new AuthError("L'ancien mot de passe est incorrect.", 403, "bad_current");
      }
      const problem = checkNewPassword(body.next, { username: user.username, defaultPassword: cfg.defaultPassword, current: body.current });
      if (problem) throw new AuthError(problem.charAt(0).toUpperCase() + problem.slice(1) + ".", 422, "weak_password");
      await store.users.update(user.id, { passwordHash: await hashPassword(body.next), mustChangePassword: false, failedLogins: 0, lockedUntil: 0, updatedAt: now() });
      await store.sessions.deleteByUser(user.id, actor.sessionHash); // les autres connexions sont fermées
      await record(user.username, "mdp_change", user.username, null, ctx && ctx.ip);
    },
    async updateProfile(actor, body) {
      if (!isObject(body) || !text(body.displayName, 2, 40) || !body.displayName.trim()) throw new AuthError("Le nom doit faire de 2 à 40 caractères.", 422);
      const u = await store.users.update(actor.user.id, { displayName: body.displayName.trim(), updatedAt: now() });
      await record(actor, "profil_modifie", u.username, "nom affiché");
      return publicUser(u);
    },

    // ----- comptes (administration) -----
    async listUsers(actor) {
      need(actor, "users.view");
      const m = await rolesMap();
      const out = [];
      for (const u of await store.users.list()) {
        const pu = await publicUser(u, m);
        if (can(actor, "users.sessions")) pu.sessionCount = (await store.sessions.listByUser(u.id)).filter((s) => s.expiresAt > now()).length;
        out.push(pu);
      }
      return out;
    },
    async createUser(actor, body, ctx) {
      need(actor, "users.create");
      if (!isObject(body)) throw new AuthError("Compte invalide.", 422);
      const username = normUser(body.username);
      if (!USERNAME.test(username)) throw new AuthError("Nom d'utilisateur : 3 à 32 caractères (lettres minuscules, chiffres, point, tiret, tiret bas), commençant par une lettre ou un chiffre.", 422);
      const displayName = body.displayName === undefined || body.displayName === "" ? username : body.displayName;
      if (!text(displayName, 2, 40)) throw new AuthError("Le nom doit faire de 2 à 40 caractères.", 422);
      await assertAssignable(actor, body.roleId);
      const cfg = await settings();
      const password = body.password === undefined || body.password === "" ? cfg.defaultPassword : body.password;
      if (typeof password !== "string" || password.length < 8 || password.length > 128) throw new AuthError("Le mot de passe de départ doit faire de 8 à 128 caractères.", 422);
      if (await store.users.getByUsername(username)) throw new AuthError("Ce nom d'utilisateur existe déjà.", 409, "duplicate");
      // Un mot de passe de départ est toujours à changer à la première connexion, sauf demande explicite pour un compte de confiance.
      const mustChange = password === cfg.defaultPassword ? true : body.mustChangePassword !== false;
      const user = { id: "u" + rid(8), username, displayName: displayName.trim(), passwordHash: await hashPassword(password), roleId: body.roleId, mustChangePassword: mustChange, disabled: false, failedLogins: 0, lockedUntil: 0, lastLoginAt: null, createdAt: now(), updatedAt: now(), createdBy: actor.user.username };
      try { await store.users.insert(user); } catch (e) { if (e.code === "duplicate") throw new AuthError("Ce nom d'utilisateur existe déjà.", 409, "duplicate"); throw e; }
      await record(actor, "compte_cree", username, "rôle " + body.roleId, ctx && ctx.ip);
      return publicUser(user);
    },
    async updateUser(actor, id, body, ctx) {
      if (!isObject(body)) throw new AuthError("Modification invalide.", 422);
      const user = await store.users.getById(id);
      if (!user) throw new AuthError("Compte introuvable.", 404);
      if (user.roleId === P.ADMIN_ROLE_ID && !isAdmin(actor)) throw new AuthError("Seul un administrateur peut modifier un administrateur.", 403, "forbidden");
      const patch = {};
      const self = user.id === actor.user.id;
      if (body.displayName !== undefined) { need(actor, "users.edit"); if (!text(body.displayName, 2, 40) || !body.displayName.trim()) throw new AuthError("Le nom doit faire de 2 à 40 caractères.", 422); patch.displayName = body.displayName.trim(); }
      if (body.roleId !== undefined && body.roleId !== user.roleId) {
        need(actor, "users.edit");
        if (self) throw new AuthError("Tu ne peux pas changer ton propre rôle.", 403, "forbidden");
        if (user.roleId === P.ADMIN_ROLE_ID && !isAdmin(actor)) throw new AuthError("Seul un administrateur peut modifier un administrateur.", 403, "forbidden");
        await assertAssignable(actor, body.roleId);
        if (user.roleId === P.ADMIN_ROLE_ID && !user.disabled && (await activeAdmins(user.id)) === 0) throw new AuthError("Il doit rester au moins un administrateur actif.", 409, "last_admin");
        patch.roleId = body.roleId;
      }
      if (body.disabled !== undefined) {
        need(actor, "users.disable");
        if (typeof body.disabled !== "boolean") throw new AuthError("Valeur « désactivé » invalide.", 422);
        if (self && body.disabled) throw new AuthError("Tu ne peux pas désactiver ton propre compte.", 403, "forbidden");
        if (user.roleId === P.ADMIN_ROLE_ID && !isAdmin(actor)) throw new AuthError("Seul un administrateur peut modifier un administrateur.", 403, "forbidden");
        if (body.disabled && user.roleId === P.ADMIN_ROLE_ID && !user.disabled && (await activeAdmins(user.id)) === 0) throw new AuthError("Il doit rester au moins un administrateur actif.", 409, "last_admin");
        patch.disabled = body.disabled;
        if (!body.disabled) { patch.failedLogins = 0; patch.lockedUntil = 0; }
      }
      if (!Object.keys(patch).length) return publicUser(user);
      patch.updatedAt = now();
      const next = await store.users.update(id, patch);
      if (patch.disabled === true || patch.roleId !== undefined) await store.sessions.deleteByUser(id);
      const what = Object.keys(patch).filter((k) => k !== "updatedAt" && k !== "failedLogins" && k !== "lockedUntil").map((k) => (k === "roleId" ? "rôle → " + patch.roleId : k === "disabled" ? (patch.disabled ? "désactivé" : "réactivé") : "nom")).join(", ");
      await record(actor, patch.disabled === true ? "compte_desactive" : patch.disabled === false ? "compte_reactive" : "compte_modifie", user.username, what, ctx && ctx.ip);
      return publicUser(next);
    },
    async resetPassword(actor, id, body, ctx) {
      need(actor, "users.reset_password");
      const user = await store.users.getById(id);
      if (!user) throw new AuthError("Compte introuvable.", 404);
      if (user.id === actor.user.id) throw new AuthError("Pour ton propre mot de passe, utilise « Mon compte ».", 403, "forbidden");
      if (user.roleId === P.ADMIN_ROLE_ID && !isAdmin(actor)) throw new AuthError("Seul un administrateur peut modifier un administrateur.", 403, "forbidden");
      const cfg = await settings();
      const password = body && typeof body.password === "string" && body.password !== "" ? body.password : cfg.defaultPassword;
      if (password.length < 8 || password.length > 128) throw new AuthError("Le mot de passe doit faire de 8 à 128 caractères.", 422);
      await store.users.update(id, { passwordHash: await hashPassword(password), mustChangePassword: true, failedLogins: 0, lockedUntil: 0, updatedAt: now() });
      await store.sessions.deleteByUser(id);
      await record(actor, "mdp_reinitialise", user.username, null, ctx && ctx.ip);
      return { ok: true, usedDefault: password === cfg.defaultPassword };
    },
    async deleteUser(actor, id, ctx) {
      need(actor, "users.delete");
      const user = await store.users.getById(id);
      if (!user) throw new AuthError("Compte introuvable.", 404);
      if (user.id === actor.user.id) throw new AuthError("Tu ne peux pas supprimer ton propre compte.", 403, "forbidden");
      if (user.roleId === P.ADMIN_ROLE_ID && !user.disabled && (await activeAdmins(user.id)) === 0) throw new AuthError("Il doit rester au moins un administrateur actif.", 409, "last_admin");
      await store.users.delete(id);
      await record(actor, "compte_supprime", user.username, null, ctx && ctx.ip);
    },
    async listSessions(actor, id) {
      need(actor, "users.sessions");
      return (await store.sessions.listByUser(id)).filter((s) => s.expiresAt > now()).map((s) => ({ createdAt: s.createdAt, lastSeenAt: s.lastSeenAt, expiresAt: s.expiresAt, ip: s.ip, userAgent: s.userAgent }));
    },
    async revokeSessions(actor, id, ctx) {
      need(actor, "users.sessions");
      const user = await store.users.getById(id);
      if (!user) throw new AuthError("Compte introuvable.", 404);
      const n = await store.sessions.deleteByUser(id, user.id === actor.user.id ? actor.sessionHash : undefined);
      await record(actor, "sessions_fermees", user.username, n + " session(s)", ctx && ctx.ip);
      return { closed: n };
    },

    // ----- rôles -----
    async listRoles(actor) {
      if (!can(actor, "roles.view") && !can(actor, "users.create") && !can(actor, "users.edit")) need(actor, "roles.view");
      const out = [P.adminRole()].concat(await store.roles.list());
      const users = await store.users.list();
      return out.map((r) => ({ id: r.id, name: r.name, description: r.description, permissions: r.permissions, builtin: !!r.builtin, userCount: users.filter((u) => u.roleId === r.id).length }));
    },
    async createRole(actor, body, ctx) {
      need(actor, "roles.manage");
      const v = await validateRole(body, null);
      const role = { id: await newRoleId(v.name), name: v.name, description: v.description, permissions: v.permissions, createdAt: now(), updatedAt: now() };
      try { await store.roles.insert(role); } catch (e) { if (e.code === "duplicate") throw new AuthError("Un rôle porte déjà ce nom.", 409, "duplicate"); throw e; }
      await record(actor, "role_cree", role.name, role.permissions.length + " permission(s)", ctx && ctx.ip);
      return role;
    },
    async updateRole(actor, id, body, ctx) {
      need(actor, "roles.manage");
      if (id === P.ADMIN_ROLE_ID) throw new AuthError("Le rôle administrateur ne se modifie pas.", 403, "forbidden");
      const current = await store.roles.get(id);
      if (!current) throw new AuthError("Rôle introuvable.", 404);
      const v = await validateRole(body, id);
      let next;
      try { next = await store.roles.update(id, { name: v.name, description: v.description, permissions: v.permissions, updatedAt: now() }); } catch (e) { if (e.code === "duplicate") throw new AuthError("Un rôle porte déjà ce nom.", 409, "duplicate"); throw e; }
      const before = new Set(current.permissions);
      const added = v.permissions.filter((x) => !before.has(x)).length, removed = current.permissions.filter((x) => !v.permissions.includes(x)).length;
      await record(actor, "role_modifie", next.name, "+" + added + " / −" + removed + " permission(s)", ctx && ctx.ip);
      return next;
    },
    async deleteRole(actor, id, ctx) {
      need(actor, "roles.manage");
      if (id === P.ADMIN_ROLE_ID) throw new AuthError("Le rôle administrateur ne se supprime pas.", 403, "forbidden");
      const role = await store.roles.get(id);
      if (!role) throw new AuthError("Rôle introuvable.", 404);
      const n = await store.roles.countUsers(id);
      if (n > 0) throw new AuthError("Ce rôle est donné à " + n + " compte(s) : change d'abord leur rôle.", 409, "in_use");
      await store.roles.delete(id);
      await record(actor, "role_supprime", role.name, null, ctx && ctx.ip);
    },

    // ----- sécurité -----
    async getSettings(actor) {
      need(actor, "security.settings");
      return settings();
    },
    async updateSettings(actor, body, ctx) {
      need(actor, "security.settings");
      if (!isObject(body)) throw new AuthError("Réglages invalides.", 422);
      const patch = {};
      for (const k of Object.keys(body)) {
        if (!(k in DEFAULT_SETTINGS)) throw new AuthError("Réglage inconnu : " + k.slice(0, 40), 422);
        if (k === "defaultPassword") {
          if (!text(body[k], 8, 64)) throw new AuthError("Le mot de passe de départ doit faire de 8 à 64 caractères.", 422);
        } else if (!Number.isInteger(body[k]) || body[k] < SETTING_LIMITS[k][0] || body[k] > SETTING_LIMITS[k][1]) {
          throw new AuthError("« " + k + " » doit être un entier de " + SETTING_LIMITS[k][0] + " à " + SETTING_LIMITS[k][1] + ".", 422);
        }
        patch[k] = body[k];
      }
      await store.settings.put(patch);
      await record(actor, "securite_modifiee", Object.keys(patch).join(", "), null, ctx && ctx.ip);
      return settings();
    },
    async listAudit(actor, limit) {
      need(actor, "audit.view");
      return store.audit.list(limit);
    },
    async catalog(actor) {
      if (!can(actor, "roles.view")) need(actor, "roles.view");
      return P.CATEGORIES.map((c) => ({ id: c.id, label: c.label, description: c.description, permissions: c.permissions.map((x) => ({ id: x.id, label: x.label, description: x.description, adminOnly: x.adminOnly })) }));
    },
  };

  async function validateRole(body, existingId) {
    if (!isObject(body)) throw new AuthError("Rôle invalide.", 422);
    if (!text(body.name, 2, 40) || !body.name.trim()) throw new AuthError("Le nom du rôle doit faire de 2 à 40 caractères.", 422);
    const name = body.name.trim();
    if (name.toLowerCase() === "administrateur" || name.toLowerCase() === "admin") throw new AuthError("Ce nom est réservé.", 422);
    const description = body.description === undefined ? "" : body.description;
    if (!text(description, 0, 200)) throw new AuthError("La description fait 200 caractères au plus.", 422);
    const check = P.checkRolePermissions(body.permissions);
    if (!check.ok) throw new AuthError("Permissions : " + check.error + ".", 422);
    const clash = (await store.roles.list()).find((r) => r.id !== existingId && r.name.toLowerCase() === name.toLowerCase());
    if (clash) throw new AuthError("Un rôle porte déjà ce nom.", 409, "duplicate");
    return { name, description, permissions: check.clean };
  }
  async function newRoleId(name) {
    const base = name.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24) || "role";
    for (let i = 0; i < 20; i++) {
      const id = i === 0 ? base : base.slice(0, 22) + "-" + rid(2);
      if (ROLE_ID.test(id) && id !== P.ADMIN_ROLE_ID && !(await store.roles.get(id))) return id;
    }
    throw new AuthError("Impossible de créer un identifiant de rôle.", 500);
  }
  return api;
}

module.exports = { createAuth, AuthError, USERNAME, DEFAULT_SETTINGS, SETTING_LIMITS };
