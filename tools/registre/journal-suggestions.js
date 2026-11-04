  /* Suggestions fondées sur les configurations et les ressources du projet. */
  function journalChoices(schema, fd, current) {
    var choices = [], seen = Object.create(null);
    function add(value, label) {
      if (value === undefined || value === null || value === "") return;
      var id = String(value);
      if (seen[id] || id === "__custom__") return;
      if ((fd.type === "text" || fd.type === "long") && id.length > fd.max) return;
      seen[id] = true; choices.push({ id: id, label: label || id });
    }
    function many(values) { (values || []).forEach(function (v) { add(v); }); }
    var key = schema.id + "." + fd.key, game = D.game || {}, map = game.map || {}, settings = game.settings || {};
    if (fd.type === "enum") (fd.values || []).forEach(function (v) { if (v.id !== "autre") add(v.id, v.label); });
    if (fd.type === "bool") { add("true", "Oui"); add("false", "Non"); }
    if (fd.type === "date") {
      [0, 1, 7].forEach(function (days, index) {
        var d = new Date(); d.setDate(d.getDate() - days);
        add(d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"), ["Aujourd’hui", "Hier", "Il y a une semaine"][index]);
      });
    }
    var scenarios = ["Démarrer une manche à 2 joueurs", "Démarrer une manche à 8 joueurs", "Poser une bombe et déclencher une explosion", "Déclencher une réaction en chaîne", "Détruire une caisse et récupérer un bonus", "Gagner une manche et recevoir les récompenses", "Terminer une manche à égalité", "Quitter la partie pendant une manche", "Rejoindre une manche en cours", "Rejouer après les résultats", "Acheter et équiper un cosmétique", "Valider une quête", "Tester le mode solo avec des bots", "Inviter un ami", "Tester le chat rapide et les émotes", "Sauvegarder et recharger le profil", "Tester le joystick et les boutons tactiles"];
    var devices = ["PC Windows · Roblox Studio", "PC Windows · jeu publié", "Téléphone Android", "iPhone", "Tablette Android", "iPad", "Émulateur mobile de Studio", "Mac · Roblox Studio", "Mac · jeu publié", "Console avec manette"];
    var notes = ["À vérifier en multijoueur", "À reproduire sur mobile", "À comparer entre Studio et le jeu publié", "Préciser les étapes de reproduction", "Ajouter une capture ou une mesure", "Vérifier les erreurs dans la console", "Contrôler le résultat après reconnexion"];
    var presets = {
      "playtests.scenario": scenarios, "playtests.device": devices, "playtests.players": [1, 2, 3, 4, 5, 6, 7, 8], "playtests.notes": notes,
      "perf.device": devices, "perf.scenario": ["Menu principal et décor 3D", "Manche complète à 8 joueurs", "Explosions simultanées et réactions en chaîne", "Génération d’une grande carte", "Partie solo avec 3 bots", "Déplacement sur téléphone", "Ouverture de la boutique"], "perf.fps": [30, 60, 90, 120, 144, 165, 240], "perf.memoryMb": [128, 256, 512, 768, 1024, 1536, 2048], "perf.note": notes,
      "feedback.author": ["SmiledPolecat34", "steph-mss", "Testeur mobile", "Testeur PC", "Groupe de playtest"],
      "feedback.text": ["Le texte est difficile à lire", "Le bouton est trop petit sur téléphone", "Un élément dépasse de l’écran", "Le déplacement manque de fluidité", "Le joystick répond avec retard", "La bombe est difficile à repérer", "Le résultat de la manche n’est pas clair", "Le prix du cosmétique manque de visibilité", "Le joueur reste bloqué au lobby", "La sauvegarde ne se retrouve pas après reconnexion", "Le bot reste bloqué dans l’arène"],
      "balance.name": ["Durée de la manche", "Compte à rebours", "Durée de la mèche", "Durée des explosions", "Capacité maximale de bombes", "Portée maximale des explosions", "Vitesse par bonus", "Probabilité de bonus par caisse", "Densité des caisses", "Récompense de participation", "Récompense de victoire", "Récompense d’égalité", "Prix des bombes cosmétiques", "Prix des effets d’explosion"],
      "balance.proposed": ["1 s", "1,5 s", "2 s", "2,5 s", "3 s", "5 s", "10 s", "120 s", "150 s", "180 s", "10 pièces", "20 pièces", "30 pièces", "50 pièces", "60 pièces", "100 pièces", "250 pièces", "400 pièces", "500 pièces", "20 %", "25 %", "30 %", "50 %"],
      "balance.note": ["Réduire le temps d’attente entre deux manches", "Rendre les explosions plus lisibles", "Améliorer l’équité entre les points d’apparition", "Limiter l’accumulation de bonus", "Rendre les récompenses plus progressives", "Faciliter les premières parties", "Vérifier le résultat en playtest"],
      "images.usage": ["Logo du jeu", "Bouton de lancement", "Icône d’aide", "Icône de réglages", "Icône de quêtes", "Bombe cosmétique", "Effet d’explosion", "Aperçu de carte", "Écran de résultats", "Menu principal"],
      "texts.where": ["Menu principal", "Lobby", "HUD de manche", "Écran des résultats", "Boutique", "Inventaire", "Quêtes", "Aide", "Réglages", "Chat rapide", "Mode solo"],
      "texts.key": ["menu.play", "menu.solo", "lobby.ready", "lobby.waiting", "hud.timer", "results.victory", "results.defeat", "results.draw", "shop.buy", "shop.equip", "quests.progress", "settings.title"],
      "texts.text": ["Jouer", "Solo avec des bots", "Prêt", "En attente des joueurs", "Victoire !", "Égalité", "Rejouer", "Retour au menu", "Acheter", "Équiper", "Déjà possédé", "Quête terminée", "Réglages", "Inviter un ami"],
      "seeds.note": ["Vérifier l’équité des points d’apparition", "Contrôler les chemins bloqués", "Rejouer la carte avec la même seed", "Tester les réactions en chaîne", "Vérifier la densité des caisses", "Comparer les cinq thèmes", "Contrôler la fluidité sur mobile"],
      "decisions.question": ["Quel nom retenir pour le jeu ?", "Quelle récompense donner à la victoire ?", "Comment équilibrer les prix des cosmétiques ?", "Quelle durée retenir pour une manche ?", "Quel comportement choisir pour les spectateurs ?", "Quels sons intégrer en priorité ?", "Comment conserver les favoris du chat rapide ?", "Quand publier la version de test ?"],
      "decisions.options": ["Conserver le fonctionnement actuel", "Comparer deux variantes pendant un playtest", "Tester sur PC et mobile avant de choisir", "Prioriser les corrections bloquantes", "Reporter après la version de test"],
      "decisions.decision": ["Décision en attente du prochain playtest", "Conserver le fonctionnement actuel", "Préparer une variante à tester", "Valider après les tests multijoueur et mobile", "Reporter à la prochaine version"],
      "releases.tests": ["Tests automatisés Lune", "Tests du registre local", "Playtest multijoueur à 2 clients", "Playtest multijoueur à 8 clients", "Test sur téléphone", "Vérification du DataStore", "Vérification des invitations", "Tests automatisés et playtest multijoueur"],
      "releases.notes": ["Corrections de bugs", "Améliorations de l’interface", "Améliorations du mode solo", "Ajustements de l’équilibrage", "Nouveaux cosmétiques", "Améliorations des contrôles tactiles", "Optimisations des performances"]
    };
    many(presets[key]);
    var assets = (D.manifest && D.manifest.assets) || [];
    if (schema.id === "images") assets.forEach(function (a) {
      if (fd.key === "file") add(a.fichier);
      if (fd.key === "sha256") add(a.sha256, a.fichier + " · empreinte enregistrée");
      if (fd.key === "assetId") add(a.assetId, a.fichier + " · " + a.assetId);
      if (fd.key === "usage") add(a.utilisePar);
    });
    if (key === "balance.current") {
      Object.keys(settings).forEach(function (group) { Object.keys(settings[group] || {}).forEach(function (name) { if (typeof settings[group][name] === "number") add(settings[group][name], name + " · " + settings[group][name]); }); });
      if (map.crateDensity !== undefined) add(Math.round(map.crateDensity * 100) + " %", "Densité des caisses · " + Math.round(map.crateDensity * 100) + " %");
    }
    if (key === "releases.version") add(game.version, "Version configurée · " + game.version);
    (journalState.items[schema.id] || []).forEach(function (entry) { add(entry[fd.key]); });
    return choices.slice(0, 100);
  }
