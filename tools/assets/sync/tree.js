// Contexte, arbre de fichiers (scan + SHA-256 avec cache taille/date), diff, versions.
"use strict";
const fs = require("fs");
const path = require("path");
const { hashFile, readJson, AssetsError, progress, setLogFile } = require("./util");
const G = require("./git");

const ART_REL = "assets/3D/BOOM_BATTLE_ART";
const RESERVED = "__bbpatch__.json";

function makeCtx(cwd) {
	const repo = path.resolve(process.env.BB_ASSETS_REPO || G.toplevel(cwd || process.cwd()));
	const ctx = {
		repo,
		artDir: path.join(repo, ART_REL),
		syncDir: path.join(repo, ".assets-sync"),          // état local, jamais versionné
		metaDir: path.join(repo, "assets-sync"),           // métadonnées versionnées
		verDir: path.join(repo, "assets-sync", "versions"),
	};
	ctx.statePath = path.join(ctx.syncDir, "state.json");
	ctx.tmpDir = path.join(ctx.syncDir, "tmp");
	ctx.backupDir = path.join(ctx.syncDir, "backup");
	fs.mkdirSync(ctx.syncDir, { recursive: true });
	setLogFile(path.join(ctx.syncDir, "sync.log"));
	const base = readJson(path.join(ctx.metaDir, "config.json"), {});
	const local = readJson(path.join(ctx.syncDir, "local.json"), {});
	ctx.cfg = { ...base, ...local, remote: { ...(base.remote || {}), ...(local.remote || {}) } };
	return ctx;
}

const loadState = (ctx) => readJson(ctx.statePath, { applied: 0, cache: {} });

// ---- scan -------------------------------------------------------------------
async function scan(ctx, { full = false, cache = {}, quiet = false } = {}) {
	const files = {}, dirs = [], newCache = {};
	const todo = [];
	const walk = (dir, rel) => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const r = rel ? rel + "/" + e.name : e.name;
			const f = path.join(dir, e.name);
			if (e.isDirectory()) { dirs.push(r); walk(f, r); }
			else if (e.isFile()) {
				if (r === RESERVED) throw new AssetsError(`Nom de fichier réservé : ${r}`, "FATAL");
				const st = fs.statSync(f);
				const c = cache[r];
				if (!full && c && c.size === st.size && c.mtimeMs === st.mtimeMs) {
					files[r] = { size: st.size, sha256: c.sha256 }; newCache[r] = c;
				} else todo.push({ r, f, st });
			}
		}
	};
	if (fs.existsSync(ctx.artDir)) walk(ctx.artDir, "");
	if (todo.length) {
		const total = todo.reduce((a, t) => a + t.st.size, 0);
		const pr = quiet ? { update() {}, done() {} } : progress(`Empreintes SHA-256 (${todo.length} fichiers)`, total);
		let base = 0;
		for (const t of todo) {
			const h = await hashFile(t.f, false, (n) => pr.update(base + n));
			base += t.st.size;
			files[t.r] = { size: t.st.size, sha256: h.sha256 };
			newCache[t.r] = { size: t.st.size, mtimeMs: t.st.mtimeMs, sha256: h.sha256 };
		}
		pr.done();
	}
	dirs.sort();
	return { files, dirs, cache: newCache };
}

// Rapide (sans hachage) : des fichiers ont-ils changé de taille/date, ou ont-ils été ajoutés/supprimés ?
function quickChanged(ctx, state, baseTree) {
	const seen = new Set();
	let changed = false;
	const walk = (dir, rel) => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const r = rel ? rel + "/" + e.name : e.name;
			if (e.isDirectory()) { seen.add(r + "/"); walk(path.join(dir, e.name), r); }
			else if (e.isFile()) {
				seen.add(r);
				const st = fs.statSync(path.join(dir, e.name));
				const c = (state.cache || {})[r];
				if (!c || c.size !== st.size || c.mtimeMs !== st.mtimeMs) changed = true;
			}
		}
	};
	if (fs.existsSync(ctx.artDir)) walk(ctx.artDir, "");
	if (changed) return true;
	const known = Object.keys(baseTree.files).concat(baseTree.dirs.map((d) => d + "/"));
	return known.length !== seen.size || known.some((k) => !seen.has(k));
}

function diffTrees(from, to) {
	const added = [], modified = [], deleted = [];
	for (const [p, f] of Object.entries(to.files)) {
		if (!from.files[p]) added.push(p);
		else if (from.files[p].sha256 !== f.sha256) modified.push(p);
	}
	for (const p of Object.keys(from.files)) if (!to.files[p]) deleted.push(p);
	const fd = new Set(from.dirs), td = new Set(to.dirs);
	return {
		added: added.sort(), modified: modified.sort(), deleted: deleted.sort(),
		addedDirs: to.dirs.filter((d) => !fd.has(d)), deletedDirs: from.dirs.filter((d) => !td.has(d)),
	};
}
const isEmptyDiff = (d) => !d.added.length && !d.modified.length && !d.deleted.length && !d.addedDirs.length && !d.deletedDirs.length;

// ---- versions (métadonnées versionnées dans Git) ----------------------------
const VER_RE = /^v(\d{6})_([0-9a-f]{8})\.json$/;
const verFileName = (n, sha) => `v${String(n).padStart(6, "0")}_${sha.slice(0, 8)}.json`;

// Charge les versions de l'arbre de travail. Un numéro en double = fourche entre développeurs.
function loadVersions(ctx) {
	const byNum = {};
	if (fs.existsSync(ctx.verDir)) {
		for (const n of fs.readdirSync(ctx.verDir)) {
			const m = VER_RE.exec(n);
			if (!m) continue;
			(byNum[Number(m[1])] = byNum[Number(m[1])] || []).push({ ...readJson(path.join(ctx.verDir, n)), _file: n });
		}
	}
	const nums = Object.keys(byNum).map(Number).sort((a, b) => a - b);
	const fork = nums.filter((n) => byNum[n].length > 1);
	const list = nums.map((n) => byNum[n][0]);
	return { list, fork, byNum, head: nums.length ? nums[nums.length - 1] : 0 };
}

// Vérifie la chaîne : 1..N contigu, première = FULL, parent = version précédente.
function checkChain(V) {
	if (V.fork.length) {
		throw new AssetsError(`Conflit de versions (plusieurs archives pour la version ${V.fork.join(", ")}) : deux développeurs ont publié en parallèle. Lancez \`npm run assets:rebase\`.`, "FORK");
	}
	V.list.forEach((v, i) => {
		if (v.version !== i + 1) throw new AssetsError(`Chaîne de versions incohérente : version ${i + 1} manquante.`, "FATAL");
		if (v.parent !== i) throw new AssetsError(`Version ${v.version} : parent ${v.parent} attendu ${i}.`, "FATAL");
		if (i === 0 && v.type !== "full") throw new AssetsError("La version 1 doit être une archive complète.", "FATAL");
	});
}
const treeOf = (V, n) => (n === 0 ? { files: {}, dirs: [] } : V.list[n - 1].tree);

module.exports = { ART_REL, RESERVED, makeCtx, loadState, scan, quickChanged, diffTrees, isEmptyDiff, loadVersions, checkChain, treeOf, verFileName, VER_RE };
