"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { createProjects, githubUrl, inspect } = require("./projects");
const { createServer } = require("./serve");
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "registre-projects-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const folder = path.join(root, "Projet été"); fs.mkdirSync(folder);
  fs.writeFileSync(path.join(folder, "index.js"), "throw new Error('ne doit jamais être exécuté');");
  fs.writeFileSync(path.join(folder, ".env"), "SECRET=confidentiel");
  fs.mkdirSync(path.join(folder, "node_modules")); fs.writeFileSync(path.join(folder, "node_modules", "ignore.js"), "");
  return { root, folder, dir: path.join(root, "data") };
}
test("projets : dossier lié, aperçu réel sans exécuter le code, persistance, doublon et actualisation", async t => {
  const f = fixture(t), catalog = createProjects(f);
  const p = await catalog.add({ source: "folder", path: f.folder, name: "Projet été" });
  assert.deepEqual(p.snapshot.files, ["index.js"]);
  assert.equal(p.snapshot.count, 1);
  assert.equal(p.path, fs.realpathSync(f.folder));
  assert.equal(createProjects(f).list()[0].id, p.id);
  assert.equal((await catalog.add({ source: "folder", path: f.folder })).id, p.id);
  assert.equal(catalog.list().length, 1);
  fs.writeFileSync(path.join(f.folder, "theme.css"), "body{}");
  assert.equal(catalog.refresh(p.id).snapshot.count, 2);
  assert.throws(() => catalog.refresh("p0000000000000000"), /introuvable/);
});
test("projets : adresses GitHub strictes, sans identifiants, options ou chemins supplémentaires", () => {
  assert.equal(githubUrl("https://github.com/owner/repo.git"), "https://github.com/owner/repo");
  for (const url of [null, "http://github.com/o/r", "https://user:secret@github.com/o/r", "https://github.com.evil/o/r", "file:///x", "--upload-pack=evil", "https://github.com/o/r/tree/main", "https://github.com/o/r?x=y", "https://github.com/o/.."])
    assert.throws(() => githubUrl(url));
});
test("projets : import GitHub attend la copie, mémorise la source et évite de cloner deux fois", async t => {
  const f = fixture(t); let calls = 0;
  const catalog = createProjects({ ...f, clone: async (url, destination) => {
    calls++; assert.equal(url, "https://github.com/demo/site");
    assert.ok(destination.startsWith(path.join(f.dir, "repositories")));
    fs.mkdirSync(destination); fs.writeFileSync(path.join(destination, "README.md"), "Projet");
  } });
  const p = await catalog.add({ source: "github", url: "https://github.com/demo/site.git" });
  assert.equal(p.name, "site"); assert.deepEqual(p.snapshot.files, ["README.md"]);
  assert.equal((await catalog.add({ source: "github", url: "https://github.com/demo/site" })).id, p.id);
  assert.equal(calls, 1);
});
test("projets : import échoué et demandes invalides ne créent pas de projet", async t => {
  const f = fixture(t), catalog = createProjects({ ...f, clone: async () => { throw new Error("Accès refusé"); } });
  for (const input of [null, {}, { source: "folder", path: "relative" }, { source: "folder", path: f.folder, name: "x".repeat(81) }, { source: "folder", path: path.parse(f.folder).root }, { source: "folder", path: path.join(f.root, "absent") }, { source: "github", url: "https://github.com/demo/private" }])
    await assert.rejects(catalog.add(input));
  assert.deepEqual(catalog.list(), []);
});
test("projets : import concurrent refusé et sélection annulée sans création", async t => {
  const f = fixture(t); let release;
  const catalog = createProjects({ ...f, chooseFolder: async () => "", clone: async (url, destination) => {
    await new Promise(resolve => { release = resolve; }); fs.mkdirSync(destination);
  } });
  const pending = catalog.add({ source: "github", url: "https://github.com/demo/site" });
  await assert.rejects(catalog.add({ source: "folder", path: f.folder }), /déjà en cours/);
  release(); await pending;
  assert.deepEqual(await catalog.pick(), { path: "" });
  assert.equal(catalog.list().length, 1);
});
test("projets : fichiers cachés, dépendances et liens symboliques ne sont pas parcourus", t => {
  const f = fixture(t);
  fs.symlinkSync(f.root, path.join(f.folder, "lien"), process.platform === "win32" ? "junction" : "dir");
  assert.deepEqual(inspect(f.folder).files, ["index.js"]);
});

test("profils : auteur du package, modification durable et source protégée", async t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.folder, "package.json"), JSON.stringify({ author: { name: "Équipe locale" }, description: "Description du package", scripts: { postinstall: "interdit" } }));
  const catalog = createProjects(f), p = await catalog.add({ source: "folder", path: f.folder });
  assert.equal(p.author, "Équipe locale"); assert.equal(p.description, "Description du package");
  const updated = catalog.update(p.id, { name: "Nouveau nom", author: "Deux auteurs", description: "Nouvelle présentation", path: "C:\\autre", source: "github" });
  assert.equal(updated.path, p.path); assert.equal(updated.source, "folder");
  assert.equal(createProjects(f).get(p.id).name, "Nouveau nom");
  assert.equal(catalog.get(p.id).author, "Deux auteurs");
  for (const raw of [{ name: "" }, { name: " " }, { name: "x".repeat(81) }, { author: 5 }, { description: "x".repeat(2001) }, null]) assert.throws(() => catalog.update(p.id, raw));
  assert.equal(catalog.get(p.id).name, "Nouveau nom");
});

test("profils : suppression du catalogue sans toucher au dossier, ni à ses fichiers", async t => {
  const f = fixture(t), catalog = createProjects(f), p = await catalog.add({ source: "folder", path: f.folder });
  assert.deepEqual(catalog.remove(p.id), { ok: true, filesPreserved: true });
  assert.equal(fs.existsSync(path.join(f.folder, "index.js")), true);
  assert.equal(createProjects(f).list().length, 0);
  assert.throws(() => catalog.get(p.id), /introuvable/);
  assert.throws(() => catalog.remove("../../autre"), /introuvable/);
});

test("profils : BOOM BATTLE et Luma sont modifiables et retirables sans supprimer leurs données", t => {
  const f = fixture(t), catalog = createProjects(f);
  catalog.update("luma", { name: "Luma studio", author: "Équipe Luma" });
  assert.equal(createProjects(f).get("luma").name, "Luma studio");
  catalog.remove("luma");
  assert.equal(createProjects(f).builtins().find(p => p.id === "luma").deleted, true);
  assert.throws(() => catalog.get("luma"), /introuvable/);
  assert.equal(catalog.get("boom").name, "BOOM BATTLE");
});
test("projets : routes protégées, sélection native, création et relecture au chargement", async t => {
  const f = fixture(t), server = createServer({ initialData: {}, dataDir: f.dir, dir: path.join(f.root, "contrib"), runsDir: path.join(f.root, "runs"), projectOptions: { chooseFolder: async () => f.folder } });
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const url = "http://127.0.0.1:" + server.address().port;
  for (const route of ["/api/projects", "/api/projects/pick-folder"])
    assert.equal((await fetch(url + route, { method: "POST" })).status, 403);
  const headers = { "X-Registre": "1", "Content-Type": "application/json" };
  const pick = await fetch(url + "/api/projects/pick-folder", { method: "POST", headers });
  assert.deepEqual(await pick.json(), { path: f.folder });
  const response = await fetch(url + "/api/projects", { method: "POST", headers, body: JSON.stringify({ source: "folder", path: f.folder }) });
  assert.equal(response.status, 201); const p = await response.json();
  assert.equal((await (await fetch(url + "/api/projects", { headers })).json())[0].id, p.id);
  assert.equal((await fetch(url + "/api/projects/" + p.id + "/refresh", { method: "POST", headers })).status, 200);
  assert.match(await (await fetch(url)).text(), /Projet été/);
  for (const method of ["GET", "PATCH", "DELETE"]) assert.equal((await fetch(url + "/api/projects/" + p.id, { method })).status, 403);
  const changed = await fetch(url + "/api/projects/" + p.id, { method: "PATCH", headers, body: JSON.stringify({ name: "Renommé", author: "Auteur" }) });
  assert.equal(changed.status, 200); assert.equal((await changed.json()).name, "Renommé");
  assert.equal((await fetch(url + "/api/projects/" + p.id, { method: "DELETE", headers })).status, 200);
  assert.equal(fs.existsSync(f.folder), true);
  assert.equal((await fetch(url + "/api/projects/" + p.id, { headers })).status, 404);
});
