# Tests

Deux familles, qui ne se remplacent pas :

| Famille | Où | Exécution | Ce que ça couvre |
|---|---|---|---|
| **Tests automatisés (Lune)** | `tests/unit/**/*.spec.luau` | `lune run tests/run`, **et en CI à chaque push / PR** | Toute la logique pure et la validation des données : grille, génération, explosions, manches, profil, boutique, quêtes, bots, réglages, configs, syntaxe, intégrité des assets |
| **Scripts Studio** | `tests/Phase*Tests.luau` | à coller dans Studio (voir plus bas) | Ce qui exige le moteur Roblox : construction des Parts, thèmes, UI réelle |

Ni l'une ni l'autre ne remplace les tests multijoueur, mobile et DataStore réels (voir `docs/TEST_PLAN.md`).

## Lancer les tests automatisés

Prérequis : [Lune](https://github.com/lune-org/lune) 0.10.5 (`winget install Lune.Lune`).

```bash
lune run tests/run                          # tout (≈ 0,3 s)
lune run tests/run -- GridService           # seulement les fichiers dont le chemin contient « GridService »
lune run tests/run -- --filter "pilier"     # seulement les tests dont le nom contient « pilier »
lune run tests/run -- --verbose             # liste chaque test
lune run tests/run -- --json rapport.json   # rapport machine
```

Code de sortie : `0` tout passe, `1` au moins un échec, `2` erreur d'utilisation.

## Règle d'or : une modification = un test

Toute modification de `src/` s'accompagne, **dans le même changement**, d'un test qui échouerait sans elle :

1. **Bug corrigé** → écrire d'abord le test qui reproduit le bug (il doit échouer), puis corriger.
2. **Fonctionnalité ajoutée** → un test par règle, y compris les cas limites et hostiles (nil, NaN, négatif, type
   inattendu, trop long, spam, joueur absent).
3. **Nouveau module** → une suite `tests/unit/<server|client|shared>/<Module>.spec.luau`.

Deux garde-fous le font respecter :

- `tests/unit/meta/Repository.spec.luau` échoue si un module de `src/` n'est chargé par aucune suite et ne figure pas dans
  `tests/untested.json` (avec la raison). Cette liste ne doit que **rétrécir** ; un module testé qui y reste fait aussi échouer.
- `tools/ci/check-tests-changed.js` (étape CI sur les PR) échoue si un module de `src/` est modifié sans qu'une suite qui le
  charge soit modifiée dans le même changement. Étiquette `no-test-needed` sur la PR pour une exception justifiée
  (commentaire, renommage pur).

## Écrire une suite

```luau
--!nocheck
local GridService = world.module("GridService")   -- charge src/ tel quel, par nom de module (unique)

describe("findPath", function()
	it("refuse un départ hors grille", function()
		local grid = Fixtures.emptyGrid(9)
		expect(grid:findPath({ x = -1, y = 1 }, { x = 2, y = 1 })).toBeNil()
	end)
end)
```

Globales disponibles : `describe`, `it`, `xit` (ignoré), `beforeEach`, `afterEach`, `expect(x).toBe / toEqual /
toBeTruthy / toBeFalsy / toBeNil / toBeCloseTo / toBeGreaterThan(OrEqual) / toBeLessThan(OrEqual) / toHaveLength /
toContain / toThrow` (et `.never` pour la négation), `world` (instance isolée du jeu simulé : `world.module`, `world.mock`,
`world.reset`, `world.advance`, `world.addPlayer`, `world.removePlayer`, `world.dataStoreFailure`, `world.warnings`, `world.output`),
`Fixtures` (`emptyGrid`, `fakePlayer`, `fakeCharacter`, `fakeRemotes`, `mockMapService`, `roundHarness`), `Lune` (fs/serde pour les tests « méta »).

Principes :

- **Isolation** : chaque fichier `.spec.luau` reçoit un monde neuf (modules rechargés). Dans un même fichier, l'état des
  modules est partagé : utiliser `beforeEach` pour le remettre à zéro.
- **Aucun faux succès** : un service ou une classe Roblox non simulé (`Instance.new("Part")`, `TweenService`...) lève
  une erreur explicite. Un module qui en dépend relève des tests Studio ; ajouter une simulation dans
  `tests/runner/loader.luau` seulement si elle est fidèle.
- **`Random` est un remplaçant** déterministe (pas celui de Roblox) : tester des **propriétés** (validité, symétrie,
  reproductibilité), jamais des cases précises tirées au hasard.
- Les messages de test sont en français, comme le reste du projet.

## Ce qui n'est PAS couvert (et pourquoi)

Plus aucun module de `src/` n'est exempté (hors `Types`, des déclarations de types sans code), mais « couvert » veut dire
« testé contre des **simulations** du moteur » (`tests/runner/loader.luau`, `tests/runner/instances.luau`) :

- Pas de moteur physique ni de rendu : positions, collisions réelles, apparence à l'écran, animations réelles, sons.
- `Random`, `CFrame.lookAt`, `Humanoid`, `Animator`, `TweenService`, `UserInputService`, `SocialService`, `TextChatService`
  sont des doubles minimaux : un test vert prouve la logique, pas le comportement exact de Roblox.
- Les scripts d'entrée `Bootstrap.server` et `Bootstrap.client` ne sont pas des modules : seul le contrat des remotes qu'ils
  créent et attendent est vérifié (suite `meta`).
- Hors portée de tout test local : plusieurs clients en réseau, latence, DataStore réel, vraie fenêtre d'invitation, mobile
  réel, performances. À faire par le propriétaire (`docs/TEST_PLAN.md`).

## Scripts Studio (`tests/Phase*Tests.luau`)

Non synchronisés par Rojo : à coller dans la barre de commande de Roblox Studio après synchronisation de `src/`.

**Important :** en mode Edit, `require` peut garder en cache une ancienne version d'un module après une synchronisation
Rojo. Pour être sûr de tester le code courant, lancer une session **Play** et exécuter le script côté serveur (ou client
pour les Phases 4 et 8).

| Fichier | Contenu | Où l'exécuter |
|---|---|---|
| `Phase1Tests.luau` | Génération 10/16/24, zones de spawn, symétrie, chemins, conversions | Serveur |
| `Phase2Tests.luau` | Explosions en croix, chaînes, bombes bloquantes | Serveur |
| `Phase3Tests.luau` | Résultat de manche (victoire, égalité), porte d'actions | Serveur |
| `Phase4Tests.luau` | Choix de l'écran, réglages | Client |
| `Phase5Tests.luau` | 5 thèmes × 3 tailles, construction, décors (**seul à vérifier la construction des Parts**) | Serveur |
| `Phase6Tests.luau` | Profil, boutique, récompenses, quêtes, stockage | Serveur |
| `Phase8Tests.luau` | Émotes, chat rapide, emplacements du groupe, limite d'invitations | Client |
| `Phase9Tests.luau` | Cerveau des bots | Serveur |
| `Phase11BombSkinsTests.luau` | Bombes 3D : 24 modèles (style, pose), contrôleur en jeu, repli sur échec de chargement, boutique / inventaire réels, achat avec équipement automatique (vrais remotes) | **Client** (session Play ; section achat : `DevStartCoins`, voir l'en-tête) |

Les Phases 1-4, 6, 8 et 9 ont leur équivalent (étendu) dans `tests/unit/` et s'exécutent désormais sans Studio ; leurs
scripts Studio restent utiles comme contrôle croisé dans le vrai moteur (notamment le vrai `Random` de Roblox). Seule la
Phase 5 n'a pas d'équivalent Lune.
