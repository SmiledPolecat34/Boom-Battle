  /* ---------- Tableau de suivi (colonnes À faire / En cours / Terminé) et journaux du projet ----------
     Ce fichier est inséré dans le script de la page (même portée que core.js : esc, $, backend, whenText, fmtBytes…). */
  /* Icônes : un seul style (trait 1,6, bouts arrondis, couleur du texte), partagé par tous les écrans. */
  var ICON = {
    up: '<path d="m6 15 6-6 6 6"/>', down: '<path d="m6 9 6 6 6-6"/>', left: '<path d="m15 6-6 6 6 6"/>', right: '<path d="m9 6 6 6-6 6"/>', close: '<path d="m6 6 12 12M18 6 6 18"/>',
    plus: '<path d="M12 5v14M5 12h14"/>', bomb: '<circle cx="10" cy="14" r="6"/><path d="M14 9l3-3M17 3.5l.6 1.9 1.9.6-1.9.6-.6 1.9-.6-1.9-1.9-.6 1.9-.6z"/>',
    flag: '<path d="M5 21V4M5 5h12l-2 4 2 4H5"/>', map: '<path d="m3 6 6-2 6 2 6-2v14l-6 2-6-2-6 2zM9 4v14M15 6v14"/>',
    palette: '<path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-1 1.5-2.2-.5-1.3.3-2.3 1.7-2.3H17a4 4 0 0 0 4-4C21 6.5 17 3 12 3z"/><circle cx="8" cy="11" r="1"/><circle cx="12" cy="7.5" r="1"/><circle cx="16" cy="11" r="1"/>',
    star: '<path d="m12 3 2.7 5.6 6.1.9-4.4 4.3 1 6.1L12 17l-5.4 2.9 1-6.1L3.2 9.5l6.1-.9z"/>', smile: '<circle cx="12" cy="12" r="9"/><path d="M8 14c1 1.5 2.3 2 4 2s3-.5 4-2M9 9.5v.5M15 9.5v.5"/>',
    bubble: '<path d="M4 5h16v11H9l-5 4z"/>', sliders: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
    check: '<path d="m8 12 3 3 5-6"/><rect x="3" y="3" width="18" height="18"/>', image: '<rect x="3" y="3" width="18" height="18"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m3 17 6-6 4 4 3-3 5 5"/>',
    type: '<path d="M5 6V4h14v2M12 4v16M9 20h6"/>', gauge: '<path d="M4 17a8 8 0 1 1 16 0"/><path d="m12 17 4-5"/>', pack: '<path d="m3 8 9-5 9 5v8l-9 5-9-5zM3 8l9 5 9-5M12 13v8"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>', bars: '<path d="M5 20V10M12 20V4M19 20v-7"/>', edit: '<path d="M4 20h4L19 9l-4-4L4 16z"/>'
  };
  function ico(name, size) {
    var s = size || 20;
    return '<svg class="ico" viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICON[name] || ICON.edit) + "</svg>";
  }
  var GAME_ICON = { cosmetiques: "bomb", quetes: "flag", cartes: "map", themes: "palette", bonus: "star", emotes: "smile", chat: "bubble", reglages: "sliders" };
  var TYPE_ICON = { quest: "flag", bomb: "bomb", effect: "star", chat: "bubble", emote: "smile", note: "edit" };
  var JOURNAL_ICON = { playtests: "check", balance: "sliders", feedback: "bubble", images: "image", texts: "type", seeds: "map", decisions: "flag", perf: "gauge", releases: "pack", activity: "clock", coverage: "bars" };
  var ACTION_LABELS = {
    ticket_cree: "Ticket créé", ticket_modifie: "Ticket modifié", priorite_changee: "Priorité changée", ticket_deplace: "Ticket déplacé", ticket_reordonne: "Ticket réordonné",
    ticket_supprime: "Ticket supprimé", retour_ajoute: "Retour ajouté", retour_supprime: "Retour supprimé", entree_ajoutee: "Entrée ajoutée", entree_modifiee: "Entrée modifiée", entree_supprimee: "Entrée supprimée"
  };
  var kb = { schema: null, tickets: [], selected: null, filter: { q: "", type: "", priority: "" }, msg: "", error: "", confirm: "", dragId: null, ready: false };

  function labelFrom(list, id) { for (var i = 0; i < list.length; i++) if (list[i].id === id) return list[i].label; return id; }
  function statusLabel(id) { return labelFrom(kb.schema.board.statuses, id); }
  function historyText(h) {
    var p = kb.schema.board;
    switch (h.action) {
      case "created": return "Ticket créé dans « " + statusLabel(h.to) + " »";
      case "moved": return "Déplacé de « " + statusLabel(h.from) + " » vers « " + statusLabel(h.to) + " »";
      case "reordered": return "Réordonné (" + (h.text || "") + ")";
      case "priority": return "Priorité " + labelFrom(p.priorities, h.from) + " → " + labelFrom(p.priorities, h.to);
      case "edited": return "Modifié : " + (h.text || "");
      case "commented": return "Retour ajouté : " + (h.text || "");
      case "comment_removed": return "Retour supprimé";
      default: return h.action;
    }
  }
  function boardNote(kind, text) { kb.msg = kind === "error" ? "" : text; kb.error = kind === "error" ? text : ""; }
  function boardErr(err) { return (err && err.message) || String(err); }

  function loadBoard() {
    if (!backend.storage) { renderBoardView(); return Promise.resolve(); }
    return backend.storage.board.schema().then(function (schema) {
      if (!schema || !schema.board || !Array.isArray(schema.journal)) throw new Error("Réponse inattendue du serveur.");
      kb.schema = schema; return backend.storage.board.list();
    }).then(function (list) {
      kb.tickets = Array.isArray(list) ? list : []; kb.ready = true; kb.error = ""; renderBoardView();
    }, function (err) { kb.error = "Lecture du tableau impossible : " + boardErr(err); kb.ready = false; renderBoardView(); });
  }
  function ticketById(id) { for (var i = 0; i < kb.tickets.length; i++) if (kb.tickets[i].id === id) return kb.tickets[i]; return null; }
  function matches(t) {
    var f = kb.filter;
    if (f.type && t.type !== f.type) return false;
    if (f.priority && t.priority !== f.priority) return false;
    if (f.q) { var q = f.q.toLowerCase(); if ((t.title + " " + t.description + " " + t.module).toLowerCase().indexOf(q) < 0) return false; }
    return true;
  }
  function options(list, current, blank) {
    return (blank ? '<option value="">' + esc(blank) + "</option>" : "") + list.map(function (x) { return '<option value="' + esc(x.id) + '"' + (x.id === current ? " selected" : "") + ">" + esc(x.label) + "</option>"; }).join("");
  }

  function renderBoardView() {
    var root = $("view-tableau");
    if (!root) return;
    if (!backend.storage) { root.innerHTML = '<div class="notice">' + esc(NO_SERVER) + "</div>"; return; }
    if (!kb.ready) { root.innerHTML = kb.error ? '<div class="notice" role="alert">' + esc(kb.error) + "</div>" : '<p class="hint">Chargement du tableau…</p>'; return; }
    var p = kb.schema.board;
    var h = '<div class="row" style="justify-content:space-between;align-items:center;gap:12px"><div class="row" style="gap:8px;align-items:center;flex-wrap:wrap">';
    h += '<input type="search" id="kb-q" placeholder="Rechercher un ticket" aria-label="Rechercher un ticket" value="' + esc(kb.filter.q) + '" style="max-width:240px">';
    h += '<select id="kb-ftype" aria-label="Filtrer par type">' + options(p.types, kb.filter.type, "Tous les types") + "</select>";
    h += '<select id="kb-fprio" aria-label="Filtrer par priorité">' + options(p.priorities, kb.filter.priority, "Toutes les priorités") + "</select></div>";
    h += '<button class="btn" type="button" data-newticket="1">' + ico("plus", 18) + 'Nouveau ticket</button></div>';
    if (kb.error) h += '<div class="notice" role="alert">' + esc(kb.error) + "</div>";
    if (kb.msg) h += '<div class="notice" role="status">' + esc(kb.msg) + "</div>";
    h += '<div class="kanban" id="kb-cols">';
    p.statuses.forEach(function (s, ci) {
      var list = kb.tickets.filter(function (t) { return t.status === s.id; }), shown = list.filter(matches);
      h += '<section class="kcol" aria-label="' + esc(s.label) + '"><h3>' + esc(s.label) + ' <span class="tag">' + (shown.length === list.length ? list.length : shown.length + "/" + list.length) + '</span></h3><div class="kdrop" data-col="' + esc(s.id) + '">';
      shown.forEach(function (t) {
        h += '<article class="kcard prio-' + esc(t.priority) + (kb.selected === t.id ? " selected" : "") + '" draggable="true" data-ticket="' + esc(t.id) + '">';
        h += '<div class="row" style="gap:6px;flex-wrap:wrap"><span class="tag prio-tag-' + esc(t.priority) + '">' + esc(t.priority) + " · " + esc(labelFrom(p.priorities, t.priority)) + '</span><span class="tag">' + esc(labelFrom(p.types, t.type)) + "</span></div>";
        h += '<button class="ktitle" type="button" data-open="' + esc(t.id) + '">' + esc(t.title) + "</button>";
        if (t.module) h += '<div class="hint mono">' + esc(t.module) + "</div>";
        h += '<div class="row" style="justify-content:space-between;align-items:center"><span class="hint">' + (t.comments.length ? t.comments.length + " retour" + (t.comments.length > 1 ? "s" : "") : "Aucun retour") + '</span><span class="kmove">';
        h += '<button class="copy" type="button" data-mv="' + esc(t.id) + '|up" aria-label="Monter « ' + esc(t.title) + ' »">' + ico("up") + '</button><button class="copy" type="button" data-mv="' + esc(t.id) + '|down" aria-label="Descendre « ' + esc(t.title) + ' »">' + ico("down") + '</button>';
        if (ci > 0) h += '<button class="copy" type="button" data-mv="' + esc(t.id) + '|left" aria-label="Déplacer « ' + esc(t.title) + ' » vers « ' + esc(p.statuses[ci - 1].label) + ' »">' + ico("left") + '</button>';
        if (ci < p.statuses.length - 1) h += '<button class="copy" type="button" data-mv="' + esc(t.id) + '|right" aria-label="Déplacer « ' + esc(t.title) + ' » vers « ' + esc(p.statuses[ci + 1].label) + ' »">' + ico("right") + '</button>';
        h += "</span></div></article>";
      });
      if (!shown.length) h += '<p class="hint">' + (list.length ? "Aucun ticket ne correspond au filtre." : "Aucun ticket.") + "</p>";
      h += "</div></section>";
    });
    h += "</div>";
    root.innerHTML = h.replace('<div class="kanban"', '<div id="kb-detail">' + (kb.selected ? detailHtml() : "") + '</div><div class="kanban"');
    if (kb.focusDetail) { kb.focusDetail = false; var d = $("kb-detail"); if (d && d.scrollIntoView) d.scrollIntoView({ block: "start" }); }
  }

  function detailHtml() {
    var p = kb.schema.board, isNew = kb.selected === "new", t = isNew ? { title: "", description: "", priority: "P2", type: "tache", module: "", status: "todo", comments: [], history: [] } : ticketById(kb.selected);
    if (!t) return "";
    var h = '<form class="card stack" id="kb-form" style="gap:12px"><div class="row" style="justify-content:space-between;align-items:center"><h3>' + (isNew ? "Nouveau ticket" : "Ticket") + '</h3><button class="copy" type="button" data-close="1">Fermer</button></div>';
    h += '<div class="field"><label for="kb-title">Titre</label><input id="kb-title" type="text" maxlength="120" value="' + esc(t.title) + '"></div>';
    h += '<div class="field"><label for="kb-desc">Description</label><textarea id="kb-desc" rows="4" maxlength="4000">' + esc(t.description) + "</textarea></div>";
    h += '<div class="row" style="gap:12px;flex-wrap:wrap"><div class="field"><label for="kb-prio">Priorité</label><select id="kb-prio">' + options(p.priorities, t.priority) + '</select></div>';
    h += '<div class="field"><label for="kb-type">Type</label><select id="kb-type">' + options(p.types, t.type) + '</select></div>';
    h += '<div class="field"><label for="kb-status">Colonne</label><select id="kb-status">' + options(p.statuses, t.status) + '</select></div>';
    h += '<div class="field"><label for="kb-module">Module concerné</label><input id="kb-module" type="text" maxlength="60" placeholder="ex. RoundService" value="' + esc(t.module) + '"></div></div>';
    h += '<div class="row" style="gap:10px;align-items:center"><button class="btn" id="kb-save" type="submit">' + (isNew ? "Créer le ticket" : "Enregistrer") + "</button>";
    if (!isNew) h += '<button class="copy" type="button" data-delticket="' + esc(t.id) + '">' + (kb.confirm === t.id ? "Confirmer ?" : "Supprimer le ticket") + "</button>";
    h += '<span class="hint" id="kb-formmsg" role="status" aria-live="polite"></span></div></form>';
    if (!isNew) {
      h += '<div class="card stack" style="gap:10px"><h3>Retours <span class="tag">' + t.comments.length + "</span></h3>";
      t.comments.forEach(function (c) { h += '<div class="kcomment"><div class="row" style="justify-content:space-between;gap:8px"><span class="hint">' + esc(whenText(c.at)) + '</span><button class="hdel" type="button" data-delcomment="' + esc(c.id) + '" aria-label="Supprimer ce retour">' + ico("close", 18) + '</button></div><div style="white-space:pre-wrap">' + esc(c.text) + "</div></div>"; });
      if (!t.comments.length) h += '<p class="hint">Aucun retour pour l\'instant.</p>';
      h += '<div class="composer"><textarea id="kb-ctext" rows="2" maxlength="2000" placeholder="Ajouter un retour (test, remarque, blocage…)" aria-label="Nouveau retour"></textarea><button class="btn" id="kb-cadd" type="button">Ajouter</button></div><span class="hint" id="kb-cmsg" role="status" aria-live="polite"></span></div>';
      h += '<div class="card stack" style="gap:8px"><h3>Historique du ticket</h3><ol class="khistory">';
      t.history.slice().reverse().forEach(function (e) { h += "<li><span class=\"hint\">" + esc(whenText(e.at)) + "</span> " + esc(historyText(e)) + "</li>"; });
      h += "</ol></div>";
    }
    return h;
  }

  function mutate(promise, okMsg) {
    return promise.then(function () { boardNote("ok", okMsg || ""); return backend.storage.board.list(); }).then(function (list) {
      kb.tickets = Array.isArray(list) ? list : kb.tickets; renderBoardView(); if (journalState.coll === "activity") loadJournal();
    }, function (err) { boardNote("error", "Action refusée : " + boardErr(err)); renderBoardView(); });
  }
  function dropIndex(zone, y) {
    var cards = zone.querySelectorAll ? zone.querySelectorAll(".kcard") : [], idx = 0;
    for (var i = 0; i < cards.length; i++) {
      var r = cards[i].getBoundingClientRect ? cards[i].getBoundingClientRect() : null;
      if (r && typeof y === "number" && y > r.top + r.height / 2) idx = i + 1;
    }
    return idx;
  }
  function moveBy(id, dir) {
    var t = ticketById(id); if (!t) return;
    var order = kb.schema.board.statuses.map(function (s) { return s.id; }), i = order.indexOf(t.status);
    var col = kb.tickets.filter(function (x) { return x.status === t.status; }), pos = col.indexOf(t);
    if (dir === "left" && i > 0) return mutate(backend.storage.board.move(id, { status: order[i - 1] }), "Ticket déplacé vers « " + statusLabel(order[i - 1]) + " ».");
    if (dir === "right" && i < order.length - 1) return mutate(backend.storage.board.move(id, { status: order[i + 1] }), "Ticket déplacé vers « " + statusLabel(order[i + 1]) + " ».");
    if (dir === "up" && pos > 0) return mutate(backend.storage.board.move(id, { status: t.status, index: pos - 1 }));
    if (dir === "down" && pos < col.length - 1) return mutate(backend.storage.board.move(id, { status: t.status, index: pos + 1 }));
  }
  function saveTicket() {
    var raw = { title: $("kb-title").value.trim(), description: $("kb-desc").value, priority: $("kb-prio").value, type: $("kb-type").value, module: $("kb-module").value.trim() };
    var status = $("kb-status").value, msg = $("kb-formmsg");
    if (raw.title.length < 3) { msg.textContent = "Le titre doit faire au moins 3 caractères."; return; }
    var p;
    if (kb.selected === "new") {
      raw.status = status;
      p = backend.storage.board.create(raw).then(function (t) { kb.selected = t.id; });
    } else {
      var id = kb.selected, cur = ticketById(id);
      p = backend.storage.board.update(id, raw).then(function () { return cur && cur.status !== status ? backend.storage.board.move(id, { status: status }) : null; });
    }
    $("kb-save").disabled = true;
    mutate(p, "Ticket enregistré.");
  }
  function bindBoard() {
    var root = $("view-tableau");
    root.addEventListener("click", function (e) {
      var t = e.target, el;
      if (t.closest("[data-newticket]")) { kb.selected = "new"; kb.focusDetail = true; kb.msg = ""; renderBoardView(); return; }
      if (t.closest("[data-close]")) { kb.selected = null; kb.confirm = ""; renderBoardView(); return; }
      if ((el = t.closest("[data-open]"))) { kb.selected = el.getAttribute("data-open"); kb.focusDetail = true; kb.msg = ""; kb.error = ""; kb.confirm = ""; renderBoardView(); return; }
      if ((el = t.closest("[data-mv]"))) { var parts = el.getAttribute("data-mv").split("|"); moveBy(parts[0], parts[1]); return; }
      if ((el = t.closest("[data-delticket]"))) {
        var id = el.getAttribute("data-delticket");
        if (kb.confirm !== id) { kb.confirm = id; renderBoardView(); setTimeout(function () { if (kb.confirm === id) { kb.confirm = ""; renderBoardView(); } }, 3000); return; }
        kb.confirm = ""; kb.selected = null; mutate(backend.storage.board.remove(id), "Ticket supprimé."); return;
      }
      if ((el = t.closest("[data-delcomment]"))) { mutate(backend.storage.board.uncomment(kb.selected, el.getAttribute("data-delcomment")), "Retour supprimé."); return; }
      if (t.closest("#kb-cadd")) {
        var text = $("kb-ctext").value;
        if (!text.trim()) { $("kb-cmsg").textContent = "Écris ton retour avant de l'ajouter."; return; }
        mutate(backend.storage.board.comment(kb.selected, text), "Retour ajouté.");
      }
    });
    root.addEventListener("submit", function (e) { if (e.preventDefault) e.preventDefault(); saveTicket(); });
    root.addEventListener("input", function (e) { var t = e.target; if (t && t.id === "kb-q") { kb.filter.q = t.value; renderBoardView(); var q = $("kb-q"); if (q && q.focus) q.focus(); } });
    root.addEventListener("change", function (e) {
      var t = e.target; if (!t) return;
      if (t.id === "kb-ftype") { kb.filter.type = t.value; renderBoardView(); }
      if (t.id === "kb-fprio") { kb.filter.priority = t.value; renderBoardView(); }
    });
    /* Glisser-déposer : la colonne et la position d'arrivée sont envoyées au serveur, qui les valide et renumérote. */
    root.addEventListener("dragstart", function (e) { var c = e.target && e.target.closest && e.target.closest("[data-ticket]"); if (c) { kb.dragId = c.getAttribute("data-ticket"); if (e.dataTransfer) { e.dataTransfer.effectAllowed = "move"; try { e.dataTransfer.setData("text/plain", kb.dragId); } catch (x) { /* navigateurs stricts */ } } } });
    root.addEventListener("dragover", function (e) { if (kb.dragId && e.target.closest && e.target.closest("[data-col]")) e.preventDefault(); });
    root.addEventListener("drop", function (e) {
      var zone = e.target.closest && e.target.closest("[data-col]");
      if (!zone || !kb.dragId) return;
      e.preventDefault();
      var id = kb.dragId; kb.dragId = null;
      mutate(backend.storage.board.move(id, { status: zone.getAttribute("data-col"), index: dropIndex(zone, e.clientY) }));
    });
    root.addEventListener("dragend", function () { kb.dragId = null; });
  }

  /* ---------- Journaux du projet (schéma fourni par le serveur) + activité + couverture des tests ---------- */
  var journalState = { coll: "playtests", items: {}, editing: null, msg: "", error: "", confirm: "", activity: [], runs: [], formMsg: "", customDrafts: {} };
  function jschema(id) { var l = kb.schema ? kb.schema.journal : []; for (var i = 0; i < l.length; i++) if (l[i].id === id) return l[i]; return null; }
  function todayIso() { var d = new Date(); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
  function loadJournal() {
    if (!backend.storage) { renderJournalView(); return Promise.resolve(); }
    var c = journalState.coll, job;
    if (c === "activity") job = backend.storage.activity(300).then(function (l) { journalState.activity = Array.isArray(l) ? l : []; });
    else if (c === "coverage") job = backend.storage.runs().then(function (r) { journalState.runs = r && Array.isArray(r.runs) ? r.runs : []; });
    else job = backend.storage.journal.list(c).then(function (l) { journalState.items[c] = Array.isArray(l) ? l : []; });
    return job.then(function () { journalState.error = ""; renderJournalView(); }, function (err) { journalState.error = "Lecture impossible : " + boardErr(err); renderJournalView(); });
  }
  function cell(fd, v) {
    if (v === undefined || v === "") return "";
    if (fd.type === "bool") return v ? "Oui" : "Non";
    if (fd.type === "enum") return esc(labelFrom(fd.values, v));
    return esc(v);
  }
  function entryFormHtml(schema, cur) {
    var h = '<form class="card stack" id="jr-form" style="gap:16px" novalidate><h3>' + (cur ? "Modifier l'entrée" : "Nouvelle entrée") + '</h3><p class="hint">Choisis une proposition adaptée au projet, ou « Autre… » pour saisir ta propre valeur. Les propositions ne remplacent pas les mesures et observations de tes tests.</p><div class="journal-fields">';
    schema.fields.forEach(function (fd) {
      var id = "j-" + fd.key, v = cur ? cur[fd.key] : (fd.type === "date" && !fd.optional ? todayIso() : undefined), lab = esc(fd.label) + (fd.optional && fd.type !== "bool" ? " (facultatif)" : "");
      if (fd.type === "bool" && v === undefined) v = false;
      var choices = journalChoices(schema, fd, v), value = v === undefined ? "" : String(v);
      var hasChoice = choices.some(function (c) { return c.id === value; }), custom = value !== "" && !hasChoice;
      h += '<div class="field' + (fd.type === "long" ? ' journal-wide' : '') + '"><label for="j-choice-' + esc(fd.key) + '">' + lab + '</label><select id="j-choice-' + esc(fd.key) + '" data-jchoice="' + esc(fd.key) + '" aria-controls="j-custom-' + esc(fd.key) + '"><option value=""' + (!value ? ' selected' : '') + '>' + (fd.optional ? 'Non renseigné' : 'Choisir…') + '</option>';
      h += choices.map(function (c) { return '<option value="' + esc(c.id) + '"' + (value === c.id ? ' selected' : '') + '>' + esc(c.label) + '</option>'; }).join("");
      h += '<option value="__custom__"' + (custom ? ' selected' : '') + '>Autre… (écrire une valeur)</option></select><div id="j-custom-' + esc(fd.key) + '" class="journal-custom"' + (custom ? '' : ' hidden') + '><label class="hint" for="' + (fd.type === "bool" ? 'j-free-' + fd.key : id) + '">Préciser : ' + esc(fd.label) + '</label>';
      if (fd.type === "bool") h += '<input id="j-free-' + esc(fd.key) + '" type="text" placeholder="Oui ou non" value=""><input id="' + id + '" style="display:none" type="checkbox"' + (v ? ' checked' : '') + '>';
      else if (fd.type === "long") h += '<textarea id="' + id + '" rows="3" maxlength="' + fd.max + '">' + esc(v || "") + "</textarea>";
      else if (fd.type === "int") h += '<input id="' + id + '" type="number" min="' + fd.min + '" max="' + fd.max + '" step="1" value="' + esc(v === undefined ? "" : v) + '">';
      else if (fd.type === "date") h += '<input id="' + id + '" type="date" value="' + esc(v || "") + '">';
      else h += '<input id="' + id + '" type="text" maxlength="' + (fd.max || 120) + '" value="' + esc(v || "") + '">';
      h += "</div></div>";
    });
    return h + '</div><div class="row" style="gap:10px;align-items:center"><button class="btn" id="jr-save" type="submit">Enregistrer</button><button class="btn ghost" type="button" data-jcancel="1">Annuler</button><span class="hint" id="jr-msg" role="status" aria-live="polite">' + esc(journalState.formMsg) + "</span></div></form>";
  }
  function renderJournalView() {
    var root = $("view-journal");
    if (!root) return;
    if (!backend.storage) { root.innerHTML = '<div class="notice">' + esc(NO_SERVER) + "</div>"; return; }
    if (!kb.schema) { root.innerHTML = kb.error ? '<div class="notice" role="alert">' + esc(kb.error) + "</div>" : '<p class="hint">Chargement…</p>'; return; }
    var c = journalState.coll, h = '<div class="pills" role="group" aria-label="Rubriques">';
    kb.schema.journal.forEach(function (s) { h += '<button class="pill" type="button" data-jcoll="' + esc(s.id) + '" aria-pressed="' + (s.id === c) + '">' + ico(JOURNAL_ICON[s.id] || "edit", 18) + esc(s.label) + "</button>"; });
    h += '<button class="pill" type="button" data-jcoll="activity" aria-pressed="' + (c === "activity") + '">' + ico("clock", 18) + 'Activité</button><button class="pill" type="button" data-jcoll="coverage" aria-pressed="' + (c === "coverage") + '">' + ico("bars", 18) + 'Couverture des tests</button></div>';
    if (journalState.error) h += '<div class="notice" role="alert">' + esc(journalState.error) + "</div>";
    if (journalState.msg) h += '<div class="notice" role="status">' + esc(journalState.msg) + "</div>";
    if (c === "activity") {
      h += '<div class="card stack" style="gap:8px"><h3>Historique de tout ce qui a été fait <span class="tag">' + journalState.activity.length + "</span></h3><p class=\"muted\">Tickets créés, déplacés, commentés ou supprimés, et entrées de journal. Écrit par le serveur : on ne peut pas le modifier à la main.</p><ol class=\"khistory\">";
      journalState.activity.forEach(function (e) { h += "<li><span class=\"hint\">" + esc(whenText(e.at)) + "</span> <b>" + esc(ACTION_LABELS[e.action] || e.action) + "</b> — " + esc(e.title) + (e.detail ? ' <span class="hint">(' + esc(e.detail) + ")</span>" : "") + "</li>"; });
      if (!journalState.activity.length) h += '<li class="hint">Aucune activité pour l\'instant.</li>';
      root.innerHTML = h + "</ol></div>"; return;
    }
    if (c === "coverage") {
      var runs = journalState.runs.slice().sort(function (a, b) { return b.startedAt - a.startedAt; });
      h += '<div class="card stack" style="gap:8px"><h3>Couverture des tests au fil du temps</h3><p class="muted">Nombre de tests réussis à chaque exécution complète ; la différence avec l\'exécution précédente montre la progression.</p><div class="tablewrap"><table><thead><tr><th>Date</th><th>Réussis</th><th>Évolution</th><th>Échecs</th><th>Suites</th><th>Origine</th></tr></thead><tbody>';
      var full = runs.filter(function (r) { return !r.filter; });
      runs.forEach(function (r) {
        var i = full.indexOf(r), prev = i >= 0 ? full[i + 1] : null, d = prev ? r.passed - prev.passed : null;
        h += "<tr><td>" + esc(whenText(r.startedAt)) + '</td><td class="num">' + r.passed + '</td><td class="num">' + (d === null ? "—" : (d > 0 ? "+" : "") + d) + '</td><td class="num">' + r.failed + '</td><td class="num">' + r.suites + "</td><td>" + esc(r.filter ? "Partielle (" + r.filter + ")" : r.trigger === "site" ? "Site" : "Démarrage") + "</td></tr>";
      });
      if (!runs.length) h += '<tr><td colspan="6" class="hint">Aucune exécution enregistrée.</td></tr>';
      root.innerHTML = h + "</tbody></table></div></div>"; return;
    }
    var schema = jschema(c) || kb.schema.journal[0], items = journalState.items[schema.id] || [];
    h += '<div class="jhead"><div class="stack" style="gap:6px"><h2>' + esc(schema.label) + ' <span class="tag">' + items.length + '</span></h2><p class="muted">' + esc(schema.description) + '</p></div><button class="btn" type="button" data-jnew="1">' + ico("plus", 18) + 'Ajouter</button></div>';
    var formHtml = journalState.editing ? entryFormHtml(schema, journalState.editing === "new" ? null : items.filter(function (e) { return e.id === journalState.editing; })[0]) : "";
    h += '<div class="' + (formHtml ? "jsplit" : "") + '">';
    h += '<div class="card tablewrap"><table><thead><tr>' + schema.fields.map(function (fd) { return "<th>" + esc(fd.label) + "</th>"; }).join("") + "<th></th></tr></thead><tbody>";
    items.forEach(function (e) {
      h += "<tr>" + schema.fields.map(function (fd) { return "<td>" + cell(fd, e[fd.key]) + "</td>"; }).join("") + '<td><button class="copy" type="button" data-jedit="' + esc(e.id) + '">Modifier</button> <button class="copy" type="button" data-jdel="' + esc(e.id) + '">' + (journalState.confirm === e.id ? "Confirmer ?" : "Supprimer") + "</button></td></tr>";
    });
    if (!items.length) h += '<tr><td colspan="' + (schema.fields.length + 1) + '" class="hint">Aucune entrée pour l\'instant.</td></tr>';
    root.innerHTML = h + "</tbody></table></div>" + formHtml + "</div>";
  }
  function readEntryForm(schema) {
    var raw = {};
    schema.fields.forEach(function (fd) {
      var el = $("j-" + fd.key);
      if (fd.type === "bool") {
        if ($("j-choice-" + fd.key).value === "__custom__") {
          var free = $("j-free-" + fd.key).value.trim().toLowerCase();
          raw[fd.key] = /^(oui|true|1)$/.test(free) ? true : /^(non|false|0)$/.test(free) ? false : free;
        } else raw[fd.key] = !!el.checked;
        return;
      }
      var v = el.value;
      if (fd.type === "int") { if (String(v).trim() !== "") raw[fd.key] = Number(v); return; }
      v = String(v).trim();
      if (v !== "") raw[fd.key] = v;
    });
    return raw;
  }
  function saveEntry() {
    var schema = jschema(journalState.coll), msg = $("jr-msg"), id = journalState.editing === "new" ? undefined : journalState.editing;
    $("jr-save").disabled = true; msg.textContent = "Enregistrement…";
    backend.storage.journal.save(schema.id, readEntryForm(schema), id).then(function () {
      journalState.editing = null; journalState.formMsg = ""; journalState.msg = "Entrée enregistrée."; return loadJournal();
    }, function (err) { journalState.formMsg = "Refusé : " + boardErr(err); msg.textContent = journalState.formMsg; $("jr-save").disabled = false; });
  }
  function bindJournal() {
    var root = $("view-journal");
    root.addEventListener("change", function (e) {
      var key = e.target.getAttribute("data-jchoice"); if (!key) return;
      var schema = jschema(journalState.coll), fd = schema.fields.filter(function (f) { return f.key === key; })[0];
      if (!fd) return;
      var custom = e.target.value === "__custom__", input = $("j-" + key), wrapper = $("j-custom-" + key);
      wrapper.hidden = !custom;
      if (custom) {
        var free = $(fd.type === "bool" ? "j-free-" + key : "j-" + key);
        if (journalState.customDrafts[key] !== undefined) free.value = journalState.customDrafts[key];
        free.focus();
      }
      else if (fd.type === "bool") input.checked = e.target.value === "true";
      else input.value = e.target.value;
    });
    root.addEventListener("input", function (e) {
      var id = e.target.id || "";
      if (id.indexOf("j-choice-") === 0) return;
      var key = id.indexOf("j-free-") === 0 ? id.slice(7) : id.indexOf("j-") === 0 ? id.slice(2) : "";
      var choice = key && $("j-choice-" + key);
      if (choice && choice.value === "__custom__") journalState.customDrafts[key] = e.target.value;
    });
    root.addEventListener("click", function (e) {
      var t = e.target, el;
      if ((el = t.closest("[data-jcoll]"))) { journalState.coll = el.getAttribute("data-jcoll"); journalState.editing = null; journalState.msg = ""; journalState.formMsg = ""; loadJournal(); return; }
      if (t.closest("[data-jnew]")) { journalState.editing = "new"; journalState.customDrafts = {}; journalState.msg = ""; journalState.formMsg = ""; renderJournalView(); return; }
      if (t.closest("[data-jcancel]")) { journalState.editing = null; journalState.formMsg = ""; renderJournalView(); return; }
      if ((el = t.closest("[data-jedit]"))) { journalState.editing = el.getAttribute("data-jedit"); journalState.customDrafts = {}; journalState.msg = ""; journalState.formMsg = ""; renderJournalView(); return; }
      if ((el = t.closest("[data-jdel]"))) {
        var id = el.getAttribute("data-jdel");
        if (journalState.confirm !== id) { journalState.confirm = id; renderJournalView(); setTimeout(function () { if (journalState.confirm === id) { journalState.confirm = ""; renderJournalView(); } }, 3000); return; }
        journalState.confirm = "";
        backend.storage.journal.remove(journalState.coll, id).then(function () { journalState.msg = "Entrée supprimée."; return loadJournal(); }, function (err) { journalState.error = "Suppression impossible : " + boardErr(err); renderJournalView(); });
      }
    });
    root.addEventListener("submit", function (e) { if (e.preventDefault) e.preventDefault(); saveEntry(); });
  }
  function startBoard() {
    bindBoard(); bindJournal();
    loadBoard().then(function () { return loadJournal(); });
  }
