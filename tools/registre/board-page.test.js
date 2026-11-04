"use strict";
// Page : tableau de suivi (colonnes, déplacements, retours, historique) et journaux (formulaires pilotés par le schéma).
const test = require("node:test");
const assert = require("node:assert/strict");
const { boot, wait, fakeServer, ok } = require("./page-helpers");
const { SCHEMAS } = require("./journal");

const el = (env, id) => env.sandbox.document.getElementById(id);
const target = (selector, value) => ({ target: { closest: (s) => (s === selector ? { getAttribute: () => value } : null) } });
const click = (env, view, selector, value) => env.els[view].handlers.click(target(selector, value));
const view = "view-tableau";
const seed = (server, over) => {
  const base = { id: "tseed00001", title: "Corriger le menu", description: "Bouton coupé", priority: "P1", type: "bug", module: "MainMenu", status: "todo", position: 0, createdAt: 1, updatedAt: 1, comments: [], history: [{ at: 1, action: "created", to: "todo" }] };
  server.state.tickets.push(Object.assign(base, over));
  return base;
};
async function open(server) {
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(60);
  return env;
}
const calls = (server, method) => server.state.boardCalls.filter((c) => c.method === method);

test("tableau : trois colonnes avec les tickets, priorité, type, module et nombre de retours", async () => {
  const server = fakeServer();
  seed(server);
  seed(server, { id: "tseed00002", title: "Ajouter un son", priority: "P3", type: "idee", module: "", status: "doing", comments: [{ id: "kseed00001", text: "ok", at: 5 }] });
  seed(server, { id: "tseed00003", title: "Menu fini", status: "done" });
  const env = await open(server);
  const html = env.els[view].innerHTML;
  assert.match(html, /<h3>À faire <span class="tag">1<\/span>/);
  assert.match(html, /<h3>En cours <span class="tag">1<\/span>/);
  assert.match(html, /<h3>Terminé <span class="tag">1<\/span>/);
  assert.match(html, /P1 · Haute/);
  assert.match(html, /Bug/);
  assert.match(html, /MainMenu/);
  assert.match(html, /1 retour</);
  assert.match(html, /Aucun retour/);
  assert.match(html, /data-ticket="tseed00001"/);
});

test("tableau : titres et descriptions échappés (aucune injection de HTML)", async () => {
  const server = fakeServer();
  seed(server, { title: "<img src=x onerror=alert(1)>", module: "<b>m</b>" });
  const env = await open(server);
  const html = env.els[view].innerHTML;
  assert.doesNotMatch(html, /<img src=x|<b>m<\/b>/);
  assert.match(html, /&lt;img src=x/);
});

test("tableau : créer un ticket (formulaire, validation, envoi), il apparaît dans À faire", async () => {
  const server = fakeServer();
  const env = await open(server);
  click(env, view, "[data-newticket]", "1");
  assert.match(env.els[view].innerHTML, /Nouveau ticket/);
  el(env, "kb-title").value = "ab";
  el(env, "kb-desc").value = ""; el(env, "kb-prio").value = "P0"; el(env, "kb-type").value = "bug"; el(env, "kb-module").value = ""; el(env, "kb-status").value = "todo";
  env.els[view].handlers.submit({ preventDefault() {} });
  assert.match(el(env, "kb-formmsg").textContent, /au moins 3 caractères/);
  assert.equal(calls(server, "POST").length, 0);
  el(env, "kb-title").value = "Tester sur mobile";
  env.els[view].handlers.submit({ preventDefault() {} });
  await wait(30);
  assert.equal(calls(server, "POST").length, 1);
  assert.deepEqual(calls(server, "POST")[0].body, { title: "Tester sur mobile", description: "", priority: "P0", type: "bug", module: "", status: "todo" });
  assert.match(env.els[view].innerHTML, /Tester sur mobile/);
  assert.match(env.els[view].innerHTML, /Historique du ticket/, "le ticket créé reste ouvert");
});

test("tableau : modifier un ticket et changer sa colonne dans le formulaire", async () => {
  const server = fakeServer();
  seed(server);
  const env = await open(server);
  click(env, view, "[data-open]", "tseed00001");
  assert.match(env.els[view].innerHTML, /value="Corriger le menu"/);
  el(env, "kb-title").value = "Corriger le menu principal"; el(env, "kb-desc").value = "Nouvelle description"; el(env, "kb-prio").value = "P0"; el(env, "kb-type").value = "bug"; el(env, "kb-module").value = "MainMenu"; el(env, "kb-status").value = "doing";
  env.els[view].handlers.submit({ preventDefault() {} });
  await wait(40);
  assert.deepEqual(calls(server, "PATCH")[0].body, { title: "Corriger le menu principal", description: "Nouvelle description", priority: "P0", type: "bug", module: "MainMenu" });
  assert.deepEqual(calls(server, "POST").map((c) => c.body), [{ status: "doing" }]);
  assert.match(env.els[view].innerHTML, /<h3>En cours <span class="tag">1<\/span>/);
});

test("tableau : boutons ◀ ▶ ▲ ▼ déplacent le ticket (colonne voisine ou position), sans effet aux bords", async () => {
  const server = fakeServer();
  seed(server);
  seed(server, { id: "tseed00002", title: "Second", position: 1 });
  const env = await open(server);
  click(env, view, "[data-mv]", "tseed00001|right");
  await wait(30);
  assert.deepEqual(calls(server, "POST")[0].body, { status: "doing" });
  assert.match(env.els[view].innerHTML, /<h3>En cours <span class="tag">1<\/span>/);
  click(env, view, "[data-mv]", "tseed00001|left");
  await wait(30);
  click(env, view, "[data-mv]", "tseed00001|up"); // après le retour en À faire, il est en seconde position
  await wait(30);
  const last = calls(server, "POST").pop().body;
  assert.equal(last.status, "todo");
  assert.equal(typeof last.index, "number");
  const before = calls(server, "POST").length;
  click(env, view, "[data-mv]", "tseed00002|left"); // déjà dans la première colonne
  click(env, view, "[data-mv]", "tseed00001|up"); // déjà en tête
  await wait(20);
  assert.equal(calls(server, "POST").length, before);
  assert.match(env.els[view].innerHTML, /aria-label="Déplacer « Second » vers « En cours »"/);
  assert.doesNotMatch(env.els[view].innerHTML, /vers « À faire »/);
});

test("tableau : glisser-déposer envoie la colonne d'arrivée ; déposer sans glisser ne fait rien", async () => {
  const server = fakeServer();
  seed(server);
  const env = await open(server);
  const zone = (col) => ({ closest: (s) => (s === "[data-col]" ? { getAttribute: () => col, querySelectorAll: () => [] } : null) });
  env.els[view].handlers.drop({ target: zone("done"), preventDefault() {}, clientY: 10 });
  await wait(20);
  assert.equal(calls(server, "POST").length, 0, "aucun glissement en cours");
  env.els[view].handlers.dragstart({ target: { closest: (s) => (s === "[data-ticket]" ? { getAttribute: () => "tseed00001" } : null) }, dataTransfer: { setData() {} } });
  let prevented = false;
  env.els[view].handlers.dragover({ target: zone("done"), preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  env.els[view].handlers.drop({ target: zone("done"), preventDefault() {}, clientY: 10 });
  await wait(30);
  assert.deepEqual(calls(server, "POST")[0].body, { status: "done", index: 0 });
  assert.match(env.els[view].innerHTML, /<h3>Terminé <span class="tag">1<\/span>/);
  env.els[view].handlers.drop({ target: zone("todo"), preventDefault() {}, clientY: 10 });
  await wait(10);
  assert.equal(calls(server, "POST").length, 1, "un seul dépôt par glissement");
});

test("tableau : retours — ajout, refus d'un retour vide, suppression ; l'historique du ticket se met à jour", async () => {
  const server = fakeServer();
  seed(server);
  const env = await open(server);
  click(env, view, "[data-open]", "tseed00001");
  el(env, "kb-ctext").value = "   ";
  click(env, view, "#kb-cadd", "x");
  assert.match(el(env, "kb-cmsg").textContent, /Écris ton retour/);
  assert.equal(calls(server, "POST").length, 0);
  el(env, "kb-ctext").value = "Toujours coupé sur téléphone";
  click(env, view, "#kb-cadd", "x");
  await wait(30);
  const html = env.els[view].innerHTML;
  assert.match(html, /Toujours coupé sur téléphone/);
  assert.match(html, /Retours <span class="tag">1<\/span>/);
  assert.match(html, /Retour ajouté : Toujours coupé/);
  click(env, view, "[data-delcomment]", server.state.tickets[0].comments[0].id);
  await wait(30);
  assert.match(env.els[view].innerHTML, /Aucun retour pour l&#39;instant|Aucun retour pour l'instant/);
});

test("tableau : suppression en deux clics, filtres par recherche, type et priorité", async () => {
  const server = fakeServer();
  seed(server);
  seed(server, { id: "tseed00002", title: "Ajouter un son", type: "idee", priority: "P3", module: "Audio", position: 1 });
  const env = await open(server);
  env.els[view].handlers.input({ target: { id: "kb-q", value: "son" } });
  assert.doesNotMatch(env.els[view].innerHTML, /data-open="tseed00001"/);
  assert.match(env.els[view].innerHTML, /data-open="tseed00002"/);
  assert.match(env.els[view].innerHTML, /<h3>À faire <span class="tag">1\/2<\/span>/);
  env.els[view].handlers.input({ target: { id: "kb-q", value: "" } });
  env.els[view].handlers.change({ target: { id: "kb-ftype", value: "bug" } });
  assert.doesNotMatch(env.els[view].innerHTML, /data-open="tseed00002"/);
  env.els[view].handlers.change({ target: { id: "kb-ftype", value: "" } });
  env.els[view].handlers.change({ target: { id: "kb-fprio", value: "P3" } });
  assert.match(env.els[view].innerHTML, /data-open="tseed00002"/);
  assert.doesNotMatch(env.els[view].innerHTML, /data-open="tseed00001"/);
  env.els[view].handlers.change({ target: { id: "kb-fprio", value: "" } });
  env.els[view].handlers.input({ target: { id: "kb-q", value: "introuvable" } });
  assert.match(env.els[view].innerHTML, /Aucun ticket ne correspond au filtre/);
  env.els[view].handlers.input({ target: { id: "kb-q", value: "" } });

  click(env, view, "[data-open]", "tseed00002");
  click(env, view, "[data-delticket]", "tseed00002");
  assert.equal(server.state.tickets.length, 2, "un seul clic ne supprime rien");
  assert.match(env.els[view].innerHTML, /Confirmer \?/);
  click(env, view, "[data-delticket]", "tseed00002");
  await wait(30);
  assert.equal(server.state.tickets.length, 1);
  assert.doesNotMatch(env.els[view].innerHTML, /data-open="tseed00002"/);
});

test("tableau : un refus du serveur est affiché, le tableau reste utilisable ; serveur arrêté => message clair", async () => {
  const server = fakeServer();
  seed(server);
  const env = await open(server);
  server.state.storageDown = true;
  click(env, view, "[data-mv]", "tseed00001|right");
  await wait(30);
  assert.match(env.els[view].innerHTML, /Action refusée/);
  assert.match(env.els[view].innerHTML, /data-open="tseed00001"/);
  const down = fakeServer();
  down.state.storageDown = true;
  const env2 = await open(down);
  assert.match(env2.els[view].innerHTML, /Lecture du tableau impossible/);
  assert.match(env2.els["view-journal"].innerHTML, /Lecture du tableau impossible|Chargement/);
});

// ----- journaux ----------------------------------------------------------------------------------------------------------------
const jv = "view-journal";
const jclick = (env, selector, value) => env.els[jv].handlers.click(target(selector, value));
function jchoose(env, key, value) {
  const select = el(env, "j-choice-" + key); select.value = value;
  select.setAttribute("data-jchoice", key);
  env.els[jv].handlers.input({ target: select });
  assert.equal(env.els["j-choice-choice-" + key], undefined, "un événement input du sélecteur ne doit pas chercher un champ de saisie");
  env.els[jv].handlers.change({ target: select });
}

test("journal : toutes les rubriques proposent un sélecteur et une saisie libre pour chaque champ", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: (url, init) => {
    if (url === "/api/schema") return server.fetchImpl(url, init).then(r => r.json()).then(data => ok({ ...data, journal: SCHEMAS }));
    if (url.startsWith("/api/journal/")) return ok([]);
    return server.fetchImpl(url, init);
  } });
  await wait(60);
  for (const schema of SCHEMAS) {
    jclick(env, "[data-jcoll]", schema.id); await wait();
    jclick(env, "[data-jnew]", "1");
    const html = env.els[jv].innerHTML;
    for (const fd of schema.fields) {
      assert.ok(html.includes('<select id="j-choice-' + fd.key + '"'), schema.id + "." + fd.key);
      assert.ok(html.includes('id="j-custom-' + fd.key + '"'), "saisie libre " + schema.id + "." + fd.key);
    }
    assert.equal((html.match(/Autre… \(écrire une valeur\)/g) || []).length, schema.fields.length);
    if (schema.id === "images") { assert.match(html, /assets\/ui\/logo.png/); assert.match(html, /rbxassetid:\/\/1/); }
    if (schema.id === "playtests") assert.match(html, /réaction en chaîne|partie pendant une manche/);
  }
});

test("journal : les propositions enregistrent leurs valeurs typées et Autre ouvre le champ sans perdre le brouillon", async () => {
  const server = fakeServer(), env = await open(server);
  jclick(env, "[data-jnew]", "1");
  jchoose(env, "date", "2026-11-04");
  jchoose(env, "scenario", "Tester le mode solo avec des bots");
  jchoose(env, "players", "3"); jchoose(env, "result", "ok"); jchoose(env, "done", "true");
  assert.equal(el(env, "j-scenario").value, "Tester le mode solo avec des bots");
  assert.equal(el(env, "j-custom-scenario").hidden, true);
  jchoose(env, "scenario", "__custom__");
  assert.equal(el(env, "j-custom-scenario").hidden, false);
  assert.equal(el(env, "j-scenario").focused, true);
  el(env, "j-scenario").value = "Déconnexion simultanée de deux bots";
  env.els[jv].handlers.input({ target: el(env, "j-scenario") });
  jchoose(env, "scenario", "Inviter un ami"); jchoose(env, "scenario", "__custom__");
  assert.equal(el(env, "j-scenario").value, "Déconnexion simultanée de deux bots");
  jchoose(env, "done", "__custom__"); el(env, "j-free-done").value = "non";
  env.els[jv].handlers.submit({ preventDefault() {} }); await wait(30);
  const body = calls(server, "POST").pop().body;
  assert.equal(body.scenario, "Déconnexion simultanée de deux bots");
  assert.equal(body.players, 3); assert.equal(body.done, false); assert.equal(body.result, "ok");
});

test("journal : rubriques proposées, rubrique vide, formulaire généré depuis le schéma (types, listes, facultatifs)", async () => {
  const env = await open(fakeServer());
  const html = env.els[jv].innerHTML;
  assert.match(html, /data-jcoll="playtests" aria-pressed="true"/);
  assert.match(html, /data-jcoll="decisions"/);
  assert.match(html, /data-jcoll="activity"/);
  assert.match(html, /Couverture des tests/);
  assert.match(html, /Aucune entrée pour l'instant/);
  jclick(env, "[data-jnew]", "1");
  const form = env.els[jv].innerHTML;
  assert.match(form, /Nouvelle entrée/);
  assert.match(form, /id="j-date" type="date" value="\d{4}-\d{2}-\d{2}"/);
  assert.match(form, /<option value="ok">Réussi<\/option>/);
  assert.match(form, /Joueurs \(facultatif\)/);
  assert.match(form, /<textarea id="j-notes"/);
  assert.match(form, /id="j-done" style/);
});

test("journal : ajouter, modifier, supprimer une entrée ; champs vides facultatifs non envoyés", async () => {
  const server = fakeServer();
  const env = await open(server);
  jclick(env, "[data-jnew]", "1");
  el(env, "j-date").value = "2026-11-04"; el(env, "j-scenario").value = "2 clients Studio"; el(env, "j-result").value = "ok"; el(env, "j-players").value = "2"; el(env, "j-notes").value = ""; el(env, "j-done").checked = true;
  env.els[jv].handlers.submit({ preventDefault() {} });
  await wait(30);
  assert.deepEqual(calls(server, "POST").pop().body, { date: "2026-11-04", scenario: "2 clients Studio", result: "ok", players: 2, done: true });
  assert.match(env.els[jv].innerHTML, /2 clients Studio/);
  assert.match(env.els[jv].innerHTML, /Réussi/);
  assert.match(env.els[jv].innerHTML, /Entrée enregistrée/);
  const id = server.state.journal.playtests[0].id;
  jclick(env, "[data-jedit]", id);
  assert.match(env.els[jv].innerHTML, /Modifier l'entrée/);
  assert.match(env.els[jv].innerHTML, /value="2 clients Studio"/);
  el(env, "j-result").value = "ko"; el(env, "j-scenario").value = "2 clients Studio"; el(env, "j-players").value = "";
  env.els[jv].handlers.submit({ preventDefault() {} });
  await wait(30);
  assert.equal(server.state.journal.playtests[0].result, "ko");
  assert.equal(server.state.journal.playtests[0].players, undefined);
  jclick(env, "[data-jdel]", id);
  assert.equal(server.state.journal.playtests.length, 1, "un clic ne supprime rien");
  jclick(env, "[data-jdel]", id);
  await wait(30);
  assert.equal(server.state.journal.playtests.length, 0);
  assert.match(env.els[jv].innerHTML, /Entrée supprimée/);
});

test("journal : un refus du serveur est affiché dans le formulaire sans le fermer ; annuler le ferme", async () => {
  const server = fakeServer();
  server.state.journalRefuse = "Scénario testé : champ obligatoire";
  const env = await open(server);
  jclick(env, "[data-jnew]", "1");
  el(env, "j-scenario").value = ""; el(env, "j-result").value = "ok"; el(env, "j-date").value = "2026-11-04";
  env.els[jv].handlers.submit({ preventDefault() {} });
  await wait(30);
  assert.match(el(env, "jr-msg").textContent, /champ obligatoire/);
  assert.equal(el(env, "jr-save").disabled, false);
  assert.match(env.els[jv].innerHTML, /id="jr-form"/);
  jclick(env, "[data-jcancel]", "1");
  assert.doesNotMatch(env.els[jv].innerHTML, /id="jr-form"/);
});

test("journal : changer de rubrique charge ses entrées ; l'activité liste tout ce qui a été fait, du plus récent", async () => {
  const server = fakeServer();
  server.state.journal.decisions.push({ id: "jseed00001", createdAt: 1, updatedAt: 1, question: "Quel nom pour le jeu ?" });
  seed(server);
  const env = await open(server);
  jclick(env, "[data-jcoll]", "decisions");
  await wait(30);
  assert.match(env.els[jv].innerHTML, /Quel nom pour le jeu \?/);
  click(env, view, "[data-mv]", "tseed00001|right");
  await wait(30);
  jclick(env, "[data-jcoll]", "activity");
  await wait(30);
  const html = env.els[jv].innerHTML;
  assert.match(html, /Historique de tout ce qui a été fait/);
  assert.match(html, /Ticket déplacé<\/b> — Corriger le menu/);
});

test("journal : la couverture des tests montre l'évolution entre exécutions complètes et marque les exécutions partielles", async () => {
  const server = fakeServer();
  server.state.runs = [
    { startedAt: 3000, finishedAt: 3100, passed: 700, failed: 0, suites: 26, filter: "", trigger: "site", ok: true, failures: [] },
    { startedAt: 2500, finishedAt: 2600, passed: 12, failed: 0, suites: 1, filter: "GridService", trigger: "site", ok: true, failures: [] },
    { startedAt: 2000, finishedAt: 2100, passed: 665, failed: 0, suites: 25, filter: "", trigger: "demarrage", ok: true, failures: [] },
  ];
  const env = await open(server);
  jclick(env, "[data-jcoll]", "coverage");
  await wait(30);
  const html = env.els[jv].innerHTML;
  assert.match(html, /<td class="num">700<\/td><td class="num">\+35<\/td>/);
  assert.match(html, /<td class="num">665<\/td><td class="num">—<\/td>/);
  assert.match(html, /Partielle \(GridService\)/);
});

test("journal : entrées affichées échappées (aucune injection de HTML)", async () => {
  const server = fakeServer();
  server.state.journal.decisions.push({ id: "jseed00002", createdAt: 1, updatedAt: 1, question: "<script>alert(1)</script>" });
  const env = await open(server);
  jclick(env, "[data-jcoll]", "decisions");
  await wait(30);
  assert.doesNotMatch(env.els[jv].innerHTML, /<script>alert/);
  assert.match(env.els[jv].innerHTML, /&lt;script&gt;/);
});
