local Modes = {}

export type ModeDefinition = {
	Id: string,
	DisplayName: string,
	RoundDuration: number,
	Respawns: boolean,
	EliminationEndsRound: boolean,
	HasTimer: boolean,
	ZoneRequired: boolean,
}

Modes.FFA = {
	Id = "FFA",
	DisplayName = "Free For All",
	RoundDuration = 5 * 60,
	Respawns = true,
	EliminationEndsRound = false,
	HasTimer = true,
	ZoneRequired = true,
} :: ModeDefinition

Modes.BattleRoyale = {
	Id = "BattleRoyale",
	DisplayName = "Battle Royale",
	RoundDuration = 5 * 60,
	Respawns = false,
	EliminationEndsRound = true,
	HasTimer = false,
	ZoneRequired = true,
} :: ModeDefinition

function Modes.Get(id: string): ModeDefinition?
	if id == Modes.FFA.Id then
		return Modes.FFA
	elseif id == Modes.BattleRoyale.Id then
		return Modes.BattleRoyale
	end
	return nil
end

function Modes.GetAll(): {ModeDefinition}
	return { Modes.FFA, Modes.BattleRoyale }
end

return Modes
