return {
	Enabled = true,
	RingSlots = { 10, 11 },
	-- Use -1 to return to the character's normal appearance.
	ClearSkin = -1,
	ReapplyEverySeconds = 0,
	RecalcAfterItemMoveSeconds = 1,
	Rings = {
		{
			Name = "Skeleton",
			ItemSection = 13,
			ItemIndex = 21,
			Level = nil,
			MonsterSkin = 14,
		},
		{
			Name = "Skeleton Archer",
			ItemSection = 13,
			ItemIndex = 22,
			Level = nil,
			MonsterSkin = 15,
		},
		{
			Name = "Chief Skeleton Warrior",
			ItemSection = 13,
			ItemIndex = 23,
			Level = nil,
			MonsterSkin = 16,
		},
		{
			Name = "Cyclops",
			ItemSection = 13,
			ItemIndex = 24,
			Level = nil,
			MonsterSkin = 17,
		},
	},

	SendMessage = true,
	MessageOnApply = "Aparencia alterada para %s.",
	MessageOnClear = "Aparencia normal restaurada.",
}
