"use strict";
// Validation STRICTE d'une contribution (côté serveur : on ne fait jamais confiance au navigateur).
// Mêmes règles que les tests du jeu (src/shared) : identifiants en minuscules, phrase de chat de 30 caractères au plus,
// prix et objectifs entiers, couleurs #rrggbb, événements de quête connus, identifiant d'animation Roblox réel.
// Retourne { ok, errors, clean } : `clean` ne contient que les champs attendus, jamais un champ inconnu.

const TYPES = ["quest", "bomb", "effect", "chat", "emote", "note"];
const MATERIALS = ["SmoothPlastic", "Neon", "Ice", "Metal"];
const QUEST_EVENTS = ["round_played", "round_won", "crates_destroyed"];

// Caractères de contrôle interdits (retour à la ligne compris, sauf pour les détails d'une idée libre).
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u001f\u007f]/;

function text(min, max, multiline) {
  return (value) => {
    if (typeof value !== "string") return "doit être du texte";
    if (value.length < min || value.length > max) return `doit faire entre ${min} et ${max} caractères`;
    if (multiline ? /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value) : CONTROL.test(value)) return "contient un caractère interdit";
    return "";
  };
}
function integer(min, max) {
  return (value) => (Number.isInteger(value) && value >= min && value <= max ? "" : `doit être un entier entre ${min} et ${max}`);
}
function pattern(re, message) {
  return (value) => (typeof value === "string" && re.test(value) ? "" : message);
}
function oneOf(list) {
  return (value) => (list.includes(value) ? "" : `doit valoir ${list.join(", ")}`);
}
function bool() {
  return (value) => (typeof value === "boolean" ? "" : "doit être vrai ou faux");
}

const SPECS = {
  quest: {
    id: pattern(/^[a-z][a-z0-9_]{2,40}$/, "identifiant invalide (a-z, 0-9, _ ; 3 à 41 caractères)"),
    name: text(2, 40),
    description: text(3, 80),
    event: oneOf(QUEST_EVENTS),
    goal: integer(1, 1000),
    reward: integer(1, 10000),
  },
  bomb: {
    id: pattern(/^bomb_[a-z0-9_]{2,30}$/, "identifiant invalide (bomb_nom)"),
    name: text(2, 24),
    price: integer(0, 100000),
    color: pattern(/^#[0-9a-fA-F]{6}$/, "couleur invalide (#rrggbb)"),
    material: oneOf(MATERIALS),
    description: text(3, 80),
  },
  effect: {
    id: pattern(/^effect_[a-z0-9_]{2,30}$/, "identifiant invalide (effect_nom)"),
    name: text(2, 24),
    price: integer(0, 100000),
    color: pattern(/^#[0-9a-fA-F]{6}$/, "couleur invalide (#rrggbb)"),
    description: text(3, 80),
  },
  chat: {
    id: pattern(/^[a-z][a-z0-9_]{1,30}$/, "identifiant invalide (a-z, 0-9, _)"),
    text: text(1, 30),
  },
  emote: {
    id: pattern(/^[a-z][a-z0-9_]{2,30}$/, "identifiant invalide (a-z, 0-9, _)"),
    name: text(2, 24),
    animationId: pattern(/^rbxassetid:\/\/\d{1,20}$/, "identifiant d'animation invalide (rbxassetid://nombre)"),
    looped: bool(),
  },
  note: {
    title: text(3, 80),
    details: text(3, 1500, true),
  },
};

function validate(doc) {
  const errors = [];
  if (doc === null || typeof doc !== "object" || Array.isArray(doc)) return { ok: false, errors: ["contribution invalide"], clean: null };
  if (!TYPES.includes(doc.type)) return { ok: false, errors: ["type inconnu"], clean: null };
  if (doc.fields === null || typeof doc.fields !== "object" || Array.isArray(doc.fields)) return { ok: false, errors: ["champs manquants"], clean: null };

  const spec = SPECS[doc.type];
  const fields = {};
  for (const key of Object.keys(doc.fields)) {
    if (!(key in spec)) errors.push(`champ inattendu : ${key}`);
  }
  for (const key of Object.keys(spec)) {
    if (!(key in doc.fields)) {
      errors.push(`${key} : obligatoire`);
      continue;
    }
    const message = spec[key](doc.fields[key]);
    if (message) errors.push(`${key} : ${message}`);
    else fields[key] = doc.fields[key];
  }

  let note = "";
  if (doc.note !== undefined && doc.note !== "") {
    const message = text(0, 500, true)(doc.note);
    if (message) errors.push(`note : ${message}`);
    else note = doc.note;
  }
  if (errors.length) return { ok: false, errors, clean: null };
  return { ok: true, errors: [], clean: { type: doc.type, fields, note } };
}

module.exports = { validate, TYPES, MATERIALS, QUEST_EVENTS };
