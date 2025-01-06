ENTITY_TRAIN_STOP_NAME = "ma-train-stop"
ENTITY_TRAIN_STOP_LAMP_NAME = "ma-train-stop-lamp"
ENTITY_TRAIN_STOP_CC_NAME = "ma-train-stop-cc"

ITEM_TRAIN_STOP_NAME = "ma-train-stop"

RECIPE_TRAIN_STOP_NAME = "ma-train-stop"

TECHNOLOGY_MTN_NAME = "ma-train-network"

SIGNAL_DEPOT = "mtn-depot"
SIGNAL_REQUEST_THRESHOLD = "mtn-request-threshold"
SIGNAL_PROVIDE_THRESHOLD = "mtn-provide-threshold"

SECTION_GROUP_CONFIG = "MLT - Config"
SECTION_GROUP_CONFIG_INDEX = 1
SECTION_GROUP_OUTPUT = "MLT - Output"
SECTION_GROUP_OUTPUT_INDEX = 2


function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k, v in pairs(o) do
         if type(k) ~= 'number' then k = '"' .. k .. '"' end
         s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end

LEVEL = {
   TRACE = 0,
   DEBUG = 1,
   INFO = 2,
   ERROR = 3,
   SILENT = 4,
}

local level_to_log = 0
local level_to_user = 0

function MTL_Log(level, message)
   local msg
   if level == LEVEL.TRACE then
      msg = "MLT TRACE: " .. message
   end
   if level == LEVEL.DEBUG then
      msg = "MLT DEBUG: " .. message
   end
   if level == LEVEL.INFO then
      msg = "MLT INFO: " .. message
   end
   if level == LEVEL.ERROR then
      msg = "MLT ERROR: " .. message
   end

   if level >= level_to_log then
      log(msg)
   end
   if level >= level_to_user then
      game.print(msg)
   end
end

function string.starts_with(self, start)
   return self:sub(1, #start) == start
end

function split_type_name(type_name)
   local slash_pos = string.find(type_name, "/")
   return string.sub(type_name, 1, slash_pos-1), string.sub(type_name, slash_pos+1)
end