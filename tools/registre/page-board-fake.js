"use strict";
// Faux serveur du tableau, des journaux et de l'activité pour les tests de page (en mémoire, mêmes règles essentielles que le vrai).
const STATUSES = [{ id: "todo", label: "À faire" }, { id: "doing", label: "En cours" }, { id: "done", label: "Terminé" }];
const PRIORITIES = [{ id: "P0", label: "Critique" }, { id: "P1", label: "Haute" }, { id: "P2", label: "Normale" }, { id: "P3", label: "Basse" }];
const TYPES = [{ id: "tache", label: "Tâche" }, { id: "bug", label: "Bug" }, { id: "idee", label: "Idée" }];
const JOURNAL = [
  { id: "playtests", label: "Tests réels", description: "Ce que tu testes toi-même.", titleField: "scenario", fields: [
    { key: "date", label: "Date", type: "date" }, { key: "scenario", label: "Scénario testé", type: "text", min: 1, max: 120 },
    { key: "result", label: "Résultat", type: "enum", values: [{ id: "ok", label: "Réussi" }, { id: "ko", label: "Échec" }] },
    { key: "players", label: "Joueurs", type: "int", min: 1, max: 8, optional: true }, { key: "notes", label: "Notes", type: "long", max: 4000, optional: true }, { key: "done", label: "Terminé", type: "bool" }] },
  { id: "decisions", label: "Décisions", description: "Questions à trancher.", titleField: "question", fields: [{ key: "question", label: "Question", type: "text", min: 1, max: 200 }] },
];

function ok(body, status) { return Promise.resolve({ ok: true, status: status || 200, json: () => Promise.resolve(JSON.parse(JSON.stringify(body))) }); }
function failure(status, error) { return Promise.resolve({ ok: false, status, json: () => Promise.resolve({ error }) }); }

function createBoardFake(state) {
  state.tickets = state.tickets || [];
  state.journal = state.journal || { playtests: [], decisions: [] };
  state.activity = state.activity || [];
  state.boardCalls = [];
  let n = 0;
  const log = (action, title) => state.activity.unshift({ at: state.now + state.activity.length, kind: "ticket", action, title });
  const find = (id) => state.tickets.find((t) => t.id === id);
  const column = (status) => state.tickets.filter((t) => t.status === status).sort((a, b) => a.position - b.position);
  const renumber = (list) => list.forEach((t, i) => (t.position = i));
  return function route(url, init) {
    const method = init.method || "GET";
    const body = init.body ? JSON.parse(init.body) : undefined;
    const parts = url.split("?")[0].split("/").slice(2); // sans « /api »
    if (parts[0] === "schema") return ok({ journal: JOURNAL, board: { statuses: STATUSES, priorities: PRIORITIES, types: TYPES } });
    if (parts[0] === "activity") return ok(state.activity.slice());
    if (parts[0] === "tickets") {
      state.boardCalls.push({ method, url, body });
      if (!parts[1]) {
        if (method === "GET") return ok(STATUSES.flatMap((s) => column(s.id)));
        if (body.title === undefined || String(body.title).length < 3) return failure(422, "titre invalide (3 à 120 caractères)");
        const t = { id: "tfake" + String(100000 + ++n), title: body.title, description: body.description || "", priority: body.priority || "P2", type: body.type || "tache", module: body.module || "", status: body.status || "todo", position: column(body.status || "todo").length, createdAt: state.now, updatedAt: state.now, comments: [], history: [{ at: state.now, action: "created", to: body.status || "todo" }] };
        state.tickets.push(t); log("ticket_cree", t.title);
        return ok(t, 201);
      }
      const t = find(parts[1]);
      if (!t) return failure(404, "ticket introuvable");
      if (!parts[2]) {
        if (method === "GET") return ok(t);
        if (method === "PATCH") { Object.assign(t, body); t.history.push({ at: state.now, action: "edited", text: Object.keys(body).join(", ") }); log("ticket_modifie", t.title); return ok(t); }
        if (method === "DELETE") { state.tickets = state.tickets.filter((x) => x !== t); log("ticket_supprime", t.title); return ok({ ok: true }); }
      }
      if (parts[2] === "move") {
        const from = t.status;
        const target = column(body.status).filter((x) => x !== t);
        target.splice(Math.min(body.index === undefined ? target.length : body.index, target.length), 0, t);
        t.status = body.status; renumber(target); renumber(column(from));
        t.history.push({ at: state.now, action: from === body.status ? "reordered" : "moved", from, to: body.status, text: "x" }); log("ticket_deplace", t.title);
        return ok(t);
      }
      if (parts[2] === "comments") {
        if (method === "POST") { t.comments.push({ id: "kfake" + String(100000 + ++n), text: body.text, at: state.now }); t.history.push({ at: state.now, action: "commented", text: body.text }); log("retour_ajoute", t.title); return ok(t, 201); }
        if (method === "DELETE") { t.comments = t.comments.filter((c) => c.id !== parts[3]); log("retour_supprime", t.title); return ok(t); }
      }
    }
    if (parts[0] === "journal") {
      state.boardCalls.push({ method, url, body });
      const coll = parts[1], list = state.journal[coll];
      if (!list) return failure(404, "rubrique inconnue");
      if (!parts[2] && method === "GET") return ok(list.slice());
      if (!parts[2] && method === "POST") {
        if (state.journalRefuse) return failure(422, state.journalRefuse);
        const e = Object.assign({ id: "jfake" + String(100000 + ++n), createdAt: state.now, updatedAt: state.now }, body); list.push(e); return ok(e, 201);
      }
      const i = list.findIndex((e) => e.id === parts[2]);
      if (i < 0) return failure(404, "entrée introuvable");
      if (method === "PUT") { list[i] = Object.assign({ id: list[i].id, createdAt: list[i].createdAt, updatedAt: state.now }, body); return ok(list[i]); }
      if (method === "DELETE") { list.splice(i, 1); return ok({ ok: true }); }
    }
    return null;
  };
}

module.exports = { createBoardFake };
