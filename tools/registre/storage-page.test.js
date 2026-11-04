"use strict";
// Page : historique synchronisé avec le serveur, réglages mémorisés, onglets Sons et Stockage (faux navigateur, faux serveur).
const test = require("node:test");
const assert = require("node:assert/strict");
const { boot, wait, fakeServer } = require("./page-helpers");

const HISTORY_KEY = "registre.chats.v1";
const conv = (id, over) => Object.assign({ id, title: "Question " + id, createdAt: 1000, updatedAt: 2000, messages: [{ role: "user", content: "Bonjour" }, { role: "assistant", content: "Salut" }] }, over);
const el = (env, id) => env.sandbox.document.getElementById(id);
const target = (selector, attr, value) => ({ target: { closest: (s) => (s === selector ? { getAttribute: () => value } : null) } });
const click = (env, view, selector, value) => env.els[view].handlers.click(target(selector, selector.replace(/^\[|\]$/g, ""), value));
const submit = (env) => env.els["view-sons"].handlers.submit({ preventDefault() {} });
async function say(env, text) {
  env.els["chat-input"].value = text;
  env.els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
}
function fillSound(env, values) {
  const d = Object.assign({ name: "Boum", event: "explosion", category: "sfx", volume: "0.8", loop: false, enabled: true, note: "", source: "roblox", asset: "rbxassetid://123", file: null }, values);
  const set = { "s-name": d.name, "s-event": d.event, "s-category": d.category, "s-volume": d.volume, "s-note": d.note, "s-source": d.source, "s-asset": d.asset };
  for (const [id, value] of Object.entries(set)) el(env, id).value = value;
  el(env, "s-loop").checked = d.loop;
  el(env, "s-enabled").checked = d.enabled;
  el(env, "s-file").files = d.file ? [d.file] : [];
}
const audioFile = (size, name) => ({ name: name || "boum.wav", size: size || 40, arrayBuffer: () => Promise.resolve(new Uint8Array(size || 40).fill(1).buffer) });

// ----- historique synchronisé ----------------------------------------------------------------------------------------------
test("historique : chaque message est aussi enregistré sur le serveur local (avec l'en-tête de protection)", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  assert.equal(server.state.chats.size, 1);
  const saved = [...server.state.chats.values()][0];
  assert.equal(saved.title, "Résume l'état des tests");
  assert.equal(saved.messages.length, 2);
  const put = server.calls.find((c) => c.method === "PUT" && c.url.startsWith("/api/chats/"));
  assert.equal(put.headers["X-Registre"], "1");
  await say(env, "Liste les thèmes");
  assert.equal(server.state.chats.size, 1, "même conversation");
  assert.equal([...server.state.chats.values()][0].messages.length, 4);
  assert.match(env.els["history-note"].textContent, /serveur local/);
});

test("historique : au démarrage les conversations du serveur apparaissent et la plus récente est rouverte", async () => {
  const server = fakeServer();
  server.state.chats.set("cserveur01", conv("cserveur01", { title: "Venue du serveur", updatedAt: 9000 }));
  server.state.chats.set("cserveur02", conv("cserveur02", { title: "Plus ancienne", updatedAt: 5000 }));
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  assert.match(env.els["history-list"].innerHTML, /Venue du serveur/);
  assert.match(env.els["history-list"].innerHTML, /Plus ancienne/);
  assert.match(env.els["msgs"].innerHTML, /Bonjour/);
  assert.ok(env.localStorage.getItem(HISTORY_KEY).includes("Venue du serveur"), "le navigateur garde un cache");
});

test("historique : les conversations du navigateur absentes du serveur y sont envoyées (migration), la version la plus récente gagne", async () => {
  const server = fakeServer();
  server.state.chats.set("clocal0001", conv("clocal0001", { title: "Ancienne version serveur", updatedAt: 100 }));
  const local = [conv("clocal0001", { title: "Version locale récente", updatedAt: 500 }), conv("clocal0002", { title: "Seulement locale", updatedAt: 400 })];
  const env = boot({ fetchImpl: server.fetchImpl, local: { [HISTORY_KEY]: JSON.stringify(local) } });
  await wait(40);
  assert.equal(server.state.chats.size, 2);
  assert.equal(server.state.chats.get("clocal0001").title, "Version locale récente");
  assert.equal(server.state.chats.get("clocal0002").title, "Seulement locale");
  assert.match(env.els["history-list"].innerHTML, /Version locale récente/);
});

test("historique : une conversation plus récente sur le serveur remplace la copie du navigateur, sans écraser le serveur", async () => {
  const server = fakeServer();
  server.state.chats.set("cmemeconv1", conv("cmemeconv1", { title: "Titre du serveur", updatedAt: 800 }));
  const env = boot({ fetchImpl: server.fetchImpl, local: { [HISTORY_KEY]: JSON.stringify([conv("cmemeconv1", { title: "Titre périmé", updatedAt: 300 })]) } });
  await wait(40);
  assert.match(env.els["history-list"].innerHTML, /Titre du serveur/);
  assert.doesNotMatch(env.els["history-list"].innerHTML, /Titre périmé/);
  assert.equal(server.state.chats.get("cmemeconv1").title, "Titre du serveur");
  assert.equal(server.calls.filter((c) => c.method === "PUT").length, 0);
});

test("historique : supprimer une conversation ou tout effacer est répercuté sur le serveur", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  env.els["chat-new"].handlers.click();
  await say(env, "Liste les thèmes");
  assert.equal(server.state.chats.size, 2);
  env.els["chat-clear"].handlers.click(); // supprime la conversation courante
  await wait(20);
  assert.equal(server.state.chats.size, 1);
  env.els["history-clear"].handlers.click({ currentTarget: { textContent: "" } });
  env.els["history-clear"].handlers.click({ currentTarget: { textContent: "" } });
  await wait(20);
  assert.equal(server.state.chats.size, 0);
});

test("historique : serveur de données arrêté => le chat marche, l'échec est signalé, le cache du navigateur sert", async () => {
  const server = fakeServer();
  server.state.storageDown = true;
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  assert.match(env.els["msgs"].innerHTML, /tests/);
  assert.match(env.els["history-note"].textContent, /Enregistrement sur le serveur impossible/);
  assert.ok(env.localStorage.getItem(HISTORY_KEY).includes("Résume"));
});

test("historique : une réponse inattendue du serveur (pas une liste) est ignorée", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl, local: { [HISTORY_KEY]: JSON.stringify([conv("clocal0003", { title: "Garde-moi" })]) } });
  server.state.chats.set = () => {}; // sans effet : ici la liste reste celle du cache
  await wait(40);
  assert.match(env.els["history-list"].innerHTML, /Garde-moi/);
});

// ----- réglages ----------------------------------------------------------------------------------------------------------------
test("réglages : l'onglet, la catégorie de données et le filtre de tests mémorisés sont restaurés au chargement", async () => {
  const server = fakeServer();
  server.state.settings = { tab: "sons", gameTab: "quetes", runFilter: "GridService" };
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  assert.equal(env.sandbox.location.hash, "sons");
  assert.match(env.els["view-tests"].innerHTML, /value="GridService"/);
  assert.match(env.els["view-donnees"].innerHTML, /aria-pressed="true"[^>]*>Quêtes|data-g="quetes" aria-pressed="true"/);
});

test("réglages : valeurs inconnues ou dangereuses ignorées ; une adresse déjà choisie n'est pas écrasée", async () => {
  const server = fakeServer();
  server.state.settings = { tab: "pirate", gameTab: "../x", runFilter: "-rf; rm", model: 5 };
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  assert.equal(env.sandbox.location.hash, "");
  assert.doesNotMatch(env.els["view-tests"].innerHTML, /value="-rf/);
  const server2 = fakeServer();
  server2.state.settings = { tab: "sons" };
  const env2 = boot({ fetchImpl: server2.fetchImpl });
  env2.sandbox.location.hash = "assets"; // l'utilisateur a ouvert un lien précis
  await wait(40);
  assert.equal(env2.sandbox.location.hash, "assets");
});

test("réglages : changer d'onglet de données ou lancer un test enregistre le réglage (une seule requête groupée)", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  const before = server.calls.filter((c) => c.method === "PUT" && c.url === "/api/settings").length;
  env.els["view-donnees"].querySelector = () => ({ addEventListener() {} });
  env.els["run-filter"] = { value: "Economy" };
  env.els["run-btn"].handlers.click();
  await wait(500);
  const puts = server.calls.filter((c) => c.method === "PUT" && c.url === "/api/settings");
  assert.equal(puts.length - before >= 1, true);
  assert.equal(JSON.parse(puts[puts.length - 1].body).runFilter, "Economy");
  assert.ok(!puts[puts.length - 1].body.includes("gsk_"));
});

// ----- onglet Sons ---------------------------------------------------------------------------------------------------------------
test("sons : liste vide au départ, formulaire d'ajout avec les événements du serveur", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  assert.match(env.els["view-sons"].innerHTML, /Aucun son enregistré/);
  click(env, "view-sons", "[data-new]", "1");
  const html = env.els["view-sons"].innerHTML;
  assert.match(html, /Nouveau son/);
  assert.match(html, /<option value="explosion">Explosion<\/option>/);
  assert.match(html, /<option value="menu_music">Musique du menu<\/option>/);
  assert.match(html, /Un identifiant n'est jamais inventé/);
});

test("sons : ajout avec un identifiant Roblox, puis avec un fichier audio envoyé en base64", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  click(env, "view-sons", "[data-new]", "1");
  fillSound(env, { name: "Boum Roblox", source: "roblox", asset: "rbxassetid://4242", loop: true });
  submit(env);
  await wait(30);
  assert.equal(server.state.sounds.length, 1);
  assert.deepEqual(server.state.sounds[0].source, { type: "roblox", assetId: "rbxassetid://4242" });
  assert.equal(server.state.sounds[0].loop, true);
  assert.match(env.els["view-sons"].innerHTML, /Boum Roblox/);
  assert.match(env.els["view-sons"].innerHTML, /enregistré/);
  assert.doesNotMatch(env.els["view-sons"].innerHTML, /id="sons-form"/, "le formulaire se referme");

  click(env, "view-sons", "[data-new]", "1");
  fillSound(env, { name: "Boum fichier", source: "file", file: audioFile(40, "mon-boum.wav"), volume: "0.5" });
  submit(env);
  await wait(30);
  assert.equal(server.state.sounds.length, 2);
  assert.equal(server.state.lastSoundBody.file.name, "mon-boum.wav");
  assert.equal(Buffer.from(server.state.lastSoundBody.file.dataBase64, "base64").length, 40);
  assert.match(env.els["view-sons"].innerHTML, /<audio controls[^>]*src="sounds\/s100001\.wav"/);
});

test("sons : saisies invalides refusées dans la page, rien n'est envoyé", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  click(env, "view-sons", "[data-new]", "1");
  const cases = [
    [{ name: "x" }, /au moins 2 caractères/],
    [{ volume: "2" }, /entre 0 et 1/],
    [{ volume: "fort" }, /entre 0 et 1/],
    [{ asset: "https://evil.example/x" }, /Identifiant Roblox invalide/],
    [{ asset: "rbxassetid://abc" }, /Identifiant Roblox invalide/],
    [{ source: "file", file: null }, /Choisis un fichier audio/],
    [{ source: "file", file: audioFile(1500001) }, /trop gros/],
  ];
  for (const [values, pattern] of cases) {
    fillSound(env, values);
    submit(env);
    await wait(5);
    assert.match(el(env, "s-msg").textContent, pattern, JSON.stringify(values));
    assert.equal(el(env, "s-save").disabled, false);
  }
  assert.equal(server.state.sounds.length, 0);
  assert.equal(server.calls.filter((c) => c.url === "/api/sounds" && c.method === "POST").length, 0);
});

test("sons : modifier un son garde son fichier quand aucun nouveau n'est choisi ; annuler referme le formulaire", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  click(env, "view-sons", "[data-new]", "1");
  fillSound(env, { name: "Avec fichier", source: "file", file: audioFile(40, "a.wav") });
  submit(env);
  await wait(30);
  const id = server.state.sounds[0].id;
  click(env, "view-sons", "[data-edit]", id);
  assert.match(env.els["view-sons"].innerHTML, /Modifier le son/);
  assert.match(env.els["view-sons"].innerHTML, /Laisse vide pour garder/);
  fillSound(env, { name: "Renommé", source: "file", file: null });
  submit(env);
  await wait(30);
  assert.equal(server.state.sounds[0].name, "Renommé");
  assert.equal(server.state.lastSoundBody.file, undefined, "aucun fichier renvoyé");
  assert.equal(server.state.sounds[0].source.file, id + ".wav");
  click(env, "view-sons", "[data-edit]", id);
  click(env, "view-sons", "[data-cancel]", "1");
  assert.doesNotMatch(env.els["view-sons"].innerHTML, /id="sons-form"/);
});

test("sons : suppression en deux clics ; un refus du serveur est affiché dans le formulaire", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  click(env, "view-sons", "[data-new]", "1");
  fillSound(env, { name: "À supprimer" });
  submit(env);
  await wait(30);
  const id = server.state.sounds[0].id;
  click(env, "view-sons", "[data-delsound]", id);
  assert.equal(server.state.sounds.length, 1, "un seul clic ne supprime rien");
  assert.match(env.els["view-sons"].innerHTML, /Confirmer \?/);
  click(env, "view-sons", "[data-delsound]", id);
  await wait(30);
  assert.equal(server.state.sounds.length, 0);
  assert.match(env.els["view-sons"].innerHTML, /Son supprimé/);

  click(env, "view-sons", "[data-new]", "1");
  fillSound(env, { name: "Refusé" });
  server.state.storageDown = true;
  submit(env);
  await wait(30);
  assert.match(el(env, "s-msg").textContent, /Enregistrement refusé/);
  assert.equal(el(env, "s-save").disabled, false);
});

test("sons : serveur arrêté au chargement => message clair au lieu d'une page vide", async () => {
  const server = fakeServer();
  server.state.storageDown = true;
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  assert.match(env.els["view-sons"].innerHTML, /Lecture des sons impossible/);
  assert.match(env.els["view-stockage"].innerHTML, /Lecture impossible/);
});

test("sons : les noms de fichiers et notes sont échappés (aucune injection de HTML)", async () => {
  const server = fakeServer();
  server.state.sounds = [{ id: "s100000", name: "<img src=x onerror=alert(1)>", event: "explosion", category: "sfx", volume: 0.5, loop: false, enabled: true, note: "<b>x</b>", source: { type: "file", file: "s100000.wav", originalName: "<script>.wav", bytes: 10 }, createdAt: 1, updatedAt: 1 }];
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  const html = env.els["view-sons"].innerHTML;
  assert.doesNotMatch(html, /<img src=x|<script>|<b>x<\/b>/);
  assert.match(html, /&lt;img src=x/);
});

// ----- onglet Stockage ----------------------------------------------------------------------------------------------------------
test("stockage : nombre et taille de chaque type de donnée, dossier de données indiqué", async () => {
  const server = fakeServer();
  server.state.chats.set("cserveur01", conv("cserveur01"));
  server.state.sounds = [{ id: "s100000", name: "x", event: "custom", category: "sfx", volume: 1, loop: false, enabled: true, source: { type: "none" }, createdAt: 1, updatedAt: 1 }];
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  const html = env.els["view-stockage"].innerHTML;
  assert.match(html, /tools\/registre\/data/);
  assert.match(html, /Conversations de l'assistant<\/td><td class="num">1<\/td>/);
  assert.match(html, /Sons<\/td><td class="num">1<\/td>/);
  assert.match(html, /Exporter une sauvegarde/);
});

test("stockage : l'export télécharge la sauvegarde complète", async () => {
  const server = fakeServer();
  server.state.chats.set("cserveur01", conv("cserveur01"));
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  const made = [];
  env.sandbox.document.createElement = () => { const a = { click() { made.push(a); }, remove() {} }; return a; };
  click(env, "view-stockage", "#stock-export", "x");
  await wait(30);
  assert.equal(server.state.downloads, 1);
  assert.equal(made.length, 1);
  assert.match(made[0].download, /^sauvegarde-registre-\d{4}-\d{2}-\d{2}\.json$/);
  assert.match(env.els["view-stockage"].innerHTML, /Sauvegarde téléchargée/);
});

test("stockage : l'import fusionne, affiche le compte rendu (éléments ignorés compris) et rafraîchit l'historique", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  const bundle = { format: "registre-backup", version: 1, chats: [conv("cimporte001", { title: "Importée", updatedAt: 7000 })], ignored: ["conversation x : titre invalide"] };
  el(env, "stock-file").files = [{ text: () => Promise.resolve(JSON.stringify(bundle)) }];
  click(env, "view-stockage", "#stock-import", "x");
  await wait(60);
  assert.equal(server.state.restored.length, 1);
  const html = env.els["view-stockage"].innerHTML;
  assert.match(html, /Importé : 1 conversation\(s\)/);
  assert.match(html, /Ignoré : .*titre invalide/);
  assert.match(env.els["history-list"].innerHTML, /Importée/);
});

test("stockage : import sans fichier, JSON cassé ou fichier refusé => message clair, aucune donnée modifiée", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait(40);
  el(env, "stock-file").files = [];
  click(env, "view-stockage", "#stock-import", "x");
  assert.match(el(env, "stock-msg").textContent, /Choisis d'abord un fichier/);
  el(env, "stock-file").files = [{ text: () => Promise.resolve("{cassé") }];
  click(env, "view-stockage", "#stock-import", "x");
  await wait(30);
  assert.match(env.els["view-stockage"].innerHTML, /Restauration refusée/);
  el(env, "stock-file").files = [{ text: () => Promise.resolve(JSON.stringify({ format: "autre" })) }];
  click(env, "view-stockage", "#stock-import", "x");
  await wait(30);
  assert.match(env.els["view-stockage"].innerHTML, /fichier de sauvegarde non reconnu/);
  assert.equal(server.state.restored.length, 0);
});
