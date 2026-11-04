"use strict";
// Remplit le tableau avec les points ouverts connus du projet (dettes et prochaines étapes de CLAUDE.md).
// Sûr à relancer : un ticket dont le titre existe déjà n'est pas recréé. Usage : node tools/registre/seed.js
const path = require("node:path");
const { createActivity } = require("./activity");
const { createBoard } = require("./board");
const { createJournal } = require("./journal");

const TICKETS = [
  { title: "Tester le mode solo avec bots dans Studio", priority: "P0", type: "tache", module: "BotService", description: "Écrit mais jamais exécuté : lancer Phase9Tests (18 attendus), puis une vraie manche (compte à rebours, bots, éliminations, retour au lobby, aucune récompense, bots nettoyés)." },
  { title: "Tests multijoueur : 2 puis 8 clients", priority: "P0", type: "tache", module: "RoundService", description: "Test > Clients and Servers. Départs en manche, arrivée tardive, spectateurs. Consigner le résultat dans le journal des tests réels." },
  { title: "Retirer l'attribut DevStartCoins avant publication", priority: "P1", type: "tache", module: "Workspace", description: "DevStartCoins = 40000 sur le Workspace, posé pour tester. Ne marche qu'en Studio sur un profil temporaire." },
  { title: "Tester sur téléphone et tactile", priority: "P1", type: "tache", module: "MobileAssets", description: "Joystick et croix tactiles, chat, boutons, lisibilité, performance sur appareil réel." },
  { title: "Tester le DataStore réel", priority: "P1", type: "tache", module: "PlayerDataService", description: "Activer « Enable Studio Access to API Services ». La persistance réelle n'a jamais été testée." },
  { title: "Tester les invitations dans le jeu publié avec 2 comptes", priority: "P2", type: "tache", module: "InviteController", description: "La vraie fenêtre d'invitation Roblox n'a jamais été vue." },
  { title: "Supprimer la Baseplate et la SpawnLocation d'origine", priority: "P2", type: "tache", module: "Place", description: "La baseplate recouvre le sol extérieur et provoque des avertissements ContentId." },
  { title: "Équilibrer l'économie, les bonus et les durées", priority: "P2", type: "tache", module: "GameConfig", description: "Valeurs de départ marquées PROPOSITION : prix, récompenses, probabilités de bonus, taille d'arène par nombre de joueurs." },
  { title: "Ajouter les sons du jeu", priority: "P2", type: "tache", module: "Audio", description: "Aucun son ni musique. Préparer le catalogue dans l'onglet Sons, puis brancher les événements dans le code et afficher les réglages de volume." },
  { title: "Verrou de session des données entre serveurs", priority: "P2", type: "tache", module: "PlayerDataService", description: "Aujourd'hui aucun verrou : deux serveurs pourraient écrire le même profil." },
  { title: "Conserver les favoris du chat rapide dans le profil", priority: "P3", type: "idee", module: "QuickChatStore", description: "Récents, favoris et réglages d'interface ne durent que la session." },
  { title: "Caméra par joueur pour le spectateur", priority: "P3", type: "idee", module: "CameraController", description: "Aujourd'hui caméra fixe sur toute l'arène." },
];
const DECISIONS = [{ question: "Quel est le nom du jeu : BOM, BOMB ou BOOM BATTLE ?", options: "Le dépôt dit BOM BATTLE, les maquettes BOMB ou BOOM BATTLE, le logo importé affiche BOMB BATTLE.", status: "ouverte" }];

function seed(dir, clock) {
  const activity = createActivity(path.join(dir, "activity.json"), clock);
  const board = createBoard({ dir, activity, clock });
  const journal = createJournal({ dir, activity, clock });
  const have = new Set(board.list().map((t) => t.title));
  let tickets = 0, decisions = 0;
  // les nouveaux tickets arrivent en haut : on crée à l'envers pour garder l'ordre de la liste
  for (const t of TICKETS.slice().reverse()) if (!have.has(t.title)) { board.create(t); tickets++; }
  const known = new Set(journal.list("decisions").map((d) => d.question));
  for (const d of DECISIONS) if (!known.has(d.question)) { journal.put("decisions", d); decisions++; }
  return { tickets, decisions };
}

if (require.main === module) {
  const { DEFAULT_DATA_DIR } = require("./serve");
  const r = seed(DEFAULT_DATA_DIR);
  console.log(r.tickets + " ticket(s) et " + r.decisions + " décision(s) ajoutés dans " + path.relative(process.cwd(), DEFAULT_DATA_DIR));
}

module.exports = { seed, TICKETS, DECISIONS };
