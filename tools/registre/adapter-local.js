  /* Adaptateur de la version locale (servie par tools/registre/serve.js) :
       - assistant : API Groq appelée depuis le navigateur, avec la clé saisie par l'utilisateur ;
       - contributions : fichiers JSON écrits par le serveur local dans tools/registre/contributions/.
     La clé n'est jamais écrite dans un fichier du projet : elle reste dans le stockage du navigateur (session, ou
     stockage local si l'utilisateur coche « mémoriser ») et n'est envoyée qu'à api.groq.com. */
  (function () {
    var API = "https://api.groq.com/openai/v1";
    var KEY = "registre.groqKey", MODEL = "registre.groqModel", REMEMBER = "registre.groqRemember";
    var DEFAULT_MODEL = "openai/gpt-oss-120b";
    /* Ordre de préférence quand le modèle mémorisé n'existe plus sur le compte (les catalogues changent souvent). */
    var PREFERRED = ["openai/gpt-oss-120b", "llama-3.3-70b-versatile", "openai/gpt-oss-20b", "qwen/qwen3-32b"];
    function pickModel(ids, current) {
      if (ids.indexOf(current) >= 0) return current;
      for (var i = 0; i < PREFERRED.length; i++) if (ids.indexOf(PREFERRED[i]) >= 0) return PREFERRED[i];
      var usable = ids.filter(function (id) { return !/allam|guard|safeguard/i.test(id); });
      return usable[0] || ids[0] || current;
    }

    function read(storage, key) { try { return storage.getItem(key) || ""; } catch (e) { return ""; } }
    function write(storage, key, value) { try { if (value) storage.setItem(key, value); else storage.removeItem(key); } catch (e) { /* stockage indisponible : la clé reste en mémoire */ } }

    var state = {
      remember: read(window.localStorage, REMEMBER) === "1",
      key: "",
      model: read(window.localStorage, MODEL) || DEFAULT_MODEL,
      models: [],
      note: ""
    };
    state.key = read(state.remember ? window.localStorage : window.sessionStorage, KEY);

    function persistKey() {
      write(window.localStorage, REMEMBER, state.remember ? "1" : "");
      write(window.localStorage, KEY, state.remember ? state.key : "");
      write(window.sessionStorage, KEY, state.remember ? "" : state.key);
    }

    function fail(code, message, status) {
      var e = new Error(message || code);
      e.code = code; e.status = status;
      return e;
    }

    function call(path, init) {
      return fetch(API + path, init).catch(function (err) {
        if (err && err.name === "AbortError") throw err;
        throw fail("network", "Service injoignable");
      }).then(function (res) {
        if (res.ok) return res.json();
        return res.json().catch(function () { return {}; }).then(function (body) {
          var message = (body && body.error && body.error.message) || ("Erreur " + res.status);
          if (res.status === 401 || res.status === 403) throw fail("auth", message, res.status);
          if (res.status === 429) throw fail("rate_limited", message, res.status);
          throw fail("http", message, res.status);
        });
      });
    }

    function headers() { return { "Authorization": "Bearer " + state.key, "Content-Type": "application/json" }; }

    /* Les modèles « gpt-oss » raisonnent avant de répondre : un effort bas et une marge de jetons évitent une réponse vide. */
    function requestBody(messages, tools) {
      var body = { model: state.model, messages: messages, tools: tools, tool_choice: "auto", temperature: 0.3, max_tokens: 1500 };
      if (/gpt-oss/i.test(state.model)) body.reasoning_effort = "low";
      return body;
    }

    /* Boucle d'appel d'outils (format compatible OpenAI) : le modèle demande des outils de la page, on les exécute ici. */
    async function ask(o) {
      await ensureModels(); /* le modèle mémorisé peut avoir disparu du catalogue : on le remplace avant le premier appel */
      var messages = [{ role: "system", content: o.system }].concat(o.messages);
      var tools = o.tools.map(function (t) { return { type: "function", function: { name: t.name, description: t.description, parameters: t.inputSchema || { type: "object", properties: {} } } }; });
      var last = "";
      for (var turn = 0; turn < 5; turn++) {
        var body = await call("/chat/completions", { method: "POST", headers: headers(), signal: o.signal, body: JSON.stringify(requestBody(messages, tools)) });
        var message = body && body.choices && body.choices[0] && body.choices[0].message;
        if (!message) throw fail("http", "Réponse vide du service");
        if (message.content) { last = message.content; o.onText(last); }
        if (!message.tool_calls || !message.tool_calls.length) return last;
        messages.push({ role: "assistant", content: message.content || "", tool_calls: message.tool_calls });
        message.tool_calls.forEach(function (call) {
          var tool = o.tools.find(function (t) { return t.name === call.function.name; });
          var output;
          try {
            var args = {};
            try { args = JSON.parse(call.function.arguments || "{}"); } catch (e) { throw new Error("Arguments illisibles."); }
            if (!tool) throw new Error("Outil inconnu.");
            output = String(tool.execute(args));
          } catch (e) { output = "Erreur : " + ((e && e.message) || e); }
          messages.push({ role: "tool", tool_call_id: call.id, content: output });
        });
      }
      return last || "(l'assistant n'a pas terminé sa réponse)";
    }

    function loadModels(done) {
      if (!state.key) return done();
      call("/models", { headers: headers() }).then(function (body) {
        var ids = ((body && body.data) || []).map(function (m) { return m.id; }).filter(function (id) { return !/whisper|tts|guard|embed|playai|orpheus|distil/i.test(id); }).sort();
        state.models = ids;
        if (ids.length) {
          var chosen = pickModel(ids, state.model);
          if (chosen !== state.model) { state.model = chosen; write(window.localStorage, MODEL, state.model); }
        }
        state.note = "";
        done();
      }, function (err) {
        state.note = err && err.code === "auth" ? "Clé refusée par Groq : vérifie-la." : "Liste des modèles indisponible.";
        done();
      });
    }

    var modelsPromise = null;
    function ensureModels() {
      if (state.models.length || !state.key) return Promise.resolve();
      if (!modelsPromise) modelsPromise = new Promise(function (resolve) { loadModels(resolve); }).then(function () { modelsPromise = null; });
      return modelsPromise;
    }

    function maskedKey() { return state.key ? "gsk_…" + state.key.slice(-4) : ""; }

    var ai = {
      ready: function () { return Promise.resolve(!!state.key); },
      status: function () { return state.key ? "Groq prêt (" + state.model + ")" : "Mode local : renseigne une clé Groq pour activer l'assistant IA"; },
      reasonText: function () { return "aucune clé Groq n'est renseignée (champ au-dessus de la conversation)"; },
      ask: ask,
      pickModel: pickModel, /* exposé pour les tests */
      mountSettings: function (el, onChange) {
        function draw() {
          var models = state.models.length ? state.models : [state.model];
          el.innerHTML =
            '<div class="field wide" style="margin-bottom:12px"><label for="groq-key">Clé Groq</label>' +
            '<div class="composer"><input id="groq-key" type="password" autocomplete="off" spellcheck="false" placeholder="' + esc(state.key ? "Clé enregistrée : " + maskedKey() : "gsk_…") + '" aria-describedby="groq-hint">' +
            '<button class="btn" id="groq-save" type="button">Enregistrer</button><button class="btn ghost" id="groq-clear" type="button"' + (state.key ? "" : " disabled") + ">Effacer</button></div>" +
            '<span class="hint" id="groq-hint">La clé reste dans ce navigateur et n\'est envoyée qu\'à api.groq.com ; elle n\'est écrite dans aucun fichier du projet. <a href="https://console.groq.com/keys" target="_blank" rel="noopener">Créer une clé</a></span>' +
            '<label class="hint" style="display:flex;gap:8px;align-items:center"><input type="checkbox" id="groq-remember"' + (state.remember ? " checked" : "") + ' style="width:auto"> Mémoriser sur cet ordinateur (sinon la clé est oubliée à la fermeture de l\'onglet)</label>' +
            (state.key ? '<label class="hint" for="groq-model">Modèle</label><select id="groq-model">' + models.map(function (m) { return '<option value="' + esc(m) + '"' + (m === state.model ? " selected" : "") + ">" + esc(m) + "</option>"; }).join("") + "</select>" : "") +
            (state.note ? '<span class="err" role="alert">' + esc(state.note) + "</span>" : "") + "</div>";
          el.querySelector("#groq-save").addEventListener("click", function () {
            var value = el.querySelector("#groq-key").value.trim();
            if (value && !/^gsk_[A-Za-z0-9]{20,}$/.test(value)) { state.note = "Format de clé inattendu (elle commence par gsk_)."; draw(); return; }
            state.remember = el.querySelector("#groq-remember").checked;
            if (value) state.key = value;
            persistKey();
            state.note = "";
            loadModels(function () { draw(); onChange(); });
          });
          el.querySelector("#groq-clear").addEventListener("click", function () { state.key = ""; state.models = []; state.note = ""; persistKey(); draw(); onChange(); });
          var select = el.querySelector("#groq-model");
          if (select) select.addEventListener("change", function () { state.model = select.value; write(window.localStorage, MODEL, state.model); onChange(); });
        }
        draw();
        loadModels(function () { draw(); onChange(); });
      }
    };

    /* Contributions : API du serveur local. Un en-tête personnalisé protège contre l'envoi depuis un autre site. */
    var listener = null, timer = null, failedOnce = false;
    var STORE_HEADERS = { "Content-Type": "application/json", "X-Registre": "1" };
    function loadItems() {
      return fetch("/api/contributions", { headers: { "X-Registre": "1" } }).then(function (res) {
        if (!res.ok) throw new Error("Erreur " + res.status);
        return res.json();
      });
    }
    function check(res) {
      if (res.ok) return res;
      return res.json().catch(function () { return {}; }).then(function (b) { throw new Error((b && b.error) || ("Erreur " + res.status)); });
    }
    function tick() {
      if (!listener) return;
      loadItems().then(function (items) { failedOnce = false; listener.onItems(items); }, function () {
        if (!failedOnce) { failedOnce = true; listener.onError({ unavailable: true }); }
      });
    }
    var store = {
      unavailableText: "Le serveur local n'est pas joignable : lance « node tools/registre/serve.js » et ouvre l'adresse affichée (la page ouverte comme simple fichier ne peut pas enregistrer).",
      subscribe: function (onItems, onError) {
        listener = { onItems: onItems, onError: onError };
        tick();
        if (!timer) timer = setInterval(function () { if (document.visibilityState !== "hidden") tick(); }, 6000);
      },
      add: function (doc) { return fetch("/api/contributions", { method: "POST", headers: STORE_HEADERS, body: JSON.stringify(doc) }).then(check).then(tick); },
      remove: function (id) { return fetch("/api/contributions/" + encodeURIComponent(id), { method: "DELETE", headers: STORE_HEADERS }).then(check).then(tick); }
    };

    /* Lancement des tests depuis la page : le serveur local exécute Lune et renvoie le rapport et l'historique à jour. */
    var tests = {
      run: function (filter) {
        return fetch("/api/tests/run", { method: "POST", headers: STORE_HEADERS, body: JSON.stringify({ filter: filter || "" }) }).then(check).then(function (res) { return res.json(); });
      }
    };

    /* Stockage durable côté serveur local : conversations, réglages, sons, vue d'ensemble, sauvegarde. */
    function api(method, url, body) {
      var init = { method: method, headers: STORE_HEADERS };
      if (body !== undefined) init.body = JSON.stringify(body);
      return fetch(url, init).then(check).then(function (res) { return res.json(); });
    }
    var storage = {
      projects: {
        update: function (id, fields) { return api("PATCH", "/api/projects/" + encodeURIComponent(id), fields); },
        remove: function (id) { return api("DELETE", "/api/projects/" + encodeURIComponent(id)); },
        list: function () { return api("GET", "/api/projects"); },
        add: function (body) { return api("POST", "/api/projects", body); },
        pick: function () { return api("POST", "/api/projects/pick-folder", {}); },
        refresh: function (id) { return api("POST", "/api/projects/" + encodeURIComponent(id) + "/refresh", {}); }
      },
      chats: {
        list: function () { return api("GET", "/api/chats"); },
        put: function (conv) { return api("PUT", "/api/chats/" + encodeURIComponent(conv.id), conv); },
        remove: function (id) { return api("DELETE", "/api/chats/" + encodeURIComponent(id)); },
        clear: function () { return api("DELETE", "/api/chats"); }
      },
      settings: {
        get: function () { return api("GET", "/api/settings"); },
        put: function (values) { return api("PUT", "/api/settings", values); }
      },
      sounds: {
        list: function () { return api("GET", "/api/sounds"); },
        save: function (meta, file, id) {
          var body = { sound: meta };
          if (file) body.file = file;
          return api(id ? "PUT" : "POST", id ? "/api/sounds/" + encodeURIComponent(id) : "/api/sounds", body);
        },
        remove: function (id) { return api("DELETE", "/api/sounds/" + encodeURIComponent(id)); },
        url: function (source) { return "sounds/" + encodeURIComponent(source.file); }
      },
      board: {
        schema: function () { return api("GET", "/api/schema"); },
        list: function () { return api("GET", "/api/tickets"); },
        create: function (raw) { return api("POST", "/api/tickets", raw); },
        update: function (id, patch) { return api("PATCH", "/api/tickets/" + encodeURIComponent(id), patch); },
        move: function (id, target) { return api("POST", "/api/tickets/" + encodeURIComponent(id) + "/move", target); },
        comment: function (id, text) { return api("POST", "/api/tickets/" + encodeURIComponent(id) + "/comments", { text: text }); },
        uncomment: function (id, commentId) { return api("DELETE", "/api/tickets/" + encodeURIComponent(id) + "/comments/" + encodeURIComponent(commentId)); },
        remove: function (id) { return api("DELETE", "/api/tickets/" + encodeURIComponent(id)); }
      },
      journal: {
        list: function (coll) { return api("GET", "/api/journal/" + encodeURIComponent(coll)); },
        save: function (coll, raw, id) { return api(id ? "PUT" : "POST", "/api/journal/" + encodeURIComponent(coll) + (id ? "/" + encodeURIComponent(id) : ""), raw); },
        remove: function (coll, id) { return api("DELETE", "/api/journal/" + encodeURIComponent(coll) + "/" + encodeURIComponent(id)); }
      },
      activity: function (limit) { return api("GET", "/api/activity?limit=" + (limit || 200)); },
      runs: function () { return api("GET", "/api/tests/latest"); },
      stats: function () { return api("GET", "/api/storage"); },
      backup: function () { return api("GET", "/api/backup"); },
      restore: function (bundle) { return api("POST", "/api/backup", bundle); }
    };

    window.__registreBackend = {
      ai: ai,
      store: store,
      storage: storage,
      tests: tests,
      refresh: function () { return fetch("/api/refresh", { method: "POST", headers: STORE_HEADERS }).then(check); }
    };
  })();
