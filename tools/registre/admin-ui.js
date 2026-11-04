  /* ---------- Comptes : « Mon compte » et « Administration » (utilisateurs, rôles, sécurité, journal de sécurité) ----------
     Même portée que core.js. Les droits affichés ici ne servent qu'au confort : le serveur refuse de toute façon ce qui n'est pas permis. */
  var ME = D.me || null;
  function can(perm) { return !ME || ME.permissions.indexOf(perm) >= 0; }
  function canAny(list) { return list.some(can); }
  var JOURNAL_VIEW_PERMS = ["journal.activity.view", "journal.coverage.view"].concat((function () { var out = []; (D.permissionCatalog || []).forEach(function (c) { c.permissions.forEach(function (p) { if (/^journal\.[a-z]+\.view$/.test(p.id)) out.push(p.id); }); }); return out; })());
  var VIEW_PERMS = {
    tableau: ["tickets.view"], journal: JOURNAL_VIEW_PERMS, tests: ["tests.view"], donnees: ["game.view"], assets: ["assets.view"], sons: ["sounds.view"],
    contribuer: ["contributions.view", "contributions.create"], assistant: ["assistant.use"], stockage: ["storage.view"],
    admin: ["users.view", "roles.view", "audit.view", "security.settings"]
  };
  function viewAllowed(view) { return !VIEW_PERMS[view] || canAny(VIEW_PERMS[view]); }

  var AUDIT_LABELS = {
    connexion: "Connexion", connexion_refusee: "Connexion refusée", deconnexion: "Déconnexion", mdp_change: "Mot de passe changé", changement_mdp_refuse: "Changement de mot de passe refusé",
    profil_modifie: "Profil modifié", compte_cree: "Compte créé", compte_modifie: "Compte modifié", compte_desactive: "Compte désactivé", compte_reactive: "Compte réactivé", compte_supprime: "Compte supprimé",
    mdp_reinitialise: "Mot de passe réinitialisé", sessions_fermees: "Connexions fermées", role_cree: "Rôle créé", role_modifie: "Rôle modifié", role_supprime: "Rôle supprimé", securite_modifiee: "Sécurité modifiée", admin_cree: "Administrateur créé"
  };
  var acct = { msg: "", err: "", pwMsg: "", pwErr: "" };
  var adm = { tab: "", users: [], roles: [], catalog: null, settings: null, audit: [], editUser: null, userForm: null, confirm: "", msg: "", err: "", role: null, permFilter: "", auditFilter: "", loaded: false, sessionsFor: null, sessions: [] };

  function when(ts) { return ts ? whenText(ts) : "Jamais"; }
  function authErr(e) { return (e && e.message) || String(e); }
  function permLabel(id) { var out = id; (D.permissionCatalog || []).forEach(function (c) { c.permissions.forEach(function (p) { if (p.id === id) out = p.label; }); }); return out; }

  /* ----- Mon compte ----- */
  function renderAccount() {
    var root = $("view-compte");
    if (!root) return;
    if (!ME) { root.innerHTML = '<div class="notice">Les comptes ne sont pas activés sur ce serveur.</div>'; return; }
    var h = '<div class="split" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(min(380px,100%),1fr));gap:24px;align-items:start">';
    h += '<form class="card stack" id="acct-profile" style="gap:16px" novalidate><h2>Profil</h2><dl class="kv" style="grid-template-columns:130px 1fr"><dt>Nom d\'utilisateur</dt><dd class="mono">' + esc(ME.username) + '</dd><dt>Rôle</dt><dd>' + esc(ME.roleName) + '</dd><dt>Dernière connexion</dt><dd>' + esc(when(ME.lastLoginAt)) + "</dd></dl>";
    h += '<div class="field"><label for="acct-name">Nom affiché</label><input id="acct-name" type="text" maxlength="40" value="' + esc(ME.displayName) + '" autocomplete="name"></div>';
    h += '<div class="row" style="gap:12px;align-items:center"><button class="btn" id="acct-save" type="submit">Enregistrer le nom</button><span class="hint" id="acct-msg" role="status" aria-live="polite">' + esc(acct.err || acct.msg) + "</span></div></form>";
    h += '<form class="card stack" id="acct-password" style="gap:16px" novalidate><h2>Mot de passe</h2><p class="muted">8 caractères au moins, avec une lettre et un chiffre. Les autres connexions de ton compte seront fermées.</p>';
    h += '<div class="field"><label for="pw-current">Mot de passe actuel</label><input id="pw-current" type="password" autocomplete="current-password" maxlength="128"></div>';
    h += '<div class="field"><label for="pw-next">Nouveau mot de passe</label><input id="pw-next" type="password" autocomplete="new-password" maxlength="128"></div>';
    h += '<div class="field"><label for="pw-again">Confirmer le nouveau mot de passe</label><input id="pw-again" type="password" autocomplete="new-password" maxlength="128"></div>';
    h += '<div class="row" style="gap:12px;align-items:center"><button class="btn" id="pw-save" type="submit">Changer le mot de passe</button><span class="hint" id="pw-msg" role="status" aria-live="polite">' + esc(acct.pwErr || acct.pwMsg) + "</span></div></form></div>";
    h += '<section class="card stack" style="gap:12px" aria-labelledby="rights-t"><h2 id="rights-t">Mes droits <span class="tag">' + ME.permissions.length + "</span></h2><p class=\"muted\">Ce que ton rôle « " + esc(ME.roleName) + " » t'autorise à faire. Pour en obtenir d'autres, demande à un administrateur.</p>";
    (D.permissionCatalog || []).forEach(function (c) {
      var mine = c.permissions.filter(function (p) { return can(p.id); });
      if (!mine.length) return;
      h += '<details class="suite"><summary><span class="name">' + esc(c.label) + '</span><span class="tag">' + mine.length + " / " + c.permissions.length + '</span></summary><ul style="margin:0;padding-left:20px;display:flex;flex-direction:column;gap:4px">' + mine.map(function (p) { return "<li>" + esc(p.label) + "</li>"; }).join("") + "</ul></details>";
    });
    h += '</section><div><button class="btn ghost" id="acct-logout" type="button">Se déconnecter</button></div>';
    root.innerHTML = h;
  }
  function bindAccount() {
    var root = $("view-compte");
    if (!root || !ME) return;
    root.addEventListener("submit", function (e) {
      if (e.preventDefault) e.preventDefault();
      var id = e.target && e.target.id;
      if (id === "acct-profile") {
        var name = $("acct-name").value;
        acct.err = ""; acct.msg = "";
        if (name.trim().length < 2 || name.trim().length > 40) { acct.err = "Le nom doit faire de 2 à 40 caractères."; renderAccount(); return; }
        backend.storage.auth.profile(name).then(function (u) { ME.displayName = u.displayName; acct.msg = "Nom enregistré."; renderAccount(); renderSessionChip(); }, function (err) { acct.err = authErr(err); renderAccount(); });
      } else if (id === "acct-password") {
        var cur = $("pw-current").value, nxt = $("pw-next").value, again = $("pw-again").value;
        acct.pwErr = ""; acct.pwMsg = "";
        if (!cur || !nxt) { acct.pwErr = "Renseigne l'ancien et le nouveau mot de passe."; renderAccount(); return; }
        if (nxt !== again) { acct.pwErr = "Les deux nouveaux mots de passe ne sont pas identiques."; renderAccount(); return; }
        backend.storage.auth.password(cur, nxt).then(function () { acct.pwMsg = "Mot de passe changé."; renderAccount(); }, function (err) { acct.pwErr = authErr(err); renderAccount(); });
      }
    });
    root.addEventListener("click", function (e) { if (e.target.closest && e.target.closest("#acct-logout")) doLogout(); });
  }
  function doLogout() {
    if (!backend.storage || !backend.storage.auth) return;
    backend.storage.auth.logout().then(function () { location.reload(); }, function () { location.reload(); });
  }
  function renderSessionChip() {
    var el = $("session-chip");
    if (el && ME) el.textContent = ME.displayName + " · " + ME.roleName;
  }

  /* ----- Administration ----- */
  function admTabs() {
    var t = [];
    if (canAny(["users.view"])) t.push(["users", "Utilisateurs", "user"]);
    if (canAny(["roles.view"])) t.push(["roles", "Rôles et droits", "key"]);
    if (can("security.settings")) t.push(["security", "Sécurité", "shield"]);
    if (can("audit.view")) t.push(["audit", "Journal de sécurité", "clock"]);
    return t;
  }
  function loadAdmin() {
    if (!backend.storage || !backend.storage.auth || !ME) { renderAdmin(); return Promise.resolve(); }
    var tabs = admTabs();
    if (!tabs.length) { renderAdmin(); return Promise.resolve(); }
    if (!adm.tab || !tabs.some(function (t) { return t[0] === adm.tab; })) adm.tab = tabs[0][0];
    var A = backend.storage.auth, jobs = [];
    if (adm.tab === "users") jobs.push(A.users.list().then(function (l) { adm.users = Array.isArray(l) ? l : []; }), (can("roles.view") || can("users.create") || can("users.edit")) ? A.roles.list().then(function (l) { adm.roles = Array.isArray(l) ? l : []; }) : Promise.resolve());
    if (adm.tab === "roles") jobs.push(A.roles.list().then(function (l) { adm.roles = Array.isArray(l) ? l : []; }), A.roles.catalog().then(function (c) { adm.catalog = Array.isArray(c) ? c : []; }));
    if (adm.tab === "security") jobs.push(A.settings.get().then(function (s) { adm.settings = s; }));
    if (adm.tab === "audit") jobs.push(A.audit(300).then(function (l) { adm.audit = Array.isArray(l) ? l : []; }));
    return Promise.all(jobs).then(function () { adm.err = ""; adm.loaded = true; renderAdmin(); }, function (err) { adm.err = "Lecture impossible : " + authErr(err); adm.loaded = true; renderAdmin(); });
  }
  function statusTags(u) {
    var t = [];
    t.push(u.disabled ? '<span class="tag bad">Désactivé</span>' : '<span class="tag good">Actif</span>');
    if (u.locked) t.push('<span class="tag warn">Verrouillé</span>');
    if (u.mustChangePassword) t.push('<span class="tag warn">Mot de passe à changer</span>');
    return t.join(" ");
  }
  function roleOptions(current) {
    return adm.roles.map(function (r) { return '<option value="' + esc(r.id) + '"' + (r.id === current ? " selected" : "") + ">" + esc(r.name) + "</option>"; }).join("");
  }
  function userFormHtml() {
    var f = adm.userForm, isNew = f.id === "new", u = isNew ? { username: "", displayName: "", roleId: "", mustChangePassword: true } : adm.users.filter(function (x) { return x.id === f.id; })[0];
    if (!u) return "";
    var h = '<form class="card stack" id="user-form" style="gap:16px" novalidate><div class="row" style="justify-content:space-between;align-items:center"><h3>' + (isNew ? "Nouveau compte" : "Modifier « " + esc(u.username) + " »") + '</h3><button class="copy" type="button" data-ucancel="1">Fermer</button></div><div class="journal-fields">';
    if (isNew) h += '<div class="field"><label for="u-username">Nom d\'utilisateur</label><input id="u-username" type="text" maxlength="32" autocomplete="off" autocapitalize="none" spellcheck="false" placeholder="ex. camille"><span class="hint">3 à 32 caractères : lettres minuscules, chiffres, point, tiret.</span></div>';
    h += '<div class="field"><label for="u-name">Nom affiché</label><input id="u-name" type="text" maxlength="40" value="' + esc(u.displayName) + '"></div>';
    var canRole = isNew ? can("users.create") : can("users.edit");
    h += '<div class="field"><label for="u-role">Rôle</label><select id="u-role"' + (canRole ? "" : " disabled") + ">" + (isNew ? '<option value="">Choisir…</option>' : "") + roleOptions(u.roleId) + "</select></div>";
    if (isNew) h += '<div class="field"><label for="u-password">Mot de passe de départ (facultatif)</label><input id="u-password" type="text" maxlength="128" autocomplete="off" placeholder="Vide : mot de passe de départ des réglages de sécurité"><span class="hint">La personne devra le changer à sa première connexion.</span></div>';
    h += '</div><div class="row" style="gap:10px;align-items:center"><button class="btn" id="user-save" type="submit">' + (isNew ? "Créer le compte" : "Enregistrer") + '</button><span class="hint" id="user-msg" role="status" aria-live="polite">' + esc(adm.userForm.msg || "") + "</span></div></form>";
    return h;
  }
  function renderUsers() {
    var q = (adm.userFilter || "").toLowerCase();
    var h = '<div class="jhead"><div class="stack" style="gap:6px"><h2>Utilisateurs <span class="tag">' + adm.users.length + '</span></h2><p class="muted">Les comptes qui peuvent se connecter, leur rôle et leur état.</p></div>';
    if (can("users.create")) h += '<button class="btn" type="button" data-unew="1">' + ico("plus", 18) + "Nouveau compte</button>";
    h += "</div>";
    h += '<div class="field" style="max-width:320px"><label for="u-search">Rechercher un compte</label><input id="u-search" type="search" placeholder="Nom ou nom d\'utilisateur" value="' + esc(adm.userFilter || "") + '"></div>';
    if (adm.userForm) h += userFormHtml();
    h += '<div class="card tablewrap"><table><thead><tr><th>Nom d\'utilisateur</th><th>Nom affiché</th><th>Rôle</th><th>État</th><th>Dernière connexion</th><th>Connexions</th><th></th></tr></thead><tbody>';
    adm.users.filter(function (u) { return !q || (u.username + " " + u.displayName).toLowerCase().indexOf(q) >= 0; }).forEach(function (u) {
      var self = ME && u.id === ME.id;
      h += '<tr><td class="mono">' + esc(u.username) + (self ? ' <span class="tag">Toi</span>' : "") + "</td><td>" + esc(u.displayName) + "</td><td>" + esc(u.roleName) + "</td><td>" + statusTags(u) + "</td><td>" + esc(when(u.lastLoginAt)) + '</td><td class="num">' + (u.sessionCount === undefined ? "" : u.sessionCount) + '</td><td><div class="row" style="gap:6px">';
      if (can("users.edit")) h += '<button class="copy" type="button" data-uedit="' + esc(u.id) + '">Modifier</button>';
      if (can("users.reset_password") && !self) h += '<button class="copy" type="button" data-ureset="' + esc(u.id) + '">' + (adm.confirm === "reset:" + u.id ? "Confirmer ?" : "Réinitialiser le mot de passe") + "</button>";
      if (can("users.disable") && !self) h += '<button class="copy" type="button" data-udisable="' + esc(u.id) + '" data-to="' + (u.disabled ? "false" : "true") + '">' + (u.disabled ? "Réactiver" : "Désactiver") + "</button>";
      if (can("users.sessions") && u.sessionCount) h += '<button class="copy" type="button" data-urevoke="' + esc(u.id) + '">' + (adm.confirm === "revoke:" + u.id ? "Confirmer ?" : "Fermer les connexions") + "</button>";
      if (can("users.delete") && !self) h += '<button class="copy" type="button" data-udelete="' + esc(u.id) + '">' + (adm.confirm === "delete:" + u.id ? "Confirmer ?" : "Supprimer") + "</button>";
      h += "</div></td></tr>";
    });
    if (!adm.users.length) h += '<tr><td colspan="7" class="hint">Aucun compte.</td></tr>';
    return h + "</tbody></table></div>";
  }

  function permissionMatrixHtml() {
    var r = adm.role, q = adm.permFilter.toLowerCase(), h = "";
    (adm.catalog || []).forEach(function (c) {
      var perms = c.permissions.filter(function (p) { return !q || (p.label + " " + p.description + " " + p.id).toLowerCase().indexOf(q) >= 0; });
      if (!perms.length) return;
      var grant = c.permissions.filter(function (p) { return !p.adminOnly; }), on = grant.filter(function (p) { return r.permissions[p.id]; }).length;
      var all = grant.length > 0 && on === grant.length;
      h += '<fieldset class="permcat" data-cat="' + esc(c.id) + '"><legend><label class="permall"><input type="checkbox" data-catall="' + esc(c.id) + '"' + (all ? " checked" : "") + (r.readOnly || !grant.length ? " disabled" : "") + '> <b>' + esc(c.label) + '</b> <span class="tag">' + (r.readOnly ? c.permissions.length : on) + " / " + c.permissions.length + "</span></label></legend>";
      h += '<p class="hint" style="margin:0 0 8px">' + esc(c.description) + '</p><div class="permgrid">';
      perms.forEach(function (p) {
        var checked = r.readOnly || r.permissions[p.id], locked = r.readOnly || p.adminOnly;
        h += '<label class="perm' + (p.adminOnly ? " perm-admin" : "") + '"><input type="checkbox" data-perm="' + esc(p.id) + '"' + (checked ? " checked" : "") + (locked ? " disabled" : "") + '><span><b>' + esc(p.label) + "</b>" + (p.adminOnly ? ' <span class="tag warn">Réservé aux admins</span>' : "") + '<span class="hint" style="display:block">' + esc(p.description) + "</span></span></label>";
      });
      h += "</div></fieldset>";
    });
    return h || '<p class="hint">Aucune permission ne correspond à la recherche.</p>';
  }
  function countSelected() { var n = 0; Object.keys(adm.role.permissions).forEach(function (k) { if (adm.role.permissions[k]) n++; }); return n; }
  function roleEditorHtml() {
    var r = adm.role, isNew = r.id === "new";
    var h = '<form class="card stack" id="role-form" style="gap:16px" novalidate><div class="row" style="justify-content:space-between;align-items:center"><h3>' + (isNew ? "Nouveau rôle" : r.readOnly ? "Rôle intégré : " + esc(r.name) : "Modifier le rôle") + '</h3><span class="tag" id="role-count">' + (r.readOnly ? "Tous les droits" : countSelected() + " droit(s)") + "</span></div>";
    if (r.readOnly) h += '<p class="muted">Le rôle administrateur possède tous les droits, y compris ceux réservés aux administrateurs. Il ne se modifie pas et ne se supprime pas.</p>';
    h += '<div class="journal-fields"><div class="field"><label for="r-name">Nom du rôle</label><input id="r-name" type="text" maxlength="40" value="' + esc(r.name) + '"' + (r.readOnly ? " disabled" : "") + '></div><div class="field"><label for="r-desc">Description (facultatif)</label><input id="r-desc" type="text" maxlength="200" value="' + esc(r.description) + '"' + (r.readOnly ? " disabled" : "") + "></div></div>";
    if (!r.readOnly) {
      h += '<div class="row" style="gap:8px;flex-wrap:wrap;align-items:flex-end"><button class="copy" type="button" data-selall="1">Tout sélectionner</button><button class="copy" type="button" data-selnone="1">Tout désélectionner</button>';
      h += '<div class="field" style="min-width:220px"><label for="r-copy">Copier les droits d\'un rôle</label><select id="r-copy"><option value="">Choisir un rôle…</option>' + adm.roles.filter(function (x) { return x.id !== r.id; }).map(function (x) { return '<option value="' + esc(x.id) + '">' + esc(x.name) + "</option>"; }).join("") + "</select></div></div>";
    }
    h += '<div class="field" style="max-width:360px"><label for="r-q">Chercher un droit</label><input id="r-q" type="search" placeholder="ex. supprimer, sons, tickets" value="' + esc(adm.permFilter) + '"></div>';
    h += '<div id="perm-matrix" class="stack" style="gap:16px">' + permissionMatrixHtml() + "</div>";
    h += '<div class="row" style="gap:10px;align-items:center">';
    if (!r.readOnly) h += '<button class="btn" id="role-save" type="submit">' + (isNew ? "Créer le rôle" : "Enregistrer") + "</button>";
    if (!isNew && !r.readOnly && can("roles.manage")) h += '<button class="copy" type="button" data-roledel="' + esc(r.id) + '">' + (adm.confirm === "role:" + r.id ? "Confirmer ?" : "Supprimer le rôle") + "</button>";
    h += '<button class="btn ghost" type="button" data-rolecancel="1">Fermer</button><span class="hint" id="role-msg" role="status" aria-live="polite">' + esc(r.msg || "") + "</span></div></form>";
    return h;
  }
  function renderRoles() {
    var h = '<div class="jhead"><div class="stack" style="gap:6px"><h2>Rôles et droits <span class="tag">' + adm.roles.length + '</span></h2><p class="muted">Un rôle est un ensemble de droits précis, rangés par catégorie. Chaque compte a un rôle ; une modification s\'applique tout de suite.</p></div>';
    if (can("roles.manage")) h += '<button class="btn" type="button" data-rolenew="1">' + ico("plus", 18) + "Nouveau rôle</button>";
    h += '</div><div class="card tablewrap"><table><thead><tr><th>Rôle</th><th>Description</th><th class="num">Droits</th><th class="num">Comptes</th><th></th></tr></thead><tbody>';
    adm.roles.forEach(function (r) {
      h += "<tr><td><b>" + esc(r.name) + "</b>" + (r.builtin ? ' <span class="tag">Intégré</span>' : "") + "</td><td>" + esc(r.description) + '</td><td class="num">' + (r.builtin ? "Tous" : r.permissions.length) + '</td><td class="num">' + r.userCount + '</td><td><button class="copy" type="button" data-roleopen="' + esc(r.id) + '">' + (r.builtin || !can("roles.manage") ? "Voir" : "Modifier") + "</button></td></tr>";
    });
    h += "</tbody></table></div>";
    if (adm.role) h += roleEditorHtml();
    return h;
  }
  function renderSecurity() {
    var s = adm.settings || {};
    var h = '<div class="stack" style="gap:6px"><h2>Sécurité</h2><p class="muted">Règles de connexion et mot de passe de départ des nouveaux comptes.</p></div>';
    h += '<form class="card stack" id="sec-form" style="gap:16px" novalidate><div class="journal-fields">';
    h += '<div class="field"><label for="s-default">Mot de passe de départ</label><input id="s-default" type="text" maxlength="64" autocomplete="off" value="' + esc(s.defaultPassword || "") + '"><span class="hint">Donné aux nouveaux comptes et lors d\'une réinitialisation ; à changer dès la première connexion.</span></div>';
    h += '<div class="field"><label for="s-hours">Durée d\'une session sans activité (heures)</label><input id="s-hours" type="number" min="1" max="72" value="' + esc(s.sessionHours) + '"></div>';
    h += '<div class="field"><label for="s-days">Durée maximale d\'une session (jours)</label><input id="s-days" type="number" min="1" max="30" value="' + esc(s.sessionMaxDays) + '"></div>';
    h += '<div class="field"><label for="s-fails">Échecs avant verrouillage</label><input id="s-fails" type="number" min="3" max="20" value="' + esc(s.maxFailedLogins) + '"></div>';
    h += '<div class="field"><label for="s-lock">Durée du verrouillage (minutes)</label><input id="s-lock" type="number" min="1" max="1440" value="' + esc(s.lockMinutes) + '"></div></div>';
    h += '<div class="row" style="gap:10px;align-items:center"><button class="btn" id="sec-save" type="submit">Enregistrer</button><span class="hint" id="sec-msg" role="status" aria-live="polite">' + esc(adm.secMsg || "") + "</span></div></form>";
    return h;
  }
  function renderAudit() {
    var q = adm.auditFilter.toLowerCase();
    var rows = adm.audit.filter(function (e) { return !q || ((AUDIT_LABELS[e.action] || e.action) + " " + (e.actor || "") + " " + (e.target || "") + " " + (e.detail || "")).toLowerCase().indexOf(q) >= 0; });
    var h = '<div class="stack" style="gap:6px"><h2>Journal de sécurité <span class="tag">' + rows.length + '</span></h2><p class="muted">Connexions, échecs, changements de comptes, de rôles et de réglages. Écrit par le serveur : on ne peut pas le modifier.</p></div>';
    h += '<div class="field" style="max-width:320px"><label for="a-search">Filtrer</label><input id="a-search" type="search" placeholder="Action, compte, détail" value="' + esc(adm.auditFilter) + '"></div>';
    h += '<div class="card tablewrap"><table><thead><tr><th>Date</th><th>Compte</th><th>Action</th><th>Cible</th><th>Détail</th><th>Adresse</th></tr></thead><tbody>';
    rows.forEach(function (e) { h += "<tr><td>" + esc(whenText(e.at)) + '</td><td class="mono">' + esc(e.actor || "—") + "</td><td>" + esc(AUDIT_LABELS[e.action] || e.action) + '</td><td class="mono">' + esc(e.target || "") + "</td><td>" + esc(e.detail || "") + '</td><td class="mono">' + esc(e.ip || "") + "</td></tr>"; });
    if (!rows.length) h += '<tr><td colspan="6" class="hint">Aucun événement.</td></tr>';
    return h + "</tbody></table></div>";
  }
  function renderAdmin() {
    var root = $("view-admin");
    if (!root) return;
    if (!ME) { root.innerHTML = '<div class="notice">Les comptes ne sont pas activés sur ce serveur.</div>'; return; }
    var tabs = admTabs();
    if (!tabs.length) { root.innerHTML = '<div class="notice">Tu n\'as accès à aucune partie de l\'administration.</div>'; return; }
    if (!adm.loaded) { root.innerHTML = adm.err ? '<div class="notice" role="alert">' + esc(adm.err) + "</div>" : '<p class="hint">Chargement…</p>'; return; }
    var h = '<div class="pills" role="group" aria-label="Administration">' + tabs.map(function (t) { return '<button class="pill" type="button" data-atab="' + t[0] + '" aria-pressed="' + (t[0] === adm.tab) + '">' + ico(t[2], 18) + esc(t[1]) + "</button>"; }).join("") + "</div>";
    if (adm.err) h += '<div class="notice" role="alert">' + esc(adm.err) + "</div>";
    if (adm.msg) h += '<div class="notice" role="status">' + esc(adm.msg) + "</div>";
    h += adm.tab === "users" ? renderUsers() : adm.tab === "roles" ? renderRoles() : adm.tab === "security" ? renderSecurity() : renderAudit();
    root.innerHTML = h;
  }
  function admDo(promise, okMsg, after) {
    return promise.then(function (r) { adm.msg = okMsg || ""; adm.err = ""; adm.confirm = ""; if (after) after(r); return loadAdmin(); }, function (err) { adm.err = authErr(err); adm.msg = ""; adm.confirm = ""; renderAdmin(); });
  }
  function confirmed(key) {
    if (adm.confirm === key) { adm.confirm = ""; return true; }
    adm.confirm = key; renderAdmin();
    setTimeout(function () { if (adm.confirm === key) { adm.confirm = ""; renderAdmin(); } }, 3000);
    return false;
  }
  function openRole(id) {
    var r = adm.roles.filter(function (x) { return x.id === id; })[0];
    if (id === "new") adm.role = { id: "new", name: "", description: "", permissions: {}, readOnly: false, msg: "" };
    else if (r) { var map = {}; r.permissions.forEach(function (p) { map[p] = true; }); adm.role = { id: r.id, name: r.name, description: r.description, permissions: map, readOnly: !!r.builtin || !can("roles.manage"), msg: "" }; }
    adm.permFilter = "";
    renderAdmin();
  }
  function refreshMatrix(focusId) {
    var box = $("perm-matrix");
    if (box) box.innerHTML = permissionMatrixHtml();
    var cnt = $("role-count");
    if (cnt) cnt.textContent = countSelected() + " droit(s)";
    if (focusId) { var el = document.querySelector && document.querySelector('[data-perm="' + focusId + '"]'); if (el && el.focus) el.focus(); }
  }
  function saveRole() {
    var r = adm.role, msg = $("role-msg");
    var body = { name: $("r-name").value, description: $("r-desc").value, permissions: Object.keys(r.permissions).filter(function (k) { return r.permissions[k]; }) };
    if (body.name.trim().length < 2) { r.msg = "Le nom du rôle doit faire au moins 2 caractères."; msg.textContent = r.msg; return; }
    var A = backend.storage.auth.roles;
    $("role-save").disabled = true;
    admDo(r.id === "new" ? A.create(body) : A.update(r.id, body), "Rôle enregistré.", function (saved) { adm.role = null; void saved; });
  }
  function readUserForm() {
    var f = adm.userForm, raw = { displayName: $("u-name").value.trim(), roleId: $("u-role").value };
    if (f.id === "new") { raw.username = $("u-username").value.trim(); var pw = $("u-password").value; if (pw) raw.password = pw; }
    return raw;
  }
  function saveUser() {
    var f = adm.userForm, raw = readUserForm(), msg = $("user-msg"), A = backend.storage.auth.users;
    function fail(t) { f.msg = t; msg.textContent = t; }
    if (f.id === "new") {
      if (!raw.username) return fail("Renseigne un nom d'utilisateur.");
      if (!raw.roleId) return fail("Choisis un rôle.");
      if (!raw.displayName) delete raw.displayName;
      $("user-save").disabled = true;
      admDo(A.create(raw), "Compte « " + raw.username.toLowerCase() + " » créé. Il devra changer son mot de passe à la première connexion.", function () { adm.userForm = null; });
    } else {
      var patch = {};
      var cur = adm.users.filter(function (x) { return x.id === f.id; })[0];
      if (raw.displayName && cur && raw.displayName !== cur.displayName) patch.displayName = raw.displayName;
      if (raw.roleId && cur && raw.roleId !== cur.roleId) patch.roleId = raw.roleId;
      if (!Object.keys(patch).length) { adm.userForm = null; renderAdmin(); return; }
      $("user-save").disabled = true;
      admDo(A.update(f.id, patch), "Compte modifié.", function () { adm.userForm = null; });
    }
  }
  function bindAdmin() {
    var root = $("view-admin");
    if (!root || !ME) return;
    root.addEventListener("click", function (e) {
      var t = e.target, el, A = backend.storage.auth;
      if ((el = t.closest("[data-atab]"))) { adm.tab = el.getAttribute("data-atab"); adm.msg = ""; adm.userForm = null; adm.role = null; adm.loaded = false; renderAdmin(); loadAdmin(); return; }
      if (t.closest("[data-unew]")) { adm.userForm = { id: "new", msg: "" }; adm.msg = ""; renderAdmin(); return; }
      if (t.closest("[data-ucancel]")) { adm.userForm = null; renderAdmin(); return; }
      if ((el = t.closest("[data-uedit]"))) { adm.userForm = { id: el.getAttribute("data-uedit"), msg: "" }; adm.msg = ""; renderAdmin(); return; }
      if ((el = t.closest("[data-udisable]"))) { var to = el.getAttribute("data-to") === "true"; admDo(A.users.update(el.getAttribute("data-udisable"), { disabled: to }), to ? "Compte désactivé." : "Compte réactivé."); return; }
      if ((el = t.closest("[data-ureset]"))) { var rid = el.getAttribute("data-ureset"); if (confirmed("reset:" + rid)) admDo(A.users.reset(rid), "Mot de passe réinitialisé : la personne devra en choisir un nouveau à la prochaine connexion."); return; }
      if ((el = t.closest("[data-urevoke]"))) { var vid = el.getAttribute("data-urevoke"); if (confirmed("revoke:" + vid)) admDo(A.users.revoke(vid), "Connexions fermées."); return; }
      if ((el = t.closest("[data-udelete]"))) { var did = el.getAttribute("data-udelete"); if (confirmed("delete:" + did)) admDo(A.users.remove(did), "Compte supprimé."); return; }
      if (t.closest("[data-rolenew]")) { openRole("new"); return; }
      if ((el = t.closest("[data-roleopen]"))) { openRole(el.getAttribute("data-roleopen")); return; }
      if (t.closest("[data-rolecancel]")) { adm.role = null; renderAdmin(); return; }
      if ((el = t.closest("[data-roledel]"))) { var roid = el.getAttribute("data-roledel"); if (confirmed("role:" + roid)) admDo(A.roles.remove(roid), "Rôle supprimé.", function () { adm.role = null; }); return; }
      if (t.closest("[data-selall]")) { (adm.catalog || []).forEach(function (c) { c.permissions.forEach(function (p) { if (!p.adminOnly) adm.role.permissions[p.id] = true; }); }); refreshMatrix(); return; }
      if (t.closest("[data-selnone]")) { adm.role.permissions = {}; refreshMatrix(); return; }
    });
    root.addEventListener("change", function (e) {
      var t = e.target; if (!t || !t.getAttribute) return;
      var perm = t.getAttribute("data-perm"), cat = t.getAttribute("data-catall");
      if (perm && adm.role) { adm.role.permissions[perm] = !!t.checked; refreshMatrix(perm); return; }
      if (cat && adm.role) { (adm.catalog || []).forEach(function (c) { if (c.id === cat) c.permissions.forEach(function (p) { if (!p.adminOnly) adm.role.permissions[p.id] = !!t.checked; }); }); refreshMatrix(); return; }
      if (t.id === "r-copy" && t.value && adm.role) {
        var src = adm.roles.filter(function (x) { return x.id === t.value; })[0];
        if (src) { adm.role.permissions = {}; src.permissions.forEach(function (p) { adm.role.permissions[p] = true; }); refreshMatrix(); }
      }
    });
    root.addEventListener("input", function (e) {
      var t = e.target; if (!t) return;
      if (t.id === "r-q") { adm.permFilter = t.value; refreshMatrix(); }
      else if (t.id === "u-search") { adm.userFilter = t.value; renderAdmin(); var el = $("u-search"); if (el && el.focus) el.focus(); }
      else if (t.id === "a-search") { adm.auditFilter = t.value; renderAdmin(); var el2 = $("a-search"); if (el2 && el2.focus) el2.focus(); }
    });
    root.addEventListener("submit", function (e) {
      if (e.preventDefault) e.preventDefault();
      var id = e.target && e.target.id;
      if (id === "user-form") saveUser();
      else if (id === "role-form") saveRole();
      else if (id === "sec-form") {
        var raw = { defaultPassword: $("s-default").value, sessionHours: Number($("s-hours").value), sessionMaxDays: Number($("s-days").value), maxFailedLogins: Number($("s-fails").value), lockMinutes: Number($("s-lock").value) };
        $("sec-save").disabled = true;
        backend.storage.auth.settings.put(raw).then(function (s) { adm.settings = s; adm.secMsg = "Réglages enregistrés."; adm.err = ""; renderAdmin(); }, function (err) { adm.secMsg = ""; adm.err = authErr(err); renderAdmin(); });
      }
    });
  }
  function startAccounts() {
    renderSessionChip();
    bindAccount(); bindAdmin();
    renderAccount();
    if (ME && admTabs().length) { adm.loaded = false; renderAdmin(); loadAdmin(); } else renderAdmin();
  }
