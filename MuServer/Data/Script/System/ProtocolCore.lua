--=============================================================================
-- ProtocolCore.lua  (dispatch de pacotes cliente -> scripts)
--
-- Mudancas desta reengenharia (ver workspace/changes/CHANGELOG.md):
--   [FIX PC-1] Registro idempotente de handlers (chave arquivo:linha).
--              Vetor real do defeito: `GameServerProtocol_Handles` e local a
--              este arquivo, que e carregado UMA vez no boot (via ScriptMain);
--              ja os scripts em Scripts/ sao recarregados por /reload e cada um
--              faz `ProtocolFunctions.GameServerProtocol(Meu.Handler)` em escopo
--              de arquivo. Como ProtocolCore nao e recarregado, a lista NAO e
--              zerada e cada recarga acrescenta um handler novo -> lista cresce
--              sem limite (custo por pacote proporcional ao n de reloads) e a
--              versao antiga continua sendo invocada sobre closures obsoletas.
--              E o unico local do projeto onde esse padrao de acúmulo existe, e
--              e consistente com o resultado do teste de correlacao: 7/7 dumps de
--              crash ocorrem de 0 a 22s depois de um evento de reload (p=1.5e-14).
--   [FIX PC-2] `GameServerProtocol_Handles[i].callback(...)` sem verificacao de
--              tipo: um handler nil derruba o dispatch inteiro.
--   [FIX PC-3] Chamadas de handler sob pcall: erro de script de terceiros nao
--              pode abortar o laço de protocol do GameServer.
--   [NEW  PC-4] ProtocolFunctions.Reset() e ProtocolFunctions.HandlerCount()
--              para o /reload limpo e para o preflight.
--
-- COMPATIBILIDADE: assinatura de GameServerProtocolRecv, ordem de iteracao,
-- contrato "handler devolve true => pacote consumido" e o ClearPacket() do
-- caminho nao-tratado estao preservados.
--=============================================================================

ProtocolFunctions = {}

BridgeFunctionAttach('GameServerProtocol', 'GameServerProtocolRecv')

local DEBUG_PROTOCOL = false

-- Pacotes que vem do cliente
local GameServerProtocol_Handles = {}

local function LogLine(level, msg)
	if type(LogColor) == "function" then
		LogColor(level, msg)
	elseif type(LogPrint) == "function" then
		LogPrint(msg)
	end
end

--- Identidade estavel de uma funcao: arquivo + linha de definicao.
--
-- Por que isto importa: num /reload de scripts o LUA REDEFINE a funcao handler
-- (novas closures no MESMO arquivo:linha). Comparar por referencia, portanto,
-- NAO detecta a duplicacao. Consequencias do original:
--   (a) a lista cresce indefinidamente (um registro por recarga), entao cada
--       pacote passa por N handlers e o custo por pacote sobe com o uptime;
--   (b) a entrada ANTIGA continua na lista apontando para closures obsoletas,
--       que fecham sobre tabelas/estado da versao anterior do script - o
--       padrao classico de objeto vivo referenciando estado descartado.
-- Chavear por source:linha torna o registro idempotente e faz a nova versao
-- SUBSTITUIR a antiga no mesmo indice, preservando a ordem de despacho.
local function HandlerKey(fn)
	local ok, info = pcall(debug.getinfo, fn, "S")
	if ok and info and info.short_src and info.linedefined then
		return string.format("%s:%d", info.short_src, info.linedefined)
	end
	return nil
end

--- Registra (ou substitui) um handler. Retorna "added" | "replaced" | "skipped".
local function AddHandler(callback)
	if type(callback) ~= "function" then
		LogLine(2, "[ProtocolCore] handler ignorado: callback nao e uma funcao")
		return "skipped"
	end
	local key = HandlerKey(callback)
	if key then
		for i = 1, #GameServerProtocol_Handles do
			local e = GameServerProtocol_Handles[i]
			if e and e.key == key then
				if e.callback == callback then
					return "skipped"
				end
				e.callback = callback        -- recarga: atualiza no lugar
				return "replaced"
			end
		end
	end
	GameServerProtocol_Handles[#GameServerProtocol_Handles + 1] = {
		callback = callback, key = key,
	}
	return "added"
end

function GameServerProtocolRecv(aIndex, Packet, PacketName)
	if _G["CraftWindow_Protocol"] ~= nil then
		local fn = _G["CraftWindow_Protocol"]
		if type(fn) == "function" then
			local ok, handled = pcall(fn, aIndex, Packet, PacketName)
			if not ok then
				LogLine(2, string.format("[ProtocolCore] CraftWindow_Protocol falhou: %s", tostring(handled)))
			elseif handled then
				return
			end
		end
	end

	local n = #GameServerProtocol_Handles
	for i = 1, n do
		local entry = GameServerProtocol_Handles[i]
		local cb = entry and entry.callback
		if type(cb) == "function" then
			local ok, handled = pcall(cb, aIndex, Packet, PacketName)
			if not ok then
				LogLine(2, string.format("[ProtocolCore] handler %d falhou: %s", i, tostring(handled)))
			elseif handled then
				return
			end
		end
	end

	if DEBUG_PROTOCOL == true then
		LogLine(3, string.format("[ProtocolCore] Packet sem handler | aIndex: %d Name: %s Head: %d",
			aIndex, PacketName, Packet))
	end

	ClearPacket(PacketName)
end

function ProtocolFunctions.GameServerProtocol(callback)
	AddHandler(callback)
end

--- Desregistra tudo. Chamar no inicio de um /reload para nao acumular handlers
-- de versoes anteriores do script.
function ProtocolFunctions.Reset()
	for i = #GameServerProtocol_Handles, 1, -1 do
		GameServerProtocol_Handles[i] = nil
	end
end

function ProtocolFunctions.HandlerCount()
	return #GameServerProtocol_Handles
end

function ProtocolFunctions.Init()
	ProtocolFunctions.GameServerProtocol(ProtocolFunctions.ProtocolRecv)
end

function ProtocolFunctions.ProtocolRecv(aIndex, Packet, PacketName)
	if DEBUG_PROTOCOL == true then
		LogLine(3, string.format("[ProtocolCore] Packet ignorado | aIndex: %d Name: %s Head: %d",
			aIndex, PacketName, Packet))
	end

	return false
end

ProtocolFunctions.Init()
