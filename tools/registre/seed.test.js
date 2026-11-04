"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { seed, TICKETS } = require("./seed");
const { createBoard } = require("./board");

test("amorçage du tableau : tous les tickets sont valides, relancer ne crée aucun doublon", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registre-seed-"));
  try {
    const first = seed(dir);
    assert.deepEqual(first, { tickets: TICKETS.length, decisions: 1 });
    const second = seed(dir);
    assert.deepEqual(second, { tickets: 0, decisions: 0 });
    const list = createBoard({ dir }).list();
    assert.equal(list.length, TICKETS.length);
    assert.ok(list.every((t) => t.status === "todo"));
    assert.equal(new Set(list.map((t) => t.title)).size, list.length);
    assert.ok(list.some((t) => t.priority === "P0"));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
