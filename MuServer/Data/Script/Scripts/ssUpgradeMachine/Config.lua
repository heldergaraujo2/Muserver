local UpgradeMachineConfig = {}

UpgradeMachineConfig.Enabled = true

UpgradeMachineConfig.GremoryFallback = {
	Enabled = true,
	Type = 2,
	Number = 9,
}

UpgradeMachineConfig.Messages = {
	InvalidItem = "Este item nao possui evolucao disponivel.",
	MachineFull = "A maquina ja possui um item.",
	InventoryFull = "Libere espaco no inventario.",
	Stored = "Item colocado na maquina.",
	Withdrawn = "Item devolvido ao inventario.",
	UpgradeFailed = "A evolucao falhou. O item continua na maquina.",
	UpgradeSuccess = "Item evoluido com sucesso.",
	MaterialsMissing = "Materiais insuficientes.",
	OperationError = "Nao foi possivel concluir a operacao.",
	GremoryReturn = "Item enviado ao Gremory Case.",
}

-- CONFIGURACAO DA RECOMPENSA (Reward):
--
-- Type = 0: evolucao que preserva os atributos do item base.
--   Somente Index e Size sao lidos deste bloco Reward.
--   Todos os outros atributos sao copiados do item colocado na maquina:
--   level, durabilidade, skill, luck, adicional, excellent, ancient,
--   Harmony, opcao 380, sockets, bonus de socket e duracao.
--   Exemplo: uma arma +9 excellent com Harmony continuara +9 excellent
--   com Harmony; apenas o Index sera transformado no item configurado.
--
-- Type = 1: recompensa totalmente definida pelo administrador.
--   O resultado usa os valores configurados neste bloco Reward.
--   Nenhum atributo do item base e herdado.
--
-- CAMPOS DO REWARD:
--   Index                 = item que sera entregue como resultado.
--                           Use GET_ITEM(grupo, indice).
--   Size                  = tamanho somente visual na interface.
--                           0 usa CreateItem; de 1 a 255 usa CreateItemSize.
--                           Nao altera os atributos do item entregue.
--   Level                 = nivel do item, por exemplo 0, 9, 10 ou 15.
--   Durability            = durabilidade do item.
--   Option1               = skill do item: 0 desativada, 1 ativada.
--   Option2               = luck do item: 0 desativada, 1 ativada.
--   Option3               = nivel da opcao adicional do item.
--   NewOption             = combinacao das opcoes excellent.
--   SetOption             = opcao ancient/set.
--   JewelOfHarmonyOption  = opcao adicionada pela Jewel of Harmony.
--   ItemOptionEx          = opcao especial 380.
--   SocketOption1 ate 5   = configuracao dos cinco sockets.
--   SocketBonus           = opcao bonus dos sockets.
--   Duration              = duracao do item; 0 cria um item permanente.
UpgradeMachineConfig.Recipes = {
	{
		Index = 1,
		Name = "Bone Blade",
		Source = {
			Index = GET_ITEM(7, 5),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
		},
		Reward = {
			Type = 1,
			Index = GET_ITEM(7, 0),
			Size = 0,
			Level = 0,
			Durability = 255,
			Option1 = 1,
			Option2 = 1,
			Option3 = 1,
			NewOption = 44,
			SetOption = 0,
			JewelOfHarmonyOption = 0,
			ItemOptionEx = 44,
			SocketOption1 = 255,
			SocketOption2 = 255,
			SocketOption3 = 255,
			SocketOption4 = 255,
			SocketOption5 = 255,
			SocketBonus = 255,
			Duration = 0,
		},
		SuccessRate = 100,
		Materials = {

			{
				Index = GET_ITEM(14, 13),
				Level = 0,
				Count = 1,
				Size = 0,
			},
			{
				Index = GET_ITEM(14, 14),
				Level = 0,
				Count = 1,
				Size = 0,
			},	
			{
				Index = GET_ITEM(14, 16),
				Level = 0,
				Count = 1,
				Size = 0,
			},
			{
				Index = GET_ITEM(14, 22),
				Level = 0,
				Count = 1,
				Size = 0,
			},			
			-- Material extra de exemplo: remova os comentarios para ativar.
			-- {
			-- 	Index = GET_ITEM(14, 14),
			-- 	Level = nil, -- nil aceita o item em qualquer level.
			-- 	Count = 1,
			-- 	Size = 0,
			-- },
		},
	},

	-- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 2,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 0),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 6),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },

    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 3,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 6),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 8),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },
 
    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 4,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 8),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 9),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },
 
    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 5,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 9),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 1),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },
 
    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 6,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 1),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 34),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },
 
    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 7,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 34),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 16),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 }, 
    -- RECEITA COMPLETA DE EXEMPLO:
	-- Remova os comentarios deste bloco para ativar a receita.
	-- O Index da receita deve ser unico.
 {
 	Index = 8,
 	Name = "Exemplo de evolucao",
 	Source = {
 		Index = GET_ITEM(7, 16),
			Size = 0,
			Level = 9,
			Durability = nil,
			Option1 = nil,
			Option2 = nil,
			Option3 = nil,
			NewOption = nil,
			SetOption = nil,
			JewelOfHarmonyOption = nil,
			ItemOptionEx = nil,
			SocketOption1 = nil,
			SocketOption2 = nil,
			SocketOption3 = nil,
			SocketOption4 = nil,
			SocketOption5 = nil,
			SocketBonus = nil,
			Duration = nil,
			ExcellentCount = 3,
			SocketCount = nil,
			FilledSocketCount = nil,
			RequireAncient = nil,
			RequireHarmony = nil,
 	},
 	Reward = {
		Type = 1,
		Index = GET_ITEM(7, 17),
		Size = 0,
		Level = 0,
		Durability = 255,
		Option1 = 1,
		Option2 = 1,
		Option3 = 1,
		NewOption = 44,
		SetOption = 0,
		JewelOfHarmonyOption = 0,
		ItemOptionEx = 44,
		SocketOption1 = 255,
		SocketOption2 = 255,
		SocketOption3 = 255,
		SocketOption4 = 255,
		SocketOption5 = 255,
		SocketBonus = 255,
		Duration = 0,
 	},
 	SuccessRate = 50,
 	Materials = {
 		{
 			Index = GET_ITEM(14, 13),
 			Level = 0,
 			Count = 10,
 			Size = 0,
 		},
 		{
 			Index = GET_ITEM(14, 14),
 			Level = nil,
 			Count = 5,
 			Size = 0,
 		},
 	},
 },
}

return UpgradeMachineConfig
