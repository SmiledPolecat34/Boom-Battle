#!/usr/bin/env node
// Point d'entrée : npm run assets:{setup,push,pull,status,verify,restore,rebase}
"use strict";
const fs = require("fs");
const path = require("path");
const U = require("./util");
const T = require("./tree");
const O = require("./ops");
const H = require("./hooks");
const { openRemote } = require("./remote");

const args = process.argv.slice(2);
const cmd = args.shift();
const flags = {};
const rest = [];
const WITH_VALUE = ["version", "path", "rclone-remote", "drive-folder-id"];
for (let i = 0; i < args.length; i++) {
	if (cmd !== "hook" && args[i].startsWith("--")) {
		const k = args[i].slice(2);
		if (WITH_VALUE.includes(k) && i + 1 < args.length) flags[k] = args[++i]; else flags[k] = true;
	} else rest.push(args[i]);
}

const GITIGNORE = [
	"# Assets 3D lourds : synchronisés via Google Drive (tools/assets/sync), jamais dans Git",
	"assets/3D/BOOM_BATTLE_ART/", "assets/3D/BOOM_BATTLE_ART*.zip", "*.zip", ".assets-sync/",
	"!tools/assets/sync/*.md",
];

async function setup(ctx) {
	U.info("Vérification de l'environnement...");
	if (Number(process.versions.node.split(".")[0]) < 18) throw new U.AssetsError("Node.js 18+ requis.", "FATAL");
	if (process.platform === "win32" && !fs.existsSync(O.TAR)) throw new U.AssetsError("bsdtar (System32\\tar.exe) introuvable : Windows 10/11 requis.", "FATAL");

	fs.mkdirSync(ctx.verDir, { recursive: true });
	const cfgFile = path.join(ctx.metaDir, "config.json");
	const cfg = U.readJson(cfgFile, { remote: { type: "rclone", remote: "boomdrive:", driveFolderId: "" }, autoPushOnCommit: true });
	if (flags["drive-folder-id"]) cfg.remote = { ...cfg.remote, type: "rclone", driveFolderId: flags["drive-folder-id"] };
	U.writeJson(cfgFile, cfg);                                    // versionné : aucun secret
	const localFile = path.join(ctx.syncDir, "local.json");        // propre à ce PC, ignoré par Git
	const local = U.readJson(localFile, {});
	if (flags.path) local.remote = { type: "folder", path: path.resolve(flags.path) };
	if (flags["rclone-remote"]) local.remote = { ...(local.remote || {}), type: "rclone", remote: flags["rclone-remote"] };
	U.writeJson(localFile, local);

	const gi = path.join(ctx.repo, ".gitignore");
	const text = fs.existsSync(gi) ? fs.readFileSync(gi, "utf8") : "";
	const have = new Set(text.split(/\r?\n/));
	const missing = GITIGNORE.filter((l) => !have.has(l));
	if (missing.length) { fs.writeFileSync(gi, text.replace(/\s*$/, "\n") + "\n" + missing.join("\n") + "\n"); U.info(".gitignore complété."); }

	for (const l of H.install(ctx.repo)) U.info("hook " + l);

	const c2 = T.makeCtx(ctx.repo);
	if (O.isConfigured(c2)) {
		try { const l = await openRemote(c2.cfg).list(); U.info(`Connexion au stockage OK (${l.length} archive(s) distante(s)).`); }
		catch (e) { U.warn("Stockage inaccessible : " + e.message); }
	} else {
		console.log([
			"", "Reste à configurer Google Drive (voir tools/assets/sync/README_ASSETS_SYNC.md) :",
			"  1. winget install Rclone.Rclone   puis   rclone config  (remote « boomdrive », type drive, scope drive)",
			"  2. Créer un dossier Drive, le partager avec votre collègue (Éditeur), copier son identifiant (fin de l'URL)",
			"  3. npm run assets:setup -- --drive-folder-id <ID>   puis commiter assets-sync/config.json",
			"  Collègue : après git pull, rclone config puis npm run assets:setup, puis npm run assets:pull",
		].join("\n"));
	}
}

async function hook(ctx, name) {
	if (process.env.BB_ASSETS_HOOK === "1" || process.env.BB_ASSETS_SKIP === "1") return 0;   // anti-récursion / contournement
	process.env.BB_ASSETS_HOOK = "1";
	try {
		if (name === "pre-push") { await O.checkPrePush(ctx); return 0; }
		if (name === "pre-commit") {
			if (ctx.cfg.autoPushOnCommit === false) return 0;
			const V = T.loadVersions(ctx); T.checkChain(V);
			const st = T.loadState(ctx);
			if (!fs.existsSync(ctx.artDir) || !T.quickChanged(ctx, st, T.treeOf(V, Math.min(st.applied, V.head)))) return 0;
			if (!O.isConfigured(ctx)) { U.warn("Les assets 3D ont changé mais Drive n'est pas configuré : rien n'est publié (npm run assets:setup)."); return 0; }
			await O.push(ctx);
			return 0;
		}
		// post-merge, post-rewrite (rebase uniquement), post-checkout (changement de branche uniquement)
		if (name === "post-rewrite" && rest[1] !== "rebase") return 0;
		if (name === "post-checkout" && rest[3] !== "1") return 0;
		const V = T.loadVersions(ctx);
		if (V.fork.length) { U.warn("Versions d'assets en conflit : `npm run assets:rebase`."); return 0; }
		T.checkChain(V);
		if (T.loadState(ctx).applied === V.head) return 0;
		if (!O.isConfigured(ctx)) { U.warn(`Nouvelles versions d'assets (v${V.head}) mais Drive non configuré : npm run assets:setup puis npm run assets:pull.`); return 0; }
		await O.pull(ctx, {});
		return 0;
	} catch (e) {
		U.err(e.message);
		return name.startsWith("pre-") ? 1 : 0;   // un hook post-* ne doit jamais casser git
	}
}

(async () => {
	if (!cmd || cmd === "help") { console.log("Commandes : setup | push | pull | status | verify | restore | rebase  (voir README_ASSETS_SYNC.md)"); return 0; }
	const ctx = T.makeCtx();
	if (cmd === "hook") return hook(ctx, rest[0]);
	try {
		switch (cmd) {
			case "setup": if (flags.uninstall) H.install(ctx.repo, true).forEach((l) => U.info("hook " + l)); else await setup(ctx); return 0;
			case "push": await O.push(ctx, { full: !!flags.full }); return 0;
			case "pull": await O.pull(ctx, { force: !!flags.force }); return 0;
			case "status": await O.status(ctx, { full: !!flags.full }); return 0;
			case "verify": return (await O.verify(ctx)).ok ? 0 : 1;
			case "restore": await O.restore(ctx, { version: flags.version }); return 0;
			case "rebase": await O.rebase(ctx); return 0;
			default: U.err("Commande inconnue : " + cmd); return 2;
		}
	} catch (e) {
		U.err(e.message);
		if (process.env.BB_ASSETS_DEBUG) console.error(e.stack);
		return e.code === "CONFLICT" ? 3 : 1;
	}
})().then((c) => process.exit(c));
