require('System\\ScriptCore')
require('System\\ProtocolCore')

require('Utils\\DataBase')
require('Utils\\DataBaseAsync')
require('Utils\\Cron')
require('Utils\\Functions')
require('Utils\\Schedule')

require('Scripts\\CalCharacter')
--require('Scripts\\WelcomeMessage')
--require('Scripts\\NpcTalk')

requirefolder('Scripts\\Musaffe')
requirefolder('Scripts\\ReaddRequirement')
requirefolder('Scripts\\UpgradeMachine')
--requirefolder('Scripts\\TransformationRing')
--requirefolder('Scripts\\TesteProtocol')
--requirefolder('Scripts\\AutoPost')

DataBase.Connect(3, "MuOnline", "", "")