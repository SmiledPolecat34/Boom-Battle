<div align="center">

# 💣 BOOM BATTLE

### Place your bomb. Escape the blast. Be the last survivor.

**Un jeu multijoueur Roblox de stratégie, de réflexes et d'explosions en chaîne.**

![Statut](https://img.shields.io/badge/Statut-En%20d%C3%A9veloppement-orange)
![Plateforme](https://img.shields.io/badge/Plateforme-Roblox-00A2FF)
![Accès](https://img.shields.io/badge/Acc%C3%A8s-Gratuit-brightgreen)
![Licence](https://img.shields.io/badge/Licence-Tous%20droits%20r%C3%A9serv%C3%A9s-red)

*Inspiré par le plaisir des jeux de bombes sur grille, avec une identité et des créations originales.*

</div>

---

## 📖 Présentation

**BOM BATTLE** est un projet de jeu multijoueur sur **Roblox**. Les joueurs évoluent dans une arène en vue de dessus, placent des bombes, détruisent des obstacles, récupèrent des bonus et tentent d'être les derniers survivants.

Le principe est simple : **facile à apprendre, difficile à maîtriser**. Les parties sont courtes et dynamiques, avec des rebondissements et des explosions en chaîne.

> **Note :** ce dépôt documente un projet en cours de conception et de développement. Les fonctionnalités ci-dessous sont des **objectifs de développement**, et non la liste de fonctionnalités déjà disponibles.

## 🎯 Vision du projet

- **Accessible :** une prise en main rapide, sans tutoriel interminable.
- **Multijoueur :** des confrontations courtes et compétitives entre amis ou avec d'autres joueurs.
- **Multi-support :** une interface pensée pour les ordinateurs, smartphones et tablettes compatibles avec Roblox.
- **Commandes simples :** objectif de contrôle à la souris sur PC et au tactile sur mobile, sans clavier obligatoire.
- **100 % gratuit :** aucun achat intégré prévu pour le lancement.
- **Équitable :** le résultat dépend avant tout du placement, de l'anticipation et des réflexes.
- **Évolutif :** nouveaux modes, cartes, défis et événements après validation du gameplay principal.

## 🕹️ Comment jouer ?

1. Rejoindre une partie et apparaître dans l'arène.
2. Se déplacer pour éviter les adversaires et les explosions.
3. Poser des bombes pour détruire des blocs et piéger les adversaires.
4. Ramasser des bonus pour améliorer ses capacités pendant la manche.
5. Survivre jusqu'à la fin pour remporter la victoire.

### Contrôles visés

| Support | Déplacement | Action principale |
| --- | --- | --- |
| 🖥️ PC | Clic sur une case accessible | Bouton de pose de bombe à la souris |
| 📱 Mobile / tablette | Toucher une case accessible | Bouton tactile de pose de bombe |

*Le système exact de contrôle et de pathfinding sera validé pendant le prototype. Aucune touche du clavier ne doit être indispensable à la boucle de jeu principale.*

## 💥 Mécaniques principales (prévues)

### Bombes et explosions

- Pose de bombes avec un délai avant détonation.
- Explosions en **croix** sur une grille.
- Blocage de l'explosion par certains obstacles.
- Destruction de blocs et révélation de bonus.
- **Réactions en chaîne** lorsque les explosions touchent d'autres bombes.
- Élimination des joueurs pris dans une explosion sans protection.

### Bonus

| Bonus | Effet envisagé |
| --- | --- |
| 🔥 Portée + | Augmente la portée de l'explosion. |
| 💣 Bombe + | Permet de poser davantage de bombes simultanément. |
| 👟 Vitesse + | Accélère les déplacements. |
| 🛡️ Bouclier | Protège d'une explosion. |

D'autres bonus pourront être ajoutés après les tests d'équilibrage.

### Déroulement d'une partie

- Objectif initial : **4 à 8 joueurs** par manche.
- Durée cible : **2 à 3 minutes** par partie.
- Une arène de départ équilibrée, avec des zones destructibles.
- Une zone dangereuse qui se rapproche en fin de manche pour éviter les parties trop longues.
- Un écran de résultat puis la possibilité de rejouer rapidement.

*Ces valeurs sont des objectifs et pourront évoluer avec les tests.*

## 🏆 Modes de jeu

| Mode | Description | Priorité |
| --- | --- | --- |
| **Classic Survival** | Chacun pour soi : le dernier survivant gagne. | MVP |
| **Bomb Royale** | L'arène rétrécit progressivement. | Après MVP |
| **Chaos Mode** | Des règles temporaires bouleversent les manches. | Après MVP |
| **Team Battle** | Affrontements en équipes. | Ultérieure |
| **Duel 1v1** | Partie rapide entre deux joueurs. | Ultérieure |

## 🗺️ Cartes et événements

**Cartes envisagées :** arène classique, laboratoire, volcan, arène glacée et jardin coloré.

**Événements potentiels :** pluie de bombes, vitesse doublée, bombes géantes, blocs mystères et sol glissant. Ils seront introduits progressivement pour conserver une bonne lisibilité du jeu.

## 🎨 Direction artistique

- Univers **coloré, lisible et dynamique**.
- Vue de dessus adaptée au gameplay sur grille.
- Cases, murs, bonus et zones d'explosion faciles à identifier.
- Personnages stylisés et animations courtes.
- Interface claire sur petit écran.
- Identité graphique, modèles, sons et visuels **originaux**.

Les noms, personnages, ressources graphiques et musiques d'autres jeux ne doivent pas être copiés sans autorisation.

## 📈 Progression (prévue)

Après la validation du cœur du gameplay :

- Niveaux et expérience.
- Statistiques de victoires et d'éliminations.
- Classements.
- Défis quotidiens.
- Skins, titres et effets visuels **déblocables gratuitement**.
- Événements temporaires.

La progression devra rester compatible avec l'objectif d'un jeu **sans achats intégrés**.

## 🧰 Technologies

| Composant | Choix |
| --- | --- |
| Plateforme | Roblox |
| Moteur / éditeur | Roblox Studio |
| Langage de script | Luau |
| Multijoueur | Architecture client / serveur Roblox |
| Versionnement | Git et GitHub |

### Principes techniques

- La **logique sensible** (pose valide, explosions, dégâts, victoire) doit être vérifiée côté **serveur**.
- Le client gère notamment les entrées et les effets visuels, sans être considéré comme une source de vérité.
- Les interactions doivent être adaptées aux écrans tactiles.
- Les effets et objets doivent être optimisés pour limiter la charge sur mobile.
- Le code doit rester modulaire pour faciliter les futurs modes et bonus.

## 🛠️ Installation et développement

Le dépôt est synchronisé avec Roblox Studio par **[Rojo](https://rojo.space)** (`default.project.json`) : les scripts vivent dans `src/`, la scène (Workspace, éclairage) dans le fichier de place.

1. Installer **Roblox Studio** et **Rojo 7.x** (CLI et plugin Studio).
2. Cloner le dépôt :

   ```bash
   git clone https://github.com/SmiledPolecat34/Boom-Battle.git
   cd Boom-Battle
   ```

3. Sauvegarder le fichier de place, puis supprimer `Workspace.Baseplate` et `Workspace.SpawnLocation` (l'arène génère son propre sol).
4. Lancer la synchronisation et se connecter depuis le plugin Rojo dans Studio :

   ```bash
   rojo serve
   ```

5. Tester avec **Play**, ou **Test > Clients and Servers** pour plusieurs joueurs. Un joueur seul peut jouer dans Studio (mode solo de test) ; hors Studio, 2 joueurs minimum sont requis.
6. Pour tester la sauvegarde, activer *Enable Studio Access to API Services* dans les paramètres du jeu.

Détails : `docs/SETUP.md` (installation), `docs/SYNC.md` (synchronisation automatique à deux), `docs/DEPLOYMENT.md` (mise en ligne), `docs/TEST_PLAN.md` (état réel des tests).

## 📍 État actuel du développement

Le MVP est **écrit et partiellement testé** (un seul joueur à la fois dans Studio) ; il n'est **pas encore validé** en multijoueur ni sur mobile.

| Domaine | État |
| --- | --- |
| Arène 10 / 16 / 24 générée au hasard, 5 thèmes | Implémenté, testé en logique et en solo |
| Déplacement au clic / toucher, bombes, explosions en chaîne, 4 bonus | Implémenté, testé en solo |
| Manches (Ready, compte à rebours, résultats, rejouer) | Implémenté, testé en solo |
| Interface (menu, lobby, HUD, résultats, aide, réglages) | Implémenté, testé par messages réseau (pas de clics réels, pas de mobile) |
| Bomb Coins, boutique, inventaire, quêtes, sauvegarde | Implémenté ; sauvegarde réelle non encore vérifiée |
| Multijoueur (2 à 8), déconnexions, mobile | **Non testé** |

## 🧪 Tests

Les scripts de `tests/` se collent dans la barre de commande de Studio (voir `tests/README.md`). Ils vérifient la logique pure (génération, chemins, explosions, résultats, données, boutique). Ils ne remplacent pas les tests multijoueur et mobile.

## 🗓️ Feuille de route

### Phase 1 — Prototype jouable

- [ ] Définir la grille et la première arène.
- [ ] Implémenter les déplacements au clic / tactile.
- [ ] Implémenter la pose des bombes.
- [ ] Implémenter les explosions en croix.
- [ ] Gérer les blocs destructibles.
- [ ] Gérer les réactions en chaîne.
- [ ] Gérer les éliminations et la victoire.

### Phase 2 — Première version multijoueur (MVP)

- [ ] Ajouter un lobby simple.
- [ ] Gérer 4 à 8 joueurs par manche.
- [ ] Ajouter quatre bonus de base.
- [ ] Ajouter un chronomètre et une fin de partie.
- [ ] Ajouter une interface PC et mobile.
- [ ] Tester la synchronisation serveur / clients.
- [ ] Ajouter la possibilité de rejouer rapidement.

### Phase 3 — Qualité et fidélisation

- [ ] Ajouter d'autres cartes.
- [ ] Équilibrer les bonus et les durées.
- [ ] Ajouter les statistiques et la progression gratuite.
- [ ] Optimiser les performances mobiles.
- [ ] Corriger les bugs repérés par les testeurs.

### Phase 4 — Contenus supplémentaires

- [ ] Ajouter Bomb Royale.
- [ ] Ajouter Chaos Mode et ses événements.
- [ ] Ajouter Team Battle.
- [ ] Ajouter des éléments cosmétiques gratuits.
- [ ] Ajouter des événements saisonniers.

## ✅ Priorités de qualité

- Parties fluides et explosions compréhensibles.
- Déplacements précis à la souris et au tactile.
- Absence de désynchronisation sur les dégâts et les victoires.
- Temps d'attente limité entre les manches.
- Bon fonctionnement sur appareils mobiles compatibles.
- Expérience agréable même sans communication entre joueurs.

## 🔐 Sécurité et équité

- Validation serveur de toutes les actions importantes.
- Limitation des requêtes distantes abusives.
- Contrôle des collisions et positions autorisées.
- Aucun avantage payant prévu.
- Respect des règles et standards de sécurité de Roblox.

## 🤝 Contributions

Les propositions d'idées et signalements de bugs peuvent être discutés via les **Issues**, si elles sont activées.

**Ce dépôt n'est pas open source.** Le fait qu'il soit public n'autorise pas la réutilisation, la modification ou la redistribution de son contenu. **Aucune contribution de code ni pull request ne doit être considérée comme acceptée sans accord préalable du titulaire des droits.**

## 📜 Licence et droits d'auteur

**Copyright © 2026 — Titulaire des droits : à renseigner. Tous droits réservés.**

Le code source, les éléments graphiques, les modèles, les sons, les textes et les autres contenus originaux du projet sont protégés par le droit d'auteur applicable.

**Aucune licence open source n'est accordée.** Sauf autorisation expresse du titulaire des droits ou exception légale applicable, leur reproduction, modification, distribution ou exploitation n'est pas autorisée.

Les marques, noms et créations de tiers demeurent la propriété de leurs titulaires respectifs. **BOM BATTLE** n'est ni affilié ni officiellement associé aux jeux qui ont inspiré son genre de gameplay.

> **GitHub :** garder le champ « License » vide (`None`) ou ajouter un fichier `LICENSE` propriétaire cohérent. Une mention « All Rights Reserved » n'est pas une licence open source standard.

---

<div align="center">

**💣 BOM BATTLE — One bomb can change everything.**

*Projet Roblox indépendant — En développement*

</div>
