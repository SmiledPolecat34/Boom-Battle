--!strict
-- Emplacements de groupe du menu (logique PURE, testable sans Roblox) : deux emplacements à côté du joueur, chacun
-- occupé par un joueur présent ou ouvert à l'invitation (« + »). Contient aussi la limite d'invitations.
--
-- Limites assumées : Roblox ne dit PAS qui a été invité (GameInvitePromptClosed renvoie un tableau vide) et la fenêtre
-- d'invitation de Roblox laisse choisir plusieurs amis. Le « blocage à 2 » est donc appliqué sur ce que le jeu maîtrise :
-- 2 emplacements « + » au plus (ils disparaissent quand ils sont occupés) et au plus 2 ouvertures de la fenêtre
-- d'invitation par minute. Il n'empêche pas un autre joueur de rejoindre le serveur.

export type Entry = {
	userId: number,
	name: string,
	queued: boolean,
	ready: boolean,
	isFriend: boolean,
}

export type Slot = {
	kind: "player" | "invite",
	userId: number?,
	name: string?,
	status: string?,
	ready: boolean?,
}

local PartySlots = {}

PartySlots.MaxSlots = 2

local function rank(entry: Entry): number
	-- Plus petit = affiché en premier : amis prêts, amis inscrits, amis au menu, puis les autres joueurs.
	local score = 0
	if not entry.isFriend then
		score += 10
	end
	if not entry.queued then
		score += 2
	elseif not entry.ready then
		score += 1
	end
	return score
end

local function statusOf(entry: Entry): string
	if entry.queued and entry.ready then
		return "Prêt !"
	elseif entry.queued then
		return "En attente"
	end
	return "Au menu"
end

-- others : tous les autres joueurs du serveur (le joueur local est exclu par l'appelant).
function PartySlots.compute(others: { Entry }, maxSlots: number?): { Slot }
	local limit = maxSlots or PartySlots.MaxSlots
	local sorted = table.clone(others)
	table.sort(sorted, function(a: Entry, b: Entry)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.userId < b.userId
	end)

	local slots: { Slot } = {}
	for index = 1, limit do
		local entry = sorted[index]
		if entry then
			table.insert(slots, {
				kind = "player",
				userId = entry.userId,
				name = entry.name,
				status = statusOf(entry),
				ready = entry.queued and entry.ready,
			})
		else
			table.insert(slots, { kind = "invite" })
		end
	end
	return slots
end

function PartySlots.openInvites(slots: { Slot }): number
	local count = 0
	for _, slot in slots do
		if slot.kind == "invite" then
			count += 1
		end
	end
	return count
end

-- Limiteur : au plus `maxPrompts` ouvertures de la fenêtre d'invitation par fenêtre glissante de `windowSeconds`.
export type Limiter = {
	maxPrompts: number,
	windowSeconds: number,
	times: { number },
}

function PartySlots.newLimiter(maxPrompts: number, windowSeconds: number): Limiter
	return { maxPrompts = maxPrompts, windowSeconds = windowSeconds, times = {} }
end

local function prune(limiter: Limiter, now: number)
	local kept: { number } = {}
	for _, t in limiter.times do
		if now - t < limiter.windowSeconds then
			table.insert(kept, t)
		end
	end
	limiter.times = kept
end

-- Tente d'enregistrer une ouverture. Retourne (true, 0) ou (false, secondes avant la prochaine possible).
function PartySlots.tryAcquire(limiter: Limiter, now: number): (boolean, number)
	prune(limiter, now)
	if #limiter.times >= limiter.maxPrompts then
		local oldest = limiter.times[1]
		return false, math.max(0, limiter.windowSeconds - (now - oldest))
	end
	table.insert(limiter.times, now)
	return true, 0
end

return PartySlots
