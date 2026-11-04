#!/usr/bin/env node
"use strict";
// Applique les contributions en attente (tools/registre/contributions/*.json) aux configurations du jeu (src/shared).
//
//   node tools/registre/apply.js            simulation : affiche les lignes qui seraient ajoutées, ne modifie rien
//   node tools/registre/apply.js --write    écrit dans src/shared, lance les tests, ANNULE tout si un test échoue
//
// Garanties : chaque contribution est revalidée ; un identifiant déjà présent est ignoré ; les fins de ligne du fichier sont
// conservées ; si `lune run tests/run` échoue, les fichiers sont remis dans leur état d'origine. Aucun commit n'est fait :
// relis le résultat avec `git diff`. Les idées libres (type « note ») ne sont jamais appliquées : elles restent en attente.

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { validate } = require("./validate");

const ROOT = path.resolve(__dirname, "..", "..");

function luauString(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
}
function rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return `${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}`;
}

// Ligne Luau d'une contribution, dans le style EXACT du fichier de configuration visé.
function renderLine(type, f) {
  switch (type) {
    case "quest":
      return `table.freeze({ id = ${luauString(f.id)}, name = ${luauString(f.name)}, description = ${luauString(f.description)}, event = ${luauString(f.event)}, goal = ${f.goal}, reward = ${f.reward} }),`;
    case "bomb":
      return `bomb(${luauString(f.id)}, ${luauString(f.name)}, ${f.price}, Color3.fromRGB(${rgb(f.color)}), Enum.Material.${f.material}, ${luauString(f.description)}),`;
    case "effect":
      return `effect(${luauString(f.id)}, ${luauString(f.name)}, ${f.price}, Color3.fromRGB(${rgb(f.color)}), ${luauString(f.description)}),`;
    case "chat":
      return `table.freeze({ id = ${luauString(f.id)}, text = ${luauString(f.text)} }),`;
    case "emote":
      return `table.freeze({ id = ${luauString(f.id)}, name = ${luauString(f.name)}, animationId = ${luauString(f.animationId)}, looped = ${f.looped ? "true" : "false"} }),`;
    default:
      return null;
  }
}

// Où insérer : { file, before } = juste avant la ligne de fermeture de la liste ; { file, after } = après la dernière ligne qui correspond.
const TARGETS = {
  quest: { file: "src/shared/QuestConfig.luau", before: /^\}\) :: \{ Quest \}/ },
  chat: { file: "src/shared/QuickChatConfig.luau", before: /^\}\) :: \{ Phrase \}/ },
  emote: { file: "src/shared/EmoteConfig.luau", before: /^\}\) :: \{ Emote \}/ },
  bomb: { file: "src/shared/CosmeticConfig.luau", after: /^\tbomb\(/ },
  effect: { file: "src/shared/CosmeticConfig.luau", after: /^\teffect\(/ },
};

// Insère `line` dans `source` selon la cible. Retourne { text, done, reason }. Pur : testable sans fichier.
function insertLine(source, target, line, id) {
  const eol = source.includes("\r\n") ? "\r\n" : "\n";
  const lines = source.split(/\r?\n/);
  const quoted = '"' + id + '"';
  if (lines.some((l) => l.includes(quoted))) return { text: source, done: false, reason: `identifiant « ${id} » déjà présent` };

  let index = -1;
  if (target.before) {
    index = lines.findIndex((l) => target.before.test(l));
  } else {
    for (let i = 0; i < lines.length; i++) if (target.after.test(lines[i])) index = i + 1;
  }
  if (index < 0) return { text: source, done: false, reason: "point d'insertion introuvable (le fichier a changé de forme ?)" };
  lines.splice(index, 0, "\t" + line);
  return { text: lines.join(eol), done: true, reason: "" };
}

function readContributions(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((n) => /^[0-9]{10,16}-[a-z0-9]{6}\.json$/.test(n))
    .sort()
    .map((name) => {
      const file = path.join(dir, name);
      let raw;
      try {
        raw = JSON.parse(fs.readFileSync(file, "utf8"));
      } catch {
        return { name, file, invalid: "JSON illisible" };
      }
      return { name, file, raw };
    });
}

function plan(contributions, readSource) {
  const sources = new Map(); // fichier -> texte courant (cumule plusieurs contributions)
  const steps = [];
  for (const c of contributions) {
    if (c.invalid) {
      steps.push({ c, status: "skip", reason: c.invalid });
      continue;
    }
    if ((c.raw.status || "pending") !== "pending") continue;
    const check = validate(c.raw);
    if (!check.ok) {
      steps.push({ c, status: "skip", reason: "invalide : " + check.errors.join(" ; ") });
      continue;
    }
    const { type, fields } = check.clean;
    const target = TARGETS[type];
    if (!target) {
      steps.push({ c, status: "skip", reason: "idée libre : à traiter à la main" });
      continue;
    }
    const line = renderLine(type, fields);
    if (!sources.has(target.file)) sources.set(target.file, readSource(target.file));
    const result = insertLine(sources.get(target.file), target, line, fields.id);
    if (!result.done) {
      steps.push({ c, status: "skip", reason: result.reason });
      continue;
    }
    sources.set(target.file, result.text);
    steps.push({ c, status: "apply", file: target.file, line });
  }
  return { steps, sources };
}

function findLune() {
  const candidates = ["lune"];
  if (process.env.LOCALAPPDATA) candidates.push(path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Links", "lune.exe"));
  for (const candidate of candidates) {
    const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
    if (!probe.error && probe.status === 0) return candidate;
  }
  return null;
}

function main(argv) {
  const write = argv.includes("--write");
  const dirArg = argv.indexOf("--dir");
  const dir = dirArg >= 0 ? path.resolve(argv[dirArg + 1]) : path.join(__dirname, "contributions");
  const contributions = readContributions(dir);
  const { steps, sources } = plan(contributions, (file) => fs.readFileSync(path.join(ROOT, file), "utf8"));

  if (!steps.length) {
    console.log("Aucune contribution en attente.");
    return 0;
  }
  for (const s of steps) {
    if (s.status === "apply") console.log(`+ ${s.file}\n    ${s.line}`);
    else console.log(`- ignorée (${s.c.name}) : ${s.reason}`);
  }
  const applied = steps.filter((s) => s.status === "apply");
  if (!applied.length) return 0;
  if (!write) {
    console.log(`\nSimulation : ${applied.length} ajout(s). Relance avec --write pour les écrire (les tests sont lancés, puis tout est annulé en cas d'échec).`);
    return 0;
  }

  const backups = new Map();
  for (const file of sources.keys()) backups.set(file, fs.readFileSync(path.join(ROOT, file), "utf8"));
  for (const [file, content] of sources) fs.writeFileSync(path.join(ROOT, file), content);

  const lune = findLune();
  if (!lune) {
    for (const [file, content] of backups) fs.writeFileSync(path.join(ROOT, file), content);
    console.error("\nLune est introuvable : impossible de vérifier par les tests, rien n'a été modifié.");
    return 1;
  }
  const run = spawnSync(lune, ["run", "tests/run"], { cwd: ROOT, encoding: "utf8" });
  if (run.status !== 0) {
    for (const [file, content] of backups) fs.writeFileSync(path.join(ROOT, file), content);
    console.error("\nLes tests échouent avec ces ajouts : tout a été annulé.\n" + `${run.stdout || ""}${run.stderr || ""}`.split("\n").filter((l) => /✗|erreur|attendu|Bilan/.test(l)).slice(0, 20).join("\n"));
    return 1;
  }
  for (const s of applied) {
    s.c.raw.status = "applied";
    s.c.raw.result = `Ajoutée à ${s.file}. Tests : OK.`;
    fs.writeFileSync(s.c.file, JSON.stringify(s.c.raw, null, 2) + "\n");
  }
  console.log(`\n${applied.length} contribution(s) appliquée(s), tests OK. Relis avec « git diff » : aucun commit n'a été fait.`);
  return 0;
}

module.exports = { renderLine, insertLine, plan, readContributions, TARGETS, luauString };

if (require.main === module) process.exit(main(process.argv.slice(2)));
