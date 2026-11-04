"use strict";
// Passerelle HTTP des comptes : cookie de session, table « route → permission », routes /api/auth/* et /api/admin/*, page de connexion.
const fs = require("node:fs");
const path = require("node:path");
const { AuthError } = require("./service");
const P = require("./permissions");

const COOKIE = "registre_session";

function parseCookies(header) {
  const out = {};
  if (typeof header !== "string") return out;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i < 0) continue;
    const k = part.slice(0, i).trim();
    if (k && !(k in out)) out[k] = part.slice(i + 1).trim();
  }
  return out;
}
function sessionCookie(token, maxAgeSeconds, secure) {
  return COOKIE + "=" + token + "; Path=/; HttpOnly; SameSite=Strict; Max-Age=" + maxAgeSeconds + (secure ? "; Secure" : "");
}
const clearCookie = (secure) => COOKIE + "=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0" + (secure ? "; Secure" : "");

// Permission exigée par une route. Retourne : une chaîne (ce droit), un tableau (un de ces droits), null (toute personne connectée), ou undefined (route inconnue).
function requiredPermission(method, p) {
  let m;
  if (p === "/api/projects") return method === "GET" ? "projects.view" : method === "POST" ? "projects.add" : undefined;
  if (p === "/api/projects/pick-folder") return method === "POST" ? "projects.add" : undefined;
  if ((m = /^\/api\/projects\/p[a-f0-9]{16}\/refresh$/.exec(p))) return method === "POST" ? "projects.refresh" : undefined;
  if (/^\/api\/projects\/(boom|luma|p[a-f0-9]{16})$/.test(p)) return method === "GET" ? "projects.view" : method === "PATCH" ? "projects.edit" : method === "DELETE" ? "projects.remove" : undefined;
  if (p === "/api/storage") return method === "GET" ? "storage.view" : undefined;
  if (p === "/api/settings") return method === "GET" || method === "PUT" ? null : undefined;
  if (p === "/api/chats" || /^\/api\/chats\/[^/]+$/.test(p)) return "assistant.use";
  if (p === "/api/sounds") return method === "GET" ? "sounds.view" : method === "POST" ? "sounds.create" : undefined;
  if (/^\/api\/sounds\/[^/]+$/.test(p)) return method === "PUT" ? "sounds.edit" : method === "DELETE" ? "sounds.delete" : undefined;
  if (p === "/api/schema") return method === "GET" ? null : undefined;
  if (p === "/api/activity") return method === "GET" ? "journal.activity.view" : undefined;
  if (p === "/api/tickets") return method === "GET" ? "tickets.view" : method === "POST" ? "tickets.create" : undefined;
  if ((m = /^\/api\/tickets\/[^/]+(?:\/(move|comments)(?:\/[^/]+)?)?$/.exec(p))) {
    if (!m[1]) return method === "GET" ? "tickets.view" : method === "PATCH" ? "tickets.edit" : method === "DELETE" ? "tickets.delete" : undefined;
    if (m[1] === "move") return method === "POST" && p.split("/").length === 5 ? "tickets.move" : undefined;
    const parts = p.split("/").length;
    if (parts === 5) return method === "POST" ? "tickets.comment" : undefined;
    return method === "DELETE" ? "tickets.comment.delete" : undefined;
  }
  if ((m = /^\/api\/journal\/([a-z]+)(?:\/([^/]+))?$/.exec(p))) {
    const base = "journal." + m[1] + ".";
    if (!P.isPermission(base + "view")) return undefined;
    if (!m[2]) return method === "GET" ? base + "view" : method === "POST" ? base + "create" : undefined;
    return method === "PUT" ? base + "edit" : method === "DELETE" ? base + "delete" : undefined;
  }
  if (p === "/api/backup") return method === "GET" ? "storage.export" : method === "POST" ? "storage.import" : undefined;
  if (p === "/api/contributions") return method === "GET" ? "contributions.view" : method === "POST" ? "contributions.create" : undefined;
  if (/^\/api\/contributions\/[^/]+$/.test(p)) return method === "DELETE" ? "contributions.delete" : undefined;
  if (p === "/api/refresh") return method === "POST" ? "tests.run" : undefined;
  if (p === "/api/tests/latest") return method === "GET" ? ["tests.view", "journal.coverage.view"] : undefined;
  if (p === "/api/tests/run") return method === "POST" ? "tests.run" : undefined;
  return undefined;
}
function allowed(actor, perm) {
  if (perm === null) return true;
  if (Array.isArray(perm)) return perm.some((x) => actor.permissions.has(x));
  return actor.permissions.has(perm);
}

function loginPage(state) {
  const html = fs.readFileSync(path.join(__dirname, "login.html"), "utf8");
  return html.replace("__STATE__", () => JSON.stringify(state || { mode: "login" }).replace(/</g, "\\u003c"));
}

// Routes /api/auth/* et /api/admin/*. `ctx` : { send, jsonBody, ip, userAgent, secure }. Retourne true si la route a répondu.
async function authRoutes(auth, req, res, url, actor, ctx) {
  const method = req.method, p = url.pathname;
  const { send, jsonBody } = ctx;
  const info = { ip: ctx.ip, userAgent: ctx.userAgent };
  try {
    if (p === "/api/auth/login" && method === "POST") {
      const body = await jsonBody(req, 2000);
      const r = await auth.login(body.username, body.password, info);
      res.setHeader("Set-Cookie", sessionCookie(r.token, r.maxAgeSeconds, ctx.secure));
      return send(res, 200, { user: r.user, mustChangePassword: r.mustChangePassword }), true;
    }
    if (p === "/api/auth/logout" && method === "POST") {
      const token = parseCookies(req.headers.cookie)[COOKIE];
      await auth.logout(token, info);
      res.setHeader("Set-Cookie", clearCookie(ctx.secure));
      return send(res, 200, { ok: true }), true;
    }
    if (p.startsWith("/api/auth/") || p.startsWith("/api/admin/")) {
      if (!actor) return send(res, 401, { error: "Connexion requise.", code: "login_required" }), true;
    } else return false;

    if (p === "/api/auth/me" && method === "GET") return send(res, 200, await auth.me(actor)), true;
    if (p === "/api/auth/password" && method === "POST") { await auth.changePassword(actor, await jsonBody(req, 2000), info); return send(res, 200, { ok: true }), true; }
    if (p === "/api/auth/profile" && method === "PATCH") return send(res, 200, await auth.updateProfile(actor, await jsonBody(req, 2000))), true;

    if (actor.user.mustChangePassword) return send(res, 403, { error: "Change d'abord ton mot de passe.", code: "must_change_password" }), true;

    if (p === "/api/admin/users") {
      if (method === "GET") return send(res, 200, await auth.listUsers(actor)), true;
      if (method === "POST") return send(res, 201, await auth.createUser(actor, await jsonBody(req, 4000), info)), true;
    }
    let m = /^\/api\/admin\/users\/(u[a-f0-9]{16})$/.exec(p);
    if (m) {
      if (method === "PATCH") return send(res, 200, await auth.updateUser(actor, m[1], await jsonBody(req, 4000), info)), true;
      if (method === "DELETE") { await auth.deleteUser(actor, m[1], info); return send(res, 200, { ok: true }), true; }
    }
    m = /^\/api\/admin\/users\/(u[a-f0-9]{16})\/reset-password$/.exec(p);
    if (m && method === "POST") return send(res, 200, await auth.resetPassword(actor, m[1], await jsonBody(req, 2000), info)), true;
    m = /^\/api\/admin\/users\/(u[a-f0-9]{16})\/sessions$/.exec(p);
    if (m && method === "GET") return send(res, 200, await auth.listSessions(actor, m[1])), true;
    if (m && method === "DELETE") return send(res, 200, await auth.revokeSessions(actor, m[1], info)), true;

    if (p === "/api/admin/roles") {
      if (method === "GET") return send(res, 200, await auth.listRoles(actor)), true;
      if (method === "POST") return send(res, 201, await auth.createRole(actor, await jsonBody(req, 20000), info)), true;
    }
    if (p === "/api/admin/permissions" && method === "GET") return send(res, 200, await auth.catalog(actor)), true;
    m = /^\/api\/admin\/roles\/([a-z0-9][a-z0-9_-]{1,31})$/.exec(p);
    if (m) {
      if (method === "PUT") return send(res, 200, await auth.updateRole(actor, m[1], await jsonBody(req, 20000), info)), true;
      if (method === "DELETE") { await auth.deleteRole(actor, m[1], info); return send(res, 200, { ok: true }), true; }
    }
    if (p === "/api/admin/settings") {
      if (method === "GET") return send(res, 200, await auth.getSettings(actor)), true;
      if (method === "PUT") return send(res, 200, await auth.updateSettings(actor, await jsonBody(req, 2000), info)), true;
    }
    if (p === "/api/admin/audit" && method === "GET") return send(res, 200, await auth.listAudit(actor, Number(url.searchParams.get("limit")) || 200)), true;
    return send(res, 404, { error: "introuvable" }), true;
  } catch (error) {
    // Erreurs de saisie ou de droits (AuthError, ou corps illisible/trop gros signalé par jsonBody) : réponse claire ; le reste remonte en erreur interne.
    if (error && Number.isInteger(error.status) && error.status >= 400 && error.status < 500) return send(res, error.status, { error: error.message, code: error.code || "invalid" }), true;
    throw error;
  }
}

module.exports = { COOKIE, parseCookies, sessionCookie, clearCookie, requiredPermission, allowed, loginPage, authRoutes };
