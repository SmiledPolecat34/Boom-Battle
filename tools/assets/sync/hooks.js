// Installation idempotente des hooks Git. Un bloc balisé est inséré après le shebang des hooks
// existants (ceux de Git LFS par exemple restent intacts).
"use strict";
const fs = require("fs");
const path = require("path");

const BEGIN = "# >>> boom-battle-assets (géré par npm run assets:setup) >>>";
const END = "# <<< boom-battle-assets <<<";
const HOOKS = {
	"pre-commit": true,     // true = peut bloquer l'opération git
	"pre-push": true,
	"post-merge": false,
	"post-rewrite": false,  // pull --rebase
	"post-checkout": false, // changement de branche
};

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

function block(name, blocking) {
	const call = `node "$(git rev-parse --show-toplevel)/tools/assets/sync/cli.js" hook ${name} "$@"`;
	return `${BEGIN}\n${call}${blocking ? " || exit $?" : " || true"}\n${END}`;
}

function strip(text) {
	return text.replace(new RegExp(`${esc(BEGIN)}[\\s\\S]*?${esc(END)}\\r?\\n?`, "g"), "");
}

function install(repo, uninstall = false) {
	const dir = path.join(repo, ".git", "hooks");
	fs.mkdirSync(dir, { recursive: true });
	const out = [];
	for (const [name, blocking] of Object.entries(HOOKS)) {
		const f = path.join(dir, name);
		let text = fs.existsSync(f) ? strip(fs.readFileSync(f, "utf8")) : null;
		if (uninstall) {
			if (text !== null) {
				if (!text.trim() || text.trim() === "#!/bin/sh") fs.rmSync(f); else fs.writeFileSync(f, text, { mode: 0o755 });
			}
			out.push(`${name}: retiré`);
			continue;
		}
		if (text === null) text = "#!/bin/sh\n";
		else if (!/^#!.*\bsh\b/.test(text.split("\n")[0])) { out.push(`${name}: hook existant non-shell, IGNORÉ (ajoutez l'appel à la main)`); continue; }
		const lines = text.split("\n");
		lines.splice(1, 0, block(name, blocking));
		fs.writeFileSync(f, lines.join("\n"), { mode: 0o755 });
		out.push(`${name}: installé`);
	}
	return out;
}

module.exports = { install, HOOKS };
