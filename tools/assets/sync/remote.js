// Stockage distant des archives : rclone (Google Drive) ou dossier local/partagé.
// Contrat : list() -> [{name,id,size,md5}], put(local,name,onProgress) -> {id}, get(entry,dest,onProgress).
// Les archives publiées sont immuables : put() refuse d'écraser un nom existant.
"use strict";
const fs = require("fs");
const path = require("path");
const { spawn, execFileSync } = require("child_process");
const { AssetsError, hashFile } = require("./util");

// Injection de panne pour les tests : BB_ASSETS_FAULT="put@<octets>" ou "get@<octets>".
function fault(kind) {
	const m = /^(put|get)@(\d+)$/.exec(process.env.BB_ASSETS_FAULT || "");
	return m && m[1] === kind ? Number(m[2]) : null;
}

function copyStream(src, dest, failAfter, onProgress) {
	return new Promise((resolve, reject) => {
		const total = fs.statSync(src).size;
		let done = 0, failed = false;
		const r = fs.createReadStream(src, { highWaterMark: 1 << 20 });
		const w = fs.createWriteStream(dest);
		r.on("data", (c) => {
			done += c.length;
			if (onProgress) onProgress(done, total);
			if (failAfter !== null && done >= failAfter && !failed) {
				failed = true; r.destroy(); w.end();
				w.on("close", () => reject(new Error("coupure réseau simulée")));
			}
		});
		r.on("error", reject); w.on("error", reject);
		w.on("finish", () => { if (!failed) resolve(); });
		r.pipe(w);
	});
}

class FolderRemote {
	constructor(dir) { this.dir = dir; fs.mkdirSync(dir, { recursive: true }); }
	describe() { return `dossier ${this.dir}`; }
	async list() {
		const out = [];
		for (const e of fs.readdirSync(this.dir, { withFileTypes: true })) {
			if (!e.isFile() || e.name.endsWith(".partial")) continue;
			const f = path.join(this.dir, e.name);
			out.push({ name: e.name, id: e.name, size: fs.statSync(f).size, md5: null, _file: f });
		}
		return out;
	}
	async put(local, name, onProgress) {
		const final = path.join(this.dir, name);
		if (fs.existsSync(final)) throw new AssetsError(`L'archive ${name} existe déjà (jamais écrasée).`, "FATAL");
		const part = final + ".partial";
		await copyStream(local, part, fault("put"), onProgress);
		fs.renameSync(part, final);
		return { id: name };
	}
	async get(entry, dest, onProgress) {
		await copyStream(path.join(this.dir, entry.name), dest, fault("get"), onProgress);
	}
}

class RcloneRemote {
	constructor({ remote, driveFolderId }) {
		this.remote = remote.endsWith(":") ? remote : remote + ":";
		this.flags = ["--drive-root-folder-id", driveFolderId, "--retries", "3", "--low-level-retries", "10"];
	}
	describe() { return `rclone ${this.remote} (dossier Drive ${this.flags[1]})`; }
	_run(args, onLine) {
		return new Promise((resolve, reject) => {
			const p = spawn("rclone", [...args, ...this.flags], { windowsHide: true });
			let out = "", errTxt = "";
			p.stdout.on("data", (d) => { out += d; });
			p.stderr.on("data", (d) => {
				errTxt += d;
				if (onLine) for (const l of String(d).split(/\r?\n/)) if (l) onLine(l);
			});
			p.on("error", (e) => reject(new AssetsError("rclone introuvable : installez-le (winget install Rclone.Rclone) puis `npm run assets:setup`. " + e.message, "FATAL")));
			p.on("close", (c) => c === 0 ? resolve(out) : reject(new Error(`rclone ${args[0]} a échoué (code ${c}) : ${errTxt.trim().split("\n").slice(-3).join(" | ")}`)));
		});
	}
	async list() {
		const j = JSON.parse(await this._run(["lsjson", this.remote, "--files-only", "--hash", "--no-modtime"]) || "[]");
		return j.map((x) => ({ name: x.Name, id: x.ID, size: x.Size, md5: (x.Hashes || {}).md5 || null }));
	}
	async put(local, name, onProgress) {
		const total = fs.statSync(local).size;
		const track = (l) => { const m = /,\s*(\d+)%/.exec(l); if (m && onProgress) onProgress(total * Number(m[1]) / 100, total); };
		// --immutable : rclone refuse de modifier un fichier distant existant.
		await this._run(["copyto", local, this.remote + name, "--immutable", "--drive-chunk-size", "64M",
			"--stats", "2s", "--stats-one-line", "-v"], track);
		const e = (await this.list()).find((x) => x.name === name);
		if (!e) throw new Error("fichier introuvable sur Drive juste après l'envoi");
		return { id: e.id };
	}
	async get(entry, dest, onProgress) {
		const track = (l) => { const m = /,\s*(\d+)%/.exec(l); if (m && onProgress) onProgress(entry.size * Number(m[1]) / 100, entry.size); };
		await this._run(["copyto", this.remote + entry.name, dest, "--stats", "2s", "--stats-one-line", "-v"], track);
	}
}

function openRemote(cfg) {
	const r = cfg.remote || {};
	if (r.type === "folder") {
		if (!r.path) throw new AssetsError("Remote 'folder' sans chemin : lancez `npm run assets:setup`.", "FATAL");
		return new FolderRemote(r.path);
	}
	if (r.type === "rclone") {
		if (!r.driveFolderId) throw new AssetsError("Dossier Google Drive non configuré (driveFolderId). Lancez `npm run assets:setup`.", "FATAL");
		return new RcloneRemote(r);
	}
	throw new AssetsError("Type de remote inconnu : " + r.type, "FATAL");
}

// Vérifie qu'une archive distante correspond à ses métadonnées (taille, id stable, md5 si connu).
function matchesRemote(entry, meta) {
	return entry && entry.size === meta.size && (!meta.driveId || entry.id === meta.driveId) &&
		(!entry.md5 || !meta.md5 || entry.md5 === meta.md5);
}

module.exports = { openRemote, matchesRemote, hashFile };
