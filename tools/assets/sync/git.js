// Accès git minimal (lecture de l'amont, ajout à l'index, racine du dépôt).
"use strict";
const { execFileSync } = require("child_process");

function git(repo, args, opts = {}) {
	return execFileSync("git", args, { cwd: repo, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 1 << 28, ...opts });
}
const tryGit = (repo, args) => { try { return git(repo, args); } catch (_) { return null; } };
const toplevel = (cwd) => git(cwd, ["rev-parse", "--show-toplevel"]).trim();
const upstream = (repo) => { const r = tryGit(repo, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]); return r ? r.trim() : null; };
const lsTree = (repo, ref, dir) => {
	const r = tryGit(repo, ["ls-tree", "-r", "--name-only", ref, "--", dir]);
	return r ? r.split("\n").filter(Boolean) : [];
};
const show = (repo, ref, file) => tryGit(repo, ["show", `${ref}:${file}`]);
const addForce = (repo, files) => { try { git(repo, ["add", "-f", "--", ...files]); return true; } catch (_) { return false; } };
const userName = (repo) => (tryGit(repo, ["config", "user.name"]) || "inconnu").trim();

module.exports = { git, tryGit, toplevel, upstream, lsTree, show, addForce, userName };
