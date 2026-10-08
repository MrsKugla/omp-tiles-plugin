--!strict
-- The parts of Flow's hooks/sound.ts the scenes call while they step. Tern
-- plays no sound, so the events are only queued (bounded) and dropped.

local M = {}

M.PLAYER_LEAD_MS = 380
M.EVENTS_HELD = 16

export type SoundEvent = { kind: string, v: number }

function M.hear(queue: { SoundEvent }, e: SoundEvent)
	if #queue < M.EVENTS_HELD then
		table.insert(queue, e)
	end
end

function M.leadFrames(strength: number, tint: string): number
	return M.PLAYER_LEAD_MS / (if strength <= 1 and tint == "normal" then 125 else 70)
end

return M
