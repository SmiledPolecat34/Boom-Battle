"use strict";
// Test de bout en bout de la page locale générée : le vrai script (core.js + adapter-local.js) tourne dans un faux navigateur
// (éléments simulés, fetch simulé). Vérifie les 5 vues, le formulaire (identifiants automatiques, validation, envoi),
// l'assistant sans clé (mode local) et avec clé (appels Groq simulés, outils, brouillon).
const test = require("node:test");
const assert = require("node:assert/strict");
const { FAKE_KEY, boot, wait, ok, fakeServer, fillQuestForm } = require("./page-helpers");

test("page : les cinq vues se construisent avec les données", async () => {
  const server = fakeServer();
  const { els } = boot({ fetchImpl: server.fetchImpl });
  await wait();
  assert.match(els["view-tests"].innerHTML, /Tous les tests automatisés passent/);
  assert.match(els["view-tests"].innerHTML, /server\/Demo/);
  assert.match(els["view-donnees"].innerHTML, /Cosmétiques/);
  assert.match(els["view-assets"].innerHTML, /rbxassetid:\/\/1/);
  assert.match(els["view-contribuer"].innerHTML, /Identifiant \(automatique\)/);
  assert.doesNotMatch(els["view-contribuer"].innerHTML, /id="f-id"/, "l'identifiant ne se saisit pas");
  assert.match(els["view-assistant"].innerHTML, /Clé Groq|ai-settings/);
});

test("page : pas de bandeau d'erreur quand tout va bien, bandeau explicite quand la collecte a échoué", async () => {
  const healthy = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  assert.doesNotMatch(healthy.els["view-tests"].innerHTML, /role="alert"/);
  const broken = boot({ fetchImpl: fakeServer().fetchImpl, error: "Lune est introuvable : installe-le." });
  await wait();
  assert.match(broken.els["view-tests"].innerHTML, /role="alert">Lune est introuvable/);
});

test("formulaire : identifiant automatique et unique, envoi au serveur local, doublon suffixé", async () => {
  const server = fakeServer();
  const { els } = boot({ fetchImpl: server.fetchImpl });
  await wait();
  fillQuestForm(els, { name: "Démolisseur Pro", description: "Détruire 50 caisses", event: "crates_destroyed", goal: 50, reward: 120 });
  els["f-note"] = els["f-note"] || { value: "" };
  els["contrib-form"].handlers.input();
  assert.equal(els["auto-id"].textContent, "demolisseur_pro");
  els["contrib-form"].handlers.submit({ preventDefault() {} });
  await wait();
  const posted = server.calls.find((c) => c.method === "POST");
  assert.equal(posted.headers["X-Registre"], "1");
  const body = JSON.parse(posted.body);
  assert.equal(body.fields.id, "demolisseur_pro");
  assert.equal(body.type, "quest");
  assert.equal(body.status, "pending");
  assert.match(els["contrib-list"].innerHTML, /En attente/);

  fillQuestForm(els, { name: "Démolisseur Pro", description: "Détruire 50 caisses", event: "crates_destroyed", goal: 50, reward: 120 });
  els["f-note"] = els["f-note"] || { value: "" };
  els["contrib-form"].handlers.submit({ preventDefault() {} });
  await wait();
  assert.equal(JSON.parse(server.calls.filter((c) => c.method === "POST")[1].body).fields.id, "demolisseur_pro_2");
});

test("formulaire : une saisie invalide n'est jamais envoyée", async () => {
  const server = fakeServer();
  const { els } = boot({ fetchImpl: server.fetchImpl });
  await wait();
  fillQuestForm(els, { name: "", description: "x", event: "round_won", goal: 0, reward: -3 });
  els["f-note"] = els["f-note"] || { value: "" };
  els["contrib-form"].handlers.submit({ preventDefault() {} });
  await wait();
  assert.equal(server.calls.filter((c) => c.method === "POST").length, 0);
  assert.match(els["send-msg"].textContent, /Corrige/);
});

test("assistant sans clé : réponse locale avec la raison, brouillon de bombe déduit de la phrase", async () => {
  const server = fakeServer();
  const { els } = boot({ fetchImpl: server.fetchImpl });
  await wait();
  els["chat-input"].value = "Propose une nouvelle bombe dorée à 400 pièces";
  els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
  assert.match(els["msgs"].innerHTML, /Réponse locale, sans IA/);
  assert.match(els["msgs"].innerHTML, /aucune clé Groq/);
  assert.match(els["msgs"].innerHTML, /Ouvrir le brouillon/);
  assert.equal(server.calls.filter((c) => c.url.startsWith("https://api.groq.com/")).length, 0);
});

test("assistant avec clé : appel Groq, outil exécuté, brouillon proposé et ouvert dans Contribuer", async () => {
  const server = fakeServer();
  const replies = [
    { choices: [{ message: { content: "", tool_calls: [{ id: "t1", function: { name: "propose_addition", arguments: JSON.stringify({ type: "bomb", fields: { name: "Dorée", price: 400, color: "#d4af37", material: "Metal", description: "Une bombe dorée." }, note: "idée" }) } }] } }] },
    { choices: [{ message: { content: "Brouillon prêt." } }] },
  ];
  server.calls.groq = (url, init) => (url.endsWith("/models") ? ok({ data: [{ id: "llama-3.3-70b-versatile" }, { id: "whisper-large-v3" }] }) : ok(replies.shift()));
  const { els, sandbox } = boot({ session: { "registre.groqKey": FAKE_KEY }, fetchImpl: server.fetchImpl });
  await wait();
  els["chat-input"].value = "Propose une bombe dorée";
  els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(60);
  assert.match(els["msgs"].innerHTML, /Brouillon prêt/);
  assert.doesNotMatch(els["msgs"].innerHTML, /Réponse locale/);
  const chatCalls = server.calls.filter((c) => c.url.endsWith("/chat/completions"));
  assert.equal(chatCalls.length, 2);
  assert.equal(chatCalls[0].headers.Authorization, "Bearer " + FAKE_KEY);
  assert.ok(!els["view-assistant"].innerHTML.includes(FAKE_KEY), "la clé ne s'affiche jamais dans la page");
  const key = /data-draft="([^"]+)"/.exec(els["msgs"].innerHTML);
  assert.ok(key, "un bouton de brouillon est proposé");
  els["msgs"].handlers.click({ target: { closest: (s) => (s === "[data-draft]" ? { getAttribute: () => key[1] } : null) } });
  assert.equal(sandbox.location.hash, "contribuer");
});

test("assistant avec une clé refusée : message clair, pas de plantage", async () => {
  const server = fakeServer();
  server.calls.groq = (url) => (url.endsWith("/models") ? ok({ data: [] }) : Promise.resolve({ ok: false, status: 401, json: () => Promise.resolve({ error: { message: "Invalid API Key" } }) }));
  const { els } = boot({ session: { "registre.groqKey": FAKE_KEY }, fetchImpl: server.fetchImpl });
  await wait();
  els["chat-input"].value = "Bonjour";
  els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
  assert.match(els["msgs"].innerHTML, /refusée/);
});

test("assistant sans clé : « quelles couleurs dispos pour les bombes ? » et « quelles bombes ? » reçoivent une vraie réponse", async () => {
  const { els } = boot({ fetchImpl: fakeServer().fetchImpl });
  await wait();
  els["chat-input"].value = "Quelles couleurs dispos pour les bombes ?";
  els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
  assert.match(els["msgs"].innerHTML, /Couleurs des bombes \(2\)/);
  assert.match(els["msgs"].innerHTML, /Rouge : #c82828/);
  assert.doesNotMatch(els["msgs"].innerHTML, /Je n&#39;ai pas compris/);
  els["chat-input"].value = "Quelles bombes sont disponibles ?";
  els["chat-form"].handlers.submit({ preventDefault() {} });
  await wait(40);
  assert.match(els["msgs"].innerHTML, /Bombes de la boutique/);
  assert.match(els["msgs"].innerHTML, /250 pièces/);
});
