"use strict";
// Tests de l'adaptateur Groq (adapter-local.js) dans un contexte isolé : fetch simulé, aucun réseau, aucune vraie clé.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const SOURCE = fs.readFileSync(path.join(__dirname, "adapter-local.js"), "utf8");
const FAKE_KEY = "gsk_" + "A".repeat(40);

function memoryStorage(initial) {
  const data = new Map(Object.entries(initial || {}));
  return { getItem: (k) => (data.has(k) ? data.get(k) : null), setItem: (k, v) => data.set(k, String(v)), removeItem: (k) => data.delete(k), data };
}

const DEFAULT_CATALOG = ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "allam-2-7b"];

// Le catalogue de modèles (/models) est servi à part : les tests ne comptent que les appels de conversation.
function load({ session, local, fetchImpl, catalog }) {
  const window = { localStorage: memoryStorage(local), sessionStorage: memoryStorage(session) };
  const routed = (url, init) => (String(url).endsWith("/models") ? jsonResponse(200, { data: (catalog || DEFAULT_CATALOG).map((id) => ({ id })) }) : fetchImpl(url, init));
  const context = { window, fetch: routed, document: { visibilityState: "visible" }, esc: (s) => String(s), setInterval: () => 0, console };
  vm.createContext(context);
  vm.runInContext(SOURCE, context);
  return { backend: window.__registreBackend, window };
}

function jsonResponse(status, body) {
  return Promise.resolve({ ok: status >= 200 && status < 300, status, json: () => Promise.resolve(body) });
}

const TOOLS = [
  { name: "get_game_data", description: "d", inputSchema: { type: "object", properties: { section: { type: "string" } } }, execute: (i) => "données:" + i.section },
  {
    name: "boom",
    description: "d",
    execute: () => {
      throw new Error("panne volontaire");
    },
  },
];

async function ask(backend, extra) {
  return backend.ai.ask(Object.assign({ system: "S", messages: [{ role: "user", content: "?" }], tools: TOOLS, onText: () => {} }, extra));
}

test("sans clé : pas d'assistant IA, raison claire, aucune requête réseau", async () => {
  let calls = 0;
  const { backend } = load({
    fetchImpl: () => {
      calls++;
      return jsonResponse(200, {});
    },
  });
  assert.equal(await backend.ai.ready(), false);
  assert.match(backend.ai.status(), /renseigne une clé Groq/);
  assert.match(backend.ai.reasonText(), /aucune clé/);
  assert.equal(calls, 0);
});

test("avec une clé de session : la clé n'est envoyée qu'à api.groq.com, dans l'en-tête Authorization", async () => {
  const seen = [];
  const { backend } = load({
    session: { "registre.groqKey": FAKE_KEY },
    fetchImpl: (url, init) => {
      seen.push({ url, init });
      return jsonResponse(200, { choices: [{ message: { content: "Bonjour" } }] });
    },
  });
  assert.equal(await backend.ai.ready(), true);
  const texts = [];
  const answer = await ask(backend, { system: "Sys", messages: [{ role: "user", content: "Salut" }], onText: (t) => texts.push(t) });
  assert.equal(answer, "Bonjour");
  assert.deepEqual(texts, ["Bonjour"]);
  assert.equal(seen.length, 1);
  assert.ok(seen[0].url.startsWith("https://api.groq.com/openai/v1/"));
  assert.equal(seen[0].init.headers.Authorization, "Bearer " + FAKE_KEY);
  const body = JSON.parse(seen[0].init.body);
  assert.equal(body.messages[0].role, "system");
  assert.equal(body.messages[0].content, "Sys");
  assert.equal(body.tools[0].function.name, "get_game_data");
  assert.ok(!seen[0].init.body.includes(FAKE_KEY), "la clé ne doit jamais figurer dans le corps de la requête");
});

test("boucle d'outils : exécute chaque outil demandé, renvoie les résultats, gère pannes et arguments cassés", async () => {
  const requests = [];
  const replies = [
    {
      choices: [
        {
          message: {
            content: "",
            tool_calls: [
              { id: "c1", function: { name: "get_game_data", arguments: '{"section":"quetes"}' } },
              { id: "c2", function: { name: "boom", arguments: "{}" } },
              { id: "c3", function: { name: "inconnu", arguments: "{}" } },
              { id: "c4", function: { name: "get_game_data", arguments: "pas du json" } },
            ],
          },
        },
      ],
    },
    { choices: [{ message: { content: "Voilà" } }] },
  ];
  const { backend } = load({
    session: { "registre.groqKey": FAKE_KEY },
    fetchImpl: (url, init) => {
      requests.push(JSON.parse(init.body));
      return jsonResponse(200, replies.shift());
    },
  });
  assert.equal(await ask(backend), "Voilà");
  const tools = requests[1].messages.filter((m) => m.role === "tool");
  assert.equal(tools.length, 4);
  assert.equal(tools[0].content, "données:quetes");
  assert.match(tools[1].content, /panne volontaire/);
  assert.match(tools[2].content, /Outil inconnu/);
  assert.match(tools[3].content, /Arguments illisibles/);
  assert.deepEqual(tools.map((t) => t.tool_call_id), ["c1", "c2", "c3", "c4"]);
});

test("boucle d'outils bornée : un modèle qui redemande des outils sans fin s'arrête", async () => {
  let count = 0;
  const { backend } = load({
    session: { "registre.groqKey": FAKE_KEY },
    fetchImpl: () => {
      count++;
      return jsonResponse(200, { choices: [{ message: { content: "", tool_calls: [{ id: "x", function: { name: "get_game_data", arguments: "{}" } }] } }] });
    },
  });
  const answer = await ask(backend);
  assert.equal(count, 5);
  assert.match(answer, /pas terminé/);
});

test("erreurs du service : clé refusée, limite de débit, panne, réseau coupé, réponse vide", async () => {
  async function codeFor(fetchImpl) {
    const { backend } = load({ session: { "registre.groqKey": FAKE_KEY }, fetchImpl });
    try {
      await ask(backend, { tools: [] });
    } catch (e) {
      return e.code;
    }
    return "aucune erreur";
  }
  assert.equal(await codeFor(() => jsonResponse(401, { error: { message: "Invalid API Key" } })), "auth");
  assert.equal(await codeFor(() => jsonResponse(403, {})), "auth");
  assert.equal(await codeFor(() => jsonResponse(429, { error: { message: "rate" } })), "rate_limited");
  assert.equal(await codeFor(() => jsonResponse(500, {})), "http");
  assert.equal(await codeFor(() => Promise.reject(new TypeError("Failed to fetch"))), "network");
  assert.equal(await codeFor(() => jsonResponse(200, { choices: [] })), "http");
});

test("l'annulation par l'utilisateur n'est pas confondue avec une panne réseau", async () => {
  const { backend } = load({
    session: { "registre.groqKey": FAKE_KEY },
    fetchImpl: () => Promise.reject(Object.assign(new Error("abort"), { name: "AbortError" })),
  });
  await assert.rejects(ask(backend, { tools: [] }), (e) => e.name === "AbortError");
});

test("la clé en stockage local n'est lue que si l'utilisateur a choisi de la mémoriser", async () => {
  const forgotten = load({ local: { "registre.groqKey": FAKE_KEY } });
  assert.equal(await forgotten.backend.ai.ready(), false);
  const remembered = load({ local: { "registre.groqKey": FAKE_KEY, "registre.groqRemember": "1" } });
  assert.equal(await remembered.backend.ai.ready(), true);
});

test("contributions : écritures avec l'en-tête de protection, erreur du serveur lisible", async () => {
  const seen = [];
  const { backend } = load({
    fetchImpl: (url, init) => {
      seen.push({ url, init: init || {} });
      if (init && init.method === "POST") return jsonResponse(422, { error: "text : doit faire entre 1 et 30 caractères" });
      return jsonResponse(200, []);
    },
  });
  await assert.rejects(backend.store.add({ type: "chat" }), /entre 1 et 30/);
  assert.equal(seen[0].init.headers["X-Registre"], "1");
  assert.equal(seen[0].url, "/api/contributions");
  assert.match(backend.store.unavailableText, /node tools\/registre\/serve\.js/);
});

test("modèle : celui du compte est choisi quand le modèle par défaut a disparu, les modèles inadaptés sont évités", () => {
  const { backend } = load({ fetchImpl: () => jsonResponse(200, {}) });
  const pick = backend.ai.pickModel;
  assert.equal(pick(["allam-2-7b", "openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b"], "llama-3.3-70b-versatile"), "openai/gpt-oss-120b");
  assert.equal(pick(["allam-2-7b", "openai/gpt-oss-20b"], "llama-3.3-70b-versatile"), "openai/gpt-oss-20b");
  assert.equal(pick(["allam-2-7b", "qwen/qwen3.8-27b"], "x"), "qwen/qwen3.8-27b");
  assert.equal(pick(["allam-2-7b"], "x"), "allam-2-7b");
  assert.equal(pick(["a", "b"], "b"), "b"); // un modèle encore disponible est conservé
  assert.equal(pick([], "x"), "x");
});

test("requête : le modèle mémorisé disparu est remplacé AVANT le premier appel ; effort de raisonnement réservé aux gpt-oss", async () => {
  const bodies = [];
  const { backend } = load({
    session: { "registre.groqKey": FAKE_KEY },
    local: { "registre.groqModel": "llama-3.3-70b-versatile" },
    fetchImpl: (url, init) => {
      bodies.push(JSON.parse(init.body));
      return jsonResponse(200, { choices: [{ message: { content: "ok" } }] });
    },
  });
  await ask(backend, { tools: [] });
  assert.equal(bodies[0].model, "openai/gpt-oss-120b");
  assert.equal(bodies[0].reasoning_effort, "low");
  assert.ok(bodies[0].max_tokens >= 1000);

  const other = [];
  const second = load({
    session: { "registre.groqKey": FAKE_KEY },
    catalog: ["qwen/qwen3.8-27b"],
    fetchImpl: (url, init) => {
      other.push(JSON.parse(init.body));
      return jsonResponse(200, { choices: [{ message: { content: "ok" } }] });
    },
  });
  await ask(second.backend, { tools: [] });
  assert.equal(other[0].model, "qwen/qwen3.8-27b");
  assert.equal("reasoning_effort" in other[0], false);
});
