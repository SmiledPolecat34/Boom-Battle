"use strict";
// Mots de passe : jamais stockés en clair. scrypt avec sel aléatoire (format « scrypt$N$r$p$sel$empreinte »), comparaison en temps constant.
const crypto = require("node:crypto");

const PARAMS = { N: 16384, r: 8, p: 1, keylen: 64 };
const MAX_LENGTH = 128;
// Mots de passe trop courants refusés lors d'un changement (le mot de passe de départ en fait partie).
const COMMON = new Set(["qwerty1234", "password", "password1", "motdepasse", "12345678", "123456789", "1234567890", "azerty1234", "azertyuiop", "qwertyuiop", "00000000", "11111111", "boombattle", "bombbattle"]);

function scrypt(password, salt, params) {
  return new Promise((resolve, reject) => {
    crypto.scrypt(String(password), salt, params.keylen, { N: params.N, r: params.r, p: params.p, maxmem: 64 * 1024 * 1024 }, (error, key) => (error ? reject(error) : resolve(key)));
  });
}

async function hashPassword(password) {
  if (typeof password !== "string" || password.length === 0 || password.length > MAX_LENGTH) throw new Error("mot de passe invalide");
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, PARAMS);
  return ["scrypt", PARAMS.N, PARAMS.r, PARAMS.p, salt.toString("base64"), key.toString("base64")].join("$");
}

async function verifyPassword(password, stored) {
  if (typeof password !== "string" || password.length === 0 || password.length > MAX_LENGTH || typeof stored !== "string") return false;
  const parts = stored.split("$");
  if (parts.length !== 6 || parts[0] !== "scrypt") return false;
  const [, N, r, p, saltB64, keyB64] = parts;
  const params = { N: Number(N), r: Number(r), p: Number(p) };
  if (![params.N, params.r, params.p].every((n) => Number.isInteger(n) && n > 0) || params.N > 1 << 20) return false;
  const expected = Buffer.from(keyB64, "base64");
  if (expected.length < 16 || expected.length > 128) return false;
  let actual;
  try {
    actual = await scrypt(password, Buffer.from(saltB64, "base64"), { N: params.N, r: params.r, p: params.p, keylen: expected.length });
  } catch {
    return false;
  }
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

// Règles d'un NOUVEAU mot de passe choisi par une personne. Retourne null si correct, sinon le message d'erreur.
function checkNewPassword(password, ctx) {
  const c = ctx || {};
  if (typeof password !== "string") return "mot de passe invalide";
  if (password.length < 8) return "le mot de passe doit faire au moins 8 caractères";
  if (password.length > MAX_LENGTH) return "le mot de passe est trop long (" + MAX_LENGTH + " caractères au plus)";
  if (/[\u0000-\u001f\u007f]/.test(password)) return "le mot de passe contient des caractères interdits";
  if (!/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) return "le mot de passe doit contenir au moins une lettre et un chiffre";
  const lower = password.toLowerCase();
  if (COMMON.has(lower)) return "ce mot de passe est trop courant";
  if (c.defaultPassword && password === c.defaultPassword) return "choisis un mot de passe différent de celui de départ";
  if (c.username && lower.includes(String(c.username).toLowerCase()) && String(c.username).length >= 3) return "le mot de passe ne doit pas contenir le nom d'utilisateur";
  if (c.current && password === c.current) return "le nouveau mot de passe doit être différent de l'ancien";
  return null;
}

module.exports = { hashPassword, verifyPassword, checkNewPassword, MAX_LENGTH, PARAMS };
