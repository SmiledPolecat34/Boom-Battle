// Tests de bout en bout avec de VRAIS dépôts Git (origin nu + deux clones = deux PC) et un stockage « dossier ».
// Lancer : npm run assets:test      (n'utilise ni Google Drive ni le dépôt réel)
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const crypto = require("crypto");
const { spawnSync, execFileSync } = require("child_process");

const SRC = path.resolve(__dirname, "..");
const TAR = process.platform === "win32" ? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe") : "tar";
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "bbsync-"));
const drive = path.join(tmp, "drive");
const origin = path.join(tmp, "origin.git");
const A = path.join(tmp, "pcA"), B = path.join(tmp, "pcB");

let pass = 0, fail = 0;
function ok(cond, name, extra) {
	if (cond) { pass++; console.log("  PASS  " + name); }
	else { fail++; console.log("  FAIL  " + name + (extra ? "  -> " + extra : "")); }
}
const step = (t) => console.log("\n== " + t);

const cleanEnv = () => { const e = { ...process.env, BB_ASSETS_RETRY_MS: "10" }; for (const k of Object.keys(e)) if (/^BB_ASSETS_(FAULT|REPO|HOOK|SKIP)$/.test(k)) delete e[k]; return e; };
function sh(cwd, cmd, args, env) {
	const r = spawnSync(cmd, args, { cwd, encoding: "utf8", env: { ...cleanEnv(), ...(env || {}) } });
	return { code: r.status, out: (r.stdout || "") + (r.stderr || "") };
}
const git = (cwd, ...a) => sh(cwd, "git", a);
const cli = (cwd, args, env) => sh(cwd, process.execPath, [path.join(cwd, "tools/assets/sync/cli.js"), ...args], env);
const art = (pc) => path.join(pc, "assets/3D/BOOM_BATTLE_ART");
const w = (pc, rel, data) => { const f = path.join(art(pc), rel); fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, data); };
const state = (pc) => JSON.parse(fs.readFileSync(path.join(pc, ".assets-sync/state.json"), "utf8"));
const driveZips = () => fs.readdirSync(drive).filter((n) => n.endsWith(".zip")).sort();
const vers = (pc) => fs.existsSync(path.join(pc, "assets-sync/versions")) ? fs.readdirSync(path.join(pc, "assets-sync/versions")).sort() : [];

function treeOf(dir) {
	const out = {};
	const walk = (d, rel) => {
		for (const e of fs.readdirSync(d, { withFileTypes: true })) {
			const r = rel ? rel + "/" + e.name : e.name;
			if (e.isDirectory()) { out[r + "/"] = "dir"; walk(path.join(d, e.name), r); }
			else out[r] = crypto.createHash("sha256").update(fs.readFileSync(path.join(d, e.name))).digest("hex");
		}
	};
	if (fs.existsSync(dir)) walk(dir, "");
	return out;
}
const sameTree = (a, b) => JSON.stringify(treeOf(art(a))) === JSON.stringify(treeOf(art(b)));
function commit(pc, msg) { return git(pc, "commit", "--allow-empty", "-q", "-m", msg); }

try {
	step("Préparation : origin nu + PC A (avec outils) + Drive simulé");
	fs.mkdirSync(drive, { recursive: true });
	git(tmp, "init", "--bare", "-q", "-b", "main", origin);
	git(tmp, "clone", "-q", origin, A);
	for (const [k, v] of [["user.name", "Dev A"], ["user.email", "a@x"], ["core.autocrlf", "false"]]) git(A, "config", k, v);
	fs.mkdirSync(path.join(A, "tools/assets/sync"), { recursive: true });
	for (const f of fs.readdirSync(SRC)) if (f.endsWith(".js")) fs.copyFileSync(path.join(SRC, f), path.join(A, "tools/assets/sync", f));
	fs.copyFileSync(path.resolve(SRC, "../../../package.json"), path.join(A, "package.json"));
	let r = cli(A, ["setup", "--path", drive]);
	ok(r.code === 0, "setup A", r.out);
	ok(["pre-commit", "pre-push", "post-merge", "post-rewrite", "post-checkout"].every((h) => fs.readFileSync(path.join(A, ".git/hooks", h), "utf8").includes("boom-battle-assets")), "hooks installés");
	r = cli(A, ["setup", "--path", drive]);
	const pc = fs.readFileSync(path.join(A, ".git/hooks/pre-commit"), "utf8");
	ok((pc.match(/>>> boom-battle-assets/g) || []).length === 1, "setup idempotent (un seul bloc de hook)");
	git(A, "add", "-A"); git(A, "commit", "-q", "--no-verify", "-m", "outils");
	git(A, "push", "-q", "-u", "origin", "main");

	step("Premier envoi (archive FULL) déclenché par le hook pre-commit");
	w(A, "models/bombe.bin", crypto.randomBytes(1 << 20));
	w(A, "models/é accentué.txt", "bonjour");
	w(A, "docs/lisez.txt", "v1");
	fs.mkdirSync(path.join(art(A), "dossier vide"), { recursive: true });
	r = commit(A, "assets v1");
	ok(r.code === 0, "git commit réussit avec le hook", r.out);
	ok(driveZips().length === 1 && /^BOOM_BATTLE_ART_FULL_\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d\.zip$/.test(driveZips()[0]), "nom FULL_YYYY-MM-DD_HH-mm-ss", driveZips().join());
	ok(fs.readFileSync(path.join(drive, driveZips()[0])).subarray(0, 2).toString() === "PK", "l'archive est un vrai ZIP (PK)");
	const v1 = JSON.parse(fs.readFileSync(path.join(A, "assets-sync/versions", vers(A)[0]), "utf8"));
	ok(v1.version === 1 && v1.type === "full" && v1.sha256.length === 64 && v1.driveId && v1.createdAtParis && v1.timezone === "Europe/Paris", "manifeste : version, sha256, driveId, date Paris");
	ok(git(A, "show", "--stat", "--format=", "HEAD").out.includes("assets-sync/versions/v000001_"), "le fichier de version est dans le commit");
	ok(!git(A, "ls-files").out.match(/\.zip|BOOM_BATTLE_ART\//), "aucun ZIP ni asset 3D dans Git");
	r = git(A, "push", "-q"); ok(r.code === 0, "git push (pre-push vérifie Drive)", r.out);

	step("Deuxième PC sans assets");
	git(tmp, "clone", "-q", origin, B);
	for (const [k, v] of [["user.name", "Dev B"], ["user.email", "b@x"], ["core.autocrlf", "false"]]) git(B, "config", k, v);
	ok(!fs.existsSync(art(B)), "B n'a aucun asset au départ");
	r = cli(B, ["setup", "--path", drive]); ok(r.code === 0, "setup B", r.out);
	r = cli(B, ["pull"]);
	ok(r.code === 0 && sameTree(A, B), "pull initial : dossier identique à A (accents, dossier vide, binaire)", r.out);
	ok(state(B).applied === 1 && r.out.includes("Décompression"), "version locale = 1 et progression affichée");
	ok(!fs.existsSync(path.join(B, "assets/3D/BOOM_BATTLE_ART/BOOM_BATTLE_ART")), "pas de dossier imbriqué");
	ok(!fs.existsSync(path.join(B, ".assets-sync/tmp/dl")) || fs.readdirSync(path.join(B, ".assets-sync/tmp/dl")).length === 0, "ZIP temporaires supprimés, Drive intact", driveZips().join());
	ok(cli(B, ["verify"]).code === 0, "verify OK");

	step("Aucune modification");
	const nZip = driveZips().length;
	r = cli(A, ["push"]); ok(r.code === 0 && r.out.includes("Aucune modification") && driveZips().length === nZip, "push sans changement : rien envoyé", r.out);
	r = cli(B, ["pull"]); ok(r.code === 0 && r.out.includes("à jour") && !r.out.includes("Téléchargement"), "pull à jour : rien téléchargé", r.out);

	step("Ajout d'un fichier -> patch incrémental, appliqué par git pull (post-merge)");
	w(A, "docs/nouveau.txt", "nouveau");
	r = commit(A, "ajout"); ok(r.code === 0 && driveZips().length === nZip + 1, "patch v2 envoyé", r.out);
	const patchName = driveZips().find((n) => n.includes("_PATCH_"));
	ok(!!patchName, "nom PATCH_YYYY-MM-DD_HH-mm-ss", patchName);
	const listing = sh(tmp, TAR, ["-tf", path.join(drive, patchName)]).out.split(/\r?\n/).filter((l) => l && !l.endsWith("/")).sort();
	ok(listing.length === 2 && listing.includes("__bbpatch__.json") && listing.includes("docs/nouveau.txt"),"le patch ne contient que le fichier ajouté", listing.join(","));
	git(A, "push", "-q");
	r = git(B, "pull", "-q"); ok(r.code === 0 && fs.existsSync(path.join(art(B), "docs/nouveau.txt")) && state(B).applied === 2, "git pull applique automatiquement le patch", r.out);

	step("Plusieurs patches de retard : modification, suppression fichier+dossier, ajout");
	w(A, "docs/lisez.txt", "v3 modifié"); commit(A, "modif");
	fs.rmSync(path.join(art(A), "docs/nouveau.txt")); fs.rmSync(path.join(art(A), "dossier vide"), { recursive: true }); fs.rmSync(path.join(art(A), "models/é accentué.txt")); commit(A, "suppr");
	w(A, "extra/a/b/c.txt", "profond"); commit(A, "ajout profond");
	ok(vers(A).length === 5, "5 versions au total", vers(A).join());
	git(A, "push", "-q");
	r = git(B, "pull", "-q");
	ok(sameTree(A, B) && state(B).applied === 5, "B (3 patches de retard) identique à A, appliqués dans l'ordre", r.out);
	const bk = path.join(B, ".assets-sync/backup");
	const bkFiles = fs.existsSync(bk) ? Object.keys(treeOf(bk)).filter((k) => !k.endsWith("/")) : [];
	ok(bkFiles.some((f) => f.endsWith("nouveau.txt")) && bkFiles.some((f) => f.endsWith("é accentué.txt")), "fichiers supprimés sauvegardés (pas perdus)", bkFiles.join());

	step("Interruption réseau (téléchargement)");
	w(A, "docs/reseau.txt", crypto.randomBytes(300000).toString("hex")); commit(A, "gros"); git(A, "push", "-q");
	const before = JSON.stringify(treeOf(art(B)));
	r = git(B, "fetch", "-q");
	r = sh(B, "git", ["pull", "-q"], { BB_ASSETS_FAULT: "get@1000" });
	ok(state(B).applied === 5 && JSON.stringify(treeOf(art(B))) === before, "coupure : version locale inchangée, fichiers préservés", r.out);
	ok(r.out.includes("tentative"), "erreur réseau signalée, plusieurs tentatives", r.out.slice(-300));
	r = cli(B, ["pull"]); ok(r.code === 0 && sameTree(A, B) && state(B).applied === 6, "reprise après coupure : synchronisation terminée", r.out);

	step("Interruption réseau (envoi) puis reprise");
	w(A, "docs/envoi.txt", crypto.randomBytes(200000).toString("hex"));
	r = sh(A, process.execPath, [path.join(A, "tools/assets/sync/cli.js"), "push"], { BB_ASSETS_FAULT: "put@1000" });
	ok(r.code !== 0 && vers(A).length === 6, "envoi interrompu : aucune version publiée dans Git", r.out.slice(-200));
	const zipsBefore = driveZips().length;
	ok(zipsBefore === 6, "Drive : aucun ZIP final pour l'envoi interrompu", String(zipsBefore));
	r = cli(A, ["push"]); ok(r.code === 0 && r.out.includes("Reprise") && vers(A).length === 7, "reprise : l'archive créée est réutilisée et publiée", r.out);
	commit(A, "envoi repris"); git(A, "push", "-q"); git(B, "pull", "-q");
	ok(sameTree(A, B), "B à jour");

	step("Conflit : modifications locales non publiées de B vs patch de A");
	w(B, "docs/lisez.txt", "version locale de B (non publiée)");
	w(A, "docs/lisez.txt", "version de A"); commit(A, "A modifie lisez"); git(A, "push", "-q");
	r = git(B, "pull", "-q");
	ok(fs.readFileSync(path.join(art(B), "docs/lisez.txt"), "utf8") === "version locale de B (non publiée)", "pull : le travail local de B n'est PAS écrasé", r.out);
	r = cli(B, ["pull"]); ok(r.code === 3 && r.out.includes("CONFLIT") && r.out.includes("docs/lisez.txt"), "conflit signalé (code 3)", r.out);
	ok(state(B).applied === 7, "version locale non avancée");
	r = cli(B, ["pull", "--force"]);
	const saved = Object.entries(treeOf(path.join(B, ".assets-sync/backup"))).filter(([k]) => k.endsWith("lisez.txt"));
	ok(r.code === 0 && fs.readFileSync(path.join(art(B), "docs/lisez.txt"), "utf8") === "version de A" && saved.length >= 1, "--force : écrasé après sauvegarde de la version de B", r.out);

	step("Conflit : publication simultanée par deux développeurs (même numéro de version)");
	w(A, "parallele/de_a.txt", "A");
	w(B, "parallele/de_b.txt", "B");
	r = commit(A, "A publie v9"); ok(r.code === 0, "A publie", r.out);
	git(A, "push", "-q");
	r = commit(B, "B publie aussi v9 (sans avoir tiré)"); ok(r.code === 0, "B publie en parallèle (fourche)", r.out);
	r = git(B, "push", "-q"); ok(r.code !== 0, "git push de B refusé (non fast-forward)", r.out.slice(-150));
	r = git(B, "pull", "--no-rebase", "-q", "--no-edit");
	ok(r.code === 0 && r.out !== undefined && cli(B, ["status"]).out.includes("Fourche"), "après merge : fourche détectée", r.out);
	r = git(B, "push", "-q"); ok(r.code !== 0, "pre-push bloque la fourche", r.out.slice(-250));
	r = cli(B, ["rebase"]); ok(r.code === 0, "assets:rebase", r.out);
	r = cli(B, ["pull"]); ok(r.code === 0 && fs.existsSync(path.join(art(B), "parallele/de_a.txt")) && fs.existsSync(path.join(art(B), "parallele/de_b.txt")), "pull sans conflit : travail de B conservé + travail de A appliqué", r.out);
	r = cli(B, ["push"]); ok(r.code === 0 && r.out.includes("publiée"), "B republie ses changements en nouveau patch", r.out);
	commit(B, "fusion assets");
	r = git(B, "push", "-q"); ok(r.code === 0, "git push de B accepté", r.out);
	git(A, "pull", "--no-rebase", "-q", "--no-edit");
	ok(sameTree(A, B), "A et B identiques, aucun travail perdu");

	step("pre-push : manifeste pointant vers une archive absente de Drive");
	w(A, "docs/orphelin.txt", "x"); commit(A, "orphelin");
	const last = vers(A).slice(-1)[0];
	const lm = JSON.parse(fs.readFileSync(path.join(A, "assets-sync/versions", last), "utf8"));
	fs.renameSync(path.join(drive, lm.name), path.join(tmp, "cache-" + lm.name));
	r = git(A, "push", "-q"); ok(r.code !== 0 && r.out.includes("absente") , "push bloqué si l'archive manque", r.out.slice(-200));
	fs.renameSync(path.join(tmp, "cache-" + lm.name), path.join(drive, lm.name));
	r = git(A, "push", "-q"); ok(r.code === 0, "push accepté une fois l'archive présente", r.out);
	git(B, "pull", "--no-rebase", "-q", "--no-edit");

	step("Intégrité et reconstruction complète");
	fs.writeFileSync(path.join(art(B), "docs/lisez.txt"), "CORROMPU");
	r = cli(B, ["verify"]); ok(r.code === 1 && r.out.includes("docs/lisez.txt"), "verify détecte une modification", r.out);
	const refTree = JSON.stringify(treeOf(art(A)));
	r = cli(B, ["restore"]);
	ok(r.code === 0 && JSON.stringify(treeOf(art(B))) === refTree, "restore reconstruit le dossier exact depuis FULL + patches", r.out.slice(-300));
	ok(fs.readdirSync(path.join(B, ".assets-sync/backup")).some((n) => n.endsWith("avant-restore")), "ancien dossier conservé en sauvegarde");
	ok(cli(B, ["verify"]).code === 0, "verify OK après restore");
	r = cli(B, ["status"]); ok(r.code === 0 && r.out.includes("aucune"), "status : aucune modification locale", r.out);
	const names = driveZips();
	const used = vers(A).map((n) => JSON.parse(fs.readFileSync(path.join(A, "assets-sync/versions", n), "utf8")).name);
	ok(new Set(names).size === names.length && used.every((n) => names.includes(n)), "chaque version a son archive Drive distincte");
	ok(names.length === used.length + 1, "l'archive abandonnée par le rebase n'a PAS été supprimée de Drive (1 orpheline)", names.length + " zips / " + used.length + " versions");
} catch (e) {
	fail++; console.log("EXCEPTION", e.stack);
} finally {
	console.log(`\nRésultat : ${pass} réussis, ${fail} échecs  (dossier de test : ${tmp})`);
	if (!fail && !process.env.BB_KEEP) fs.rmSync(tmp, { recursive: true, force: true, maxRetries: 3 });
	process.exit(fail ? 1 : 0);
}
