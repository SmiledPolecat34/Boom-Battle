  /* Contrat du backend, fourni par un adaptateur chargé avant ce fichier (window.__registreBackend) :
       store : { subscribe(onItems, onError), add(doc) -> Promise, remove(id) -> Promise, unavailableText }
       ai    : { ready() -> Promise<bool>, status() -> texte, reasonText() -> texte,
                 ask({ system, messages, tools, signal, onText }) -> Promise<texte>, mountSettings?(element, onChange) }
       refresh? : () -> Promise  (version locale : relance les tests et l'export des données) */
  var backend = window.__registreBackend;
  /* ---------- Contribuer : formulaire, exemples, aperçu et file d'attente (db) ---------- */
  var MATERIALS = ["SmoothPlastic", "Neon", "Ice", "Metal"];
  var QUEST_EVENTS = ["round_played", "round_won", "crates_destroyed"];
  var QUEST_EVENT_LABELS = { round_played: "Jouer une manche", round_won: "Gagner une manche", crates_destroyed: "Détruire des caisses" };

  function textCheck(min, max) {
    return function (v) { return v.length >= min && v.length <= max ? "" : "Entre " + min + " et " + max + " caractères."; };
  }
  function intCheck(min, max) {
    return function (v) { var n = Number(v); return v !== "" && Number.isInteger(n) && n >= min && n <= max ? "" : "Nombre entier entre " + min + " et " + max + "."; };
  }
  function slug(s) {
    return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 16).replace(/_+$/g, "");
  }
  function hexRgb(hex) {
    var m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || "");
    return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [136, 136, 136];
  }
  function lq(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }

  /* L'identifiant n'est jamais saisi : il est déduit du nom (ou du texte) et rendu unique automatiquement. */
  var FORMS = {
    quest: {
      label: "Quête", idFrom: "name", prefix: "", file: "src/shared/QuestConfig.luau",
      about: "Apparaît dans l'écran Quêtes. Le serveur verse la récompense une seule fois, quand l'objectif est atteint.",
      example: function () { return D.game.quests[0]; },
      examples: function () { return D.game.quests; },
      fields: [
        { k: "name", label: "Nom", check: textCheck(2, 40), doc: "Titre affiché dans la liste des quêtes. L'identifiant en est déduit." },
        { k: "description", label: "Description", check: textCheck(3, 80), wide: true, doc: "La consigne lue par le joueur (ex. « Jouer 3 manches »)." },
        { k: "event", label: "Événement", type: "select", options: QUEST_EVENTS, labels: QUEST_EVENT_LABELS, doc: "Ce que le serveur compte : manches jouées, manches gagnées ou caisses détruites." },
        { k: "goal", label: "Objectif", type: "number", check: intCheck(1, 1000), doc: "Combien de fois l'événement doit se produire pour terminer la quête." },
        { k: "reward", label: "Récompense (pièces)", type: "number", check: intCheck(1, 10000), doc: "Bomb Coins versés une seule fois, à la fin de la quête." }
      ],
      luau: function (p) { return "table.freeze({ id = " + lq(p.id) + ", name = " + lq(p.name) + ", description = " + lq(p.description) + ", event = " + lq(p.event) + ", goal = " + p.goal + ", reward = " + p.reward + " })," ; }
    },
    bomb: {
      label: "Bombe (produit)", idFrom: "name", prefix: "bomb_", file: "src/shared/CosmeticConfig.luau",
      about: "Un produit de la Boutique et de l'Inventaire. Ne change que l'apparence de la bombe : jamais sa portée ni son délai.",
      example: function () { return D.game.cosmetics.bomb[1]; },
      examples: function () { return D.game.cosmetics.bomb; },
      fields: [
        { k: "name", label: "Nom", check: textCheck(2, 24), doc: "Nom affiché sur la carte du produit. L'identifiant bomb_… en est déduit." },
        { k: "price", label: "Prix (pièces)", type: "number", check: intCheck(0, 100000), doc: "Prix en Bomb Coins ; 0 = gratuit. Le serveur revérifie le solde à chaque achat." },
        { k: "color", label: "Couleur", type: "color", doc: "Couleur de la bombe en jeu, de la pastille de la boutique et de l'aperçu." },
        { k: "material", label: "Matière", type: "select", options: MATERIALS, doc: "Aspect de la surface : plastique lisse, néon, glace ou métal." },
        { k: "description", label: "Description", check: textCheck(3, 80), wide: true, doc: "Phrase courte affichée dans le détail du produit." }
      ],
      luau: function (p) { var c = hexRgb(p.color); return "bomb(" + lq(p.id) + ", " + lq(p.name) + ", " + p.price + ", Color3.fromRGB(" + c.join(", ") + "), Enum.Material." + p.material + ", " + lq(p.description) + "),"; }
    },
    effect: {
      label: "Effet d'explosion (produit)", idFrom: "name", prefix: "effect_", file: "src/shared/CosmeticConfig.luau",
      about: "Un produit de la Boutique : la couleur des flammes quand TA bombe explose. Purement visuel.",
      example: function () { return D.game.cosmetics.effect[1]; },
      examples: function () { return D.game.cosmetics.effect; },
      fields: [
        { k: "name", label: "Nom", check: textCheck(2, 24), doc: "Nom affiché sur la carte du produit. L'identifiant effect_… en est déduit." },
        { k: "price", label: "Prix (pièces)", type: "number", check: intCheck(0, 100000), doc: "Prix en Bomb Coins ; 0 = gratuit." },
        { k: "color", label: "Couleur des flammes", type: "color", doc: "Couleur des cases touchées par l'explosion, vue par tous les joueurs." },
        { k: "description", label: "Description", check: textCheck(3, 80), wide: true, doc: "Phrase courte affichée dans le détail du produit." }
      ],
      luau: function (p) { var c = hexRgb(p.color); return "effect(" + lq(p.id) + ", " + lq(p.name) + ", " + p.price + ", Color3.fromRGB(" + c.join(", ") + "), " + lq(p.description) + "),"; }
    },
    chat: {
      label: "Phrase de chat rapide", idFrom: "text", prefix: "", file: "src/shared/QuickChatConfig.luau",
      about: "Une phrase préfaite : seul son identifiant part au serveur, qui affiche la bulle au-dessus du personnage.",
      example: function () { return D.game.quickChat.phrases[0]; },
      examples: function () { return D.game.quickChat.phrases; },
      fields: [
        { k: "text", label: "Texte affiché", hint: "30 caractères au maximum", check: textCheck(1, 30), doc: "La phrase dans la bulle et dans la liste. L'identifiant en est déduit." }
      ],
      luau: function (p) { return "table.freeze({ id = " + lq(p.id) + ", text = " + lq(p.text) + " }),"; }
    },
    emote: {
      label: "Émote", idFrom: "name", prefix: "", file: "src/shared/EmoteConfig.luau",
      about: "Une entrée de la roue des émotes, jouée par le serveur pour que tout le monde la voie.",
      example: function () { return D.game.emotes.list[0]; },
      examples: function () { return D.game.emotes.list; },
      fields: [
        { k: "name", label: "Nom affiché", check: textCheck(2, 24), doc: "Texte du bouton dans la roue. L'identifiant en est déduit." },
        { k: "animationId", label: "Identifiant d'animation Roblox", hint: "un identifiant réel, jamais inventé", check: function (v) { return /^rbxassetid:\/\/\d+$/.test(v) ? "" : "Format rbxassetid://123456."; }, doc: "L'animation à jouer ; elle doit exister vraiment sur Roblox." },
        { k: "looped", label: "Danse en boucle", type: "checkbox", doc: "Coché : la danse tourne (arrêtée après 8 s). Décoché : geste joué une fois." }
      ],
      luau: function (p) { return "table.freeze({ id = " + lq(p.id) + ", name = " + lq(p.name) + ", animationId = " + lq(p.animationId) + ", looped = " + (p.looped ? "true" : "false") + " })," ; }
    },
    note: {
      label: "Idée ou demande libre", idFrom: null, prefix: "", file: "",
      about: "Un message libre pour le développeur : rien n'est ajouté au code tel quel, il sert à décrire ce que tu veux.",
      example: function () { return { title: "Mode équipe", details: "Deux équipes de 4 joueurs, victoire quand une équipe est éliminée." }; },
      examples: function () { return []; },
      fields: [
        { k: "title", label: "Titre", check: textCheck(3, 80), wide: true, doc: "Résumé en une ligne." },
        { k: "details", label: "Détails", type: "textarea", check: textCheck(3, 1500), wide: true, doc: "Tout ce qu'il faut savoir pour l'implémenter." }
      ],
      luau: function () { return ""; }
    }
  };
  var formState = { type: "quest", values: {}, note: "" };
  var contribDb = { ready: false, unavailable: false, items: [], error: "", api: null };

  function existingIds(type) {
    var base = [];
    if (type === "quest") base = D.game.quests.map(function (x) { return x.id; });
    else if (type === "bomb") base = D.game.cosmetics.bomb.map(function (x) { return x.id; });
    else if (type === "effect") base = D.game.cosmetics.effect.map(function (x) { return x.id; });
    else if (type === "chat") base = D.game.quickChat.phrases.map(function (x) { return x.id; });
    else if (type === "emote") base = D.game.emotes.list.map(function (x) { return x.id; });
    contribDb.items.forEach(function (c) { if (c.type === type && c.status !== "rejected" && c.fields && c.fields.id) base.push(c.fields.id); });
    return base;
  }
  function autoId(type, values) {
    var spec = FORMS[type];
    if (!spec.idFrom) return null;
    var core = slug(values[spec.idFrom]);
    if (!core) return "";
    var base = spec.prefix + core, taken = existingIds(type), id = base, n = 2;
    while (taken.indexOf(id) >= 0) { id = base + "_" + n; n++; }
    return id;
  }
  function payloadOf(type, values) {
    var out = {};
    var id = autoId(type, values);
    if (id) out.id = id;
    FORMS[type].fields.forEach(function (f) {
      var v = values[f.k];
      if (v === undefined || v === "") v = f.type === "color" ? "#888888" : f.type === "checkbox" ? false : f.type === "select" ? f.options[0] : v;
      if (v !== undefined && v !== "") out[f.k] = v;
    });
    return out;
  }

  function fieldHtml(f) {
    var v = formState.values[f.k];
    var id = "f-" + f.k;
    var control;
    if (f.type === "select") {
      control = '<select id="' + id + '">' + f.options.map(function (o) { return '<option value="' + esc(o) + '"' + (String(v) === o ? " selected" : "") + ">" + esc(f.labels ? f.labels[o] + " (" + o + ")" : o) + "</option>"; }).join("") + "</select>";
    } else if (f.type === "checkbox") {
      control = '<input type="checkbox" id="' + id + '"' + (v ? " checked" : "") + ">";
    } else if (f.type === "textarea") {
      control = '<textarea id="' + id + '" rows="5">' + esc(v || "") + "</textarea>";
    } else {
      control = '<input id="' + id + '" type="' + (f.type || "text") + '" value="' + esc(v === undefined ? (f.type === "color" ? "#c9a227" : "") : v) + '"' + (f.type === "number" ? ' inputmode="numeric"' : "") + ">";
    }
    return '<div class="field' + (f.wide ? " wide" : "") + '"><label for="' + id + '">' + esc(f.label) + "</label>" + control + (f.hint ? '<span class="hint">' + esc(f.hint) + "</span>" : "") + '<span class="err" id="e-' + f.k + '" aria-live="polite"></span></div>';
  }

  function readForm() {
    var out = {};
    FORMS[formState.type].fields.forEach(function (f) {
      var node = $("f-" + f.k);
      if (!node) return;
      var v = f.type === "checkbox" ? node.checked : String(node.value || "").trim();
      if (f.type === "number" && v !== "") v = Number(v);
      out[f.k] = v;
    });
    return out;
  }

  function validateForm(values) {
    var ok = true, spec = FORMS[formState.type];
    spec.fields.forEach(function (f) {
      var raw = values[f.k];
      var message = f.check ? f.check(f.type === "number" ? String(raw === undefined ? "" : raw) : String(raw === undefined ? "" : raw)) : "";
      var node = $("e-" + f.k);
      if (node) node.textContent = message;
      if (message) ok = false;
    });
    if (spec.idFrom && ok && !autoId(formState.type, values)) {
      var n = $("e-" + spec.idFrom);
      if (n) n.textContent = "Utilise au moins une lettre ou un chiffre.";
      ok = false;
    }
    return ok;
  }

  function summary(c) {
    var f = c.fields || {};
    switch (c.type) {
      case "quest": return (f.name || f.id) + " : " + f.description + " (objectif " + f.goal + ", +" + f.reward + " pièces)";
      case "bomb": case "effect": return (f.name || f.id) + " : " + (f.price === 0 ? "gratuit" : fmt(f.price) + " pièces") + ", " + f.color;
      case "chat": return "« " + f.text + " »";
      case "emote": return (f.name || f.id) + " (" + f.animationId + ")";
      default: return f.title || "Idée";
    }
  }

  var STATUS_LABEL = { pending: "En attente", applied: "Appliquée", rejected: "Refusée" };

  function renderContribList() {
    var box = $("contrib-list");
    if (!box) return;
    var msg = "";
    if (contribDb.unavailable) msg = '<div class="notice">' + esc(backend.store.unavailableText) + "</div>";
    else if (!contribDb.ready) msg = '<div class="notice" role="status">Chargement des contributions…</div>';
    else if (contribDb.error) msg = '<div class="notice" role="alert">' + esc(contribDb.error) + "</div>";
    else if (!contribDb.items.length) msg = '<div class="notice">Aucune contribution pour l\'instant. Remplis le formulaire ou demande un brouillon à l\'assistant.</div>';
    var list = contribDb.items.map(function (c) {
      var status = c.status || "pending";
      var date = c.createdAt ? new Date(c.createdAt).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }) : "";
      return '<div class="card contrib"><header><span class="tag">' + esc((FORMS[c.type] && FORMS[c.type].label) || c.type) + '</span><span class="status-pill ' + esc(status) + '">' + esc(STATUS_LABEL[status] || status) + '</span><span class="muted" style="margin-left:auto">' + esc(date) + "</span></header><div><b>" + esc(summary(c)) + "</b>" + (c.fields && c.fields.id ? ' <span class="mono muted">' + esc(c.fields.id) + "</span>" : "") + "</div>" +
        (c.note ? '<div class="muted">Note : ' + esc(c.note) + "</div>" : "") +
        (c.result ? '<div class="notice">Retour : ' + esc(c.result) + "</div>" : "") +
        (status === "pending" ? '<div><button class="btn ghost" data-del="' + esc(c._id) + '">Retirer</button></div>' : "") + "</div>";
    }).join("");
    box.innerHTML = msg + '<div class="stack" style="gap:10px">' + list + "</div>";
  }

  function updatePreview() {
    if (!$("pv-json")) return;
    var type = formState.type, spec = FORMS[type], values = readForm();
    var payload = payloadOf(type, values);
    var idNode = $("auto-id");
    if (idNode) idNode.textContent = payload.id || (spec.idFrom ? "(sera créé dès que le nom est rempli)" : "aucun");
    $("pv-json").textContent = JSON.stringify({ type: type, fields: payload, note: ($("f-note") && $("f-note").value.trim()) || "", status: "pending" }, null, 2);
    var luau = "";
    if (spec.file && payload.id) {
      try { luau = spec.luau(payload); } catch (e) { luau = ""; }
    }
    $("pv-luau").textContent = spec.file ? ("-- " + spec.file + "\n" + (luau || "-- remplis le formulaire pour voir la ligne ajoutée")) : "-- Aucune ligne de code : une idée libre sert de cahier des charges.";
  }

  function asideHtml() {
    var type = formState.type, spec = FORMS[type];
    var h = '<aside class="stack" style="gap:12px" aria-label="Exemples et aide">';
    h += '<div class="card stack" style="gap:6px"><h3>À quoi ça sert</h3><p class="muted" style="margin:0">' + esc(spec.about) + "</p></div>";
    h += '<div class="card stack" style="gap:8px"><h3>Exemple existant (JSON)</h3><pre class="json" id="ex-json">' + esc(JSON.stringify(spec.example(), null, 2)) + "</pre><h3 style=\"margin-top:6px\">Ce que fait chaque champ</h3>";
    h += spec.idFrom ? '<div class="fdoc"><b>id</b><span>Créé automatiquement à partir du nom, unique : tu n\'as rien à saisir.</span></div>' : "";
    h += spec.fields.map(function (f) { return '<div class="fdoc"><b>' + esc(f.k) + "</b><span>" + esc(f.doc) + "</span></div>"; }).join("") + "</div>";
    h += '<div class="card stack" style="gap:8px"><h3>Ce qui sera envoyé</h3><pre class="json" id="pv-json"></pre><h3 style="margin-top:6px">Ligne ajoutée dans le code</h3><pre class="json" id="pv-luau"></pre></div>';
    var examples = spec.examples().slice(0, 6);
    if (examples.length) {
      h += '<div class="card stack" style="gap:8px"><h3>Exemples existants</h3>' + examples.map(function (x, i) {
        var label = x.name || x.text || x.id;
        var extra = x.price !== undefined ? (x.price === 0 ? "gratuit" : fmt(x.price) + " pièces") : (x.reward !== undefined ? "+" + x.reward + " pièces" : (x.animationId ? x.animationId : ""));
        var dot = x.color ? '<i class="swatch" style="background:' + esc(x.color) + '"></i>' : "";
        return '<div class="row" style="align-items:center;gap:8px">' + dot + '<div style="flex:1;min-width:140px"><b>' + esc(label) + '</b> <span class="muted">' + esc(extra) + '</span></div><button class="copy" data-model="' + i + '">Prendre comme modèle</button></div>';
      }).join("") + "</div>";
    }
    return h + "</aside>";
  }

  function renderContribuer() {
    var spec = FORMS[formState.type];
    var h = '<div class="stack" style="gap:6px"><h2>Ajouter du contenu au jeu</h2><p class="muted">Ce que tu envoies est enregistré dans la page. Il entre dans le dépôt quand tu demandes à l\'assistant de le traiter dans ta session de travail : il écrit le code et ses tests, puis te laisse valider. Rien n\'est commité sans ton accord.</p></div>';
    h += '<div class="pills" id="type-pills" role="group" aria-label="Type de contenu">' + Object.keys(FORMS).map(function (k) { return '<button class="pill" data-t="' + k + '" aria-pressed="' + (k === formState.type) + '">' + ico(TYPE_ICON[k] || "edit", 18) + esc(FORMS[k].label) + "</button>"; }).join("") + "</div>";
    h += '<div class="split"><div class="stack" style="gap:16px"><div class="card stack" style="gap:14px"><h3>' + esc(spec.label) + "</h3>";
    h += '<form id="contrib-form" class="stack" style="gap:14px" novalidate><div class="form">' + spec.fields.map(fieldHtml).join("") + "</div>";
    h += spec.idFrom ? '<div class="field wide"><label>Identifiant (automatique)</label><code class="mono" id="auto-id" style="padding:9px 12px;background:var(--soft);border-radius:10px"></code></div>' : "";
    h += '<div class="field wide"><label for="f-note">Note pour le développeur (facultatif)</label><textarea id="f-note" rows="2">' + esc(formState.note || "") + '</textarea></div><div class="row" style="align-items:center"><button class="btn" type="submit" id="send-btn">Envoyer la contribution</button><span id="send-msg" class="hint" role="status" aria-live="polite"></span></div></form></div>';
    h += '<div class="card stack" style="gap:8px"><h3>Faire traiter les contributions</h3><p class="muted" style="margin:0">Dans ta session de travail, dis :</p><pre class="json" id="how">Traite les contributions en attente du registre BOOM BATTLE : applique-les dans le dépôt avec leurs tests, sans commit.</pre><div><button class="copy" id="copy-how">Copier la phrase</button></div></div></div>';
    h += asideHtml() + "</div>";
    h += '<div class="stack" style="gap:10px"><h2>Suivi</h2><div id="contrib-list"></div></div>';
    $("view-contribuer").innerHTML = h;
    renderContribList();
    updatePreview();

    $("type-pills").addEventListener("click", function (e) {
      var b = e.target.closest(".pill"); if (!b) return;
      formState.note = $("f-note") ? $("f-note").value : "";
      formState.type = b.getAttribute("data-t"); formState.values = {};
      renderContribuer();
    });
    $("contrib-form").addEventListener("input", updatePreview);
    $("contrib-form").addEventListener("change", updatePreview);
    $("view-contribuer").querySelector("aside").addEventListener("click", function (e) {
      var b = e.target.closest("[data-model]"); if (!b) return;
      var x = spec.examples()[Number(b.getAttribute("data-model"))];
      if (!x) return;
      var copy = {};
      Object.keys(x).forEach(function (k) { if (k !== "id" && k !== "kind") copy[k] = x[k]; });
      if (copy.name) copy.name = copy.name + " 2";
      fillForm(formState.type, copy, formState.note);
    });
    $("copy-how").addEventListener("click", function (e) {
      var b = e.currentTarget, text = $("how").textContent;
      try { navigator.clipboard.writeText(text).then(function () { b.textContent = "Copié"; }, function () { b.textContent = "Sélectionne et copie"; }); } catch (err) { b.textContent = "Sélectionne et copie"; }
      setTimeout(function () { b.textContent = "Copier la phrase"; }, 1800);
    });
    $("contrib-list").addEventListener("click", function (e) {
      var b = e.target.closest("[data-del]"); if (!b || !contribDb.api) return;
      b.disabled = true;
      contribDb.api.remove(b.getAttribute("data-del")).catch(function (err) { contribDb.error = "Suppression impossible : " + (err && err.message || err); renderContribList(); });
    });
    $("contrib-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var values = readForm();
      formState.values = values; formState.note = $("f-note").value.trim();
      var msg = $("send-msg");
      if (!validateForm(values)) { msg.textContent = "Corrige les champs signalés."; return; }
      if (!contribDb.api) { msg.textContent = backend.store.unavailableText; return; }
      var payload = payloadOf(formState.type, values);
      var btn = $("send-btn"); btn.disabled = true; msg.textContent = "Envoi…";
      contribDb.api.add({ type: formState.type, fields: payload, note: formState.note, status: "pending", createdAt: Date.now() }).then(function () {
        formState.values = {}; formState.note = "";
        renderContribuer();
        $("send-msg").textContent = "Contribution enregistrée : elle apparaît dans le suivi.";
      }, function (err) { btn.disabled = false; msg.textContent = "Envoi impossible : " + (err && err.message || err); });
    });
  }

  function fillForm(type, fields, note) {
    if (!FORMS[type]) return false;
    formState.type = type; formState.values = {}; formState.note = note || "";
    FORMS[type].fields.forEach(function (f) { if (fields && fields[f.k] !== undefined) formState.values[f.k] = fields[f.k]; });
    renderContribuer();
    return true;
  }

  function startContribDb() {
    var timer = setTimeout(function () { if (!contribDb.ready) { contribDb.error = "Le stockage ne répond pas encore. Réessaie dans un instant."; renderContribList(); } }, 10000);
    contribDb.api = backend.store;
    backend.store.subscribe(function (items) {
      clearTimeout(timer);
      contribDb.ready = true; contribDb.unavailable = false; contribDb.error = "";
      contribDb.items = items;
      renderContribList();
      updatePreview();
    }, function (err) {
      clearTimeout(timer);
      contribDb.ready = true;
      if (err && err.unavailable) { contribDb.unavailable = true; contribDb.api = null; }
      else contribDb.error = "Lecture impossible : " + ((err && (err.message || err.code)) || err);
      renderContribList();
    });
  }

  /* ---------- Assistant ---------- */
  var chat = { hist: [], pending: null, busy: false, abort: null, drafts: [], draftStore: {}, convId: null };

  /* ---- Historique des conversations : stocké dans le navigateur (jamais envoyé ailleurs que vers l'assistant choisi) ---- */
  var HISTORY_KEY = "registre.chats.v1", MAX_CONVERSATIONS = 30, MAX_MESSAGES = 200;
  var history = { list: [], persistent: true };

  function validConv(c) {
    return !!c && typeof c.id === "string" && typeof c.title === "string" && typeof c.updatedAt === "number" && Array.isArray(c.messages) &&
      c.messages.every(function (m) { return !!m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string"; });
  }
  function loadHistory() {
    var raw = null, list = [];
    try { raw = window.localStorage.getItem(HISTORY_KEY); } catch (e) { history.persistent = false; }
    try { var parsed = raw ? JSON.parse(raw) : []; if (Array.isArray(parsed)) list = parsed.filter(validConv); } catch (e) { list = []; }
    history.list = list.sort(function (a, b) { return b.updatedAt - a.updatedAt; }).slice(0, MAX_CONVERSATIONS);
  }
  function saveHistory() {
    try { window.localStorage.setItem(HISTORY_KEY, JSON.stringify(history.list)); history.persistent = true; } catch (e) { history.persistent = false; }
  }
  /* Une clé collée par mégarde dans une question n'est ni envoyée à l'assistant ni conservée dans l'historique. */
  function maskSecrets(text) { return String(text).replace(/gsk_[A-Za-z0-9_-]{16,}/g, "[clé masquée]"); }
  function copyMsg(m) {
    var out = { role: m.role, content: m.content };
    if (m.drafts) { out.drafts = m.drafts; out.draftKey = m.draftKey; }
    return out;
  }
  function currentConv() {
    for (var i = 0; i < history.list.length; i++) if (history.list[i].id === chat.convId) return history.list[i];
    return null;
  }
  function titleOf(messages) {
    for (var i = 0; i < messages.length; i++) if (messages[i].role === "user") { var t = messages[i].content.replace(/\s+/g, " ").trim(); return t.length > 48 ? t.slice(0, 47) + "…" : t; }
    return "Conversation";
  }
  function whenText(ts) { return new Date(ts).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" }); }

  function persistCurrent() {
    if (!chat.hist.length) return;
    var conv = currentConv(), now = Date.now();
    if (!conv) {
      conv = { id: "c" + now.toString(36) + Math.random().toString(36).slice(2, 6), title: "", createdAt: now, updatedAt: now, messages: [] };
      chat.convId = conv.id;
      history.list.unshift(conv);
    }
    if (!conv.title) conv.title = titleOf(chat.hist);
    conv.updatedAt = now;
    conv.messages = chat.hist.slice(-MAX_MESSAGES).map(copyMsg);
    history.list.sort(function (a, b) { return b.updatedAt - a.updatedAt; });
    history.list = history.list.slice(0, MAX_CONVERSATIONS);
    saveHistory();
    pushChat(conv);
    renderHistoryList();
  }
  /* Le serveur local garde les conversations dans des fichiers ; le navigateur n'en est qu'un cache. */
  function pushChat(conv) {
    if (!backend.storage) return;
    backend.storage.chats.put(conv).then(function () {
      if (history.syncNote) { history.syncNote = ""; renderHistoryList(); }
    }, function (err) {
      history.syncNote = "Enregistrement sur le serveur impossible : " + ((err && err.message) || err);
      renderHistoryList();
    });
  }
  function syncHistory() {
    if (!backend.storage) return Promise.resolve();
    return backend.storage.chats.list().then(function (remote) {
      if (!Array.isArray(remote)) return;
      var byId = {};
      remote.filter(validConv).forEach(function (c) { byId[c.id] = c; });
      history.list.forEach(function (c) { /* conversations du navigateur absentes ou plus récentes : montées vers le serveur */
        var r = byId[c.id];
        if (!r || r.updatedAt < c.updatedAt) { byId[c.id] = c; pushChat(c); }
      });
      history.list = Object.keys(byId).map(function (k) { return byId[k]; }).sort(function (a, b) { return b.updatedAt - a.updatedAt; }).slice(0, MAX_CONVERSATIONS);
      saveHistory();
      if (!chat.convId && !chat.hist.length && !chat.busy && history.list.length) {
        chat.hist = history.list[0].messages.map(copyMsg); chat.convId = history.list[0].id; rebuildDrafts(); renderMsgs();
      }
      renderHistoryList();
    }, function () { /* serveur injoignable : le cache du navigateur suffit */ });
  }
  function rebuildDrafts() {
    chat.draftStore = {};
    chat.hist.forEach(function (m) { if (m.drafts && m.draftKey) chat.draftStore[m.draftKey] = m.drafts; });
  }
  function newConversation() {
    if (chat.abort) chat.abort.abort();
    chat.hist = []; chat.pending = null; chat.convId = null; chat.draftStore = {};
    renderMsgs(); renderHistoryList();
  }
  function openConversation(id) {
    var conv = null;
    history.list.forEach(function (c) { if (c.id === id) conv = c; });
    if (!conv || chat.busy) return;
    chat.hist = conv.messages.map(copyMsg); chat.convId = id; chat.pending = null;
    rebuildDrafts();
    renderMsgs(); renderHistoryList();
  }
  function deleteConversation(id) {
    history.list = history.list.filter(function (c) { return c.id !== id; });
    saveHistory();
    if (backend.storage) backend.storage.chats.remove(id).then(null, function () { /* déjà absente ou serveur arrêté */ });
    if (chat.convId === id) newConversation(); else renderHistoryList();
  }
  function renderHistoryList() {
    var box = $("history-list");
    if (!box) return;
    var h = history.list.map(function (c) {
      return '<div class="hitem' + (c.id === chat.convId ? " active" : "") + '"><button class="hopen" data-open="' + esc(c.id) + '" title="' + esc(c.title) + '"><span class="htitle">' + esc(c.title) + '</span><span class="hmeta">' + esc(whenText(c.updatedAt)) + " · " + c.messages.length + ' messages</span></button><button class="hdel" data-delconv="' + esc(c.id) + '" aria-label="Supprimer la conversation « ' + esc(c.title) + ' »">×</button></div>';
    }).join("");
    box.innerHTML = h || '<p class="hint">Aucune conversation enregistrée pour l\'instant.</p>';
    var note = $("history-note");
    if (note) {
      var lost = "L'historique ne peut pas être conservé dans cette vue (ni le navigateur ni le serveur local ne l'enregistrent) : il disparaît à la fermeture de la page.";
      if (!history.persistent && (history.syncNote || !backend.storage)) note.textContent = lost;
      else if (history.syncNote) note.textContent = history.syncNote;
      else if (backend.storage) note.textContent = "L'historique est enregistré dans le dossier de données du serveur local (jusqu'à " + MAX_CONVERSATIONS + " conversations affichées).";
      else note.textContent = history.persistent ? "L'historique reste dans ce navigateur (jusqu'à " + MAX_CONVERSATIONS + " conversations)." : "L'historique ne peut pas être conservé dans cette vue (stockage du navigateur indisponible) : il disparaît à la fermeture de la page.";
    }
  }
  loadHistory();
  if (history.list.length) { chat.hist = history.list[0].messages.map(copyMsg); chat.convId = history.list[0].id; rebuildDrafts(); }
  var testsSummary = D.tests.passed + " tests réussis, " + D.tests.failed + " échecs, " + D.tests.suites + " suites ; modules sans suite : " + (Object.keys(D.untested.untested || {}).join(", ") || "aucun");
  var SYSTEM = [
    "Tu es l'assistant du registre BOOM BATTLE, un jeu Roblox de combat à la bombe sur grille (2 à 8 joueurs, manches de 2 min 30, monnaie Bomb Coins).",
    "Réponds en français, de façon brève et précise. Pour tout chiffre ou nom du jeu, appelle d'abord l'outil get_game_data (sections : cosmetiques, quetes, cartes, themes, bonus, emotes, chat, reglages, tests, assets) et n'invente rien.",
    "Résumé des tests : " + testsSummary + ".",
    "Tu ne modifies jamais le dépôt. Pour proposer un ajout, appelle l'outil propose_addition : cela prépare un brouillon dans l'onglet Contribuer que l'utilisateur relit puis envoie. L'identifiant est créé automatiquement : ne le fournis pas.",
    "Contraintes à respecter dans un brouillon : texte de chat rapide de 30 caractères au plus ; prix entiers >= 0 ; événements de quête parmi round_played, round_won, crates_destroyed ; couleurs au format #rrggbb ; un identifiant d'animation d'émote doit être réel (rbxassetid://nombre), n'en invente jamais.",
    "Types de brouillon : quest (name, description, event, goal, reward), bomb (name, price, color, material parmi SmoothPlastic/Neon/Ice/Metal, description), effect (name, price, color, description), chat (text), emote (name, animationId, looped), note (title, details)."
  ].join("\n");

  var SECTIONS = {
    cosmetiques: function () { return D.game.cosmetics; },
    quetes: function () { return D.game.quests; },
    cartes: function () { return D.game.map.sizes.map(function (s) { return { id: s.id, taille: s.size, joueurs: s.minPlayers + "-" + s.maxPlayers, spawns: s.spawns.length }; }); },
    themes: function () { return D.game.map.themes.map(function (t) { return { id: t.id, nom: t.displayName, modulaire: !!t.modular, heure: t.lighting.clockTime, luminosite: t.lighting.brightness, decors: t.decorKinds }; }); },
    bonus: function () { return { bonus: D.game.powerups, tirage: D.game.settings.powerupDrops, plafonds: { bombes: D.game.settings.bomb.MaxCapacity, portee: D.game.settings.bomb.MaxBlastRange, vitesse: D.game.settings.movement.MaxSpeedPickups } }; },
    emotes: function () { return D.game.emotes; },
    chat: function () { return D.game.quickChat; },
    reglages: function () { return D.game.settings; },
    tests: function () {
      var by = {};
      D.tests.results.forEach(function (t) { var b = by[t.suite] || (by[t.suite] = { tests: 0, echecs: 0 }); b.tests++; if (!t.ok) b.echecs++; });
      return { reussis: D.tests.passed, echecs: D.tests.failed, suites: by, sansSuite: D.untested.untested };
    },
    assets: function () { return D.manifest.assets.map(function (a) { return { fichier: a.fichier, dimensions: a.dimensions, assetId: a.assetId, utilisePar: a.utilisePar }; }); }
  };

  var TOOLS = [
    {
      name: "get_game_data",
      description: "Lit une section des données réelles du jeu (JSON).",
      inputSchema: { type: "object", properties: { section: { type: "string", enum: Object.keys(SECTIONS) } }, required: ["section"] },
      execute: function (input) {
        var fn = SECTIONS[input && input.section];
        if (!fn) throw new Error("Section inconnue.");
        var text = JSON.stringify(fn());
        return text.length > 7000 ? text.slice(0, 7000) + "…(tronqué)" : text;
      }
    },
    {
      name: "propose_addition",
      description: "Prépare un brouillon de contribution dans l'onglet Contribuer (l'utilisateur le relit et l'envoie lui-même). Ne pas fournir d'identifiant : il est automatique.",
      inputSchema: {
        type: "object",
        properties: {
          type: { type: "string", enum: Object.keys(FORMS) },
          fields: { type: "object", description: "Champs du brouillon selon le type, sans id." },
          note: { type: "string", description: "Note courte pour le développeur." }
        },
        required: ["type", "fields"]
      },
      execute: function (input) {
        if (!input || !FORMS[input.type]) throw new Error("Type inconnu.");
        chat.drafts.push({ type: input.type, fields: input.fields || {}, note: input.note || "" });
        return "Brouillon « " + FORMS[input.type].label + " » préparé ; l'utilisateur peut l'ouvrir depuis la conversation.";
      }
    }
  ];

  function inline(text) {
    return esc(text).replace(/`([^`]+)`/g, "<code>$1</code>").replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>");
  }

  function renderMsgs() {
    var box = $("msgs");
    if (!box) return;
    var all = chat.hist.slice();
    if (chat.pending !== null) all.push({ role: "assistant", content: chat.pending || "Réflexion en cours…" });
    if (!all.length) {
      box.innerHTML = '<div class="msg bot">Bonjour ! Je connais les données du jeu (cosmétiques, quêtes, cartes, thèmes, bonus, émotes, chat) et l\'état des tests. Pose une question, ou demande-moi de préparer un ajout.</div>';
      return;
    }
    box.innerHTML = all.map(function (m) {
      var drafts = "";
      if (m.drafts) drafts = m.drafts.map(function (d, i) { return '<br><button class="btn ghost draft" data-draft="' + esc(m.draftKey) + ":" + i + '">Ouvrir le brouillon « ' + esc(FORMS[d.type].label) + " »</button>"; }).join("");
      return '<div class="msg ' + (m.role === "user" ? "user" : "bot") + '">' + inline(m.content) + drafts + "</div>";
    }).join("");
    box.scrollTop = box.scrollHeight;
  }

  function setStatus(text) { if ($("chat-status")) $("chat-status").textContent = text; }

  function setBusy(v) {
    chat.busy = v;
    if ($("chat-send")) $("chat-send").disabled = v;
    if ($("chat-stop")) $("chat-stop").hidden = !v;
  }

  /* L'assistant IA est fourni par l'adaptateur (backend.ai). Sa disponibilité est vérifiée à chaque envoi : un échec n'est jamais définitif. */
  function getSample() {
    return backend.ai.ready().then(function (ok) { setStatus(backend.ai.status()); return ok; }, function () { setStatus(backend.ai.status()); return false; });
  }

  /* ---- Mode local : répond depuis les données de la page quand l'assistant IA n'est pas disponible ---- */
  function norm(s) { return String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase(); }
  var COLOR_WORDS = { doree: ["Dorée", "#d4af37"], dore: ["Dorée", "#d4af37"], rouge: ["Rouge vif", "#d93a2f"], bleu: ["Bleue", "#2f6fe0"], bleue: ["Bleue", "#2f6fe0"], vert: ["Verte", "#2fae4f"], verte: ["Verte", "#2fae4f"], jaune: ["Jaune soleil", "#f2cd2e"], violet: ["Violette", "#7b4df0"], violette: ["Violette", "#7b4df0"], noir: ["Noire", "#1e1e26"], noire: ["Noire", "#1e1e26"], blanc: ["Blanche", "#f2f2f2"], blanche: ["Blanche", "#f2f2f2"], orange: ["Orange", "#f08a1c"], rose: ["Rose", "#ec6fb0"], argent: ["Argentée", "#b8c0cc"], argentee: ["Argentée", "#b8c0cc"] };
  function list(items) { return items.map(function (x) { return "• " + x; }).join("\n"); }

  function localAnswer(question) {
    var q = norm(question), G = D.game, T = D.tests, drafts = null, text;
    var wantsDraft = /\b(propose|ajoute|ajouter|cree|creer|invente|nouvelle|nouveau)\b/.test(q);
    var type = /bombe/.test(q) ? "bomb" : /effet|explosion/.test(q) ? "effect" : /quete/.test(q) ? "quest" : /phrase|chat/.test(q) ? "chat" : /emote/.test(q) ? "emote" : null;
    if (wantsDraft && type) {
      var fields = {};
      var price = /(\d+)\s*(pieces|piece|coins|bomb coins)?/.exec(q);
      Object.keys(COLOR_WORDS).forEach(function (w) { if (!fields.color && new RegExp("\\b" + w + "\\b").test(q)) { fields.color = COLOR_WORDS[w][1]; fields.name = COLOR_WORDS[w][0]; } });
      if (type === "bomb" || type === "effect") { if (price) fields.price = Number(price[1]); if (type === "bomb") fields.material = "SmoothPlastic"; if (fields.name) fields.description = (type === "bomb" ? "Une bombe " : "Une explosion ") + fields.name.toLowerCase() + "."; }
      drafts = [{ type: type, fields: fields, note: "" }];
      return { text: "Assistant IA indisponible : je prépare un brouillon de base à partir de ta phrase (" + FORMS[type].label + "). Complète-le dans l'onglet Contribuer : l'identifiant sera créé automatiquement.", drafts: drafts };
    }
    if (/\b(test|tests|echec|echecs|reussi|reussis|suite|suites)\b/.test(q)) {
      var untested = Object.keys(D.untested.untested || {});
      text = T.passed + " tests réussis, " + T.failed + " échec(s), " + T.suites + " suites.\n" + (untested.length ? "Module(s) sans suite : " + untested.join(", ") + "." : "Tous les modules ont une suite.");
    } else if (/couleur|teinte|coloris/.test(q)) {
      var colorKind = /effet|explosion|flamme/.test(q) ? "effect" : "bomb";
      var colored = G.cosmetics[colorKind];
      text = "Couleurs des " + (colorKind === "bomb" ? "bombes" : "effets d'explosion") + " (" + colored.length + ") :\n" + list(colored.map(function (c) { return c.name + " : " + c.color; }));
    } else if (/\b(bombes|effets)\b/.test(q) && /(quelle|quelles|liste|lister|dispo|disponible|disponibles|toutes|tous|montre|donne)/.test(q)) {
      var allKind = /effet/.test(q) ? "effect" : "bomb";
      text = (allKind === "bomb" ? "Bombes" : "Effets d'explosion") + " de la boutique :\n" + list(G.cosmetics[allKind].map(function (c) { return c.name + " : " + (c.price === 0 ? "gratuit" : fmt(c.price) + " pièces") + " (" + c.color + ")"; }));
    } else if (/(plus cher|plus chere|le plus cher|prix max|couteux)/.test(q) || /(moins cher|moins chere|gratuit)/.test(q) || /\b(prix|cout|coute)\b/.test(q)) {
      var kind = /effet|explosion/.test(q) ? "effect" : "bomb";
      var items = G.cosmetics[kind].slice().sort(function (a, b) { return b.price - a.price; });
      var cheap = /moins cher|moins chere|gratuit/.test(q);
      text = cheap ? "Les moins chers (" + (kind === "bomb" ? "bombes" : "effets") + ") :\n" + list(items.slice().reverse().slice(0, 3).map(function (c) { return c.name + " : " + (c.price === 0 ? "gratuit" : fmt(c.price) + " pièces"); }))
        : "Le plus cher (" + (kind === "bomb" ? "bombes" : "effets") + ") : " + items[0].name + " à " + fmt(items[0].price) + " pièces.\nClassement :\n" + list(items.map(function (c) { return c.name + " : " + (c.price === 0 ? "gratuit" : fmt(c.price) + " pièces"); }));
    } else if (/quete/.test(q)) {
      var qs = G.quests.slice().sort(function (a, b) { return b.reward - a.reward; });
      text = "Quêtes (de la mieux payée à la moins bien payée) :\n" + list(qs.map(function (x) { return x.name + " : " + x.description + ", +" + x.reward + " pièces"; })) + "\nTotal : " + qs.reduce(function (a, x) { return a + x.reward; }, 0) + " pièces.";
    } else if (/theme/.test(q)) {
      text = G.map.themes.length + " thèmes :\n" + list(G.map.themes.map(function (t) { return t.displayName + " (" + t.id + "), " + t.lighting.clockTime + " h"; }));
    } else if (/(carte|arene|taille|joueurs)/.test(q)) {
      text = "Cartes jouables :\n" + list(G.map.sizes.map(function (s) { return s.id + " : " + s.size + " × " + s.size + " cases, " + s.minPlayers + " à " + s.maxPlayers + " joueurs"; }));
    } else if (/(bonus|power|bouclier)/.test(q)) {
      text = "Bonus :\n" + list(G.powerups.map(function (p) { return p.displayName + " : " + p.description; })) + "\nChance de bonus par caisse : " + Math.round(G.settings.powerupDrops.DropChancePerCrate * 100) + " %.";
    } else if (/emote|danse/.test(q)) {
      text = G.emotes.list.length + " émotes :\n" + list(G.emotes.list.map(function (e) { return e.name + (e.looped ? " (danse en boucle)" : " (geste)"); }));
    } else if (/(chat|phrase)/.test(q)) {
      text = G.quickChat.phrases.length + " phrases rapides :\n" + list(G.quickChat.phrases.map(function (p) { return p.text; }));
    } else if (/(asset|image|logo|icone)/.test(q)) {
      text = D.manifest.assets.length + " images importées :\n" + list(D.manifest.assets.map(function (a) { return a.fichier.split("/").pop() + " : " + a.assetId; }));
    } else if (/(duree|manche|meche|delai|reglage|recompense|pieces)/.test(q)) {
      var s = G.settings;
      text = "Manche : " + s.round.RoundDuration + " s, compte à rebours " + s.round.QuickCountdown + " s, résultats " + s.round.ResultDuration + " s.\nBombe : mèche " + s.bomb.FuseTime + " s, flammes " + s.bomb.ExplosionDuration + " s.\nRécompenses : participation " + s.rewards.ParticipationCoins + ", victoire +" + s.rewards.WinCoins + ", égalité +" + s.rewards.DrawCoins + " pièces.";
    } else {
      text = "Je n'ai pas compris en mode local. Je sais répondre sur : les tests, les prix des bombes et effets, les quêtes, les thèmes, les cartes, les bonus, les émotes, le chat rapide, les assets et les réglages de manche. Tu peux aussi écrire « propose une bombe dorée à 400 pièces » pour préparer un brouillon. Pour des questions libres, utilise la version locale du registre avec ta clé Groq (node tools/registre/serve.js).";
    }
    return { text: text, drafts: drafts };
  }

  async function sendChat(text) {
    if (chat.busy || !text.trim()) return;
    text = maskSecrets(text.trim());
    chat.hist.push({ role: "user", content: text });
    persistCurrent();
    setBusy(true); chat.pending = ""; renderMsgs(); setStatus("Connexion à l'assistant…");
    var ok = await getSample();
    if (!ok) {
      /* Pas d'assistant IA disponible : réponse locale à partir des données de la page, avec la raison exacte. */
      var local = localAnswer(text);
      var entry0 = { role: "assistant", content: local.text + "\n\n— Réponse locale, sans IA : " + backend.ai.reasonText() + "." };
      if (local.drafts) { entry0.drafts = local.drafts; entry0.draftKey = "m" + chat.hist.length; chat.draftStore[entry0.draftKey] = local.drafts; }
      chat.pending = null; chat.hist.push(entry0);
      persistCurrent();
      setBusy(false); renderMsgs(); return;
    }
    chat.drafts = [];
    var ac = new AbortController(); chat.abort = ac;
    var finalText = "";
    try {
      var answer = await backend.ai.ask({
        system: SYSTEM,
        messages: chat.hist.map(function (m) { return { role: m.role, content: m.content }; }),
        tools: TOOLS,
        signal: ac.signal,
        onText: function (t) { chat.pending = t; renderMsgs(); }
      });
      finalText = answer || chat.pending || "";
    } catch (e) {
      finalText = chat.pending || "";
      if (e && e.name === "AbortError") finalText = finalText + (finalText ? "\n\n" : "") + "(réponse interrompue)";
      else if (e && e.code === "rate_limited") finalText = "Trop de demandes d'un coup. Attends quelques secondes avant de réessayer.";
      else if (e && e.code === "not_granted") finalText = "L'assistant n'est pas autorisé pour cette page.";
      else if (e && e.code === "auth") finalText = "La clé a été refusée par le service. Vérifie-la ou crée-en une nouvelle.";
      else if (e && e.code === "network") finalText = "Le service est injoignable (connexion ou blocage du navigateur). Réessaie.";
      else finalText = finalText || ("L'assistant n'a pas pu répondre (" + ((e && (e.message || e.code)) || "erreur") + "). Réessaie.");
    }
    var entry = { role: "assistant", content: finalText || "(réponse vide)" };
    if (chat.drafts.length) { entry.drafts = chat.drafts.slice(); entry.draftKey = "m" + chat.hist.length; chat.draftStore[entry.draftKey] = entry.drafts; }
    chat.hist.push(entry);
    chat.pending = null; chat.abort = null;
    persistCurrent();
    setStatus(backend.ai.status());
    setBusy(false); renderMsgs();
  }

  var SUGGESTIONS = ["Quelle est la bombe la plus chère ?", "Résume l'état des tests", "Quelles quêtes rapportent le plus de pièces ?", "Propose une nouvelle bombe dorée à 400 pièces"];

  function renderAssistant() {
    var h = '<div class="stack" style="gap:6px"><h2>Assistant</h2><p class="muted">Pose des questions sur les données du jeu et les tests, ou demande un brouillon d\'ajout. L\'assistant ne modifie jamais le dépôt : un brouillon passe par l\'onglet Contribuer.</p></div>';
    h += '<div class="chatsplit"><div class="card chat"><div id="ai-settings"></div><div class="msgs" id="msgs" role="log" aria-live="polite"></div>';
    h += '<div class="pills" id="sugg">' + SUGGESTIONS.map(function (s) { return '<button class="pill" data-s="' + esc(s) + '">' + esc(s) + "</button>"; }).join("") + "</div>";
    h += '<form class="composer" id="chat-form"><textarea id="chat-input" rows="2" placeholder="Ta question…" aria-label="Ta question"></textarea><button class="btn" id="chat-send" type="submit">Envoyer</button><button class="btn ghost" id="chat-stop" type="button" hidden>Arrêter</button></form>';
    h += '<div class="row" style="justify-content:space-between;align-items:center"><span class="hint">Entrée envoie, Maj+Entrée saute une ligne. <span id="chat-status"></span></span><button class="copy" id="chat-clear" type="button">Supprimer cette conversation</button></div></div>';
    h += '<aside class="card stack" style="gap:10px" aria-label="Historique des conversations"><div class="row" style="justify-content:space-between;align-items:center"><h3>Conversations</h3><button class="btn" id="chat-new" type="button">Nouvelle</button></div><div id="history-list" class="stack" style="gap:6px"></div><div><button class="copy" id="history-clear" type="button">Tout effacer</button></div><p class="hint" id="history-note"></p></aside></div>';
    $("view-assistant").innerHTML = h;
    if (backend.ai.mountSettings) backend.ai.mountSettings($("ai-settings"), function () { setStatus(backend.ai.status()); });
    renderMsgs();
    renderHistoryList();
    setBusy(false);
    var input = $("chat-input");
    $("chat-form").addEventListener("submit", function (e) { e.preventDefault(); var t = input.value; if (!t.trim()) return; input.value = ""; sendChat(t); });
    input.addEventListener("keydown", function (e) { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); $("chat-send").click(); } });
    $("chat-stop").addEventListener("click", function () { if (chat.abort) chat.abort.abort(); });
    $("chat-new").addEventListener("click", function () { if (!chat.busy) newConversation(); });
    $("chat-clear").addEventListener("click", function () { if (chat.busy) return; if (chat.convId) deleteConversation(chat.convId); else newConversation(); });
    $("history-list").addEventListener("click", function (e) {
      var del = e.target.closest("[data-delconv]");
      if (del) { if (!chat.busy) deleteConversation(del.getAttribute("data-delconv")); return; }
      var open = e.target.closest("[data-open]");
      if (open) openConversation(open.getAttribute("data-open"));
    });
    var armed = 0;
    $("history-clear").addEventListener("click", function (e) {
      var b = e.currentTarget;
      if (!armed) { armed = 1; b.textContent = "Confirmer ?"; setTimeout(function () { armed = 0; b.textContent = "Tout effacer"; }, 3000); return; }
      armed = 0; b.textContent = "Tout effacer";
      history.list = []; saveHistory(); newConversation();
      if (backend.storage) backend.storage.chats.clear().then(null, function () { /* serveur arrêté */ });
    });
    $("sugg").addEventListener("click", function (e) { var b = e.target.closest("[data-s]"); if (b) sendChat(b.getAttribute("data-s")); });
    $("msgs").addEventListener("click", function (e) {
      var b = e.target.closest("[data-draft]"); if (!b) return;
      var parts = b.getAttribute("data-draft").split(":"), list = chat.draftStore[parts[0]] || [], d = list[Number(parts[1])];
      if (d && fillForm(d.type, d.fields, d.note)) navigate("contribuer");
    });
  }

  function startSample() {
    getSample();
  }

  /* ---------- Stockage durable : réglages de la page, sons, vue d'ensemble et sauvegarde ---------- */
  var NO_SERVER = "Cette page a besoin du serveur local pour conserver des données : lance « node tools/registre/serve.js » et ouvre l'adresse affichée.";
  var settingsCache = {}, settingsTimer = null;
  function saveSetting(patch) {
    if (!backend.storage) return;
    Object.keys(patch).forEach(function (k) { settingsCache[k] = patch[k]; });
    clearTimeout(settingsTimer);
    settingsTimer = setTimeout(function () { backend.storage.settings.put(settingsCache).then(null, function () { /* réglage non conservé : sans gravité */ }); }, 400);
  }
  function loadSettings() {
    if (!backend.storage) return;
    backend.storage.settings.get().then(function (s) {
      if (!s || typeof s !== "object") return;
      settingsCache = {};
      ["tab", "gameTab", "runFilter", "model"].forEach(function (k) { if (typeof s[k] === "string") settingsCache[k] = s[k]; });
      if (settingsCache.gameTab && gamePanels[settingsCache.gameTab] && settingsCache.gameTab !== currentGame) { currentGame = settingsCache.gameTab; renderGame(); }
      if (settingsCache.runFilter && !runFilterValue && /^[A-Za-z0-9 ._\/-]{1,60}$/.test(settingsCache.runFilter)) { runFilterValue = settingsCache.runFilter; renderTests(); }
    }, function () { /* serveur injoignable */ });
  }
  function fmtBytes(n) { return n < 1024 ? n + " o" : n < 1048576 ? (n / 1024).toFixed(1) + " Ko" : (n / 1048576).toFixed(1) + " Mo"; }
  function toBase64(buffer) {
    var bytes = new Uint8Array(buffer), out = "";
    for (var i = 0; i < bytes.length; i += 8192) out += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
    return btoa(out);
  }

  var EVENT_LABELS = {
    bomb_place: "Pose d'une bombe", bomb_fuse: "Mèche allumée", explosion: "Explosion", powerup_pickup: "Bonus ramassé", shield_break: "Bouclier brisé",
    elimination: "Élimination", victory: "Victoire", defeat: "Défaite", draw: "Égalité", countdown_tick: "Compte à rebours", round_start: "Début de manche",
    button_click: "Clic de bouton", purchase_success: "Achat réussi", purchase_fail: "Achat refusé", quest_complete: "Quête terminée",
    menu_music: "Musique du menu", lobby_music: "Musique du lobby", round_music: "Musique de manche", custom: "Autre"
  };
  var CATEGORY_LABELS = { sfx: "Effet sonore", music: "Musique", ui: "Interface" };
  var sons = { list: [], limits: null, editing: null, msg: "", error: "", confirm: "", loaded: false };

  function loadSons() {
    if (!backend.storage) { renderSons(); return Promise.resolve(); }
    return Promise.all([backend.storage.sounds.list(), backend.storage.stats()]).then(function (r) {
      sons.list = Array.isArray(r[0]) ? r[0] : []; sons.limits = r[1] && r[1].limits; sons.error = ""; sons.loaded = true; renderSons();
    }, function (err) { sons.error = "Lecture des sons impossible : " + ((err && err.message) || err); sons.loaded = true; renderSons(); });
  }
  function soundFor(id) { for (var i = 0; i < sons.list.length; i++) if (sons.list[i].id === id) return sons.list[i]; return null; }
  function sourceText(s) {
    if (s.source.type === "file") return "Fichier : " + esc(s.source.originalName || s.source.file) + " (" + fmtBytes(s.source.bytes || 0) + ")";
    if (s.source.type === "roblox") return "Roblox : " + esc(s.source.assetId);
    return "Aucune source pour l'instant";
  }
  function soundFormHtml(cur) {
    var ev = (sons.limits && sons.limits.soundEvents) || Object.keys(EVENT_LABELS), cats = (sons.limits && sons.limits.soundCategories) || Object.keys(CATEGORY_LABELS);
    var src = cur ? cur.source.type : "file", v = cur || { name: "", event: ev[0], category: "sfx", volume: 0.8, loop: false, enabled: true, note: "", source: { type: "file" } };
    var h = '<form class="card stack" id="sons-form" style="gap:12px"><h3>' + (cur ? "Modifier le son" : "Nouveau son") + "</h3>";
    h += '<div class="field"><label for="s-name">Nom</label><input id="s-name" type="text" maxlength="40" value="' + esc(v.name) + '"></div>';
    h += '<div class="field"><label for="s-event">Événement du jeu</label><select id="s-event">' + ev.map(function (e) { return '<option value="' + esc(e) + '"' + (e === v.event ? " selected" : "") + ">" + esc(EVENT_LABELS[e] || e) + "</option>"; }).join("") + "</select></div>";
    h += '<div class="field"><label for="s-category">Catégorie</label><select id="s-category">' + cats.map(function (c) { return '<option value="' + esc(c) + '"' + (c === v.category ? " selected" : "") + ">" + esc(CATEGORY_LABELS[c] || c) + "</option>"; }).join("") + "</select></div>";
    h += '<div class="field"><label for="s-volume">Volume (0 à 1)</label><input id="s-volume" type="number" min="0" max="1" step="0.05" value="' + esc(v.volume) + '"></div>';
    h += '<label class="hint" style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="s-loop"' + (v.loop ? " checked" : "") + ' style="width:auto"> Jouer en boucle</label>';
    h += '<label class="hint" style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="s-enabled"' + (v.enabled ? " checked" : "") + ' style="width:auto"> Son activé</label>';
    h += '<div class="field"><label for="s-source">Source</label><select id="s-source"><option value="file"' + (src === "file" ? " selected" : "") + '>Fichier audio (mp3, ogg, wav)</option><option value="roblox"' + (src === "roblox" ? " selected" : "") + '>Identifiant Roblox (rbxassetid://…)</option><option value="none"' + (src === "none" ? " selected" : "") + ">Pas encore de source</option></select></div>";
    h += '<div class="field"><label for="s-file">Fichier audio (' + fmtBytes((sons.limits && sons.limits.maxSoundBytes) || 1500000) + ' au plus)</label><input id="s-file" type="file" accept="audio/mpeg,audio/ogg,audio/wav,.mp3,.ogg,.wav">' + (cur && cur.source.type === "file" ? '<span class="hint">Laisse vide pour garder « ' + esc(cur.source.originalName || cur.source.file) + " ».</span>" : "") + "</div>";
    h += '<div class="field"><label for="s-asset">Identifiant Roblox</label><input id="s-asset" type="text" maxlength="40" placeholder="rbxassetid://123456" value="' + esc(cur && cur.source.type === "roblox" ? cur.source.assetId : "") + '"><span class="hint">Un identifiant n\'est jamais inventé : colle celui d\'un son réellement importé dans Roblox.</span></div>';
    h += '<div class="field"><label for="s-note">Note (facultatif)</label><input id="s-note" type="text" maxlength="200" value="' + esc(v.note || "") + '"></div>';
    h += '<div class="row" style="align-items:center;gap:10px"><button class="btn" id="s-save" type="submit">Enregistrer</button><button class="btn ghost" id="s-cancel" type="button" data-cancel="1">Annuler</button><span class="hint" id="s-msg" role="status" aria-live="polite"></span></div></form>';
    return h;
  }
  function renderSons() {
    var root = $("view-sons");
    if (!root) return;
    if (!backend.storage) { root.innerHTML = '<h2>Sons</h2><div class="notice">' + esc(NO_SERVER) + "</div>"; return; }
    var h = '<div class="row" style="justify-content:space-between;align-items:center"><div class="stack" style="gap:6px"><h2>Sons <span class="tag">' + sons.list.length + '</span></h2><p class="muted">Catalogue des sons du jeu. Le jeu ne joue encore aucun son : ce catalogue prépare les fichiers et les réglages (volume, boucle) avant leur branchement dans le code.</p></div>' + (can("sounds.create") ? '<button class="btn" id="sons-new" type="button" data-new="1">Ajouter un son</button>' : "") + '</div>';
    if (sons.error) h += '<div class="notice" role="alert">' + esc(sons.error) + "</div>";
    if (sons.msg) h += '<div class="notice" role="status">' + esc(sons.msg) + "</div>";
    if (sons.editing) h += soundFormHtml(sons.editing === "new" ? null : soundFor(sons.editing));
    if (!sons.list.length && sons.loaded && !sons.error) h += '<p class="hint">Aucun son enregistré pour l\'instant.</p>';
    h += '<div class="grid" id="sons-list">';
    sons.list.forEach(function (s) {
      h += '<div class="card stack" style="gap:8px"><h3>' + esc(s.name) + (s.enabled ? "" : ' <span class="tag">désactivé</span>') + '</h3><div class="muted">' + esc(EVENT_LABELS[s.event] || s.event) + " · " + esc(CATEGORY_LABELS[s.category] || s.category) + " · volume " + esc(s.volume) + (s.loop ? " · boucle" : "") + "</div><div class=\"muted\">" + sourceText(s) + "</div>";
      if (s.note) h += '<div class="hint">' + esc(s.note) + "</div>";
      if (s.source.type === "file") h += '<audio controls preload="none" src="' + esc(backend.storage.sounds.url(s.source)) + '" aria-label="Écouter ' + esc(s.name) + '"></audio>';
      h += '<div class="row" style="gap:8px">' + (can("sounds.edit") ? '<button class="copy" data-edit="' + esc(s.id) + '" type="button">Modifier</button>' : "") + (can("sounds.delete") ? '<button class="copy" data-delsound="' + esc(s.id) + '" type="button">' + (sons.confirm === s.id ? "Confirmer ?" : "Supprimer") + "</button>" : "") + "</div></div>";
    });
    root.innerHTML = h + "</div>";
    if (sons.editing && $("s-save")) $("s-msg").textContent = sons.formMsg || "";
  }
  function saveSound() {
    var cur = sons.editing === "new" ? null : soundFor(sons.editing), msg = $("s-msg"), type = $("s-source").value;
    var meta = { name: $("s-name").value.trim(), event: $("s-event").value, category: $("s-category").value, volume: Number($("s-volume").value), loop: !!$("s-loop").checked, enabled: !!$("s-enabled").checked, note: $("s-note").value.trim(), source: { type: type } };
    function fail(text) { sons.formMsg = text; msg.textContent = text; $("s-save").disabled = false; }
    if (meta.name.length < 2) return fail("Donne un nom d'au moins 2 caractères.");
    if (isNaN(meta.volume) || meta.volume < 0 || meta.volume > 1) return fail("Le volume doit être compris entre 0 et 1.");
    var file = type === "file" && $("s-file").files && $("s-file").files[0];
    if (type === "roblox") { meta.source.assetId = $("s-asset").value.trim(); if (!/^rbxassetid:\/\/[0-9]{1,20}$/.test(meta.source.assetId)) return fail("Identifiant Roblox invalide (format rbxassetid://123456)."); }
    var keep = !!cur && cur.source.type === "file" && type === "file" && !file;
    if (type === "file" && !file && !keep) return fail("Choisis un fichier audio.");
    if (file && sons.limits && file.size > sons.limits.maxSoundBytes) return fail("Fichier trop gros (" + fmtBytes(file.size) + ") : " + fmtBytes(sons.limits.maxSoundBytes) + " au plus.");
    if (keep) meta.source = { type: "file" };
    $("s-save").disabled = true; msg.textContent = "Enregistrement…";
    var ready = file ? file.arrayBuffer().then(function (buf) { return { name: file.name, dataBase64: toBase64(buf) }; }) : Promise.resolve(undefined);
    ready.then(function (payload) { return backend.storage.sounds.save(meta, payload, cur ? cur.id : undefined); }).then(function (saved) {
      sons.editing = null; sons.formMsg = ""; sons.msg = "Son « " + saved.name + " » enregistré."; return loadSons();
    }, function (err) { fail("Enregistrement refusé : " + ((err && err.message) || err)); });
  }
  function bindSons() {
    var root = $("view-sons");
    root.addEventListener("click", function (e) {
      var t = e.target;
      if (t.closest("[data-new]")) { sons.editing = "new"; sons.msg = ""; sons.formMsg = ""; renderSons(); return; }
      if (t.closest("[data-cancel]")) { sons.editing = null; sons.formMsg = ""; renderSons(); return; }
      var ed = t.closest("[data-edit]");
      if (ed) { sons.editing = ed.getAttribute("data-edit"); sons.msg = ""; sons.formMsg = ""; renderSons(); return; }
      var del = t.closest("[data-delsound]");
      if (del) {
        var id = del.getAttribute("data-delsound");
        if (sons.confirm !== id) { sons.confirm = id; renderSons(); setTimeout(function () { if (sons.confirm === id) { sons.confirm = ""; renderSons(); } }, 3000); return; }
        sons.confirm = "";
        backend.storage.sounds.remove(id).then(function () { sons.msg = "Son supprimé."; return loadSons(); }, function (err) { sons.error = "Suppression impossible : " + ((err && err.message) || err); renderSons(); });
      }
    });
    root.addEventListener("submit", function (e) { if (e.preventDefault) e.preventDefault(); saveSound(); });
  }

  var stock = { stats: null, error: "", report: null, busy: false, msg: "" };
  function loadStock() {
    if (!backend.storage) { renderStock(); return Promise.resolve(); }
    return backend.storage.stats().then(function (s) { stock.stats = s && s.chats && s.contributions && s.runs && s.sounds && s.settings ? s : null; stock.error = stock.stats ? "" : "Réponse inattendue du serveur."; renderStock(); }, function (err) { stock.error = "Lecture impossible : " + ((err && err.message) || err); renderStock(); });
  }
  function renderStock() {
    var root = $("view-stockage");
    if (!root) return;
    if (!backend.storage) { root.innerHTML = "<h2>Stockage</h2><div class=\"notice\">" + esc(NO_SERVER) + "</div>"; return; }
    var s = stock.stats, h = '<div class="stack" style="gap:6px"><h2>Stockage des données</h2><p class="muted">Tout est enregistré dans des fichiers du dossier de données du serveur local' + (s ? " (<span class=\"mono\">" + esc(s.dir) + "</span>)" : "") + ", ignoré par git. Une sauvegarde regroupe conversations, contributions, historique des tests, réglages et sons dans un seul fichier.</p></div>";
    if (stock.error) h += '<div class="notice" role="alert">' + esc(stock.error) + "</div>";
    if (s) {
      h += '<div class="card tablewrap"><table><thead><tr><th>Donnée</th><th>Éléments</th><th>Taille</th></tr></thead><tbody>';
      [["Conversations de l'assistant", s.chats], ["Contributions", s.contributions], ["Exécutions de tests", s.runs], ["Sons", s.sounds]].forEach(function (r) { h += "<tr><td>" + r[0] + '</td><td class="num">' + r[1].count + '</td><td class="num">' + fmtBytes(r[1].bytes) + "</td></tr>"; });
      h += "<tr><td>Réglages de la page</td><td class=\"num\">" + (s.settings.exists ? 1 : 0) + "</td><td></td></tr></tbody></table></div>";
    }
    h += '<div class="card stack" style="gap:10px"><h3>Sauvegarde et restauration</h3><div class="row" style="gap:10px;align-items:center">' + (can("storage.export") ? '<button class="btn" id="stock-export" type="button">Exporter une sauvegarde</button>' : '<span class="hint">L\'export est réservé aux administrateurs.</span>') + '</div>';
    if (can("storage.import")) h += '<div class="field"><label for="stock-file">Restaurer depuis un fichier de sauvegarde</label><div class="composer"><input id="stock-file" type="file" accept="application/json,.json"><button class="btn" id="stock-import" type="button">Importer</button></div><span class="hint">La restauration fusionne : rien n\'est supprimé, une conversation plus récente est conservée, les éléments déjà présents sont ignorés.</span></div>';
    h += '<span class="hint" id="stock-msg" role="status" aria-live="polite">' + esc(stock.msg) + "</span>";
    if (stock.report) {
      var r = stock.report;
      h += '<div class="notice" role="status">Importé : ' + r.chats + " conversation(s), " + r.contributions + " contribution(s), " + r.runs + " exécution(s) de tests, " + r.sounds + " son(s)" + (r.settings ? ", réglages" : "") + "." + (r.ignored && r.ignored.length ? '<br>Ignoré : <span class="mono">' + r.ignored.map(esc).join(" · ") + "</span>" : "") + "</div>";
    }
    root.innerHTML = h + "</div>";
  }
  function bindStock() {
    $("view-stockage").addEventListener("click", function (e) {
      var t = e.target;
      if (t.closest("#stock-export")) {
        stock.msg = "Préparation de la sauvegarde…"; renderStock();
        backend.storage.backup().then(function (bundle) {
          var blob = new Blob([JSON.stringify(bundle)], { type: "application/json" }), a = document.createElement("a");
          a.href = URL.createObjectURL(blob); a.download = "sauvegarde-registre-" + new Date().toISOString().slice(0, 10) + ".json";
          document.body.appendChild(a); a.click(); a.remove();
          stock.msg = "Sauvegarde téléchargée (" + fmtBytes(blob.size) + ")."; renderStock();
        }, function (err) { stock.msg = "Sauvegarde impossible : " + ((err && err.message) || err); renderStock(); });
        return;
      }
      if (t.closest("#stock-import")) {
        var file = $("stock-file").files && $("stock-file").files[0];
        if (!file) { $("stock-msg").textContent = "Choisis d'abord un fichier de sauvegarde."; return; }
        $("stock-msg").textContent = "Restauration…";
        file.text().then(function (text) { return backend.storage.restore(JSON.parse(text)); }).then(function (report) {
          stock.report = report; stock.msg = "Restauration terminée.";
          return Promise.all([loadStock(), loadSons(), syncHistory()]);
        }, function (err) { stock.report = null; stock.msg = "Restauration refusée : " + ((err && err.message) || err); renderStock(); });
      }
    });
  }
  function startStorage() {
    bindSons(); bindStock();
    syncHistory(); loadSettings(); loadSons(); loadStock();
  }

  /* Éléments facultatifs fournis par l'adaptateur (ex. bouton « Actualiser » de la version locale). */
  function mountExtras() {
    if (!backend.refresh) return;
    var b = document.createElement("button");
    b.className = "copy"; b.type = "button"; b.textContent = "Actualiser les données";
    b.addEventListener("click", function () { b.disabled = true; b.textContent = "Actualisation…"; backend.refresh().then(function () { location.reload(); }, function (err) { b.disabled = false; b.textContent = "Échec : " + ((err && err.message) || err); }); });
    $("foot").appendChild(document.createTextNode(" "));
    $("foot").appendChild(b);
  }

