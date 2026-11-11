// Opérations de synchronisation : push, pull, status, verify, restore, rebase, contrôle pre-push.
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");
const U = require("./util");
const G = require("./git");
const T = require("./tree");
const { openRemote, matchesRemote } = require("./remote");
const { AssetsError, info, warn } = U;

// Sous Windows on appelle explicitement bsdtar (System32) : le `tar` de Git Bash est GNU tar et ne sait pas faire de ZIP.
const TAR = process.platform === "win32" ? path.join(process.env.SystemRoot || "C:\\Windows", "System32", "tar.exe") : "tar";
const VER_DIR_REL = "assets-sync/versions";

function runTar(args, onLine) {
	return new Promise((resolve, reject) => {
		const p = spawn(TAR, args, { windowsHide: true });
		let errTxt = "", buf = "";
		p.stderr.on("data", (d) => {
			buf += d;
			const lines = buf.split(/\r?\n/);
			buf = lines.pop();
			for (const l of lines) { if (onLine && /^[axr] /.test(l)) onLine(l); else errTxt += l + "\n"; }
		});
		p.on("error", (e) => reject(new AssetsError("tar introuvable (" + TAR + ") : " + e.message, "FATAL")));
		p.on("close", (c) => c === 0 ? resolve() : reject(new Error("tar a échoué (code " + c + ") : " + errTxt.trim().split("\n").slice(-2).join(" | "))));
	});
}

const rmrf = (p) => fs.rmSync(p, { recursive: true, force: true, maxRetries: 3 });
const sumSizes = (tree, paths) => paths.reduce((a, p) => a + (tree.files[p] ? tree.files[p].size : 0), 0);

function checkDisk(dir, need, what) {
	let free;
	try { fs.mkdirSync(dir, { recursive: true }); const s = fs.statfsSync(dir); free = s.bavail * s.bsize; } catch (_) { return; }
	const required = Math.ceil(need * 1.05) + (64 << 20);
	if (free < required) {
		throw new AssetsError(`Espace disque insuffisant pour ${what} : ${U.fmtBytes(required)} nécessaires, ${U.fmtBytes(free)} libres sur ${path.parse(path.resolve(dir)).root}. Libérez de la place puis relancez (rien n'a été modifié).`, "FATAL");
	}
}

// ---- création du ZIP (liens physiques : aucune copie, noms Unicode corrects) --
async function createZip(ctx, zipPath, entries, patch) {
	const stage = path.join(ctx.tmpDir, "stage-" + process.pid);
	rmrf(stage);
	fs.mkdirSync(stage, { recursive: true });
	try {
		for (const rel of entries) {
			const src = path.join(ctx.artDir, ...rel.split("/")), dst = path.join(stage, ...rel.split("/"));
			fs.mkdirSync(path.dirname(dst), { recursive: true });
			try { fs.linkSync(src, dst); } catch (_) { fs.copyFileSync(src, dst); }
		}
		U.writeJson(path.join(stage, T.RESERVED), patch);
		const tops = fs.readdirSync(stage);
		const pr = U.progress("Compression", entries.length + 1);
		let n = 0;
		fs.rmSync(zipPath, { force: true });
		await runTar(["-a", "-cvf", zipPath, "-C", stage, ...tops], () => pr.update(++n));
		pr.done();
	} finally { rmrf(stage); }
}

async function extractZip(zipPath, dest, count) {
	fs.mkdirSync(dest, { recursive: true });
	const pr = U.progress("Décompression", count);
	let n = 0;
	await runTar(["-xvf", zipPath, "-C", dest], () => pr.update(++n));
	pr.done();
}

// ---- état ------------------------------------------------------------------
const saveState = (ctx, st) => U.writeJson(ctx.statePath, st);
function isConfigured(ctx) {
	const r = ctx.cfg.remote || {};
	return !!((r.type === "folder" && r.path) || (r.type === "rclone" && r.driveFolderId));
}
function mustBeReady(ctx) {
	if (!fs.existsSync(path.join(ctx.repo, ".git"))) throw new AssetsError("Pas un dépôt Git.", "FATAL");
	if (!isConfigured(ctx)) throw new AssetsError("Synchronisation non configurée. Lancez `npm run assets:setup` (voir tools/assets/sync/README_ASSETS_SYNC.md).", "UNCONFIGURED");
}
function upstreamHead(ctx) {
	const up = G.upstream(ctx.repo);
	if (!up) return { up: null, head: 0 };
	let head = 0;
	for (const f of G.lsTree(ctx.repo, up, VER_DIR_REL)) {
		const m = T.VER_RE.exec(path.posix.basename(f));
		if (m) head = Math.max(head, Number(m[1]));
	}
	return { up, head };
}

// ---- push -------------------------------------------------------------------
async function push(ctx, opts = {}) {
	mustBeReady(ctx);
	const release = U.acquireLock(path.join(ctx.syncDir, "lock"));
	try {
		const remote = openRemote(ctx.cfg);
		const V = T.loadVersions(ctx); T.checkChain(V);
		const state = T.loadState(ctx);
		if (state.applied < V.head) throw new AssetsError(`Les assets locaux (v${state.applied}) sont en retard sur le manifeste (v${V.head}) : lancez \`npm run assets:pull\` avant de publier.`, "BEHIND");
		if (state.applied > V.head) throw new AssetsError(`Les assets locaux (v${state.applied}) sont plus récents que le manifeste (v${V.head}) : manifeste ancien ou non commité. Vérifiez votre branche.`, "FATAL");
		const upH = upstreamHead(ctx);
		if (upH.head > V.head) throw new AssetsError(`Le dépôt distant (${upH.up}) contient des assets plus récents (v${upH.head}) : faites \`git pull\` (puis \`npm run assets:pull\`) avant de publier, pour ne pas écraser le travail de l'autre développeur.`, "BEHIND");

		const base = T.treeOf(V, V.head);
		let pend = state.pending && state.pending.parent === V.head ? state.pending : null;
		if (pend && !fs.existsSync(path.join(ctx.tmpDir, pend.name))) pend = null;
		let cur, zipPath, name, hashes, patch, type;
		if (pend) {
			zipPath = path.join(ctx.tmpDir, pend.name);
			hashes = await U.hashFile(zipPath, true);
			if (hashes.sha256 === pend.sha256) {
				info(`Reprise de l'archive interrompue ${pend.name}`);
				cur = { files: pend.tree.files, dirs: pend.tree.dirs, cache: pend.cache };
				name = pend.name; patch = pend.patch; type = pend.type;
			} else { warn("Archive en attente corrompue : recréation."); pend = null; }
		}
		if (!pend) {
			cur = await T.scan(ctx, { full: opts.full, cache: state.cache });
			const d = T.diffTrees(base, cur);
			if (T.isEmptyDiff(d)) {
				state.cache = cur.cache; state.pending = null; saveState(ctx, state);
				info(`Aucune modification (assets à la version ${V.head}).`);
				return { changed: false };
			}
			type = V.head === 0 ? "full" : "patch";
			const entries = d.added.concat(d.modified);
			checkDisk(ctx.tmpDir, sumSizes(cur, entries), "créer l'archive");
			const taken = new Set((await remote.list()).map((e) => e.name).concat(V.list.map((v) => v.name)));
			name = `BOOM_BATTLE_ART_${type === "full" ? "FULL" : "PATCH"}_${U.parisStamp()}.zip`;
			if (taken.has(name)) name = name.replace(/\.zip$/, "_" + crypto.randomBytes(4).toString("hex") + ".zip");
			patch = { format: 1, type, fromVersion: V.head, toVersion: V.head + 1, ...d };
			zipPath = path.join(ctx.tmpDir, name);
			info(`Nouvelle version v${V.head + 1} (${type}) : +${d.added.length} ~${d.modified.length} -${d.deleted.length}`);
			await createZip(ctx, zipPath, entries, patch);
			hashes = await U.hashFile(zipPath, true);
			state.pending = { name, parent: V.head, sha256: hashes.sha256, tree: { files: cur.files, dirs: cur.dirs }, cache: cur.cache, patch, type };
			saveState(ctx, state);
		}

		// Envoi puis vérification, avant de publier les métadonnées dans Git.
		const want = { size: hashes.size, md5: hashes.md5 };
		let driveId = null;
		await U.retry("Envoi " + name, 3, async () => {
			if (!(await remote.list()).find((e) => e.name === name)) {
				const pr = U.progress("Envoi vers Drive", hashes.size);
				try { await remote.put(zipPath, name, pr.update); } finally { pr.done(); }
			} else info("Archive déjà présente sur Drive : vérification seule.");
			const e = (await remote.list()).find((x) => x.name === name);
			if (!e || !matchesRemote(e, want)) throw new Error("vérification de l'archive distante échouée (taille/empreinte)");
			if (e._file) { const rh = await U.hashFile(e._file); if (rh.sha256 !== hashes.sha256) throw new Error("SHA-256 distant différent"); }
			driveId = e.id;
		});

		const version = V.head + 1;
		const meta = {
			format: 1, version, parent: V.head, type, name, driveId,
			sha256: hashes.sha256, md5: hashes.md5, size: hashes.size,
			createdAt: new Date().toISOString(), createdAtParis: /(\d{4}-\d\d-\d\d_\d\d-\d\d-\d\d)/.exec(name)[1], timezone: "Europe/Paris",
			author: G.userName(ctx.repo),
			counts: { added: patch.added.length, modified: patch.modified.length, deleted: patch.deleted.length },
			tree: { files: cur.files, dirs: cur.dirs },
		};
		const vf = path.join(ctx.verDir, T.verFileName(version, hashes.sha256));
		if (fs.existsSync(vf)) throw new AssetsError("Fichier de version déjà existant : jamais écrasé.", "FATAL");
		U.writeJson(vf, meta);
		G.addForce(ctx.repo, [vf]);
		state.applied = version; state.cache = cur.cache; state.pending = null;
		saveState(ctx, state);
		fs.rmSync(zipPath, { force: true });   // ZIP temporaire ; la copie Drive est conservée
		info(`Version v${version} publiée (${name}, ${U.fmtBytes(hashes.size)}). À commiter : ${path.relative(ctx.repo, vf).replace(/\\/g, "/")}`);
		return { changed: true, version };
	} finally { release(); }
}

// ---- application d'un patch (téléchargement, contrôle, extraction sûre) ------
async function fetchArchive(ctx, remote, v) {
	const dl = path.join(ctx.tmpDir, "dl");
	fs.mkdirSync(dl, { recursive: true });
	const zip = path.join(dl, v.name);
	if (fs.existsSync(zip)) {
		const h = await U.hashFile(zip);
		if (h.sha256 === v.sha256 && h.size === v.size) { info(`Archive ${v.name} déjà téléchargée et vérifiée.`); return zip; }
		fs.rmSync(zip, { force: true });
	}
	await U.retry("Téléchargement " + v.name, 3, async () => {
		const e = (await remote.list()).find((x) => x.name === v.name);
		if (!e) throw new Error(`archive ${v.name} introuvable sur Drive`);
		if (v.driveId && e.id !== v.driveId) throw new Error(`identifiant Drive différent pour ${v.name}`);
		if (e.size !== v.size) throw new Error(`taille distante ${e.size} ≠ ${v.size}`);
		const part = zip + ".part";
		fs.rmSync(part, { force: true });
		const pr = U.progress(`Téléchargement v${v.version}`, v.size);
		try { await remote.get(e, part, pr.update); } finally { pr.done(); }
		const h = await U.hashFile(part);
		if (h.sha256 !== v.sha256 || h.size !== v.size) { fs.rmSync(part, { force: true }); throw new Error("SHA-256 invalide après téléchargement"); }
		fs.renameSync(part, zip);
	});
	return zip;
}

function validateExtracted(expected, base, v, xdir) {
	const exp = new Set(expected);
	const seen = [];
	const walk = (dir, rel) => {
		for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
			const r = rel ? rel + "/" + e.name : e.name;
			if (e.isDirectory()) walk(path.join(dir, e.name), r); else seen.push(r);
		}
	};
	walk(xdir, "");
	const patchFile = path.join(xdir, T.RESERVED);
	if (!fs.existsSync(patchFile)) throw new Error("patch.json absent de l'archive");
	const patch = U.readJson(patchFile);
	if (patch.fromVersion !== v.parent || patch.toVersion !== v.version) throw new Error("versions de départ/arrivée incohérentes");
	const dd = T.diffTrees(base, v.tree);
	for (const k of ["added", "modified", "deleted", "addedDirs", "deletedDirs"]) {
		if (JSON.stringify(patch[k]) !== JSON.stringify(dd[k])) throw new Error("patch.json en désaccord avec le manifeste (" + k + ")");
	}
	for (const r of seen) {
		if (r === T.RESERVED) continue;
		if (!U.safeRel(r)) throw new Error("chemin dangereux : " + r);
		if (!exp.has(r)) throw new Error("fichier inattendu ou dossier imbriqué dans l'archive : " + r);
	}
	const set = new Set(seen);
	for (const p of expected) if (!set.has(p)) throw new Error("fichier manquant dans l'archive : " + p);
	return patch;
}

async function checkHashes(v, xdir, expected) {
	for (const p of expected) {
		const h = await U.hashFile(path.join(xdir, ...p.split("/")));
		if (h.sha256 !== v.tree.files[p].sha256 || h.size !== v.tree.files[p].size) throw new Error("empreinte invalide : " + p);
	}
}

// Applique un patch extrait dans destRoot. Les fichiers supprimés ou en conflit forcé sont déplacés dans backupRoot.
function applyExtracted(destRoot, xdir, patch, newTree, backupRoot, forceSet, cache) {
	const backup = (rel) => {
		const src = path.join(destRoot, ...rel.split("/"));
		if (!fs.existsSync(src)) return;
		const dst = path.join(backupRoot, ...rel.split("/"));
		fs.mkdirSync(path.dirname(dst), { recursive: true });
		fs.renameSync(src, dst);
	};
	for (const p of patch.deleted) { backup(p); delete cache[p]; }
	for (const d of [...patch.deletedDirs].sort((a, b) => b.length - a.length)) {
		try { fs.rmdirSync(path.join(destRoot, ...d.split("/"))); } catch (_) {}
	}
	for (const d of patch.addedDirs) fs.mkdirSync(path.join(destRoot, ...d.split("/")), { recursive: true });
	for (const p of patch.added.concat(patch.modified)) {
		if (forceSet && forceSet.has(p)) backup(p);
		const src = path.join(xdir, ...p.split("/")), dst = path.join(destRoot, ...p.split("/"));
		fs.mkdirSync(path.dirname(dst), { recursive: true });
		fs.renameSync(src, dst);
		const st = fs.statSync(dst);
		cache[p] = { size: st.size, mtimeMs: st.mtimeMs, sha256: newTree.files[p].sha256 };
	}
}

async function installVersion(ctx, remote, V, v, destRoot, backupRoot, forceSet, cache) {
	const zip = await fetchArchive(ctx, remote, v);
	const base = T.treeOf(V, v.version - 1);
	const dd = T.diffTrees(base, v.tree);
	const expected = dd.added.concat(dd.modified);
	const xdir = path.join(ctx.tmpDir, "x-" + v.version + "-" + process.pid);
	rmrf(xdir);
	try {
		await extractZip(zip, xdir, expected.length + 1);
		const patch = validateExtracted(expected, base, v, xdir);
		await checkHashes(v, xdir, expected);
		applyExtracted(destRoot, xdir, patch, v.tree, backupRoot, forceSet, cache);
	} finally { rmrf(xdir); }
	fs.rmSync(zip, { force: true });   // ZIP temporaire uniquement, jamais la sauvegarde Drive
}

// ---- pull -------------------------------------------------------------------
async function pull(ctx, opts = {}) {
	const V = T.loadVersions(ctx);
	T.checkChain(V);
	const state = T.loadState(ctx);
	if (state.applied === V.head) { info(`Assets à jour (v${V.head}).`); return { updated: false }; }
	if (state.applied > V.head) {
		warn(`Assets locaux (v${state.applied}) plus récents que le manifeste de cette branche (v${V.head}) : aucun changement. \`npm run assets:restore\` pour revenir à v${V.head}.`);
		return { updated: false };
	}
	mustBeReady(ctx);
	const release = U.acquireLock(path.join(ctx.syncDir, "lock"));
	try {
		const remote = openRemote(ctx.cfg);
		const target = V.head;
		info(`Assets locaux v${state.applied} → v${target} : ${target - state.applied} archive(s) à appliquer.`);
		const cur = await T.scan(ctx, { cache: state.cache });
		const localDiff = T.diffTrees(T.treeOf(V, state.applied), cur);
		const localPaths = new Set(localDiff.added.concat(localDiff.modified, localDiff.deleted));
		const finalTree = T.treeOf(V, target);
		const touched = new Set();
		let need = 0;
		for (let n = state.applied + 1; n <= target; n++) {
			const dd = T.diffTrees(T.treeOf(V, n - 1), T.treeOf(V, n));
			dd.added.concat(dd.modified, dd.deleted).forEach((p) => touched.add(p));
			need += sumSizes(T.treeOf(V, n), dd.added.concat(dd.modified)) + V.list[n - 1].size;
		}
		// Conflit = fichier modifié localement (non publié) que la mise à jour changerait vers une autre valeur.
		const conflicts = [...touched].filter((p) => localPaths.has(p) &&
			((cur.files[p] || {}).sha256) !== ((finalTree.files[p] || {}).sha256));
		if (conflicts.length && !opts.force) {
			throw new AssetsError(`CONFLIT : ${conflicts.length} fichier(s) modifié(s) localement et non synchronisés seraient écrasés par la mise à jour :\n  - ${conflicts.slice(0, 20).join("\n  - ")}${conflicts.length > 20 ? "\n  - ..." : ""}\n` +
				"Rien n'a été modifié. Sauvegardez vos fichiers ailleurs puis forcez avec `npm run assets:pull -- --force` (vos versions sont alors déplacées dans .assets-sync/backup).", "CONFLICT");
		}
		checkDisk(ctx.tmpDir, need, "télécharger les mises à jour");
		const backupRoot = path.join(ctx.backupDir, U.parisStamp());
		const forceSet = new Set(conflicts);
		for (let n = state.applied + 1; n <= target; n++) {
			const v = V.list[n - 1];
			info(`Version v${n}/${target} : ${v.name}`);
			const cache = { ...state.cache };
			await installVersion(ctx, remote, V, v, ctx.artDir, backupRoot, forceSet, cache);
			state.applied = n; state.cache = cache; saveState(ctx, state);   // avancé seulement après réussite
		}
		info(`Assets synchronisés (v${target}).${fs.existsSync(backupRoot) ? " Sauvegardes : " + backupRoot : ""}`);
		return { updated: true, version: target };
	} finally { release(); }
}

// ---- status / verify --------------------------------------------------------
async function status(ctx, opts = {}) {
	const V = T.loadVersions(ctx);
	const state = T.loadState(ctx);
	console.log(`Remote : ${isConfigured(ctx) ? JSON.stringify(ctx.cfg.remote) : "NON CONFIGURÉ (npm run assets:setup)"}`);
	console.log(`Version locale : v${state.applied}   Version du manifeste (Git) : v${V.head}`);
	if (V.fork.length) { console.log(`⚠ Fourche de versions ${V.fork.join(", ")} : npm run assets:rebase`); return; }
	const up = upstreamHead(ctx);
	if (up.up) console.log(`Amont ${up.up} : v${up.head}${up.head > V.head ? "  (git pull nécessaire)" : ""}`);
	if (state.applied < V.head) console.log(`À télécharger : ${V.list.slice(state.applied).map((v) => `v${v.version} ${v.name} (${U.fmtBytes(v.size)})`).join(", ")}`);
	if (state.pending) console.log(`Envoi interrompu à reprendre : ${state.pending.name}`);
	const cur = await T.scan(ctx, { full: opts.full, cache: state.cache });
	const d = T.diffTrees(T.treeOf(V, Math.min(state.applied, V.head)), cur);
	console.log(T.isEmptyDiff(d) ? "Modifications locales non publiées : aucune." :
		`Modifications locales non publiées : +${d.added.length} ajoutés, ~${d.modified.length} modifiés, -${d.deleted.length} supprimés`);
	for (const [k, l] of [["+", d.added], ["~", d.modified], ["-", d.deleted]]) l.slice(0, 15).forEach((p) => console.log(`  ${k} ${p}`));
	state.cache = cur.cache; saveState(ctx, state);
	return d;
}

async function verify(ctx) {
	const V = T.loadVersions(ctx); T.checkChain(V);
	const state = T.loadState(ctx);
	if (state.applied === 0) { info("Aucune version appliquée localement : rien à vérifier."); return { ok: true }; }
	info(`Vérification complète (SHA-256) de v${state.applied}...`);
	const cur = await T.scan(ctx, { full: true });
	const d = T.diffTrees(T.treeOf(V, state.applied), cur);
	const bad = d.modified.concat(d.deleted);
	if (bad.length) {
		U.err(`${bad.length} fichier(s) corrompus ou manquants :\n  - ${bad.slice(0, 30).join("\n  - ")}`);
		return { ok: false, modified: d.modified, missing: d.deleted };
	}
	if (d.added.length) warn(`${d.added.length} fichier(s) local(aux) non publiés (pas une corruption).`);
	state.cache = cur.cache; saveState(ctx, state);
	info(`Intégrité OK : ${Object.keys(cur.files).length} fichiers conformes à v${state.applied}.`);
	return { ok: true };
}

// ---- restore ----------------------------------------------------------------
async function restore(ctx, opts = {}) {
	mustBeReady(ctx);
	const release = U.acquireLock(path.join(ctx.syncDir, "lock"));
	try {
		const V = T.loadVersions(ctx); T.checkChain(V);
		const target = opts.version ? Number(opts.version) : V.head;
		if (!(target >= 1 && target <= V.head)) throw new AssetsError(`Version ${opts.version} inexistante (1..${V.head}).`, "FATAL");
		const remote = openRemote(ctx.cfg);
		const stamp = U.parisStamp();
		const work = path.join(ctx.tmpDir, "restore-" + stamp);
		rmrf(work);
		fs.mkdirSync(work, { recursive: true });
		const tt = T.treeOf(V, target);
		checkDisk(ctx.tmpDir, sumSizes(tt, Object.keys(tt.files)) + V.list.slice(0, target).reduce((a, v) => Math.max(a, v.size), 0), "reconstruire le dossier");
		const cache = {};
		info(`Reconstruction de v${target} depuis l'archive complète et ${target - 1} patch(es)...`);
		try {
			for (let n = 1; n <= target; n++) {
				info(`Archive ${n}/${target}`);
				await installVersion(ctx, remote, V, V.list[n - 1], work, path.join(ctx.tmpDir, "restore-bk"), null, cache);
			}
			const chk = await T.scan({ ...ctx, artDir: work }, { full: true });
			if (!T.isEmptyDiff({ ...T.diffTrees(tt, chk), addedDirs: [], deletedDirs: [] })) throw new Error("la reconstruction ne correspond pas au manifeste");
		} catch (e) { rmrf(work); throw e; }
		const bk = path.join(ctx.backupDir, stamp + "-avant-restore");
		fs.mkdirSync(ctx.backupDir, { recursive: true });
		if (fs.existsSync(ctx.artDir)) { fs.renameSync(ctx.artDir, bk); info(`Ancien dossier sauvegardé : ${bk}`); }
		fs.mkdirSync(path.dirname(ctx.artDir), { recursive: true });
		fs.renameSync(work, ctx.artDir);
		const st = T.loadState(ctx); st.applied = target; st.cache = cache; st.pending = null; saveState(ctx, st);
		info(`Dossier restauré à la version v${target}.`);
	} finally { release(); }
}

// ---- rebase (deux développeurs ont publié en parallèle) -----------------------
async function rebase(ctx) {
	const V = T.loadVersions(ctx);
	const up = G.upstream(ctx.repo);
	if (!up) throw new AssetsError("Pas de branche amont : rien à rebaser.", "FATAL");
	const upFiles = new Set(G.lsTree(ctx.repo, up, VER_DIR_REL).map((f) => path.posix.basename(f)));
	const upNums = new Set([...upFiles].map((f) => Number((T.VER_RE.exec(f) || [])[1])));
	const mine = [];
	for (const arr of Object.values(V.byNum)) for (const v of arr) if (!upFiles.has(v._file)) mine.push(v);
	mine.sort((a, b) => a.version - b.version);
	if (!mine.length || !mine.some((m) => upNums.has(m.version))) { info("Aucune version locale en conflit avec l'amont : rien à faire."); return; }
	const common = mine[0].parent;
	info(`Versions locales non publiées : ${mine.map((m) => "v" + m.version).join(", ")} (basées sur v${common}). Elles sont retirées du manifeste ; vos fichiers sont conservés et seront republiés en nouveau patch. Les archives déjà envoyées sur Drive ne sont jamais supprimées.`);
	const st = T.loadState(ctx);
	for (const m of mine) {
		fs.rmSync(path.join(ctx.verDir, m._file), { force: true });
		try { G.git(ctx.repo, ["rm", "--cached", "-q", "--ignore-unmatch", "--", path.posix.join(VER_DIR_REL, m._file)]); } catch (_) {}
	}
	st.applied = Math.min(st.applied, common); st.pending = null;
	saveState(ctx, st);
	info("Étape suivante : `npm run assets:pull` (détecte les conflits avec vos fichiers), puis `npm run assets:push`.");
}

// ---- pre-push : le manifeste ne doit pointer que vers des archives complètes -----
async function checkPrePush(ctx) {
	const headFiles = G.lsTree(ctx.repo, "HEAD", VER_DIR_REL);
	const nums = {};
	for (const f of headFiles) { const m = T.VER_RE.exec(path.posix.basename(f)); if (m) (nums[m[1]] = nums[m[1]] || []).push(f); }
	const forks = Object.keys(nums).filter((k) => nums[k].length > 1);
	if (forks.length) throw new AssetsError(`Push bloqué : versions d'assets en conflit (${forks.join(", ")}). Lancez \`npm run assets:rebase\`.`, "FORK");
	const up = G.upstream(ctx.repo);
	const upSet = new Set(up ? G.lsTree(ctx.repo, up, VER_DIR_REL) : []);
	const fresh = headFiles.filter((f) => !upSet.has(f));
	if (!fresh.length) return;
	if (!isConfigured(ctx)) throw new AssetsError("Push bloqué : le manifeste référence de nouvelles archives mais Drive n'est pas configuré sur ce PC (`npm run assets:setup`).", "UNCONFIGURED");
	const list = await openRemote(ctx.cfg).list();
	const bad = [];
	for (const f of fresh) {
		const v = JSON.parse(G.show(ctx.repo, "HEAD", f));
		const e = list.find((x) => x.name === v.name);
		if (!matchesRemote(e, v)) bad.push(`${v.name} (${e ? "taille/identifiant différents" : "absente de Drive"})`);
	}
	if (bad.length) throw new AssetsError("Push bloqué : archives absentes ou incomplètes sur Drive :\n  - " + bad.join("\n  - ") + "\nLancez `npm run assets:push` pour les (ré)envoyer.", "MISSING");
	info(`pre-push : ${fresh.length} version(s) d'assets vérifiée(s) sur Drive.`);
}

module.exports = { push, pull, status, verify, restore, rebase, checkPrePush, isConfigured, mustBeReady, TAR };
