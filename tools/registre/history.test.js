"use strict";
// Historique des conversations (stockage du navigateur) et lancement des tests depuis la page, dans un faux navigateur.
const test = require("node:test");
const assert = require("node:assert/strict");
const { FAKE_KEY, T0, sampleData, boot, wait, ok, fakeServer } = require("./page-helpers");

const HISTORY_KEY = "registre.chats.v1";

async function say(env, text) {
  env.els["chat-input"].value = text;
  env.els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
}
const stored = (env) => JSON.parse(env.localStorage.getItem(HISTORY_KEY) || "[]");
const click = (env, id, attribute, value) => env.els[id].handlers.click({ target: { closest: (s) => (s === "[" + attribute + "]" ? { getAttribute: () => value } : null) } });

// ----- conversations ------------------------------------------------------------------------------------------------------

test("historique : une conversation est enregistrée dès la première question, avec titre, dates et messages", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  assert.deepEqual(stored(env), []);
  await say(env, "Résume l'état des tests");
  const list = stored(env);
  assert.equal(list.length, 1);
  assert.equal(list[0].title, "Résume l'état des tests");
  assert.equal(list[0].messages.length, 2); // question + réponse locale
  assert.equal(list[0].messages[0].role, "user");
  assert.ok(list[0].createdAt <= list[0].updatedAt);
  assert.match(env.els["history-list"].innerHTML, /Résume l&#39;état des tests/);
  assert.match(env.els["history-list"].innerHTML, /2 messages/);
});

test("historique : les messages suivants complètent la MÊME conversation", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  await say(env, "Liste les thèmes");
  const list = stored(env);
  assert.equal(list.length, 1);
  assert.equal(list[0].messages.length, 4);
});

test("historique : au rechargement, la dernière conversation est restaurée avec ses messages et son brouillon", async () => {
  const first = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  await say(first, "Propose une nouvelle bombe dorée à 400 pièces");
  const saved = first.localStorage.getItem(HISTORY_KEY);
  assert.ok(saved);

  const second = boot({ fetchImpl: fakeServer().fetchImpl, local: { [HISTORY_KEY]: saved } });
  await wait();
  assert.match(second.els["msgs"].innerHTML, /Propose une nouvelle bombe dorée/);
  assert.match(second.els["msgs"].innerHTML, /Ouvrir le brouillon/);
  const key = /data-draft="([^"]+)"/.exec(second.els["msgs"].innerHTML);
  second.els["msgs"].handlers.click({ target: { closest: (s) => (s === "[data-draft]" ? { getAttribute: () => key[1] } : null) } });
  assert.equal(second.sandbox.location.hash, "contribuer");
  assert.match(second.els["view-contribuer"].innerHTML, /Dorée/);
});

test("historique : nouvelle conversation, bascule entre conversations, suppression", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  env.els["chat-new"].handlers.click();
  assert.doesNotMatch(env.els["msgs"].innerHTML, /Résume l&#39;état/);
  await say(env, "Liste les thèmes");
  const list = stored(env);
  assert.equal(list.length, 2);
  assert.deepEqual(list.map((c) => c.title).sort(), ["Liste les thèmes", "Résume l'état des tests"]);

  const old = list.find((c) => c.title === "Résume l'état des tests");
  click(env, "history-list", "data-open", old.id);
  assert.match(env.els["msgs"].innerHTML, /Résume l&#39;état des tests/);
  assert.doesNotMatch(env.els["msgs"].innerHTML, /Liste les thèmes/);

  await say(env, "Quelles quêtes ?"); // la suite s'ajoute à la conversation rouverte
  assert.equal(stored(env).find((c) => c.id === old.id).messages.length, 4);
  assert.equal(stored(env).length, 2);

  click(env, "history-list", "data-delconv", old.id);
  assert.equal(stored(env).length, 1);
  assert.doesNotMatch(env.els["msgs"].innerHTML, /Résume l&#39;état des tests/);
});

test("historique : « Supprimer cette conversation » retire la conversation courante seulement", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  env.els["chat-new"].handlers.click();
  await say(env, "Liste les thèmes");
  env.els["chat-clear"].handlers.click();
  assert.deepEqual(stored(env).map((c) => c.title), ["Résume l'état des tests"]);
});

test("historique : « Tout effacer » demande une confirmation (2 clics)", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  await say(env, "Résume l'état des tests");
  env.els["history-clear"].handlers.click({ currentTarget: { textContent: "" } });
  assert.equal(stored(env).length, 1, "un seul clic n'efface rien");
  env.els["history-clear"].handlers.click({ currentTarget: { textContent: "" } });
  assert.deepEqual(stored(env), []);
});

test("historique : une clé collée dans une question n'est ni conservée ni envoyée à l'assistant", async () => {
  const server = fakeServer();
  let sent = "";
  server.calls.groq = (url, init) => {
    if (url.endsWith("/models")) return ok({ data: [{ id: "openai/gpt-oss-120b" }] });
    sent = init.body;
    return ok({ choices: [{ message: { content: "Compris." } }] });
  };
  const env = boot({ session: { "registre.groqKey": FAKE_KEY }, fetchImpl: server.fetchImpl });
  await wait();
  await say(env, "Voici ma clé " + "gsk_" + "C".repeat(40) + " tu peux l'utiliser ?");
  assert.ok(!sent.includes("C".repeat(40)), "la clé collée ne part pas vers l'assistant");
  assert.ok(!env.localStorage.getItem(HISTORY_KEY).includes("C".repeat(40)), "la clé collée n'est pas stockée");
  assert.match(env.localStorage.getItem(HISTORY_KEY), /clé masquée/);
});

test("historique : limites (30 conversations, 200 messages) et données corrompues ignorées", async () => {
  const conv = (i) => ({ id: "c" + i, title: "Conversation " + i, createdAt: i, updatedAt: i, messages: [{ role: "user", content: "x" }] });
  const many = Array.from({ length: 45 }, (_, i) => conv(i + 1));
  const withJunk = many.concat([{ id: 5 }, null, "x", { id: "z", title: "t", updatedAt: 1, messages: [{ role: "robot", content: "?" }] }]);
  const env = boot({ fetchImpl: fakeServer().fetchImpl, local: { [HISTORY_KEY]: JSON.stringify(withJunk) } });
  await wait();
  const html = env.els["history-list"].innerHTML;
  assert.equal((html.match(/data-open=/g) || []).length, 30);
  assert.match(html, /Conversation 45/); // les plus récentes d'abord
  assert.doesNotMatch(html, /Conversation 1</);
  const broken = boot({ fetchImpl: fakeServer().fetchImpl, local: { [HISTORY_KEY]: "{pas du json" } });
  await wait();
  assert.match(broken.els["history-list"].innerHTML, /Aucune conversation/);
});

test("historique : stockage du navigateur indisponible => message clair, le chat fonctionne quand même", async () => {
  const server = fakeServer();
  server.state.storageDown = true; // sans serveur de données non plus : seule la page reste
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  env.sandbox.window.localStorage.setItem = () => { throw new Error("quota"); };
  env.sandbox.window.localStorage.getItem = () => { throw new Error("bloqué"); };
  await say(env, "Résume l'état des tests");
  assert.match(env.els["msgs"].innerHTML, /tests/);
  assert.match(env.els["history-note"].textContent, /ne peut pas être conservé/);
});

// ----- tests lancés depuis la page ---------------------------------------------------------------------------------------

test("tests : dernière exécution avec date et heure, historique et bouton de lancement", async () => {
  const env = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  const html = env.els["view-tests"].innerHTML;
  assert.match(html, /Dernière exécution : <b>[^<]*2026/);
  assert.match(html, /Démarrage du serveur/);
  assert.match(html, /Tous les tests/);
  assert.match(html, /id="run-btn"/);
  assert.match(html, /<h3>Historique<\/h3>/);
});

test("tests : le bouton lance les tests, met à jour le bilan, l'historique et l'horodatage sans recharger la page", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  env.els["run-filter"] = { value: "" };
  env.els["run-btn"].handlers.click();
  await wait(30);
  assert.deepEqual(server.state.runBodies, [{ filter: "" }]);
  const post = server.calls.find((c) => c.url === "/api/tests/run");
  assert.equal(post.headers["X-Registre"], "1");
  const html = env.els["view-tests"].innerHTML;
  assert.ok(html.includes('<b class="num">3</b><span>tests réussis'), "le bilan affiche le résultat du nouveau lancement");
  assert.equal((html.match(/<td class="num">/g) || []).length, 2, "deux lignes d'historique : le démarrage et le lancement depuis le site");
  assert.match(html, /Site<\/td>/);
  assert.match(html, /Terminé à/);
});

test("tests : un lancement filtré est signalé comme partiel", async () => {
  const server = fakeServer();
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  env.els["run-filter"] = { value: "GridService" };
  env.els["run-btn"].handlers.click();
  await wait(30);
  assert.deepEqual(server.state.runBodies, [{ filter: "GridService" }]);
  const html = env.els["view-tests"].innerHTML;
  assert.match(html, /Suite « GridService » \(partielle\)/);
  assert.match(html, /Exécution partielle/);
});

test("tests : une erreur du serveur (Lune absent, délai, filtre sans résultat) est affichée, le bouton redevient actif", async () => {
  const server = fakeServer();
  server.state.runError = "Aucune suite ne correspond à « zzz ».";
  const env = boot({ fetchImpl: server.fetchImpl });
  await wait();
  env.els["run-filter"] = { value: "zzz" };
  env.els["run-btn"].handlers.click();
  await wait(30);
  assert.match(env.els["run-msg"].textContent, /Aucune suite ne correspond/);
  assert.equal(env.els["run-btn"].disabled, false);
});

test("tests : sans exécution enregistrée, la page le dit ; un échec est visible dans l'historique", async () => {
  const none = boot({ fetchImpl: fakeServer().fetchImpl, data: Object.assign(sampleData(), { runs: [] }) });
  await wait();
  assert.match(none.els["view-tests"].innerHTML, /Aucune exécution enregistrée/);
  const data = sampleData();
  data.runs = [{ startedAt: T0, finishedAt: T0 + 1000, durationMs: 1000, passed: 5, failed: 2, suites: 1, filter: "", trigger: "site", ok: false, failures: [] }];
  const failing = boot({ fetchImpl: fakeServer().fetchImpl, data });
  await wait();
  assert.match(failing.els["view-tests"].innerHTML, /status-pill rejected">Échec/);
  assert.match(failing.els["view-tests"].innerHTML, /color:var\(--bad\)/);
});
