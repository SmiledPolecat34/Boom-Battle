"use strict";
// Liens : { name, url }. Seules les adresses http et https sont acceptées (jamais javascript:, data:, file:…), sans identifiants dans l'adresse.
class LinkError extends Error {}
const MAX_URL = 500;
const MAX_NAME = 60;

function normalizeLink(raw) {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) throw new LinkError("lien invalide");
  const rawUrl = raw.url, rawName = raw.name === undefined || raw.name === null ? "" : raw.name;
  if (typeof rawUrl !== "string") throw new LinkError("adresse du lien manquante");
  const url = rawUrl.trim();
  if (!url) throw new LinkError("adresse du lien manquante");
  if (url.length > MAX_URL) throw new LinkError("adresse trop longue (" + MAX_URL + " caractères au plus)");
  if (/[\u0000-\u0020\u007f]/.test(url)) throw new LinkError("l'adresse ne doit contenir ni espace ni caractère de contrôle");
  let parsed;
  try { parsed = new URL(url); } catch { throw new LinkError("adresse invalide (exemple : https://exemple.fr/page)"); }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") throw new LinkError("seules les adresses http et https sont acceptées");
  if (parsed.username || parsed.password) throw new LinkError("l'adresse ne doit pas contenir d'identifiants");
  if (!parsed.hostname) throw new LinkError("adresse invalide");
  if (typeof rawName !== "string" || rawName.length > MAX_NAME || /[\u0000-\u001f\u007f]/.test(rawName)) throw new LinkError("nom du lien invalide (" + MAX_NAME + " caractères au plus)");
  const name = rawName.trim() || parsed.hostname.replace(/^www\./, "");
  return { name, url: parsed.href.length <= MAX_URL ? parsed.href : url };
}

function normalizeLinks(list, max) {
  if (!Array.isArray(list)) throw new LinkError("liste de liens attendue");
  if (list.length > max) throw new LinkError("trop de liens (" + max + " au plus)");
  return list.map(normalizeLink);
}

module.exports = { normalizeLink, normalizeLinks, LinkError, MAX_URL, MAX_NAME };
