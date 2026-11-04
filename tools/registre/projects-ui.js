  /* Catalogue de projets : import, sélection et aperçu des sources. */
  function customProjects() { return Array.isArray(D.projects) ? D.projects : []; }
  function builtinProfile(id) {
    var fallback = { id: id, name: id === "boom" ? "BOOM BATTLE" : "Luma", source: "builtin", author: id === "boom" ? "SmiledPolecat34 · steph-mss" : "", description: "" };
    return (D.projectProfiles || []).filter(function (p) { return p.id === id; })[0] || fallback;
  }
  function profileByView(view) {
    if (view === "profil/boom" || view === "profil/luma") { var p = builtinProfile(view.slice(7)); return p.deleted ? null : p; }
    return projectByView(view);
  }
  function rememberProject(project) {
    if (project.source === "builtin") {
      D.projectProfiles = [builtinProfile("boom"), builtinProfile("luma")].map(function (p) { return p.id === project.id ? project : p; });
    } else D.projects = customProjects().map(function (p) { return p.id === project.id ? project : p; });
  }
  function projectByView(view) { return customProjects().filter(function (p) { return "projet/" + p.id === view; })[0]; }
  function renderProjectCatalogue() {
    var projects = customProjects();
    var boom = builtinProfile("boom"), luma = builtinProfile("luma");
    $("project-boom").hidden = !!boom.deleted; $("project-luma").hidden = !!luma.deleted;
    $("project-boom").textContent = boom.name; $("project-luma").textContent = luma.name;
    $("card-boom").hidden = !!boom.deleted; $("card-luma").hidden = !!luma.deleted;
    $("card-luma-name").textContent = luma.name;
    $("luma-space-title").textContent = "Un espace pour " + luma.name;
    $("project-brand-logo").setAttribute("alt", boom.name);
    $("card-boom-open").setAttribute("aria-label", "Ouvrir le projet " + boom.name);
    $("card-luma-open").setAttribute("aria-label", "Ouvrir le projet " + luma.name);
    if (boom.description) $("card-boom-description").textContent = boom.description;
    if (luma.description) $("card-luma-description").textContent = luma.description;
    $("extra-project-links").innerHTML = projects.map(function (p) {
      return '<a href="#projet/' + esc(p.id) + '" data-project="' + esc(p.id) + '">' + esc(p.name) + '</a>';
    }).join("");
    $("project-select").innerHTML = '<option value="accueil">Tous les projets</option>' + (!boom.deleted ? '<option value="tests">' + esc(boom.name) + '</option>' : '') + (!luma.deleted ? '<option value="luma">' + esc(luma.name) + '</option>' : '') + projects.map(function (p) {
      return '<option value="projet/' + esc(p.id) + '">' + esc(p.name) + '</option>';
    }).join("") + '<option value="ajouter-projet">+ Nouveau projet…</option>';
    $("extra-project-cards").innerHTML = projects.map(function (p) {
      return '<article class="card project-card"><span class="luma-mark" aria-hidden="true">' + esc(p.name.charAt(0).toUpperCase()) + '</span><h3>' + esc(p.name) + '</h3><p>' + (p.source === "github" ? "Dépôt GitHub · copie locale" : "Dossier local lié") + '</p><a class="btn" href="#projet/' + esc(p.id) + '" aria-label="Ouvrir le projet ' + esc(p.name) + '">Ouvrir le projet <span aria-hidden="true">→</span></a></article>';
    }).join("");
  }
  function profileHtml(project) {
    var owner = project.repository ? project.repository.split("/")[3] : "";
    var h = '<div class="card stack"><h3>Informations du projet</h3><dl class="project-info"><dt>Auteur</dt><dd>' + esc(project.author || "Non renseigné") + '</dd><dt>Source</dt><dd>' + esc(project.source === "github" ? "GitHub" : project.source === "folder" ? "Dossier local" : "Projet intégré") + '</dd>';
    if (owner) h += '<dt>Propriétaire du dépôt</dt><dd>' + esc(owner) + '</dd>';
    if (project.id === "boom" && D.game && D.game.version) h += '<dt>Version du jeu</dt><dd>' + esc(D.game.version) + '</dd>';
    if (project.createdAt) h += '<dt>Ajouté au registre</dt><dd>' + esc(dateTime(project.createdAt)) + '</dd>';
    if (project.updatedAt) h += '<dt>Profil modifié</dt><dd>' + esc(dateTime(project.updatedAt)) + '</dd>';
    if (project.snapshot && project.snapshot.scannedAt) h += '<dt>Dernière analyse</dt><dd>' + esc(dateTime(project.snapshot.scannedAt)) + '</dd>';
    h += '</dl></div><form id="profile-form" class="card stack" novalidate><h3>Modifier le profil</h3><div class="field"><label for="profile-name">Nom du projet</label><input id="profile-name" maxlength="80" value="' + esc(project.name) + '"></div><div class="field"><label for="profile-author">Auteur ou équipe</label><input id="profile-author" maxlength="120" value="' + esc(project.author || "") + '" placeholder="Nom de l’auteur ou de l’équipe"></div><div class="field"><label for="profile-description">Description</label><textarea id="profile-description" rows="3" maxlength="2000">' + esc(project.description || "") + '</textarea></div><div><button id="profile-save" type="submit" class="btn">Enregistrer les modifications</button></div><span id="profile-message" role="status" aria-live="polite" class="hint"></span></form>';
    h += '<div class="card stack project-danger"' + (can("projects.remove") ? "" : " hidden") + '><h3>Supprimer le projet du site</h3><p class="muted">Le projet sera retiré du catalogue. Ses fichiers locaux et son dépôt GitHub seront conservés.</p><div><button id="profile-delete" type="button" class="btn ghost">Supprimer le projet</button></div><div id="profile-delete-confirm" class="stack" hidden><p>Retirer « ' + esc(project.name) + ' » du site ?</p><div class="row"><button id="profile-delete-confirm-btn" class="btn" type="button">Confirmer la suppression</button><button id="profile-delete-cancel" class="btn ghost" type="button">Annuler</button></div></div><span id="profile-delete-message" class="hint" role="status"></span></div>';
    return h;
  }
  function bindProjectProfile(project) {
    $("profile-form").addEventListener("submit", function (e) {
      e.preventDefault(); var btn = $("profile-save"), msg = $("profile-message");
      var fields = { name: $("profile-name").value.trim(), author: $("profile-author").value.trim(), description: $("profile-description").value.trim() };
      if (!fields.name) { msg.textContent = "Le nom du projet est obligatoire."; $("profile-name").focus(); return; }
      if (btn.disabled) return; btn.disabled = true; msg.textContent = "Enregistrement…";
      backend.storage.projects.update(project.id, fields).then(function (updated) {
        rememberProject(updated); renderProjectCatalogue(); activeView = null; route();
        $("profile-message").textContent = "Profil enregistré.";
      }, function (err) { btn.disabled = false; msg.textContent = err.message || "Enregistrement impossible."; });
    });
    $("profile-delete").addEventListener("click", function () { $("profile-delete-confirm").hidden = false; $("profile-delete-confirm-btn").focus(); });
    $("profile-delete-cancel").addEventListener("click", function () { $("profile-delete-confirm").hidden = true; $("profile-delete").focus(); });
    $("profile-delete-confirm-btn").addEventListener("click", function () {
      var btn = $("profile-delete-confirm-btn"); if (btn.disabled) return; btn.disabled = true;
      backend.storage.projects.remove(project.id).then(function () {
        if (project.source === "builtin") rememberProject(Object.assign({}, project, { deleted: true }));
        else D.projects = customProjects().filter(function (p) { return p.id !== project.id; });
        renderProjectCatalogue(); navigate("accueil");
      }, function (err) { btn.disabled = false; $("profile-delete-message").textContent = err.message || "Suppression impossible."; });
    });
  }
  function renderImportedProject(project) {
    var snap = project.snapshot || { count: 0, files: [], extensions: [] };
    if (project.source === "builtin") {
      $("view-project").innerHTML = '<div class="card stack"><h3>Présentation</h3><p>' + esc(project.description || "Les informations de ce projet restent à renseigner.") + '</p>' + (project.path ? '<p class="mono project-path">' + esc(project.path) + '</p>' : '') + '<a href="' + (project.id === "boom" ? '#tests' : '#luma') + '">Ouvrir l’espace du projet →</a></div>' + profileHtml(project);
      bindProjectProfile(project); return;
    }
    var h = '<div class="tiles project-metrics"><div class="tile info"><b>' + fmt(snap.count) + '</b><span>fichiers repérés' + (snap.truncated ? ' · aperçu limité' : '') + '</span></div><div class="tile info"><b>' + (project.source === "github" ? "GitHub" : "Local") + '</b><span>source du projet</span></div></div>';
    h += '<div class="card stack"><h3>Source du projet</h3><p class="mono project-path">' + esc(project.path) + '</p>';
    if (project.repository) h += '<a href="' + esc(project.repository) + '" target="_blank" rel="noopener noreferrer">Voir le dépôt sur GitHub <span aria-hidden="true">↗</span></a>';
    h += '<p class="hint">' + (project.source === "github" ? "Le dépôt a été cloné dans le registre. L’actualisation relit les fichiers locaux, sans récupérer les modifications distantes." : "Le dossier reste à son emplacement d’origine. L’actualisation relit ses fichiers.") + ' Aucun script du projet n’est exécuté.</p><div><button type="button" class="btn ghost" id="project-rescan">Actualiser l’aperçu</button></div><span role="status" id="project-rescan-msg" class="hint"></span></div>';
    h += '<div class="card stack"><h3>Aperçu des fichiers</h3><div class="row">' + (snap.extensions || []).map(function (ext) { return '<span class="tag">.' + esc(ext.name) + ' · ' + fmt(ext.count) + '</span>'; }).join("") + '</div><ul class="project-files mono">' + (snap.files || []).map(function (file) { return '<li>' + esc(file) + '</li>'; }).join("") + '</ul>' + (!snap.count ? '<p class="muted">Ce dossier ne contient pas encore de fichiers visibles.</p>' : '') + '<p class="hint">Aperçu limité à 80 fichiers ; dépendances, dossiers générés et fichiers cachés exclus.</p></div>';
    $("view-project").innerHTML = h + profileHtml(project);
    bindProjectProfile(project);
    $("project-rescan").addEventListener("click", function () {
      var btn = $("project-rescan"); btn.disabled = true; $("project-rescan-msg").textContent = "Lecture des fichiers…";
      backend.storage.projects.refresh(project.id).then(function (updated) {
        D.projects = customProjects().map(function (p) { return p.id === updated.id ? updated : p; });
        renderImportedProject(updated); $("project-rescan-msg").textContent = "Aperçu actualisé.";
      }, function (err) { btn.disabled = false; $("project-rescan-msg").textContent = err.message || "Lecture impossible."; });
    });
  }
  function startProjects() {
    renderProjectCatalogue();
    $("project-select").addEventListener("change", function () { navigate(this.value); });
    $("project-source").addEventListener("change", function () {
      var github = this.value === "github";
      $("project-github-fields").hidden = !github; $("project-folder-fields").hidden = github;
      $("project-import-msg").textContent = "";
    });
    $("project-pick-folder").addEventListener("click", function () {
      var btn = $("project-pick-folder"), msg = $("project-import-msg");
      btn.disabled = true; btn.textContent = "Sélection en cours…"; btn.setAttribute("aria-busy", "true");
      msg.textContent = "Choisis le dossier dans la fenêtre de l’explorateur…";
      $("project-picker-msg").textContent = "Une fenêtre Windows s’ouvre pour choisir ton dossier.";
      function done() { btn.disabled = false; btn.textContent = "Parcourir les dossiers…"; btn.setAttribute("aria-busy", "false"); }
      backend.storage.projects.pick().then(function (result) {
        done();
        if (result.path) { $("project-folder").value = result.path; msg.textContent = "Dossier sélectionné. Tu peux ajouter le projet."; }
        else msg.textContent = "Sélection annulée. Aucun projet n’a été ajouté.";
        $("project-picker-msg").textContent = msg.textContent;
      }, function (err) { done(); msg.textContent = err.message || "Sélection impossible. Tu peux saisir le chemin du dossier."; $("project-picker-msg").textContent = msg.textContent; });
    });
    $("project-import-form").addEventListener("submit", function (e) {
      e.preventDefault();
      var source = $("project-source").value, btn = $("project-import-submit"), msg = $("project-import-msg");
      var body = { source: source, name: $("project-name").value.trim() };
      if (source === "github") body.url = $("project-github-url").value.trim();
      else body.path = $("project-folder").value.trim();
      if (!(body.url || body.path)) { msg.textContent = source === "github" ? "Indique l’adresse du dépôt GitHub." : "Choisis un dossier local."; $(source === "github" ? "project-github-url" : "project-folder").focus(); return; }
      if (btn.disabled) return;
      btn.disabled = true; msg.textContent = source === "github" ? "Import du dépôt en cours…" : "Lecture du dossier…";
      backend.storage.projects.add(body).then(function (project) {
        if (!customProjects().some(function (p) { return p.id === project.id; })) D.projects = customProjects().concat([project]);
        renderProjectCatalogue(); btn.disabled = false; msg.textContent = "Projet ajouté.";
        navigate("projet/" + project.id);
        $("project-name").value = ""; $("project-github-url").value = ""; $("project-folder").value = "";
      }, function (err) { btn.disabled = false; msg.textContent = err.message || "Impossible d’ajouter ce projet."; });
    });
  }
