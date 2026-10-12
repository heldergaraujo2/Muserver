ProtocolFunctions = {}

BridgeFunctionAttach('GameServerProtocol','GameServerProtocolRecv')

local DEBUG_PROTOCOL = false

-- Packets que vem do cliente
local GameServerProtocol_Handles = {}

function GameServerProtocolRecv(aIndex, Packet, PacketName)
	if _G["CraftWindow_Protocol"] ~= nil then
		if _G["CraftWindow_Protocol"](aIndex, Packet, PacketName) then
			return
		end
	end

	for i = 1, #GameServerProtocol_Handles do
		if GameServerProtocol_Handles[i].callback(aIndex, Packet, PacketName) then
			return
		end
	end

	if DEBUG_PROTOCOL == true then
		LogColor(3, string.format("[ProtocolCore] Packet sem handler | aIndex: %d Name: %s Head: %d", aIndex, PacketName, Packet))
	end

	ClearPacket(PacketName)
end

function ProtocolFunctions.GameServerProtocol(callback)
	table.insert(GameServerProtocol_Handles, { callback = callback })
end

function ProtocolFunctions.Init()
	ProtocolFunctions.GameServerProtocol(ProtocolFunctions.ProtocolRecv)
end

function ProtocolFunctions.ProtocolRecv(aIndex, Packet, PacketName)
	if DEBUG_PROTOCOL == true then
		LogColor(3, string.format("[ProtocolCore] Packet ignorado | aIndex: %d Name: %s Head: %d", aIndex, PacketName, Packet))
	end

	return false
end

ProtocolFunctions.Init()
