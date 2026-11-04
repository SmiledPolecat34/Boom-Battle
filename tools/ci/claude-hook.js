#!/usr/bin/env node
// Crochets Claude Code (voir .claude/settings.json) qui appliquent la règle « une modif = un test » automatiquement.
//
//   node tools/ci/claude-hook.js post-edit   après chaque Edit/Write d'un fichier de src/ ou tests/ : lance les tests
//   node tools/ci/claude-hook.js stop        avant la fin d'un tour : refuse de terminer si src/ a changé sans test
//
// Protocole des crochets : le JSON de l'événement arrive sur stdin ; un code de sortie 2 renvoie stderr à Claude, qui
// doit corriger. Tout autre code laisse passer. Aucune erreur d'outillage (Lune absent, git absent) ne bloque jamais :
// l'absence de l'outil est signalée, pas punie.

const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const mode = process.argv[2];

function readStdin() {
	try {
		return JSON.parse(fs.readFileSync(0, "utf8") || "{}");
	} catch {
		return {};
	}
}

function findLune() {
	const candidates = ["lune"];
	if (process.env.LOCALAPPDATA) {
		candidates.push(path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Links", "lune.exe"));
	}
	for (const candidate of candidates) {
		const probe = spawnSync(candidate, ["--version"], { encoding: "utf8" });
		if (!probe.error && probe.status === 0) return candidate;
	}
	return null;
}

const input = readStdin();

if (mode === "post-edit") {
	const file = String((input.tool_input && (input.tool_input.file_path || input.tool_input.path)) || "").replace(/\\/g, "/");
	const relevant = /\/(src|tests)\/.*\.luau$/.test(file) || /\/tests\/untested\.json$/.test(file);
	if (!relevant) process.exit(0);

	const lune = findLune();
	if (!lune) {
		console.error("Lune introuvable : tests non exécutés (installer : winget install Lune.Lune).");
		process.exit(0);
	}
	const run = spawnSync(lune, ["run", "tests/run"], { cwd: root, encoding: "utf8" });
	if (run.status === 0) process.exit(0);
	const output = `${run.stdout || ""}${run.stderr || ""}`;
	const failures = output
		.split("\n")
		.filter((line) => /✗|Bilan|erreur|attendu/.test(line))
		.slice(0, 40)
		.join("\n");
	console.error(`Les tests automatisés échouent après la modification de ${path.basename(file)} :\n${failures || output.slice(-1500)}`);
	if (/\/src\/.*\.luau$/.test(file)) {
		console.error("\nCorrige le code OU la suite concernée, puis relance : lune run tests/run");
	}
	process.exit(2);
}

if (mode === "stop") {
	if (input.stop_hook_active) process.exit(0); // évite toute boucle : un seul rappel par tour
	const gate = spawnSync("node", [path.join("tools", "ci", "check-tests-changed.js")], { cwd: root, encoding: "utf8" });
	if (gate.status === 1) {
		console.error(
			`${gate.stderr}\nRègle du projet : toute modification de src/ s'accompagne d'un test automatisé (tests/unit/...). ` +
				"Ajoute-le, lance « lune run tests/run », puis termine."
		);
		process.exit(2);
	}
	process.exit(0);
}

console.error("Usage : claude-hook.js post-edit|stop");
process.exit(0);
