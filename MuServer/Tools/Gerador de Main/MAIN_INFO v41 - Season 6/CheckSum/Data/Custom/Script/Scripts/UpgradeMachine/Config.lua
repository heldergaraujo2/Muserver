local UpgradeMachineConfig = {}

UpgradeMachineConfig.WindowID = 158
-- true: abre pelo atalho e pelo NPC. false: abre somente pelo NPC.
UpgradeMachineConfig.OpenByShortcut = true
UpgradeMachineConfig.OpenKey = Keys.F4
UpgradeMachineConfig.NameBlockPaddingX = 70
UpgradeMachineConfig.NameBlockPaddingY = 18
UpgradeMachineConfig.MaxMaterials = 5

UpgradeMachineConfig.Window = {
	Width = 273,
	Height = 315,
	Y = 40,
	OffsetX = 0,
	BaseScreenWidth = 600,
	UseResolutionWidth = false,
}

UpgradeMachineConfig.Images = {
	MainWindow = 40007,
	Close = 40006,
	UpgradeButton = 40006,
}

UpgradeMachineConfig.Visual = {
	DrawArrow = true,
	SlotBorder = { 0.660, 0.680, 0.700, 0.78 },
	SlotHoverBorder = { 0.450, 0.850, 1.000, 0.92 },
	SeparatorLine = { 0.620, 0.640, 0.660, 0.70 },
	SeparatorShadow = { 0.220, 0.240, 0.260, 0.55 },
	SeparatorTopScale = 0.80,
	SeparatorBottomScale = 0.70,
}

-- All positions are relative to the top-left corner of the main window.
UpgradeMachineConfig.Layout = {
	Title = {
		X = 0,
		Y = 20,
		Width = 273,
		Align = 3,
	},
	CloseButton = {
		X = 250,
		Y = 8,
		Width = 14,
		Height = 14,
		TextX = 0,
		TextY = 2,
	},
	BaseItemText = {
		X = 20,
		Y = 33,
		Width = 73,
		Align = 3,
	},
	ResultItemText = {
		X = 180,
		Y = 33,
		Width = 73,
		Align = 3,
	},
	MaterialsText = {
		X = 0,
		Y = 153,
		Width = 273,
		Align = 3,
	},
	SuccessRateText = {
		X = 0,
		Y = 237,
		Width = 273,
		Align = 3,
	},
	SuccessRateValue = {
		X = 0,
		Y = 251,
		Width = 273,
		Align = 3,
	},
	UpgradeButton = {
		X = 100,
		Y = 274,
		Width = 72,
		Height = 22,
		TextX = 0,
		TextY = 6,
	},
}

UpgradeMachineConfig.Text = {
	Title = "EVOLUCAO DE ITENS",
	BaseItem = "ITEM BASE",
	ResultItem = "RESULTADO",
	Materials = "MATERIAIS NECESSARIOS",
	SuccessRate = "TAXA DE SUCESSO",
	Upgrade = "EVOLUIR",
	Close = "X",
}

return UpgradeMachineConfig
