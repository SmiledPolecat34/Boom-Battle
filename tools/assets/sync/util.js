// Utilitaires communs : journal, hachage en flux, heure de Paris, verrou, progression.
"use strict";
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

let logFile = null;
const setLogFile = (f) => { logFile = f; };

function log(level, msg) {
	const line = `[${new Date().toISOString()}] ${level} ${msg}`;
	if (logFile) { try { fs.appendFileSync(logFile, line + "\n"); } catch (_) {} }
	if (level === "ERR") console.error(`[assets] ERREUR : ${msg}`);
	else if (level === "WARN") console.warn(`[assets] ATTENTION : ${msg}`);
	else console.log(`[assets] ${msg}`);
}
const info = (m) => log("INFO", m);
const warn = (m) => log("WARN", m);
const err = (m) => log("ERR", m);

class AssetsError extends Error {
	constructor(msg, code) { super(msg); this.code = code || "ERROR"; }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RETRY_BASE_MS = () => Number(process.env.BB_ASSETS_RETRY_MS || 2000);

async function retry(label, attempts, fn) {
	let last;
	for (let i = 1; i <= attempts; i++) {
		try { return await fn(i); } catch (e) {
			last = e;
			if (e instanceof AssetsError && e.code === "FATAL") throw e;
			warn(`${label} : tentative ${i}/${attempts} échouée (${e.message})`);
			if (i < attempts) await sleep(RETRY_BASE_MS() * i);
		}
	}
	throw last;
}

function fmtBytes(n) {
	const u = ["o", "Ko", "Mo", "Go", "To"];
	let i = 0;
	while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
	return `${n.toFixed(i ? 1 : 0)} ${u[i]}`;
}

// Date/heure Europe/Paris -> "YYYY-MM-DD_HH-mm-ss"
function parisStamp(d = new Date()) {
	const p = {};
	for (const x of new Intl.DateTimeFormat("en-CA", {
		timeZone: "Europe/Paris", hourCycle: "h23", year: "numeric", month: "2-digit",
		day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
	}).formatToParts(d)) p[x.type] = x.value;
	return `${p.year}-${p.month}-${p.day}_${p.hour}-${p.minute}-${p.second}`;
}

// Hachage en flux. Renvoie { sha256, md5, size }.
function hashFile(file, withMd5 = false, onProgress) {
	return new Promise((resolve, reject) => {
		const sha = crypto.createHash("sha256");
		const md5 = withMd5 ? crypto.createHash("md5") : null;
		let size = 0;
		const s = fs.createReadStream(file, { highWaterMark: 4 << 20 });
		s.on("data", (c) => { sha.update(c); if (md5) md5.update(c); size += c.length; if (onProgress) onProgress(size); });
		s.on("error", reject);
		s.on("end", () => resolve({ sha256: sha.digest("hex"), md5: md5 ? md5.digest("hex") : null, size }));
	});
}

// Progression sur une ligne (\r en terminal, une ligne tous les 10 % sinon).
function progress(label, total) {
	const tty = process.stdout.isTTY;
	let lastPct = -1, lastT = 0;
	return {
		update(done) {
			const pct = total ? Math.min(100, Math.floor((done / total) * 100)) : 0;
			const now = Date.now();
			if (tty) {
				if (now - lastT < 250 && pct < 100) return;
				lastT = now;
				process.stdout.write(`\r[assets] ${label} ${pct}% (${fmtBytes(done)}${total ? " / " + fmtBytes(total) : ""})   `);
			} else if (pct >= lastPct + 10) {
				lastPct = pct;
				console.log(`[assets] ${label} ${pct}%`);
			}
		},
		done() { if (tty) process.stdout.write("\n"); },
	};
}

// Chemins relatifs sûrs (jamais d'évasion hors du dossier cible).
function safeRel(rel) {
	if (typeof rel !== "string" || !rel || rel.includes("\\") || rel.includes("\0") ||
		rel.startsWith("/") || /^[A-Za-z]:/.test(rel)) return false;
	return rel.split("/").every((s) => s && s !== "." && s !== "..");
}

// Verrou inter-processus (fichier créé de façon exclusive, avec détection de verrou périmé).
function acquireLock(file) {
	fs.mkdirSync(path.dirname(file), { recursive: true });
	for (let i = 0; i < 2; i++) {
		try {
			const fd = fs.openSync(file, "wx");
			fs.writeSync(fd, JSON.stringify({ pid: process.pid, at: Date.now() }));
			fs.closeSync(fd);
			const release = () => { try { fs.unlinkSync(file); } catch (_) {} };
			process.on("exit", release);
			return release;
		} catch (e) {
			if (e.code !== "EEXIST") throw e;
			let stale = false;
			try {
				const { pid } = JSON.parse(fs.readFileSync(file, "utf8"));
				try { process.kill(pid, 0); } catch (k) { stale = k.code === "ESRCH"; }
			} catch (_) { stale = true; }
			if (!stale) throw new AssetsError("Une autre synchronisation des assets est déjà en cours (verrou : " + file + ").", "LOCKED");
			try { fs.unlinkSync(file); } catch (_) {}
		}
	}
	throw new AssetsError("Impossible d'obtenir le verrou " + file, "LOCKED");
}

const readJson = (f, dflt) => {
	try { return JSON.parse(fs.readFileSync(f, "utf8")); } catch (e) {
		if (e.code === "ENOENT" && dflt !== undefined) return dflt;
		throw e;
	}
};
// Écriture atomique (fichier temporaire + renommage).
function writeJson(f, obj) {
	fs.mkdirSync(path.dirname(f), { recursive: true });
	const t = f + ".tmp" + process.pid;
	fs.writeFileSync(t, JSON.stringify(obj, null, 1) + "\n");
	fs.renameSync(t, f);
}

module.exports = {
	setLogFile, info, warn, err, AssetsError, sleep, retry, fmtBytes, parisStamp, hashFile,
	progress, safeRel, acquireLock, readJson, writeJson,
};
