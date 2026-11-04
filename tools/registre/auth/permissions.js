"use strict";
// Catalogue des permissions du registre, rangées par catégorie. Chaque permission est un droit précis (voir, créer, modifier, supprimer…).
// Le rôle intégré « admin » les possède toutes et ne se modifie pas. Les permissions « adminOnly » ne peuvent être données à aucun autre rôle :
// elles sont réservées aux administrateurs (par exemple ajouter un projet, gérer les rôles).
const { SCHEMAS } = require("../journal");

const ADMIN_ROLE_ID = "admin";

const p = (id, label, description, extra) => Object.assign({ id, label, description }, extra);

function journalPermissions() {
  const out = [];
  for (const s of SCHEMAS) {
    out.push(p("journal." + s.id + ".view", "Voir : " + s.label, "Lire les entrées de la rubrique « " + s.label + " »."));
    out.push(p("journal." + s.id + ".create", "Ajouter : " + s.label, "Créer une entrée dans « " + s.label + " »."));
    out.push(p("journal." + s.id + ".edit", "Modifier : " + s.label, "Modifier une entrée de « " + s.label + " »."));
    out.push(p("journal." + s.id + ".delete", "Supprimer : " + s.label, "Supprimer une entrée de « " + s.label + " »."));
  }
  out.push(p("journal.activity.view", "Voir l'activité", "Lire l'historique de tout ce qui a été fait (tickets, journaux)."));
  out.push(p("journal.coverage.view", "Voir la couverture des tests", "Lire l'évolution du nombre de tests au fil des exécutions."));
  return out;
}

const CATEGORIES = [
  { id: "tableau", label: "Tableau de suivi", description: "Tickets, colonnes, retours.", permissions: [
    p("tickets.view", "Voir le tableau", "Afficher les tickets et leur historique."),
    p("tickets.create", "Créer un ticket", "Ajouter un ticket dans une colonne."),
    p("tickets.edit", "Modifier un ticket", "Changer le titre, la description, la priorité, le type, le module et les liens."),
    p("tickets.move", "Déplacer un ticket", "Changer un ticket de colonne ou de position."),
    p("tickets.comment", "Ajouter un retour", "Écrire un retour (commentaire) sur un ticket."),
    p("tickets.comment.delete", "Supprimer un retour", "Retirer un retour d'un ticket."),
    p("tickets.delete", "Supprimer un ticket", "Supprimer définitivement un ticket."),
  ] },
  { id: "journal", label: "Journaux du projet", description: "Une série de droits par rubrique, plus l'activité et la couverture.", permissions: journalPermissions() },
  { id: "tests", label: "Tests", description: "Rapport et lancement des tests.", permissions: [
    p("tests.view", "Voir les tests", "Afficher le dernier rapport et l'historique des exécutions."),
    p("tests.run", "Lancer les tests", "Exécuter les tests depuis le site (consomme du temps de calcul)."),
  ] },
  { id: "game", label: "Données du jeu", description: "Configurations et contenus du jeu.", permissions: [
    p("game.view", "Voir les données du jeu", "Cosmétiques, quêtes, cartes, thèmes, bonus, émotes, chat rapide, réglages."),
  ] },
  { id: "assets", label: "Assets", description: "Images importées et leurs identifiants.", permissions: [
    p("assets.view", "Voir les assets", "Afficher la bibliothèque d'images et leurs identifiants Roblox."),
  ] },
  { id: "sounds", label: "Sons", description: "Catalogue des sons du jeu.", permissions: [
    p("sounds.view", "Voir et écouter les sons", "Afficher le catalogue et lire les fichiers audio."),
    p("sounds.create", "Ajouter un son", "Téléverser un fichier ou renseigner un identifiant Roblox."),
    p("sounds.edit", "Modifier un son", "Changer les réglages ou remplacer le fichier."),
    p("sounds.delete", "Supprimer un son", "Supprimer un son et son fichier."),
  ] },
  { id: "contributions", label: "Contributions", description: "Contenus proposés pour le jeu.", permissions: [
    p("contributions.view", "Voir les contributions", "Lister les contributions envoyées."),
    p("contributions.create", "Envoyer une contribution", "Proposer une quête, une bombe, un effet, une phrase, une émote ou une note."),
    p("contributions.delete", "Supprimer une contribution", "Retirer une contribution de la liste."),
  ] },
  { id: "assistant", label: "Assistant", description: "Discussion avec l'assistant du projet.", permissions: [
    p("assistant.use", "Utiliser l'assistant", "Discuter avec l'assistant ; chaque personne ne voit que ses propres conversations."),
  ] },
  { id: "storage", label: "Stockage", description: "Vue d'ensemble, sauvegarde et restauration.", permissions: [
    p("storage.view", "Voir le stockage", "Afficher le nombre d'éléments et les tailles."),
    p("storage.export", "Exporter une sauvegarde", "Télécharger toutes les données dans un fichier.", { adminOnly: true }),
    p("storage.import", "Importer une sauvegarde", "Restaurer des données depuis un fichier.", { adminOnly: true }),
  ] },
  { id: "projects", label: "Projets", description: "Espace des projets.", permissions: [
    p("projects.view", "Voir les projets", "Afficher la liste et le profil des projets."),
    p("projects.edit", "Modifier un profil de projet", "Changer le nom ou la description d'un projet."),
    p("projects.refresh", "Actualiser un projet", "Relire les fichiers d'un projet importé."),
    p("projects.add", "Ajouter un projet", "Importer un projet (dépôt GitHub ou dossier).", { adminOnly: true }),
    p("projects.remove", "Retirer un projet", "Supprimer un projet de l'espace.", { adminOnly: true }),
  ] },
  { id: "administration", label: "Administration", description: "Comptes, rôles, sécurité.", permissions: [
    p("users.view", "Voir les comptes", "Afficher la liste des comptes et leur état."),
    p("users.create", "Créer un compte", "Ajouter une personne avec un mot de passe de départ."),
    p("users.edit", "Modifier un compte", "Changer le nom ou le rôle d'un compte (un rôle plus puissant que le sien reste refusé)."),
    p("users.disable", "Désactiver un compte", "Bloquer ou réactiver la connexion d'un compte."),
    p("users.reset_password", "Réinitialiser un mot de passe", "Remettre le mot de passe de départ et exiger un changement."),
    p("users.sessions", "Gérer les connexions ouvertes", "Voir et fermer les sessions d'un compte."),
    p("users.delete", "Supprimer un compte", "Supprimer définitivement un compte.", { adminOnly: true }),
    p("roles.view", "Voir les rôles", "Afficher les rôles et leurs permissions."),
    p("roles.manage", "Gérer les rôles", "Créer, modifier et supprimer des rôles.", { adminOnly: true }),
    p("audit.view", "Voir le journal de sécurité", "Connexions, échecs, changements de comptes et de rôles."),
    p("security.settings", "Régler la sécurité", "Mot de passe de départ, durée des sessions, verrouillage.", { adminOnly: true }),
  ] },
];

const PERMISSIONS = [];
const BY_ID = new Map();
for (const c of CATEGORIES) {
  for (const perm of c.permissions) {
    if (BY_ID.has(perm.id)) throw new Error("permission en double : " + perm.id);
    perm.category = c.id;
    perm.adminOnly = perm.adminOnly === true;
    PERMISSIONS.push(perm);
    BY_ID.set(perm.id, perm);
  }
}

const ALL_IDS = PERMISSIONS.map((x) => x.id);
const GRANTABLE_IDS = PERMISSIONS.filter((x) => !x.adminOnly).map((x) => x.id);
const isPermission = (id) => typeof id === "string" && BY_ID.has(id);
const isAdminOnly = (id) => !!BY_ID.get(id) && BY_ID.get(id).adminOnly;

// Valide la liste des permissions d'un rôle personnalisé : identifiants connus, sans doublon, sans permission réservée aux administrateurs.
function checkRolePermissions(list) {
  if (!Array.isArray(list)) return { ok: false, error: "liste de permissions attendue" };
  if (list.length > ALL_IDS.length) return { ok: false, error: "trop de permissions" };
  const seen = new Set();
  for (const id of list) {
    if (typeof id !== "string") return { ok: false, error: "identifiant de permission invalide" };
    if (!BY_ID.has(id)) return { ok: false, error: "permission inconnue : " + id.slice(0, 60) };
    if (BY_ID.get(id).adminOnly) return { ok: false, error: "« " + BY_ID.get(id).label + " » est réservée aux administrateurs" };
    if (seen.has(id)) return { ok: false, error: "permission en double : " + id };
    seen.add(id);
  }
  return { ok: true, clean: ALL_IDS.filter((id) => seen.has(id)) };
}

// Le rôle « admin » est construit, jamais stocké : toutes les permissions, toujours à jour.
const adminRole = () => ({ id: ADMIN_ROLE_ID, name: "Administrateur", description: "Tous les droits sur le site. Ce rôle ne se modifie pas.", permissions: ALL_IDS.slice(), builtin: true });

// Rôles proposés au départ (modifiables et supprimables), pour ne pas partir d'une page blanche.
const STARTER_ROLES = [
  { id: "lecteur", name: "Lecteur", description: "Consulte tout, ne modifie rien.", permissions: ALL_IDS.filter((id) => /\.view$/.test(id) && !/^(users|roles|audit|storage)\./.test(id)) },
  { id: "contributeur", name: "Contributeur", description: "Consulte, crée et modifie du contenu ; ne supprime rien.", permissions: ALL_IDS.filter((id) => !GRANTABLE_IDS.includes(id) ? false : (/\.view$/.test(id) || /\.(create|edit|move|comment)$/.test(id) || id === "assistant.use") && !/^(users|roles|audit|storage)\./.test(id)) },
  { id: "testeur", name: "Testeur", description: "Lance les tests, remplit les tests réels, les retours et les performances.", permissions: ["tests.view", "tests.run", "tickets.view", "tickets.comment", "journal.coverage.view", "journal.activity.view"].concat(ALL_IDS.filter((id) => /^journal\.(playtests|feedback|perf)\./.test(id) && !/\.delete$/.test(id))) },
];

module.exports = { ADMIN_ROLE_ID, CATEGORIES, PERMISSIONS, ALL_IDS, GRANTABLE_IDS, isPermission, isAdminOnly, checkRolePermissions, adminRole, STARTER_ROLES };
