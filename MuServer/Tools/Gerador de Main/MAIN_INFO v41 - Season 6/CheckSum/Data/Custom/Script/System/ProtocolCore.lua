ProtocolFunctions = {}

BridgeFunctionAttach('ClientProtocol','ClientProtocolRecv')

local DEBUG_PROTOCOL = false

-- Packets que vem do gameserver
local ClientProtocol_Handles = {}

function ClientProtocolRecv(Packet, PacketName)
	for i = 1, #ClientProtocol_Handles do
		if ClientProtocol_Handles[i].callback(Packet, PacketName) then
			return
		end
	end

	if DEBUG_PROTOCOL == true then
		LogColor(3, string.format("[ProtocolCore] Packet sem handler | Name: %s Head: %d", PacketName, Packet))
	end

	ClearPacket(PacketName)
end

function ProtocolFunctions.ClientProtocol(callback)
	table.insert(ClientProtocol_Handles, { callback = callback })
end

function ProtocolFunctions.Init()
	ProtocolFunctions.ClientProtocol(ProtocolFunctions.ProtocolRecv)
end

function ProtocolFunctions.ProtocolRecv(Packet, PacketName)
	if DEBUG_PROTOCOL == true then
		LogColor(3, string.format("[ProtocolCore] Packet ignorado | Name: %s Head: %d", PacketName, Packet))
	end

	return false
end

ProtocolFunctions.Init()
