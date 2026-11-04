"use strict";
// Lancement des tests depuis le serveur local et historique des exécutions (date, heure, durée, bilan).
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createServer, listRuns, saveRun, summarize, collectData } = require("./serve");
const { sampleData } = require("./page-helpers");

const H = { "X-Registre": "1", "Content-Type": "application/json" };

function request(port, method, url, { headers = {}, body } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: "127.0.0.1", port, method, path: url, headers }, (res) => {
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve({ status: res.statusCode, json: () => JSON.parse(Buffer.concat(chunks).toString("utf8")) }));
    });
    req.on("error", reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

function fakeReport(overrides) {
  return Object.assign({ passed: 7, failed: 0, suites: 2, results: [{ suite: "a/B", name: "ok", ok: true, seconds: 0 }], error: "" }, overrides);
}

// runTests : stub qui note ses appels ; `gate` permet de le suspendre pour tester la concurrence.
async function withServer(fn, { runTests } = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-runs-"));
  const calls = [];
  const stub =
    runTests ||
    (async ({ filter, trigger }) => {
      calls.push({ filter, trigger });
      const startedAt = Date.now();
      const report = fakeReport();
      return { report, run: summarize(report, { startedAt, finishedAt: startedAt + 1234, filter, trigger }) };
    });
  const server = createServer({ dir: path.join(dir, "contributions"), runsDir: path.join(dir, "runs"), initialData: sampleData(), collect: async () => sampleData(), runTests: stub });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await fn(server.address().port, { dir, calls, runsDir: path.join(dir, "runs") });
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("lancer les tests : rapport et historique renvoyés, exécution enregistrée avec date, heure et durée", async () => {
  await withServer(async (port, { calls, runsDir }) => {
    const before = Date.now();
    const res = await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter: "" }) });
    assert.equal(res.status, 200);
    const body = res.json();
    assert.equal(body.report.passed, 7);
    assert.equal(body.runs.length, 1);
    assert.equal(body.runs[0].trigger, "site");
    assert.equal(body.runs[0].durationMs, 1234);
    assert.ok(body.runs[0].startedAt >= before && body.runs[0].finishedAt === body.runs[0].startedAt + 1234);
    assert.deepEqual(calls, [{ filter: "", trigger: "site" }]);
    assert.equal(fs.readdirSync(runsDir).length, 1); // un fichier par exécution
  });
});

test("lancer les tests : l'historique garde l'ordre chronologique inverse", async () => {
  await withServer(async (port) => {
    for (const filter of ["", "GridService", "Economy"]) {
      await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter }) });
      await new Promise((r) => setTimeout(r, 5));
    }
    const latest = (await request(port, "GET", "/api/tests/latest", { headers: H })).json();
    assert.deepEqual(latest.runs.map((r) => r.filter), ["Economy", "GridService", ""]);
    assert.equal(latest.running, false);
    assert.equal(latest.report.passed, 7);
  });
});

test("filtre : seules les noms de suites sûrs sont acceptés, rien n'est lancé sinon", async () => {
  await withServer(async (port, { calls }) => {
    const bad = ["-rf", "--json", "../etc", "a;b", "a|b", "a b$(x)", "x".repeat(61), "`id`", "a&b", "é", "\n", "/abs", " espace"];
    for (const filter of bad) {
      const res = await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter }) });
      assert.equal(res.status, 422, JSON.stringify(filter));
    }
    for (const filter of [5, null, {}, []]) {
      const res = await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter }) });
      assert.equal(res.status, 422, JSON.stringify(filter));
    }
    assert.equal(calls.length, 0);
    for (const filter of ["GridService", "server/Economy", "Round.Service", "a-b_c d"]) {
      assert.equal((await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter }) })).status, 200, filter);
    }
  });
});

test("lancer les tests : corps cassé ou trop gros refusé ; l'en-tête de protection est exigé", async () => {
  await withServer(async (port, { calls }) => {
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: H, body: "{cassé" })).status, 400);
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter: "x".repeat(30000) }) })).status, 413);
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: { "Content-Type": "application/json" }, body: "{}" })).status, 403);
    assert.equal((await request(port, "GET", "/api/tests/latest")).status, 403);
    assert.equal(calls.length, 0);
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: H })).status, 200); // corps absent = tous les tests
  });
});

test("une seule exécution à la fois : la seconde demande reçoit 409, puis tout redevient possible", async () => {
  let release;
  const gate = new Promise((resolve) => (release = resolve));
  let calls = 0;
  const runTests = async ({ filter, trigger }) => {
    calls++;
    if (calls === 1) await gate;
    const startedAt = Date.now();
    const report = fakeReport();
    return { report, run: summarize(report, { startedAt, finishedAt: startedAt + 10, filter, trigger }) };
  };
  await withServer(async (port) => {
    const first = request(port, "POST", "/api/tests/run", { headers: H, body: "{}" });
    await new Promise((r) => setTimeout(r, 40));
    const status = (await request(port, "GET", "/api/tests/latest", { headers: H })).json();
    assert.equal(status.running, true);
    const second = await request(port, "POST", "/api/tests/run", { headers: H, body: "{}" });
    assert.equal(second.status, 409);
    assert.match(second.json().error, /déjà en cours/);
    assert.equal((await request(port, "POST", "/api/refresh", { headers: H })).status, 409);
    release();
    assert.equal((await first).status, 200);
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: H, body: "{}" })).status, 200);
    assert.equal(calls, 2);
  }, { runTests });
});

test("échec du lancement (Lune absent, délai, aucune suite) : message lisible, rien d'enregistré, le serveur reste utilisable", async () => {
  let fail = true;
  const runTests = async ({ filter, trigger }) => {
    if (fail) throw new Error("Aucune suite ne correspond à « zzz ».");
    const startedAt = Date.now();
    const report = fakeReport();
    return { report, run: summarize(report, { startedAt, finishedAt: startedAt + 1, filter, trigger }) };
  };
  await withServer(async (port, { runsDir }) => {
    const res = await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter: "zzz" }) });
    assert.equal(res.status, 500);
    assert.match(res.json().error, /Aucune suite ne correspond/);
    assert.equal(fs.existsSync(runsDir) ? fs.readdirSync(runsDir).length : 0, 0);
    fail = false;
    assert.equal((await request(port, "POST", "/api/tests/run", { headers: H, body: "{}" })).status, 200);
  }, { runTests });
});

test("summarize : bilan, échecs tronqués à 20, message borné", () => {
  const results = Array.from({ length: 30 }, (_, i) => ({ suite: "s", name: "t" + i, ok: false, message: "m".repeat(500), seconds: 0 })).concat([{ suite: "s", name: "bon", ok: true, seconds: 0 }]);
  const run = summarize({ passed: 1, failed: 30, suites: 1, results }, { startedAt: 1000, finishedAt: 4500, filter: "s", trigger: "site" });
  assert.equal(run.ok, false);
  assert.equal(run.durationMs, 3500);
  assert.equal(run.failures.length, 20);
  assert.equal(run.failures[0].message.length, 300);
  assert.equal(run.filter, "s");
  assert.equal(summarize({ passed: 3, failed: 0, suites: 1, results: [] }, { startedAt: 1, finishedAt: 2, trigger: "demarrage" }).ok, true);
});

test("historique sur disque : trié du plus récent au plus ancien, plafonné à 100, fichiers illisibles ignorés", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-hist-"));
  try {
    for (let i = 1; i <= 105; i++) saveRun(dir, summarize(fakeReport(), { startedAt: 1700000000000 + i, finishedAt: 1700000000000 + i + 5, trigger: "site" }));
    assert.equal(fs.readdirSync(dir).length, 100, "les plus anciennes sont supprimées");
    fs.writeFileSync(path.join(dir, "1700000000999.json"), "{cassé");
    fs.writeFileSync(path.join(dir, "notes.txt"), "x");
    const runs = listRuns(dir);
    assert.equal(runs.length, 100);
    assert.equal(runs[0].startedAt, 1700000000105);
    assert.equal(runs[99].startedAt, 1700000000006);
    assert.deepEqual(listRuns(path.join(dir, "absent")), []);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("démarrage : les tests sont lancés et enregistrés avec le déclencheur « démarrage »", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-start-"));
  try {
    const seen = [];
    const data = await collectData({
      runsDir: dir,
      runTests: async ({ filter, trigger }) => {
        seen.push({ filter, trigger });
        const report = fakeReport({ passed: 11 });
        return { report, run: summarize(report, { startedAt: 1700000000500, finishedAt: 1700000001500, filter, trigger }) };
      },
    });
    assert.deepEqual(seen, [{ filter: "", trigger: "demarrage" }]);
    assert.equal(data.tests.passed, 11);
    assert.equal(data.runs.length, 1);
    assert.equal(data.runs[0].trigger, "demarrage");
    assert.equal(data.runs[0].durationMs, 1000);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("démarrage : si les tests ne peuvent pas tourner, l'erreur est affichée dans le rapport au lieu de planter", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-start-"));
  try {
    const data = await collectData({ runsDir: dir, runTests: async () => { throw new Error("Lune est introuvable : installe-le."); } });
    assert.match(data.tests.error, /Lune est introuvable/);
    assert.deepEqual(data.runs, []);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("la page rechargée montre les exécutions faites entre-temps (historique relu à chaque chargement)", async () => {
  await withServer(async (port) => {
    const page = (path) => new Promise((resolve, reject) => http.get({ host: "127.0.0.1", port, path }, (res) => { const c = []; res.on("data", (d) => c.push(d)); res.on("end", () => resolve(Buffer.concat(c).toString("utf8"))); }).on("error", reject));
    assert.ok(!(await page("/")).includes('"trigger":"site"'));
    await request(port, "POST", "/api/tests/run", { headers: H, body: JSON.stringify({ filter: "GridService" }) });
    const html = await page("/");
    assert.ok(html.includes('"trigger":"site"') && html.includes('"filter":"GridService"'));
  });
});
