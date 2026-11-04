"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const os = require("node:os");
const { spawn } = require("node:child_process");

class ProjectError extends Error {
  constructor(message, status = 422) { super(message); this.status = status; }
}
const OMIT = new Set([".git", "node_modules", "vendor", "dist", "build", ".next", ".venv", "__pycache__"]);
function githubUrl(value) {
  if (typeof value !== "string") throw new ProjectError("Indique une adresse de dépôt GitHub.");
  const match = /^https:\/\/github\.com\/([a-z\d](?:[a-z\d-]{0,38}))\/([a-z\d_.-]{1,100}?)(?:\.git)?\/?$/i.exec(value.trim());
  if (!match || match[2] === "." || match[2] === "..") throw new ProjectError("Utilise une adresse au format https://github.com/proprietaire/depot.");
  return "https://github.com/" + match[1] + "/" + match[2];
}
function run(command, args, { errorMessage = "Impossible d’ouvrir ce dépôt. Vérifie son adresse et les accès Git configurés sur cet ordinateur.", ...options } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"], ...options });
    let output = "";
    child.stderr.resume();
    child.stdout.on("data", data => { if (output.length < 12000) output += data.toString(); });
    const timeout = setTimeout(() => { child.kill(); reject(new ProjectError("Le délai de l’opération est dépassé. Réessaie.", 504)); }, 120000);
    child.on("error", () => { clearTimeout(timeout); reject(new ProjectError("L’outil nécessaire est introuvable sur cet ordinateur.", 503)); });
    child.on("close", code => { clearTimeout(timeout); code === 0 ? resolve(output.trim()) : reject(new ProjectError(errorMessage, 422)); });
  });
}
async function pickFolder() {
  if (process.platform !== "win32") throw new ProjectError("Le sélecteur natif est disponible sur Windows. Saisis le chemin du dossier ci-dessous.", 503);
  const compiler = ["Framework64", "Framework"].map(folder => path.join(process.env.WINDIR || "C:\\Windows", "Microsoft.NET", folder, "v4.0.30319", "csc.exe")).find(file => fs.existsSync(file));
  if (!compiler) throw new ProjectError("Le sélecteur Windows est indisponible. Tu peux saisir le chemin du dossier.", 503);
  const work = fs.mkdtempSync(path.join(os.tmpdir(), "registre-picker-"));
  const executable = path.join(work, "folder-picker.exe"), result = path.join(work, "selection.txt");
  const errorMessage = "Le sélecteur Windows n’a pas pu s’ouvrir. Tu peux saisir le chemin du dossier.";
  try {
    await run(compiler, ["/nologo", "/target:winexe", "/reference:System.Windows.Forms.dll", "/reference:System.Drawing.dll", "/out:" + executable, path.join(__dirname, "folder-picker.cs")], { errorMessage });
    // Application graphique sans console : sa fenêtre de sélection doit rester visible.
    await run(executable, [result], { windowsHide: false, errorMessage });
    return fs.readFileSync(result, "utf8");
  } finally {
    if (path.dirname(work) === os.tmpdir() && path.basename(work).startsWith("registre-picker-")) fs.rmSync(work, { recursive: true, force: true });
  }
}
function inspect(folder) {
  const files = [], languages = {};
  let count = 0, truncated = false;
  function walk(dir, depth) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      if (count >= 5000) { truncated = true; return; }
      if (entry.isSymbolicLink() || OMIT.has(entry.name) || entry.name.startsWith(".")) continue;
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) { if (depth < 8) walk(file, depth + 1); else truncated = true; }
      else if (entry.isFile()) {
        count++;
        if (files.length < 80) files.push(path.relative(folder, file).split(path.sep).join("/"));
        const ext = path.extname(entry.name).slice(1).toLowerCase();
        if (ext) languages[ext] = (languages[ext] || 0) + 1;
      }
    }
  }
  walk(folder, 0);
  return { files, count, truncated, extensions: Object.entries(languages).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([name, count]) => ({ name, count })), scannedAt: Date.now() };
}
function packageProfile(folder) {
  try {
    const file = path.join(folder, "package.json"), stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 64000) return {};
    const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
    const author = typeof pkg.author === "string" ? pkg.author : pkg.author && pkg.author.name;
    return { author: typeof author === "string" ? author.slice(0, 120) : "", description: typeof pkg.description === "string" ? pkg.description.slice(0, 2000) : "" };
  } catch { return {}; }
}
function createProjects({ dir, chooseFolder = pickFolder, clone = (url, folder) => run("git", ["-c", "core.hooksPath=", "-c", "protocol.file.allow=never", "clone", "--depth", "1", "--", url, folder], { env: { ...process.env, GIT_TERMINAL_PROMPT: "0", GCM_INTERACTIVE: "never", GIT_LFS_SKIP_SMUDGE: "1" } }) }) {
  const file = path.join(dir, "projects.json");
  const builtinFile = path.join(dir, "project-profiles.json");
  const defaults = [
    { id: "boom", name: "BOOM BATTLE", author: "SmiledPolecat34 · steph-mss", description: "Jeu Roblox de combat à la bombe sur grille. Tests, configurations, ressources et suivi du développement.", source: "builtin", path: path.resolve(__dirname, "../..") },
    { id: "luma", name: "Luma", author: "", description: "Espace du projet Luma. Contenu et sources à ajouter.", source: "builtin" }
  ];
  let busy = false, picking = false;
  function list() {
    if (!fs.existsSync(file)) return [];
    try {
      const records = JSON.parse(fs.readFileSync(file, "utf8"));
      if (!Array.isArray(records)) throw new Error();
      return records.filter(p => p && /^p[a-f0-9]{16}$/.test(p.id) && typeof p.name === "string" && typeof p.path === "string" && ["folder", "github"].includes(p.source));
    } catch { throw new ProjectError("Le catalogue des projets est illisible. Il a été conservé pour récupération.", 500); }
  }
  function save(records) {
    fs.mkdirSync(dir, { recursive: true });
    const tmp = file + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(records, null, 2), { mode: 0o600 }); fs.renameSync(tmp, file);
  }
  function builtins() {
    let overrides = {};
    if (fs.existsSync(builtinFile)) {
      try { overrides = JSON.parse(fs.readFileSync(builtinFile, "utf8")); if (!overrides || Array.isArray(overrides) || typeof overrides !== "object") throw new Error(); }
      catch { throw new ProjectError("Les profils des projets sont illisibles. Le fichier a été conservé.", 500); }
    }
    return defaults.map(p => ({ ...p, ...(overrides[p.id] || {}), id: p.id, source: p.source, path: p.path }));
  }
  function saveBuiltin(project) {
    const records = Object.fromEntries(builtins().map(p => [p.id, p.id === project.id ? project : p]));
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(builtinFile + ".tmp", JSON.stringify(records, null, 2), { mode: 0o600 });
    fs.renameSync(builtinFile + ".tmp", builtinFile);
  }
  function get(id) {
    const p = [...builtins(), ...list()].find(p => p.id === id && !p.deleted);
    if (!p) throw new ProjectError("Projet introuvable.", 404);
    return p;
  }
  function update(id, raw) {
    if (busy) throw new ProjectError("Un import est en cours. Réessaie à sa fin.", 409);
    const project = get(id);
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new ProjectError("Profil invalide.");
    for (const [key, max] of [["name", 80], ["author", 120], ["description", 2000]]) {
      if (raw[key] === undefined) continue;
      if (typeof raw[key] !== "string" || raw[key].trim().length > max || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(raw[key]) || (key !== "description" && /[\r\n\t]/.test(raw[key])) || (key === "name" && !raw[key].trim())) throw new ProjectError("Le champ " + ({ name: "nom", author: "auteur", description: "description" }[key]) + " est invalide (" + max + " caractères au plus).");
      project[key] = raw[key].trim();
    }
    project.updatedAt = Date.now();
    if (project.source === "builtin") saveBuiltin(project);
    else save(list().map(p => p.id === id ? project : p));
    return project;
  }
  function remove(id) {
    if (busy) throw new ProjectError("Un import est en cours. Réessaie à sa fin.", 409);
    const project = get(id);
    if (project.source === "builtin") saveBuiltin({ ...project, deleted: true });
    else save(list().filter(p => p.id !== id));
    return { ok: true, filesPreserved: true };
  }
  async function add(body) {
    if (busy) throw new ProjectError("Un import est déjà en cours. Attends sa fin.", 409);
    if (!body || !["folder", "github"].includes(body.source)) throw new ProjectError("Choisis GitHub ou un dossier local.");
    if (body.name !== undefined && (typeof body.name !== "string" || body.name.trim().length > 80 || /[\x00-\x1f\x7f]/.test(body.name))) throw new ProjectError("Le nom doit contenir au plus 80 caractères.");
    const records = list();
    if (records.length >= 50) throw new ProjectError("Le catalogue peut contenir au plus 50 projets.");
    let folder, repository;
    const id = "p" + crypto.randomBytes(8).toString("hex");
    if (body.source === "github") {
      repository = githubUrl(body.url);
      const existing = records.find(p => p.repository && p.repository.toLowerCase() === repository.toLowerCase());
      if (existing) return existing;
      folder = path.join(dir, "repositories", id);
    } else {
      if (typeof body.path !== "string" || !path.isAbsolute(body.path) || /[\x00-\x1f]/.test(body.path) || body.path.startsWith("\\\\")) throw new ProjectError("Choisis un dossier local ou indique son chemin absolu.");
      try { folder = fs.realpathSync(body.path); if (!fs.statSync(folder).isDirectory()) throw new Error(); }
      catch { throw new ProjectError("Ce dossier est introuvable ou inaccessible."); }
      if (folder === path.parse(folder).root) throw new ProjectError("Choisis un dossier de projet, pas la racine du disque.");
      const existing = records.find(p => process.platform === "win32" ? p.path.toLowerCase() === folder.toLowerCase() : p.path === folder);
      if (existing) return existing;
    }
    busy = true;
    try {
      if (repository) { fs.mkdirSync(path.dirname(folder), { recursive: true }); await clone(repository, folder); }
      const project = { ...packageProfile(folder), id, name: body.name && body.name.trim() || (repository ? repository.split("/").pop() : path.basename(folder)), source: body.source, path: folder, createdAt: Date.now(), snapshot: inspect(folder) };
      if (repository) project.repository = repository;
      save([...records, project]); return project;
    } finally { busy = false; }
  }
  return { list, add, builtins, get, update, remove, async pick() {
    if (picking) throw new ProjectError("Une fenêtre de sélection est déjà ouverte.", 409);
    picking = true;
    try { return { path: await chooseFolder() }; } finally { picking = false; }
  }, refresh(id) {
    const records = list(), project = records.find(p => p.id === id);
    if (!project) throw new ProjectError("Projet introuvable.", 404);
    if (!fs.existsSync(project.path)) throw new ProjectError("Le dossier a été déplacé ou supprimé. Il n’est plus accessible.", 404);
    project.snapshot = inspect(project.path); save(records); return project;
  } };
}
module.exports = { createProjects, ProjectError, githubUrl, inspect };
