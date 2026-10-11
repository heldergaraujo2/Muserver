local function MakeDrop(section, index, level)
	return {
		Index = GET_ITEM(section, index),
		Level = level or 0,
	}
end

return {
	-- Dungeon usada como fallback quando nao houver selecao valida.
	DefaultDungeonIndex = 1,
	MaxMapPlayers = 50,
	NameBlockPaddingX = 90,
	NameBlockPaddingY = 18,

	Dungeons = {
		{
			Name = "Dungeon 1",
			ButtonText = "Sala 8h",
			MapNumber = 06,
			MaxMapPlayers = 50,
			EntryCost = 1,
			Drops = {
				MakeDrop(14, 13),
				MakeDrop(14, 14),
				MakeDrop(14, 16),
				MakeDrop(12, 15),
			},
		},
		{
			Name = "Dungeon 2",
			ButtonText = "Sala 16h",
			MapNumber = 109,
			MaxMapPlayers = 50,
			EntryCost = 2,
			Drops = {
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
			},
		},
		{
			Name = "Dungeon 3",
			ButtonText = "Dungeon",
			MapNumber = 113,
			MaxMapPlayers = 0,
			EntryCost = 1,
			Drops = {
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
			},
		},
		{
			Name = "Dungeon 4",
			ButtonText = "Dungeon",
			MapNumber = 113,
			MaxMapPlayers = 0,
			EntryCost = 1,
			Drops = {
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
				MakeDrop(14, 14),
			},
		},
	},

	Window = {
		X = 10,
		Y = 350,
		Width = 70,
		Height = 24,
	},

	Data = {
		Players = 0,
		Monsters = 0,
		Time = 0,
		Visible = false,
	},

	Messages = {
		InfoWCoinC = "WcoinC:",
		InfoEntries = "Entradas:",
		EntryCostFormat = "Req. %dx",
		InfoMap = "Mapa:",
		MapFull = "FULL",

		EnterButton = "ENTRAR",
		CreateInstanceButton = "ENTRAR NA FILA",
		CreateInstanceDelayButton = "AGUARDE",
		CancelInstanceButton = "CANCELAR",
		BuyButton = "COMPRAR ENTRADA",
		BuyTitle = "Comprar entrada?",
		BuyMessage = "Deseja confirmar a compra?",
		EnterTitle = "Entrar na dungeon?",
		EnterMessage = "Deseja confirmar a entrada?",
		CreateInstanceTitle = "Os Wcoin não serão consumidos!",
		CreateInstanceMessage = "Deseja entrar na fila?",
		InstanceTitle = "Fila de espera",
		InstanceEmpty = "Entre na fila para participar.",
		InstanceWaiting = "Posicao na fila:",
		InstanceNextWait = "Voce e o proximo. Aguarde a vaga.",
		InstanceReady = "Sua vez chegou. Entre antes de fechar.",
		InstanceClosesIn = "Fecha em:",
		DropTitle = "Lista de drops",
		OkButton = "OK",
		CancelButton = "Cancelar",
	},
}

--[[
Imagens utilizadas pela interface:

40001 = Custom\\ScriptImages\\buttonx.tga       -- Botao fechar. Dimensao usada: 36x36.
40002 = Custom\\ScriptImages\\interface.tga     -- Janela principal. Dimensao usada: 512x256.
]]
