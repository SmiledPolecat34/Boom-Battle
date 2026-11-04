#!/usr/bin/env node
// Garde-fou « une modif = un test » (aucune dépendance : Node seulement).
//
// Règle : pour chaque module de src/ modifié, au moins UNE suite tests/unit/**/*.spec.luau qui le charge doit
// aussi être modifiée (ou ajoutée) dans le même changement. Les modules listés dans tests/untested.json sont
// seulement signalés (avertissement) : leur test n'est pas encore possible hors Studio.
//
// Usage :
//   node tools/ci/check-tests-changed.js <base>     compare HEAD à <base> (CI : origin/<branche cible>)
//   node tools/ci/check-tests-changed.js            compare l'arbre de travail (modifs non commitées + non suivies) à HEAD
//
// Échappatoire (CI) : variable d'environnement ALLOW_NO_TEST=1 (étiquette « no-test-needed » sur la PR). À réserver aux
// changements sans effet sur le comportement (commentaires, renommage pur) ; la justification va dans la PR.
//
// Code de sortie : 0 = OK, 1 = test manquant, 2 = erreur d'utilisation.

const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");

function git(...args) {
	return execFileSync("git", args, { cwd: root, encoding: "utf8" });
}

function changedFiles(base) {
	const names = new Set();
	if (base) {
		for (const line of git("diff", "--name-only", "--diff-filter=ACMR", `${base}...HEAD`).split("\n")) {
			if (line.trim()) names.add(line.trim());
		}
	} else {
		for (const line of git("status", "--porcelain", "--untracked-files=all").split("\n")) {
			if (!line.trim()) continue;
			// Format : « XY chemin » (ou « XY ancien -> nouveau » pour un renommage).
			const entry = line.slice(3).split(" -> ").pop().trim().replace(/^"|"$/g, "");
			if (!/^D/.test(line.slice(0, 2).trim()) && !/D$/.test(line.slice(0, 2).trim())) names.add(entry);
		}
	}
	return [...names].map((f) => f.replace(/\\/g, "/"));
}

function walk(dir, out = []) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) walk(full, out);
		else out.push(full);
	}
	return out;
}

function moduleName(file) {
	const base = path.posix.basename(file);
	if (/\.(server|client)\.luau$/.test(base)) return null; // scripts, pas des modules
	return base.replace(/\.luau$/, "");
}

const base = process.argv[2];
let changed;
try {
	changed = changedFiles(base);
} catch (error) {
	console.error(`Impossible de lire les changements git : ${error.message}`);
	process.exit(2);
}

const manifest = JSON.parse(fs.readFileSync(path.join(root, "tests", "untested.json"), "utf8"));
const untested = manifest.untested || {};

const changedSources = changed.filter((f) => /^src\/.*\.luau$/.test(f));
const changedSpecs = changed.filter((f) => /^tests\/unit\/.*\.spec\.luau$/.test(f));
const changedSpecText = changedSpecs
	.filter((f) => !f.includes("/meta/"))
	.filter((f) => fs.existsSync(path.join(root, f)))
	.map((f) => fs.readFileSync(path.join(root, f), "utf8"));

const missing = [];
const warnings = [];
for (const file of changedSources) {
	const name = moduleName(file);
	if (!name) continue;
	const hasTest = changedSpecText.some((text) => text.includes(`module("${name}")`) || text.includes(`.${name}"`));
	if (hasTest) continue;
	if (untested[name]) warnings.push(`${file} : ${untested[name]}`);
	else missing.push(file);
}

for (const warning of warnings) console.warn(`⚠ non testable hors Studio — ${warning}`);

if (missing.length > 0 && process.env.ALLOW_NO_TEST === "1") {
	console.warn(`⚠ ALLOW_NO_TEST=1 : test manquant toléré pour ${missing.join(", ")}`);
	process.exit(0);
}
if (missing.length > 0) {
	console.error("✗ Modules de src/ modifiés sans test correspondant dans ce changement :");
	for (const file of missing) console.error(`    - ${file}`);
	console.error("\nAjoute ou mets à jour la suite tests/unit/<dossier>/<Module>.spec.luau (voir tests/README.md).");
	process.exit(1);
}
console.log(`✓ garde-fou « une modif = un test » : ${changedSources.length} fichier(s) source, ${changedSpecs.length} suite(s) modifiée(s).`);
