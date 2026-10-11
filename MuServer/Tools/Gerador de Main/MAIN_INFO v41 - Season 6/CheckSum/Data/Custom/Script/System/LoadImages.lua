--[[
here you can upload images, I recommend using from the number 40000
--]]

BridgeFunctionAttach('MainLoader','LoadImages')

function LoadImages()

	LoadBitmap("Custom\\ScriptImages\\bg500.tga", 40000)
	LoadBitmap("Custom\\ScriptImages\\buttonx.tga", 40001)
	LoadBitmap("Custom\\ScriptImages\\interface.tga", 40002)
	LoadBitmap("Custom\\ScriptImages\\buttonentrar.tga", 40003)
	LoadBitmap("Custom\\ScriptImages\\comprarentrada.tga", 40004)
	LoadBitmap("Custom\\ScriptImages\\interna.tga", 40005)
	LoadBitmap("Custom\\ScriptImages\\buttondark.tga", 40006)
	LoadBitmap("Custom\\ScriptImages\\upgrademachine.tga", 40007)
	Console(2,"[LoadImages] Load lua images sucefully")
end
