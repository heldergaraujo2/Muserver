--=============================================================================
-- ScriptCore.lua  (Layer de bridge GameServer <-> Lua)
--
-- Mudancas aplicadas nesta reengenharia (ver workspace/changes/CHANGELOG.md):
--   [FIX SC-1] Todo handler agora e executado sob pcall. Antes, QUALQUER erro
--              Lua (aritmetica sobre nil, indexacao de nil, erro de script de
--              terceiros) propagava para dentro do loop do GameServer.
--   [FIX SC-2] Handler registrado com nome que nao existe em _G nao causa mais
--              "attempt to call a nil value" - era o caminho mais provavel de
--              crash apos um /reload que descarrega um script (BridgeFunctionTable
--              persiste entre reloads, os nomes nao).
--   [FIX SC-3] contadores de erro por bridge para diagnostico, com teto fixo
--              para nunca crescer sem limite em memoria (processo 32-bit, sem
--              LARGEADDRESSAWARE -> teto real de ~2GB de espaco de endereco).
--   [NEW  SC-4] BridgeFunctionReset()/BridgeFunctionStats() para o preflight e
--              para inspecao em runtime sem depender de debugger.
--
-- COMPATIBILIDADE: os nomes publicos (BridgeFunctionAttach e todos os
-- BridgeFunction_<evento>) e a semantica de retorno de cada evento estao
-- preservados byte a byte no comportamento saudavel. A ordem de execucao dos
-- handlers e mantida. Nada aqui muda regra de jogo.
--=============================================================================

BridgeFunctionTable = BridgeFunctionTable or {}

--- Estatisticas por bridge: total de chamadas, erros e handlers pendentes.
BridgeFunctionStats = {}

--- Anel circular de erros recentes (limitado) para o relatorio de preflight.
BridgeFunctionLastErrorRing = {}
local BRIDGE_ERROR_RING_MAX = 256

local BRIDGE_WARN_EVERY = 50        -- loga no maximo 1 a cada N erros por bridge
local function ShouldLog(bridge)
	local s = BridgeFunctionStats[bridge]
	if not s then return true end
	return (s.errors % BRIDGE_WARN_EVERY) == 1
end

local function StatFor(bridge)
	local s = BridgeFunctionStats[bridge]
	if not s then
		s = { calls = 0, errors = 0, missing = 0 }
		BridgeFunctionStats[bridge] = s
	end
	return s
end

local function ReportError(bridge, name, err, kind)
	local s = StatFor(bridge)
	s.errors = s.errors + 1
	if kind == "missing" then s.missing = s.missing + 1 end
	local e = BridgeFunctionLastErrorRing
	e[#e + 1] = { bridge = bridge, handler = name, kind = kind, msg = tostring(err) }
	if #e > BRIDGE_ERROR_RING_MAX then table.remove(e, 1) end
	if not ShouldLog(bridge) then return end
	local line = string.format("[ScriptCore] bridge %s | handler %s | %s: %s",
		tostring(bridge), tostring(name), tostring(kind), tostring(err))
	if type(LogColor) == "function" then
		LogColor(2, line)
	elseif type(LogPrint) == "function" then
		LogPrint(line)
	end
end

--- Resolve o handler tolerando nome (string) ou funcao direta.
-- Retorna nil quando o nome nao corresponde a uma funcao - o chamador decide
-- como reportar, em vez de lancar "attempt to call a nil value".
--- Empacota varargs preservando a contagem exata (nils intercalados ou
-- terminais). Usar { ... } + #t perderia argumentos apos o primeiro nil e,
-- portanto, mudaria a assinatura vista pelo handler em relacao ao original.
local function Pack(...)
	return { n = select('#', ...), ... }
end

local function Args(t)
	if t == nil then return nil end
	return table.unpack(t, 1, t.n)
end

local function Resolve(fn)
	if type(fn) == "function" then return fn end
	if type(fn) == "string" then
		local f = _G[fn]
		if type(f) == "function" then return f end
	end
	return nil
end

function BridgeFunctionAttach(BridgeName, FunctionName)
	if BridgeName == nil or FunctionName == nil then return end

	if BridgeFunctionTable[BridgeName] == nil then
		BridgeFunctionTable[BridgeName] = {}
	end

	-- Dedupe: mantem a semantica original de "ja registrado, nao registra de novo",
	-- mas agora tambem descobre quando o mesmo nome foi registrado em outra bridge.
	local list = BridgeFunctionTable[BridgeName]
	for i = 1, #list do
		if list[i].Function == FunctionName then
			return
		end
	end

	table.insert(list, { Function = FunctionName })
end

--- Remove todos os handlers de uma bridge (ou de todas, se BridgeName for nil).
-- Necessario para um /reload limpo: sem isto, handlers de scripts removidos
-- permanecem registrados apontando para nomes que ja nao existem em _G.
function BridgeFunctionReset(BridgeName)
	if BridgeName == nil then
		BridgeFunctionTable = {}
		BridgeFunctionStats = {}
		BridgeFunctionLastErrorRing = {}
		return
	end
	BridgeFunctionTable[BridgeName] = nil
	BridgeFunctionStats[BridgeName] = nil
end

--- Executa todos os handlers, ignorando erros individuais (modo "void").
local function RunAll(bridge, args)
	local list = BridgeFunctionTable[bridge]
	if list == nil then return end
	local s = StatFor(bridge)
	for i = 1, #list do
		local entry = list[i]
		s.calls = s.calls + 1
		local f = Resolve(entry.Function)
		if f == nil then
			ReportError(bridge, entry.Function, "funcao nao definida no ambiente global", "missing")
		else
			local ok, err
			if args then
				ok, err = pcall(f, Args(args))
			else
				ok, err = pcall(f)
			end
			if not ok then
				ReportError(bridge, entry.Function, err, "error")
			end
		end
	end
end

--- Executa ate que um handler decida; preserva a semantica original de cada bridge.
-- decide(ret) -> true se este retorno encerra a cadeia
-- value(ret)  -> valor a retornar ao GameServer
local function RunUntil(bridge, args, decide, value, fallback)
	local list = BridgeFunctionTable[bridge]
	if list ~= nil then
		local s = StatFor(bridge)
		for i = 1, #list do
			local entry = list[i]
			s.calls = s.calls + 1
			local f = Resolve(entry.Function)
			if f == nil then
				ReportError(bridge, entry.Function, "funcao nao definida no ambiente global", "missing")
			else
				local ok, ret
				if args then
					ok, ret = pcall(f, Args(args))
				else
					ok, ret = pcall(f)
				end
				if not ok then
					-- Erro de script NAO deve conceder nem negar o evento:
					-- tratamos como "handler nao decidiu" e seguimos.
					ReportError(bridge, entry.Function, ret, "error")
				elseif decide(ret) then
					return value(ret)
				end
			end
		end
	end
	return fallback
end

-- Semantica original: `if ret ~= 0 then return 1 end` ... `return 0`
local function StopOnNonZero_Return1(ret) return ret ~= 0 end
-- Semantica original: `if ret == 0 then return 0 end` ... `return 1`
local function StopOnZero_Return0(ret) return ret == 0 end
-- Semantica original: `if ret ~= 0 then return ret end` ... `return 0`
local function StopOnNonZero_ReturnRet(ret) return ret ~= 0 end

function BridgeFunction_OnReadScript()
	RunAll("OnReadScript")
end

function BridgeFunction_OnShutScript()
	RunAll("OnShutScript")
end

function BridgeFunction_OnTimerThread()
	RunAll("OnTimerThread")
end

function BridgeFunction_OnCommandManager(...)
	return RunUntil("OnCommandManager", Pack(...), StopOnNonZero_Return1, function() return 1 end, 0)
end

function BridgeFunction_OnCommandDone(...)
	RunAll("OnCommandDone", Pack(...))
end

function BridgeFunction_OnCharacterEntry(...)
	RunAll("OnCharacterEntry", Pack(...))
end

function BridgeFunction_OnCharacterClose(...)
	RunAll("OnCharacterClose", Pack(...))
end

function BridgeFunction_OnNpcTalk(...)
	return RunUntil("OnNpcTalk", Pack(...), StopOnNonZero_Return1, function() return 1 end, 0)
end

function BridgeFunction_OnMonsterDie(...)
	RunAll("OnMonsterDie", Pack(...))
end

function BridgeFunction_OnUserDie(...)
	RunAll("OnUserDie", Pack(...))
end

function BridgeFunction_OnUserMove(...)
	RunAll("OnUserMove", Pack(...))
end

function BridgeFunction_OnUserRespawn(...)
	RunAll("OnUserRespawn", Pack(...))
end

function BridgeFunction_OnCheckUserTarget(...)
	return RunUntil("OnCheckUserTarget", Pack(...), StopOnZero_Return0, function() return 0 end, 1)
end

function BridgeFunction_OnCheckUserKiller(...)
	return RunUntil("OnCheckUserKiller", Pack(...), StopOnZero_Return0, function() return 0 end, 1)
end

function BridgeFunction_OnUserItemPick(...)
	return RunUntil("OnUserItemPick", Pack(...), StopOnZero_Return0, function() return 0 end, 1)
end

function BridgeFunction_OnUserItemDrop(...)
	return RunUntil("OnUserItemDrop", Pack(...), StopOnZero_Return0, function() return 0 end, 1)
end

function BridgeFunction_OnUserItemMove(...)
	return RunUntil("OnUserItemMove", Pack(...), StopOnZero_Return0, function() return 0 end, 1)
end

function BridgeFunction_OnUserItemUse(...)
	return RunUntil("OnUserItemUse", Pack(...), StopOnNonZero_ReturnRet, function(r) return r end, 0)
end

function BridgeFunction_OnUserDamage(...)
	return RunUntil("OnUserDamage", Pack(...), StopOnNonZero_ReturnRet, function(r) return r end, 0)
end

function BridgeFunction_OnMonsterDamage(...)
	return RunUntil("OnMonsterDamage", Pack(...), StopOnNonZero_ReturnRet, function(r) return r end, 0)
end

function BridgeFunction_OnSQLAsyncResult(...)
	RunAll("OnSQLAsyncResult", Pack(...))
end

function BridgeFunction_GameServerProtocol(...)
	RunAll("GameServerProtocol", Pack(...))
end
