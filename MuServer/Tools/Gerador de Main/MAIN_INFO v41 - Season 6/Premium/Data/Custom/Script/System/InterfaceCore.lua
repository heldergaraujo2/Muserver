InterfaceController = {}

BridgeFunctionAttach('MainInterfaceProcThread','MainProcInterface')
BridgeFunctionAttach('KeyboardEvent','MainProcWorldKey')
--BridgeFunctionAttach('ScrollMouseEvent','ScrollMouse')
--BridgeFunctionAttach('RightClickEvent','InterfaceClickRightEvent')
--BridgeFunctionAttach('LeftClickEvent','InterfaceLeftClickEvent')
--BridgeFunctionAttach('UpdateMouseEvent','UpdateMouse')
--BridgeFunctionAttach('UpdateKeyEvent','UpdateKey')

local MainProcInterface_Handle = {}

function MainProcInterface()
	for i in pairs(MainProcInterface_Handle) do
		MainProcInterface_Handle[i].callback()
	end
end

function InterfaceController.MainProc(callback, ...)
	MainProcInterface_Handle[callback] = { callback = callback }
end

local MainProcWorldKey_Handle = {}

function MainProcWorldKey(key)
	for i in pairs(MainProcWorldKey_Handle) do
		MainProcWorldKey_Handle[i].callback(key)
	end
end

function InterfaceController.MainProcWorldKey(callback, ...)
	MainProcWorldKey_Handle[callback] = { callback = callback }
end

local ScrollMouse_Handle = {}

function ScrollMouse(value)
	for i in pairs(ScrollMouse_Handle) do
		ScrollMouse_Handle[i].callback(value)
	end
end

function InterfaceController.ScrollMouse(callback, ...)
	ScrollMouse_Handle[callback] = { callback = callback }
end

local InterfaceClickRightEvent_Handle = {}

function InterfaceClickRightEvent()
	for i in pairs(InterfaceClickRightEvent_Handle) do
		InterfaceClickRightEvent_Handle[i].callback()
	end
end

function InterfaceController.InterfaceClickRightEvent(callback, ...)
	InterfaceClickRightEvent_Handle[callback] = { callback = callback }
end

local InterfaceLeftClickEvent_Handle = {}

function InterfaceLeftClickEvent()
	for i in pairs(InterfaceLeftClickEvent_Handle) do
		InterfaceLeftClickEvent_Handle[i].callback()
	end
end

function InterfaceController.InterfaceLeftClickEvent(callback, ...)
	InterfaceLeftClickEvent_Handle[callback] = { callback = callback }
end

local InterfaceUpdateMouse_Handle = {}

function UpdateMouse()
	for i in pairs(InterfaceUpdateMouse_Handle) do
		InterfaceUpdateMouse_Handle[i].callback()
	end
end

function InterfaceController.UpdateMouse(callback)
	InterfaceUpdateMouse_Handle[callback] = { callback = callback }
end

local InterfaceUpdateKey_Handle = {}

function UpdateKey()
	for i in pairs(InterfaceUpdateKey_Handle) do
		InterfaceUpdateKey_Handle[i].callback()
	end
end

function InterfaceController.UpdateKey(callback)
	InterfaceUpdateKey_Handle[callback] = { callback = callback }
end