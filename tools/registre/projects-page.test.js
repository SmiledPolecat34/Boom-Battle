"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { boot, wait, fakeServer, sampleData, ok } = require("./page-helpers");
const ID = "p1234567890abcdef";
function project() { return { id: ID, name: "Mon projet", source: "github", repository: "https://github.com/demo/site", path: "C:\\Projets\\site", snapshot: { count: 1, files: ["index.html"], extensions: [{ name: "html", count: 1 }] } }; }
test("projets page : formulaire vide refusé, import réel demandé et projet ouvert sans données BOOM BATTLE", async () => {
  const server = fakeServer(), calls = [];
  const env = boot({ hash: "#ajouter-projet", fetchImpl: (url, init) => {
    if (url === "/api/projects") { calls.push(JSON.parse(init.body)); return ok(project()); }
    return server.fetchImpl(url, init);
  } });
  await wait();
  assert.equal(env.els["view-add-project"].hidden, false);
  env.els["project-source"].value = "github";
  env.els["project-import-form"].handlers.submit({ preventDefault() {} });
  assert.equal(calls.length, 0);
  assert.match(env.els["project-import-msg"].textContent, /Indique/);
  env.els["project-github-url"].value = "https://github.com/demo/site";
  env.els["project-name"].value = "Mon projet";
  env.els["project-import-form"].handlers.submit({ preventDefault() {} });
  await wait();
  assert.deepEqual(calls, [{ source: "github", name: "Mon projet", url: "https://github.com/demo/site" }]);
  assert.equal(env.sandbox.location.hash, "projet/" + ID);
  assert.equal(env.els["view-project"].hidden, false);
  assert.equal(env.els["view-tests"].hidden, true);
  assert.equal(env.els["boom-navigation"].hidden, true);
  assert.match(env.els["view-project"].innerHTML, /index.html/);
  assert.match(env.els["project-select"].innerHTML, /Mon projet/);
  assert.match(env.els["extra-project-cards"].innerHTML, /Mon projet/);
});
test("projets page : explorateur sélectionné ou annulé, puis import du chemin choisi", async () => {
  const server = fakeServer(); let selected = "", posted;
  const env = boot({ hash: "#ajouter-projet", fetchImpl: (url, init) => {
    if (url === "/api/projects/pick-folder") return ok({ path: selected });
    if (url === "/api/projects") { posted = JSON.parse(init.body); return ok({ ...project(), source: "folder" }); }
    return server.fetchImpl(url, init);
  } });
  await wait();
  const source = env.els["project-source"]; source.value = "folder"; source.handlers.change.call(source);
  assert.equal(env.els["project-folder-fields"].hidden, false);
  assert.equal(env.els["project-github-fields"].hidden, true);
  env.els["project-pick-folder"].handlers.click(); await wait();
  assert.match(env.els["project-import-msg"].textContent, /annulée/);
  assert.equal(env.els["project-pick-folder"].disabled, false);
  assert.equal(env.els["project-pick-folder"].textContent, "Parcourir les dossiers…");
  assert.equal(env.els["project-pick-folder"].attrs["aria-busy"], "false");
  assert.match(env.els["project-picker-msg"].textContent, /annulée/);
  assert.equal(posted, undefined);
  selected = "C:\\Projets\\été";
  env.els["project-pick-folder"].handlers.click(); await wait();
  assert.equal(env.els["project-folder"].value, selected);
  env.els["project-import-form"].handlers.submit({ preventDefault() {} }); await wait();
  assert.equal(posted.source, "folder"); assert.equal(posted.path, selected);
});

test("projets page : une erreur du sélecteur Windows ne laisse pas le bouton bloqué", async () => {
  const server = fakeServer();
  const env = boot({ hash: "#ajouter-projet", fetchImpl: (url, init) => url === "/api/projects/pick-folder" ? Promise.reject(new Error("Le sélecteur Windows est indisponible")) : server.fetchImpl(url, init) });
  await wait(); env.els["project-pick-folder"].handlers.click();
  assert.equal(env.els["project-pick-folder"].disabled, true);
  assert.equal(env.els["project-pick-folder"].textContent, "Sélection en cours…");
  await wait();
  assert.equal(env.els["project-pick-folder"].disabled, false);
  assert.equal(env.els["project-pick-folder"].textContent, "Parcourir les dossiers…");
  assert.match(env.els["project-picker-msg"].textContent, /indisponible/);
});
test("projets page : URL rechargeable, noms échappés et sélecteur vers les espaces existants", async () => {
  const data = sampleData(); data.projects = [{ ...project(), name: '<img src=x onerror="alert(1)">' }];
  const env = boot({ data, hash: "#projet/" + ID, fetchImpl: fakeServer().fetchImpl });
  await wait();
  assert.equal(env.els["view-project"].hidden, false);
  assert.equal(env.els["project-select"].value, "projet/" + ID);
  assert.match(env.els["extra-project-links"].innerHTML, /&lt;img/);
  assert.doesNotMatch(env.els["extra-project-links"].innerHTML, /<img/);
  const select = env.els["project-select"]; select.value = "luma"; select.handlers.change.call(select);
  assert.equal(env.els["view-luma"].hidden, false);
  assert.equal(env.els["view-project"].hidden, true);
});
test("projets page : erreur serveur visible, bouton réactivé et formulaire conservé", async () => {
  const server = fakeServer();
  const env = boot({ hash: "#ajouter-projet", fetchImpl: (url, init) => url === "/api/projects" ? Promise.reject(new Error("Dépôt privé inaccessible")) : server.fetchImpl(url, init) });
  await wait();
  env.els["project-source"].value = "github"; env.sandbox.document.getElementById("project-github-url").value = "https://github.com/demo/private";
  env.els["project-import-form"].handlers.submit({ preventDefault() {} }); await wait();
  assert.equal(env.els["project-import-submit"].disabled, false);
  assert.match(env.els["project-import-msg"].textContent, /inaccessible/);
  assert.equal(env.els["project-github-url"].value, "https://github.com/demo/private");
  assert.equal(env.els["view-add-project"].hidden, false);
});

test("profil page : renommage et auteur mis à jour dans le profil, les cartes et le sélecteur", async () => {
  const server = fakeServer(), data = sampleData(); data.projects = [project()]; let posted;
  const env = boot({ data, hash: "#projet/" + ID, fetchImpl: (url, init) => {
    if (url === "/api/projects/" + ID && init.method === "PATCH") { posted = JSON.parse(init.body); return ok({ ...project(), ...posted }); }
    return server.fetchImpl(url, init);
  } });
  await wait();
  env.sandbox.document.getElementById("profile-name").value = "Nouveau projet";
  env.sandbox.document.getElementById("profile-author").value = "Mon équipe";
  env.sandbox.document.getElementById("profile-description").value = "Une description";
  env.els["profile-form"].handlers.submit({ preventDefault() {} }); await wait();
  assert.equal(posted.name, "Nouveau projet");
  assert.match(env.els["project-select"].innerHTML, /Nouveau projet/);
  assert.match(env.els["extra-project-cards"].innerHTML, /Nouveau projet/);
  assert.match(env.els["view-project"].innerHTML, /Mon équipe/);
  assert.equal(env.els["page-title"].textContent, "Nouveau projet");
  assert.equal(env.els["profile-message"].textContent, "Profil enregistré.");
});

test("profil page : suppression en deux étapes, annulation possible, retour à l'accueil", async () => {
  const server = fakeServer(), data = sampleData(); data.projects = [project()]; let removed = 0;
  const env = boot({ data, hash: "#projet/" + ID, fetchImpl: (url, init) => {
    if (url === "/api/projects/" + ID && init.method === "DELETE") { removed++; return ok({ ok: true, filesPreserved: true }); }
    return server.fetchImpl(url, init);
  } });
  await wait();
  assert.match(env.els["view-project"].innerHTML, /fichiers locaux et son dépôt GitHub seront conservés/);
  env.els["profile-delete"].handlers.click();
  assert.equal(removed, 0); assert.equal(env.els["profile-delete-confirm"].hidden, false);
  env.els["profile-delete-cancel"].handlers.click();
  assert.equal(removed, 0); assert.equal(env.els["profile-delete-confirm"].hidden, true);
  env.els["profile-delete"].handlers.click(); env.els["profile-delete-confirm-btn"].handlers.click(); await wait();
  assert.equal(removed, 1); assert.equal(env.els["view-accueil"].hidden, false);
  assert.doesNotMatch(env.els["project-select"].innerHTML, /Mon projet/);
});

test("profil page : profil BOOM BATTLE accessible et projet intégré supprimé absent des liens et des routes", async () => {
  const env = boot({ hash: "#profil/boom", fetchImpl: fakeServer().fetchImpl }); await wait();
  assert.equal(env.els["view-project"].hidden, false);
  assert.match(env.els["view-project"].innerHTML, /SmiledPolecat34/);
  const data = sampleData(); data.projectProfiles = [{ id: "luma", name: "Luma retiré", source: "builtin", deleted: true }];
  const deleted = boot({ data, hash: "#profil/luma", fetchImpl: fakeServer().fetchImpl }); await wait();
  assert.equal(deleted.els["view-accueil"].hidden, false);
  assert.equal(deleted.els["project-luma"].hidden, true);
  assert.equal(deleted.els["card-luma"].hidden, true);
  assert.doesNotMatch(deleted.els["project-select"].innerHTML, /Luma retiré/);
});
