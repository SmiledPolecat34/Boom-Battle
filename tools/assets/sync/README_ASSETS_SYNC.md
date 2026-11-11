# Synchronisation des assets 3D (Git + Google Drive)

`assets/3D/BOOM_BATTLE_ART/` est trop lourd pour Git. Git ne porte que des **métadonnées** (`assets-sync/`), les archives ZIP vivent sur **Google Drive**.

## Principe
- **Version 1** = archive complète `BOOM_BATTLE_ART_FULL_YYYY-MM-DD_HH-mm-ss.zip`, puis un **patch** `BOOM_BATTLE_ART_PATCH_...zip` par publication (heure `Europe/Paris`, suffixe aléatoire seulement en cas de collision).
- Chaque version = un fichier `assets-sync/versions/vNNNNNN_<sha8>.json` (version, parent, nom, **id Drive**, **SHA-256**, MD5, taille, date, auteur, arbre complet des fichiers). Un patch contient aussi `__bbpatch__.json` (version de départ/arrivée, ajouts, modifications, suppressions).
- L'ordre d'application = **numéro de version + parent**, jamais la date.
- Les archives et métadonnées sont **immuables** : jamais écrasées, jamais supprimées de Drive.
- État local (non versionné) : `.assets-sync/` (version appliquée, cache SHA-256, sauvegardes, journal `sync.log`).

## Installation (chaque développeur)
1. `winget install Rclone.Rclone` puis `rclone config` : nouveau remote nommé **`boomdrive`**, type `drive`, scope `drive` (connexion OAuth dans le navigateur ; le jeton reste dans la config rclone locale, jamais dans Git).
2. **Propriétaire, une seule fois** : créer un dossier Drive, le **partager** avec le collègue en *Éditeur*, copier son identifiant (la fin de l'URL), puis :
   `npm run assets:setup -- --drive-folder-id <ID>` et commiter `assets-sync/config.json`.
3. **Collègue** : `git pull`, `rclone config` (même nom `boomdrive`, avec son compte Google), `npm run assets:setup`, puis `npm run assets:pull`.

`assets:setup` installe les hooks Git (non transmis par Git), complète `.gitignore`, teste la connexion. Les hooks existants (Git LFS...) sont conservés. `npm run assets:setup -- --uninstall` retire les hooks.

## Commandes
| Commande | Rôle |
|---|---|
| `npm run assets:push` | détecte ajouts/modifs/suppressions, crée le ZIP (FULL la 1ʳᵉ fois, PATCH ensuite), l'envoie, le **vérifie**, puis écrit le fichier de version (à commiter) |
| `npm run assets:pull` | télécharge uniquement les archives manquantes, vérifie le SHA-256, extrait dans un dossier temporaire, applique dans l'ordre. `-- --force` écrase en sauvegardant |
| `npm run assets:status` | versions, modifications locales non publiées (`-- --full` : re-hachage complet) |
| `npm run assets:verify` | re-hachage complet de tout le dossier |
| `npm run assets:restore` | reconstruit le dossier depuis FULL + patches (`-- --version N`) ; l'ancien dossier est conservé dans `.assets-sync/backup` |
| `npm run assets:rebase` | résout une publication simultanée (voir plus bas) |
| `npm run assets:test` | tests de bout en bout (vrais dépôts Git temporaires) |

## Automatisation
- `pre-commit` : si les assets ont changé, publie le patch et ajoute le fichier de version au commit (désactivable : `autoPushOnCommit: false` dans `assets-sync/config.json`).
- `pre-push` : **bloque** le push si le manifeste pointe vers une archive absente/incomplète de Drive, ou si deux versions portent le même numéro.
- `post-merge`, `post-rewrite` (pull --rebase), `post-checkout` (changement de branche) : appliquent les patches manquants. Une erreur n'annule jamais l'opération Git ; relancer `npm run assets:pull`.
- `BB_ASSETS_SKIP=1` contourne les hooks (urgence). Un verrou et une variable d'environnement évitent récursions et exécutions simultanées.

## Conflits entre deux développeurs
- **Travail local non publié** : `pull` compare vos fichiers à la version de base. Si un patch entrant changerait un fichier que vous avez modifié, rien n'est touché, la liste est affichée (code 3). Vos autres fichiers ne sont jamais écrasés.
- **Publication simultanée** (vous et l'autre créez tous deux la v9) : les fichiers de version ont des noms distincts, Git fusionne sans conflit, mais `status` signale la fourche et `pre-push` bloque. Faites `npm run assets:rebase` (retire VOTRE version locale non poussée du manifeste, vos fichiers sont conservés), `npm run assets:pull`, `npm run assets:push`, commit, push. L'archive abandonnée reste sur Drive (jamais supprimée automatiquement).
- Avant de publier, `push` refuse si l'amont Git (après `git fetch`) a des versions plus récentes.

## Fiabilité
- Envoi : archive écrite sous nom temporaire, vérifiée (taille, MD5 Drive, id) avant publication des métadonnées ; en cas d'interruption l'archive créée est **réutilisée** au `push` suivant. 3 tentatives avec attente.
- Téléchargement : 3 tentatives, SHA-256 vérifié avant extraction, extraction dans `.assets-sync/tmp`, chemins validés (aucun `..`, aucun dossier imbriqué), empreintes de chaque fichier revérifiées, version locale avancée **seulement après réussite**. Un téléchargement interrompu repart du début de l'archive (limite de rclone).
- Les suppressions et écrasements forcés vont dans `.assets-sync/backup/<date>/` (à purger à la main).
- Vérification de l'espace disque avant création ou téléchargement.

## Migration : le commit `f772dda` (ZIP de 6,27 Go)
Constats : `f772dda` n'est pas poussé (`origin/main..HEAD` = `ab2f9aa`, `f772dda`), `ab2f9aa` est sain (plus gros fichier : 165 Ko). Le « ZIP » de `f772dda` est en réalité une archive **tar GNU** (le `tar` de Git Bash ne sait pas faire de ZIP) : il est inutilisable tel quel. Réécriture **locale uniquement**, aucun historique distant touché :
```
git reset --soft HEAD~1                       # défait f772dda, garde tout en place
git restore --staged assets/3D/BOOM_BATTLE_ART.zip
# le fichier .zip (tar) peut être supprimé : le dossier source BOOM_BATTLE_ART/ n'est pas touché
git reflog expire --expire=now --all && git gc --prune=now   # libère ~6 Go dans .git
```
Puis `npm run assets:setup`, et le premier commit d'assets enverra l'archive FULL sur Drive (il faut ≥ la taille du dossier en espace libre dans `.assets-sync/tmp`, soit ~6,2 Go).

## Limites connues
- Le backend Google Drive (rclone) n'a **pas pu être testé** sans compte ni rclone ; les tests utilisent le backend « dossier » (un dossier synchronisé par Google Drive Desktop fonctionne aussi : `setup --path <dossier>`).
- Pas de reprise octet par octet d'un même ZIP interrompu (reprise par archive).
- Noms de fichiers différant seulement par la casse : non gérés (Windows).
