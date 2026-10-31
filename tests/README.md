# Tests

Les scripts de ce dossier ne sont **pas** synchronisés par Rojo : ils se collent dans la barre de commande de Roblox Studio
après synchronisation de `src/`. Ils vérifient la **logique pure** ; ils ne remplacent ni les tests multijoueur, ni les tests
mobile. Voir `docs/TEST_PLAN.md` pour l'état réel de chaque scénario.

**Important :** en mode Edit, `require` peut garder en cache une ancienne version d'un module après une synchronisation Rojo.
Pour être sûr de tester le code courant, lance une session **Play** et exécute le script côté serveur (ou client pour la Phase 4).

| Fichier | Contenu | Où l'exécuter |
|---|---|---|
| `Phase1Tests.luau` | Génération 10/16/24, zones de spawn, symétrie, chemins, conversions | Serveur |
| `Phase2Tests.luau` | Explosions en croix, chaînes, bombes bloquantes | Serveur |
| `Phase3Tests.luau` | Résultat de manche (victoire, égalité), porte d'actions | Serveur |
| `Phase4Tests.luau` | Choix de l'écran, réglages | Client |
| `Phase5Tests.luau` | 5 thèmes × 3 tailles, construction, décors | Serveur |
| `Phase6Tests.luau` | Profil, boutique, récompenses, quêtes, stockage | Serveur |

Une ligne `[PhaseXTests] N réussis, 0 échecs` dans Output signifie que ces vérifications logiques passent.
