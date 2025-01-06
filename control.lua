require("util")
require("types")

script.on_init(function() init() end)

-- Register Events
script.on_event(defines.events.on_built_entity, function(event) RegisterStop(event) end)
script.on_event(defines.events.on_robot_built_entity, function(event) RegisterStop(event) end)
script.on_event(defines.events.on_cancelled_deconstruction, function(event) RegisterStop(event) end)

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event) UpdateConstantCombinatorConfig(event) end)

-- Deregister Events
script.on_event(defines.events.on_marked_for_deconstruction, function(event) DeconstructStop(event) end)
script.on_event(defines.events.on_object_destroyed, function(event) DeconstructStop(event) end)
script.on_event(defines.events.on_tick, function(event) Tick() end)

script.on_event(defines.events.on_train_changed_state, function(event) OnTrainStateChanged(event) end)

function init()
  storage.MTL = storage.MTL or {}
  ---@type {[uint]:MaTrainNetwork.TrainStop.Umbrella}
  storage.MTL.stops = storage.MTL.stops or {}

  ---@type {[uint]:true}
  storage.MTL[Roles.DEPOT] = storage.MTL[Roles.DEPOT] or {}
  ---@type {[uint]:true}
  storage.MTL[Roles.PROVIDER] = storage.MTL[Roles.PROVIDER] or {}
  ---@type {[uint]:true}
  storage.MTL[Roles.REQUESTER] = storage.MTL[Roles.REQUESTER] or {}

  ---@type {[uint]:MaTrainNetwork.Train.Order} Train.id to Order map
  storage.MTL.train_orders = storage.MTL.train_orders or {}

  ---@type {[uint]:uint}
  storage.MTL.reverse_lookup = storage.MTL.reverse_lookup or {}
end

---@param event EventData.on_built_entity | EventData.on_robot_built_entity | EventData.on_cancelled_deconstruction
function RegisterStop(event)
  -- is not a train stop
  if event == nil or event.entity == nil or event.entity.name ~= ENTITY_TRAIN_STOP_NAME then
    return
  end

  local train_stop = event.entity
  if not storage.MTL.stops[event.entity] then
    local lamp = CreateLamp(train_stop)
    if not lamp then
      train_stop.destroy()
      MTL_Log(LEVEL.ERROR, "could not create lamp for train stop " .. train_stop.backer_name)
      return
    end

    local cc = CreateConstantCombinator(train_stop)
    if not cc then
      lamp.destroy()
      train_stop.destroy()
      MTL_Log(LEVEL.ERROR, "could not create lamp for train stop " .. train_stop.backer_name)
      return
    end

    ---@type MaTrainNetwork.TrainStop.Umbrella
    local umbrella = {
      id = event.entity.unit_number,
      train_stop = event.entity,
      lamp = lamp,
      cc = cc,
    }

    storage.MTL.reverse_lookup[lamp.unit_number] = umbrella.train_stop.unit_number
    storage.MTL.reverse_lookup[cc.unit_number] = umbrella.train_stop.unit_number
    storage.MTL.stops[train_stop.unit_number] = umbrella
    script.register_on_object_destroyed(train_stop) -- so that we can react on destruction of the train stop
  end
end

function UpdateConstantCombinatorConfig(event)
  if event == nil or event.entity == nil or event.entity.name ~= ENTITY_TRAIN_STOP_CC_NAME or not event.player_index then
    return
  end

  local train_stop_number = storage.MTL.reverse_lookup[event.entity.unit_number]
  local umbrella = storage.MTL.stops[train_stop_number]
  MTL_Log(LEVEL.DEBUG, "got constant combinator update for " .. umbrella.train_stop.backer_name)

  CheckConstantCombinatorConfig(umbrella)
  if not ReadConfig(umbrella) then
    SetStatus(umbrella, Status.TRAIN_STOP_ERROR)
    -- todo deregister
    return
  end

  SetStatus(umbrella, Status.NEUTRAL)
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
function DeregisterStop(umbrella)
  if umbrella.role then
    storage.MTL[umbrella.role][umbrella.train_stop.unit_number] = nil
  end
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
---@param status MaTrainNetwork.TrainStop.Status
---@param count? integer
function SetStatus(umbrella, status, count)
  ---@diagnostic disable-next-line: undefined-field
  umbrella.cc.get_or_create_control_behavior().get_section(SECTION_GROUP_OUTPUT_INDEX).set_slot(1,
    { value = status, min = count or 1 })
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
---@return boolean
function ReadConfig(umbrella)
  ---@type LuaLogisticSection
  ---@diagnostic disable-next-line: undefined-field -- get_or_create_control_behavior() returns [LuaConstantCombinatorControlBehavior]
  local config_section = umbrella.cc.get_or_create_control_behavior().get_section(SECTION_GROUP_CONFIG_INDEX)

  local role = {}
  local provider_config = {}
  local requester_config = {}

  for _, filter in pairs(config_section.filters) do
    if not filter.value then
      goto continue
    end

    if filter.value.type == "virtual" and filter.value.name == SIGNAL_DEPOT then
      table.insert(role, Roles.DEPOT)
    end
    if filter.value.type == "virtual" and filter.value.name == SIGNAL_PROVIDE_THRESHOLD then
      provider_config.threshold = filter.min
      table.insert(role, Roles.PROVIDER)
    end
    if filter.value.type == "virtual" and filter.value.name == SIGNAL_REQUEST_THRESHOLD then
      requester_config.threshold = filter.min
      table.insert(role, Roles.REQUESTER)
    end
    ::continue::
  end

  if #role > 1 then
    MTL_Log(LEVEL.ERROR, "train stop \"" .. umbrella.train_stop.backer_name .. "\" has multiple roles " .. dump(role))
    DeregisterStop(umbrella)
    return false
  end

  if #role == 0 then
    MTL_Log(LEVEL.DEBUG, "no role found for stop " .. umbrella.train_stop.backer_name)
    DeregisterStop(umbrella)
    return false
  end

  MTL_Log(LEVEL.INFO, "train stop \"" .. umbrella.train_stop.backer_name .. "\" assumed role " .. dump(role))
  -- remove stop from role list
  if role[1] ~= umbrella.role and umbrella.role then
    storage.MTL[umbrella.role][umbrella.train_stop.unit_number] = nil
  end
  umbrella.role = role[1]
  umbrella.provider_config = provider_config
  umbrella.requester_config = requester_config

  storage.MTL[umbrella.role] = storage.MTL[umbrella.role] or {}
  storage.MTL[umbrella.role][umbrella.train_stop.unit_number] = true

  return true
end

---comment
---@param event EventData.on_object_destroyed|EventData.on_marked_for_deconstruction
function DeconstructStop(event)
  if event.name ~= defines.events.on_object_destroyed then
    MTL_Log(LEVEL.ERROR, "invalid event called function DeconstructStop(event)")
    return
  end

  if event.useful_id == 0 or storage.MTL.stops[event.useful_id] == nil then
    MTL_Log(LEVEL.DEBUG, "could not find train stop for deconstruction request")
    return
  end

  umbrella = storage.MTL[event.useful_id]
  MTL_Log(LEVEL.ERROR, tostring(event.useful_id) .. type(umbrella))
  if not umbrella or not DeregisterStop(umbrella) then
    MTL_Log(LEVEL.ERROR, "could not deregister stop")
  end
  if not umbrella or not DeconstructConstantCombinator(umbrella) then
    MTL_Log(LEVEL.ERROR, "could not destroy constant combinator")
  end
  if not umbrella or not DeconstructLamp(umbrella) then
    MTL_Log(LEVEL.ERROR, "could not destory lamp")
  end

  storage.MTL.stops[event.useful_id] = nil
end

---comment
---@return MaTrainNetwork.Train.AvailableTrains
function GetAvaiableTrains()
  ---@type MaTrainNetwork.Train.AvailableTrains
  local available_trains = {
    fluid = {},
    item = {},
  }

  for stop_id, _ in pairs(storage.MTL[Roles.DEPOT]) do
    local umbrella = storage.MTL.stops[stop_id]
    if not umbrella or not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    if umbrella.role == Roles.DEPOT then
      SetStatus(umbrella, Status.DEPOT_READY_TO_RECEIVE_TRAIN)

      local train = umbrella.train_stop.get_stopped_train()
      if not train then
        goto continue
      end

      if #train.carriages < 2 then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO, "train in stop \"" .. umbrella.train_stop.backer_name .. "\" has too few carriages")
        goto continue
      end

      if train.carriages[2].prototype.type ~= "cargo-wagon" and train.carriages[2].prototype.type ~= "fluid-wagon" then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" has to have cargo wagon or fluid wagon on 2nd place")
        goto continue
      end

      carriage_type = (train.carriages[2].prototype.type == "fluid-wagon" and "fluid") or "item"

      if carriage_type == "item" and #train.carriages[2].get_output_inventory().get_contents() ~= 0 then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not empty and therefor not listed as available train")
        goto continue
      end

      if carriage_type == "fluid" and not train.carriages[2].get_fluid_contents() then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not empty and therefor not listed as available train")
        goto continue
      end

      if umbrella.assigned_train.id ~= train.id then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.ERROR,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not the train assigned to this depot")
        goto continue
      end

      local fluid_capacity = (carriage_type == "fluid" and train.carriages[2].prototype.fluid_capacity) or 0
      local slot_capacity = (carriage_type == "item" and train.carriages[2].get_output_inventory().get_bar() - 1) or 0

      umbrella.assigned_train = train

      ---@type MaTrainNetwork.Train.TrainInfo
      train_info = {
        train = train,
        slot_capacity = slot_capacity,
        fluid_capacity = fluid_capacity,
        depot = stop_id,
      }
      table.insert(available_trains[carriage_type], train_info)

      SetStatus(umbrella, Status.DEPOT_WITH_READY_TRAIN)
    end
    ::continue::
  end

  return available_trains
end

function GetReqests()
  ---@type {[MaTrainNetwork.ResourceTypeName]:MaTrainNetwork.Request[]}
  all_requests = {}
  storage.MTL[Roles.REQUESTER] = storage.MTL[Roles.REQUESTER] or {}

  for stop_id, _ in pairs(storage.MTL[Roles.REQUESTER]) do
    local umbrella = storage.MTL.stops[stop_id]

    if not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    local signals = umbrella.lamp.get_signals(defines.wire_connector_id.circuit_red)
    if not signals then
      MTL_Log(LEVEL.TRACE, "no signals found for " .. umbrella.train_stop.backer_name)
      goto continue
    end

    ---@type {[MaTrainNetwork.ResourceTypeName]:uint}
    local requests = {}
    for _, value in ipairs(signals) do
      -- not value.signal.type is equivalent to "item" as of api docs
      if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
        if value.count < 0 then
          local type_name = {
            type = value.signal.type or "item",
            name = value.signal.name,
          }
          requests[type_name] = value.count
        end
      end
    end

    umbrella.incoming_trains = umbrella.incoming_trains or {}
    for _, order in ipairs(umbrella.incoming_trains) do
      requests[order.resource]
      = requests[order.resource] + order.count
    end

    for type_name, count in pairs(requests) do
      if -umbrella.requester_config.threshold < count then
        requests[type_name] = nil
        goto continue
      end

      all_requests[type_name] = all_requests[type_name] or {}

      ---@type MaTrainNetwork.Request
      local request = {
        type_name = type_name,
        stop = umbrella.train_stop.unit_number,
        count = -count,
      }
      table.insert(all_requests[type_name], request)

      ::continue::
    end

    ::continue::
  end
  return all_requests
end

function GetProvides()
  all_provides = {}
  storage.MTL[Roles.PROVIDER] = storage.MTL[Roles.PROVIDER] or {}
  for stop_id, _ in pairs(storage.MTL[Roles.PROVIDER]) do
    local umbrella = storage.MTL.stops[stop_id]
    if not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    local signals = umbrella.lamp.get_signals(defines.wire_connector_id.circuit_red)
    if not signals then
      MTL_Log(LEVEL.TRACE, "no signals found for " .. umbrella.train_stop.backer_name)
      goto continue
    end

    local provides = {}
    for _, value in ipairs(signals) do
      -- not value.signal.type is equivalent to "item" as of api docs
      if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
        MTL_Log(LEVEL.DEBUG, "value.signal: " .. dump(value.signal) .. " " .. value.count)
        if umbrella.provider_config.threshold <= value.count then
          local type = value.signal.type or "item"
          local type_name = type .. "/" .. value.signal.name
          provides[type_name] = value.count
        end
      end
    end

    if #provides == 0 then
      goto continue
    end

    umbrella.incoming_trains = umbrella.incoming_trains or {}
    for train_info, resource in pairs(umbrella.incoming_trains) do
      provides[resource.type_name] = provides[resource.type_name] - resource.count
    end

    for type_name, count in pairs(provides) do
      if umbrella.provider_config.threshold > count then
        provides[type_name] = nil
        goto continue
      end

      all_provides[type_name] = all_provides[type_name] or {}

      MTL_Log(LEVEL.DEBUG, dump(umbrella.train_stop.unit_number))
      table.insert(all_provides[type_name], {
        type_name = type_name,
        threshold_count = umbrella.provider_config.threshold,
        stop = umbrella.train_stop.unit_number,
        count = count,
      })
      ::continue::
    end

    umbrella.provides = provides
    ::continue::
  end

  MTL_Log(LEVEL.DEBUG, "all_provides: " .. dump(all_provides))
  return all_provides
end

function Tick()
  local available_trains = GetAvaiableTrains()
  local all_requests = GetReqests()
  local all_provides = GetProvides()

  if #available_trains["fluid"] == 0 and #available_trains["item"] == 0 then
    MTL_Log(LEVEL.DEBUG, "#available_trains: " .. #available_trains)
    return
  end

  for type_name, requests_list in pairs(all_requests) do
    for _, request in pairs(requests_list) do
      if not all_provides[type_name] then
        goto continue
      end
      for _, provide in pairs(all_provides[type_name]) do
        if provide.count < provide.threshold_count then
          goto continue
        end

        local sent_amount = (request.count > provide.count and provide.count) or request.count
        local carriage_type = type_name.type

        MTL_Log(LEVEL.DEBUG, "type is " .. carriage_type)
        if #available_trains[carriage_type] == 0 then
          MTL_Log(LEVEL.DEBUG, "no available train for " .. carriage_type .. " found")
          goto continue
        end
        ---@type MaTrainNetwork.Train.TrainInfo
        local train_info = available_trains[carriage_type][#available_trains[carriage_type]]
        table.remove(available_trains[carriage_type])

        provide.count = provide.count - sent_amount


        for key, value in ipairs(storage.MTL.stops[request.stop].incoming_trains) do
          MTL_Log(LEVEL.DEBUG, "incoming train " .. dump(key) .. "  " .. dump(value))
        end

        MTL_Log(LEVEL.DEBUG, "train info" .. dump(train_info))
        local type, name = split_type_name(type_name)
        MTL_Log(LEVEL.DEBUG, "type: " .. type .. " name: " .. name)
        storage.MTL.stops[request.stop].incoming_trains = storage.MTL.stops[request.stop].incoming_trains or {}
        ---@type MaTrainNetwork.Train.Order
        train_order = {
          train = train_info.train,
          resource = type_name,
          count = sent_amount,
          depot = train_info.depot,
          provider = provide.stop,
          requester = request.stop,
        }
        storage.MTL.stops[request.stop].incoming_trains[train_order.train.id] = train_order
        storage.MTL.stops[provide.stop].incoming_trains[train_order.train.id] = train_order
        storage.MTL.train_orders[train_info.train.id] = train_order

        CreateTrainSchedule(train_order)

        ::continue::
      end
      ::continue::
    end
  end
end

function DispatchTrain(start, stop, train_info, resource, count)
  --storage.MTL.stops[train_info.depot].train
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
function DeconstructConstantCombinator(umbrella)
  if not umbrella.cc then
    return true
  end

  local cc_id = umbrella.cc.unit_number

  if not umbrella.cc.destroy() then
    MTL_Log(LEVEL.ERROR, "failed to destroy constant combinator")
    return false
  end

  if cc_id then
    storage.MTL.reverse_lookup[cc_id] = nil
  end
  umbrella.cc = nil
  return true
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
---@return boolean
function DeconstructLamp(umbrella)
  if not umbrella.lamp then
    return true
  end

  if umbrella.lamp.unit_number then
    storage.MTL.reverse_lookup[umbrella.lamp.unit_number] = nil
  end

  if not umbrella.lamp.destroy() then
    MTL_Log(LEVEL.ERROR, "failed to destroy lamp")
    return false
  end

  umbrella.lamp = nil
  return true
end

---@param train_stop LuaEntity
---@return LuaEntity? -- lamp created
function CreateLamp(train_stop)
  local lamp = train_stop.surface.create_entity({
    name = ENTITY_TRAIN_STOP_LAMP_NAME,
    snap_to_grid = true,
    direction = train_stop.direction,
    position = { train_stop.position.x - 2, train_stop.position.y - 1 },
    force = train_stop.force
  })
  if not lamp then
    MTL_Log(LEVEL.ERROR, "Could not create lamp for stop: " .. train_stop.backer_name)
    return nil
  end
  ---@diagnostic disable-next-line: inject-field
  lamp.get_or_create_control_behavior().use_colors = true
  lamp.always_on = true

  MTL_Log(LEVEL.TRACE, "created lamp for \"" .. umbrella.train_stop.backer_name .. "\"")
  return lamp
end

---comment
---@param train_stop LuaEntity
---@return LuaEntity? -- constant combinator created
function CreateConstantCombinator(train_stop)
  local cc = train_stop.surface.create_entity({
    name = ENTITY_TRAIN_STOP_CC_NAME,
    snap_to_grid = true,
    direction = umbrella.train_stop.direction,
    position = { umbrella.train_stop.position.x - 2, umbrella.train_stop.position.y },
    force = umbrella.train_stop.force
  })
  if not cc then
    MTL_Log(LEVEL.ERROR, "Could not create constant combinator for stop: " .. train_stop.backer_name)
    return nil
  end

  ---@type LuaConstantCombinatorControlBehavior
  ---@diagnostic disable-next-line: assign-type-mismatch
  local control_behavior = cc.get_or_create_control_behavior()

  if control_behavior.sections_count < 2 then
    for i = control_behavior.sections_count, 1, -1 do
      control_behavior.remove_section(i)
    end

    control_behavior.add_section()
    control_behavior.add_section()
    control_behavior.get_section(SECTION_GROUP_OUTPUT_INDEX).filters = {}

    MTL_Log(LEVEL.TRACE, "fixed constant combinator behavior for stop \"" .. umbrella.train_stop.backer_name .. "\"")
  end

  MTL_Log(LEVEL.TRACE, "created constant combinator for stop \"" .. train_stop.backer_name .. "\"")
  return cc
end

function CheckConstantCombinatorConfig(umbrella)
  local cc = umbrella.cc
  if not cc then
    MTL_Log(LEVEL.ERROR, "could not find constant combinator for \"" .. umbrella.train_stop.backer_name .. "\"")
  end
  -- redo_cc_config if sections do not match
  if cc.get_or_create_control_behavior().sections_count < 2 then
    for i = cc.get_or_create_control_behavior().sections_count, 1, -1 do
      cc.get_or_create_control_behavior().remove_section(i)
    end

    cc.get_or_create_control_behavior().add_section()
    cc.get_or_create_control_behavior().add_section()
    cc.get_or_create_control_behavior().get_section(SECTION_GROUP_OUTPUT_INDEX).filters = {}

    MTL_Log(LEVEL.TRACE, "fixed constant combinator behavior for \"" .. umbrella.train_stop.backer_name .. "\"")
  end
end

function ConnectConstantCombinatorAndLampCircuit(umbrella)
  local cc = umbrella.cc
  local lamp = umbrella.lamp

  cc.get_wire_connector(defines.wire_connector_id.circuit_red, true)
      .connect_to(
        lamp.get_wire_connector(defines.wire_connector_id.circuit_red, true),
        false,
        defines.wire_origin.script)
  --[[cc.get_wire_connector(defines.wire_connector_id.circuit_green, true)
      .connect_to(
        lamp.get_wire_connector(defines.wire_connector_id.circuit_green, true),
        false,
        defines.wire_origin.script)]] --

  MTL_Log(LEVEL.TRACE,
    "created circuit connection betweend constant combinator and lamp for \"" .. umbrella.train_stop.backer_name .. "\"")
end

function OnTrainStateChanged(event)
  storage.MTL.train_orders = storage.MTL.train_orders or {}
  if not storage.MTL.train_orders[event.train.id] then
    return
  end

  if event.old_state == defines.train_state.arrive_station and event.train.state == defines.train_state.wait_station then
    OnTrainArriving(event)
  end
end

function OnTrainDeparture(event)

end

function OnTrainArriving(event)
  MTL_Log(LEVEL.DEBUG, "Train " .. event.train.backer_name .. " arrived at " .. event.train.station.backer_name)
end

---comment
---@param order MaTrainNetwork.Train.Order
function CreateTrainSchedule(order)
  order.train.schedule = {
    current = 1,
    records = {
      {
        station = storage.MTL.stops[order.provider].train_stop.backer_name,
        wait_conditions = {
          {
            compare_type = "or",
            type = (type == "item" and "item_count") or "fluid_count",
            condition = {
              first_signal = { type = tostring(order.resource.type), name = order.resource.name },
              comparator = ">=",
              constant = order.count,
            }
          },
          {
            compare_type = "or",
            type = "time",
            ticks = 7200,
          },
          {
            compare_type = "or",
            type = "inactivity",
            ticks = 500,
          }
        },
      },
      {
        station = storage.MTL.stops[order.requester].train_stop.backer_name,
        wait_conditions = {
          {
            compare_type = "or",
            type = "empty",
            condition = {
              first_signal = { type = tostring(order.resource.type), name = order.resource.name },
              comparator = ">=",
              constant = order.count,
            }
          },
          {
            compare_type = "or",
            type = "time",
            ticks = 7200,
          }
        }
      },
      {
        station = storage.MTL.stops[train_info.depot].train_stop.backer_name,
        wait_conditions = {
          {
            type = "time",
            ticks = 300,
          }
        }
      },
    }
  }
end
