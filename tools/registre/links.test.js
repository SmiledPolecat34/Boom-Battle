"use strict";
// Champ « Lien » : adresses http(s) uniquement, nom facultatif, dans les journaux et les tickets.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { normalizeLink, normalizeLinks, LinkError, MAX_URL } = require("./links");
const { createJournal, JournalError, SCHEMAS } = require("./journal");
const { createBoard, BoardError, MAX_LINKS } = require("./board");
const { createActivity } = require("./activity");

const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), "registre-links-"));

test("lien : adresse normalisée, nom facultatif (par défaut le site), nom choisi conservé", () => {
  assert.deepEqual(normalizeLink({ url: "https://www.exemple.fr/page?x=1#haut" }), { name: "exemple.fr", url: "https://www.exemple.fr/page?x=1#haut" });
  assert.deepEqual(normalizeLink({ name: "  Doc de jeu ", url: " http://a.example/b " }), { name: "Doc de jeu", url: "http://a.example/b" });
  assert.deepEqual(normalizeLink({ url: "HTTPS://Exemple.FR" }), { name: "exemple.fr", url: "https://exemple.fr/" });
  assert.deepEqual(normalizeLink({ name: "", url: "https://github.com/SmiledPolecat34/Boom-Battle" }).name, "github.com");
});

test("lien : tout ce qui n'est pas une adresse http(s) sûre est refusé", () => {
  const bad = [null, undefined, "https://a.b", 5, [], {}, { url: "" }, { url: "   " }, { url: 5 }, { url: "exemple.fr" }, { url: "ftp://a.b/x" }, { url: "javascript:alert(1)" }, { url: "JaVaScRiPt:alert(1)" }, { url: "data:text/html,<script>alert(1)</script>" },
    { url: "file:///etc/passwd" }, { url: "//evil.example" }, { url: "https://user:pass@a.example" }, { url: "https://a b.example" }, { url: "https://a.example/\u0000" }, { url: "https://a.example/\nx" }, { url: "https://" },
    { url: "https://a.example/" + "x".repeat(MAX_URL) }, { url: "https://a.example", name: "x".repeat(61) }, { url: "https://a.example", name: "a\u0000b" }, { url: "https://a.example", name: 5 }, { url: "https://a.example", name: {} }];
  for (const raw of bad) assert.throws(() => normalizeLink(raw), LinkError, JSON.stringify(raw));
  assert.throws(() => normalizeLinks("x", 10), LinkError);
  assert.throws(() => normalizeLinks(Array.from({ length: 11 }, () => ({ url: "https://a.example" })), 10), LinkError);
  assert.equal(normalizeLinks([], 10).length, 0);
});

test("journaux : chaque rubrique a un champ « Lien » facultatif, enregistré normalisé, refusé s'il est dangereux", () => {
  const dir = tmp();
  try {
    const journal = createJournal({ dir });
    for (const schema of SCHEMAS) assert.ok(schema.fields.some((f) => f.type === "link" && f.key === "link" && f.optional), schema.id);
    const base = { date: "2026-11-04", scenario: "2 clients Studio", result: "ok" };
    const sans = journal.put("playtests", base);
    assert.equal(sans.link, undefined);
    const avec = journal.put("playtests", Object.assign({}, base, { link: { name: "Vidéo du test", url: "https://exemple.fr/v" } }));
    assert.deepEqual(avec.link, { name: "Vidéo du test", url: "https://exemple.fr/v" });
    assert.deepEqual(journal.list("playtests").find((e) => e.id === avec.id).link, avec.link, "relu depuis le disque");
    assert.equal(journal.put("playtests", Object.assign({}, base, { link: { url: "", name: "" } })).link, undefined, "lien vide = pas de lien");
    for (const link of [{ url: "javascript:alert(1)" }, { url: "ftp://a.b" }, "https://a.b", { name: "sans adresse" }, { url: "https://a.example", name: "x".repeat(61) }]) assert.throws(() => journal.put("playtests", Object.assign({}, base, { link })), JournalError, JSON.stringify(link));
    const edited = journal.put("playtests", Object.assign({}, base, { link: { url: "https://autre.example/x" } }), avec.id);
    assert.equal(edited.link.name, "autre.example");
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test("tickets : liste de liens (10 au plus), ajout, retrait, historique ; refus des adresses dangereuses", () => {
  const dir = tmp();
  try {
    const board = createBoard({ dir, activity: createActivity(path.join(dir, "activity.json")) });
    const t = board.create({ title: "Un ticket avec liens", links: [{ name: "Spécification", url: "https://exemple.fr/spec" }] });
    assert.deepEqual(t.links, [{ name: "Spécification", url: "https://exemple.fr/spec" }]);
    assert.deepEqual(board.create({ title: "Sans lien" }).links, []);
    const u = board.update(t.id, { links: [{ url: "https://a.example/1" }, { name: "Deux", url: "http://b.example/2" }] });
    assert.deepEqual(u.links.map((l) => l.name), ["a.example", "Deux"]);
    assert.equal(u.history[u.history.length - 1].action, "edited");
    assert.match(u.history[u.history.length - 1].text, /links/);
    const same = board.update(t.id, { links: u.links });
    assert.equal(same.history.length, u.history.length, "liens identiques : rien dans l'historique");
    assert.deepEqual(board.update(t.id, { links: [] }).links, []);
    for (const links of ["x", [{ url: "javascript:alert(1)" }], [null], Array.from({ length: MAX_LINKS + 1 }, (_, i) => ({ url: "https://a.example/" + i })), [{ url: "https://a.example", name: "x".repeat(61) }]]) {
      assert.throws(() => board.update(t.id, { links }), BoardError, JSON.stringify(links).slice(0, 60));
      assert.throws(() => board.create({ title: "Mauvais lien", links }), BoardError);
    }
    // un ticket ancien (sans champ « links ») reste lisible
    const old = JSON.parse(fs.readFileSync(path.join(dir, "tickets", t.id + ".json"), "utf8"));
    delete old.links;
    fs.writeFileSync(path.join(dir, "tickets", t.id + ".json"), JSON.stringify(old));
    assert.ok(board.get(t.id));
    // un fichier falsifié avec un lien dangereux est ignoré
    old.links = [{ name: "x", url: "javascript:alert(1)" }];
    fs.writeFileSync(path.join(dir, "tickets", t.id + ".json"), JSON.stringify(old));
    assert.throws(() => board.get(t.id), (e) => e.status === 404);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test("tickets : les liens survivent à la sauvegarde et à la restauration, et un lien falsifié dans une sauvegarde est refusé", () => {
  const dir = tmp(), dir2 = tmp();
  try {
    const a = createBoard({ dir });
    const t = a.create({ title: "Ticket sauvegardé", links: [{ name: "Doc", url: "https://exemple.fr/d" }] });
    const bundle = JSON.parse(JSON.stringify(a.extra.backup()));
    const b = createBoard({ dir: dir2 });
    const skipped = [];
    assert.equal(b.extra.restore(bundle, (...x) => skipped.push(x)), 1);
    assert.deepEqual(b.get(t.id).links, [{ name: "Doc", url: "https://exemple.fr/d" }]);
    const evil = JSON.parse(JSON.stringify(bundle));
    evil[0].id = "tmauvais01";
    evil[0].links = [{ name: "x", url: "javascript:alert(1)" }];
    assert.equal(b.extra.restore(evil, (...x) => skipped.push(x)), 0);
    assert.ok(skipped.length >= 1);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); fs.rmSync(dir2, { recursive: true, force: true }); }
});
