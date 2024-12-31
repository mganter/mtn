require("util")

script.on_init(function() init() end)

-- Register Events
script.on_event(defines.events.on_built_entity, function(event) RegisterStop(event) end)
script.on_event(defines.events.on_robot_built_entity, function(event) RegisterStop(event) end)
script.on_event(defines.events.on_cancelled_deconstruction, function(event) RegisterStop(event) end)

script.on_event(defines.events.on_entity_logistic_slot_changed, function(event) UpdateConstantCombinatorConfig(event) end)

-- Deregister Events
script.on_event(defines.events.on_marked_for_deconstruction, function(event) DeregisterStop(event) end)
script.on_event(defines.events.on_object_destroyed, function(event) DeconstructStop(event) end)
script.on_event(defines.events.on_tick, function(event) Tick() end)

function init()
  storage.MTL = storage.MTL or {}
  storage.MTL.stops = storage.MTL.stops or {}
  storage.MTL.depots = storage.MTL.depots or {}

  storage.MTL.reverse_lookup = storage.MTL.reverse_lookup or {}
end

function RegisterStop(event)
  -- is not a train stop
  if event == nil or event.entity == nil or event.entity.name ~= ENTITY_TRAIN_STOP_NAME then
    return
  end

  local train_stop = event.entity
  storage.MTL.stops[train_stop.unit_number] = storage.MTL.stops[train_stop.unit_number] or {}

  local umbrella = storage.MTL.stops[train_stop.unit_number]
  umbrella.train_stop = event.entity

  MTL_Log(LEVEL.TRACE, dump(storage))
  script.register_on_object_destroyed(train_stop)
  MTL_Log(LEVEL.ERROR, dump(storage.MTL.stops[train_stop.unit_number].train_stop))

  CreateAdditionalStopEntities(umbrella)
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
    SetStatus(umbrella, STATUS_TRAIN_STOP_ERROR)
    -- todo deregister
    return
  end

  SetStatus(umbrella, STATUS_NEUTRAL)
end

local function DeregisterStop(umbrella)

end

function SetStatus(umbrella, status, count)
  umbrella.cc.get_or_create_control_behavior().get_section(SECTION_GROUP_OUTPUT_INDEX).set_slot(1,
    { value = status, min = count or 1 })
end

function ReadConfig(umbrella)
  local config_section = umbrella.cc.get_or_create_control_behavior().get_section(SECTION_GROUP_CONFIG_INDEX)

  local role = {}
  local provider_config = {}
  local requester_config = {}

  for _, filter in pairs(config_section.filters) do
    if not filter.value then
      goto continue
    end

    if filter.value.type == "virtual" and filter.value.name == SIGNAL_DEPOT then
      table.insert(role, ROLE_DEPOT)
    end
    if filter.value.type == "virtual" and filter.value.name == SIGNAL_PROVIDE_THRESHOLD then
      provider_config.threshold = filter.min
      table.insert(role, ROLE_PROVIDER)
    end
    if filter.value.type == "virtual" and filter.value.name == SIGNAL_REQUEST_THRESHOLD then
      requester_config.threshold = filter.min
      table.insert(role, ROLE_REQUESTER)
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
  umbrella.role = role[1]

  umbrella.provider_config = provider_config
  umbrella.requester_config = requester_config
  return true
end

function DeconstructStop(event)
  if event.name ~= defines.events.on_object_destroyed then
    MTL_Log(LEVEL.ERROR, "invalid event called function DeconstructStop(event)")
    return false
  end

  if event.useful_id == 0 or storage.MTL.stops[event.useful_id] == nil then
    MTL_Log(LEVEL.DEBUG, "could not find train stop for deconstruction request")
    return
  end

  if not DeregisterStop(event.useful_id) then
    MTL_Log(LEVEL.ERROR, "could not deregister stop")
  end
  if not DeconstructConstantCombinator(event.useful_id) then
    MTL_Log(LEVEL.ERROR, "could not destroy constant combinator")
  end
  if not DeconstructLamp(event.useful_id) then
    MTL_Log(LEVEL.ERROR, "could not destory lamp")
  end

  storage.MTL.stops[event.useful_id] = nil
  --MTL_Log(LEVEL.TRACE, dump(storage))
end

function Tick()
  local all_requests = {}
  local all_provides = {}
  local available_trains = {}

  for stop_id, umbrella in pairs(storage.MTL.stops) do
    if not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    local signals = umbrella.lamp.get_signals(defines.wire_connector_id.circuit_red)
    if not signals then
      MTL_Log(LEVEL.TRACE, "no signals found for " .. umbrella.train_stop.backer_name)
      goto continue
    end

    if umbrella.role == ROLE_DEPOT then
      SetStatus(umbrella, STATUS_DEPOT_READY_TO_RECEIVE_TRAIN)

      local train = umbrella.train_stop.get_stopped_train()
      if not train then
        goto continue
      end

      if #train.carriages < 2 then
        SetStatus(umbrella, STATUS_DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO, "train in stop \"" .. umbrella.train_stop.backer_name .. "\" has too few carriages")
        goto continue
      end

      if train.carriages[2].prototype.type ~= "cargo-wagon" and train.carriages[2].prototype.type ~= "fluid-wagon" then
        SetStatus(umbrella, STATUS_DEPOT_TRAIN_ERROR)
        MTL_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" has to have cargo wagon or fluid wagon on 2nd place")
        goto continue
      end

      --train.backer_name = umbrella.train_stop.backer_name
      umbrella.assigned_train = train
      available_trains[umbrella.train_stop.unit_number] = train
      SetStatus(umbrella, STATUS_DEPOT_WITH_READY_TRAIN)
    end

    if umbrella.role == ROLE_REQUESTER then
      local requests = {}
      for _, value in ipairs(signals) do
        -- not value.signal.type is equivalent to "item" as of api docs
        if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
          if value.count < 0 then
            local type = value.signal.type or "item"
            local type_name = type .. "/" .. value.signal.name
            requests[type_name] = value.count
          end
        end
      end

      umbrella.incoming_trains = umbrella.incoming_trains or {}
      for train, resource in pairs(umbrella.incoming_trains) do
        requests[resource.type_name] = requests[resource.type_name] + resource.count
      end


      for type_name, count in pairs(requests) do
        if -umbrella.requester_config.threshold < count then
          requests[type_name] = nil
          goto continue
        end

        all_requests[type_name] = all_requests[type_name] or {}

        table.insert(all_requests[type_name], {
          type_name = type_name,
          stop = umbrella.train_stop.unit_number,
          count = -count,
        })

        ::continue::
      end

      umbrella.requests = requests
    end

    if umbrella.role == ROLE_PROVIDER then
      local provides = {}
      for _, value in ipairs(signals) do
        -- not value.signal.type is equivalent to "item" as of api docs
        if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
          if umbrella.provider_config.threshold <= value.count then
            local type = value.signal.type or "item"
            local type_name = type .. "/" .. value.signal.name
            provides[type_name] = value.count
          end
        end
      end


      umbrella.incoming_trains = umbrella.incoming_trains or {}
      for train, resource in pairs(umbrella.incoming_trains) do
        provides[resource.type_name] = provides[resource.type_name] - resource.count
      end

      for type_name, count in pairs(provides) do
        if umbrella.provider_config.threshold > count then
          provides[type_name] = nil
          goto continue
        end

        all_provides[type_name] = all_provides[type_name] or {}

        table.insert(all_provides[type_name], {
          type_name = type_name,
          stop = umbrella.train_stop.unit_number,
          count = count,
        })
        ::continue::
      end

      umbrella.provides = provides
    end

    ::continue::
  end

  for type_name, requests_list in pairs(all_requests) do
    MTL_Log(LEVEL.DEBUG, "type_name: " .. type_name .. "  requests_list: " .. dump(requests_list))
    for _, value in pairs(requests_list) do
      local it = string.gmatch(type_name, "([%w_-]+)") 
      local type = it()
      local name = it()
      MTL_Log(LEVEL.DEBUG, "type: " .. type .. "  name: " .. name)
    end
  end
end

function IsGreaterEqualThanThreshold(item_name, threshold, stack_threshold, count)

end

function DeconstructConstantCombinator(train_stop_unit_number)
  if not storage.MTL.stops[train_stop_unit_number].cc then
    return true
  end

  local cc_id = storage.MTL.stops[train_stop_unit_number].cc.unit_number

  if not storage.MTL.stops[train_stop_unit_number].cc.destroy() then
    MTL_Log(LEVEL.ERROR, "failed to destroy constant combinator")
    return false
  end

  storage.MTL.reverse_lookup[cc_id] = nil
  storage.MTL.stops[train_stop_unit_number].cc = nil
  return true
end

function DeconstructLamp(train_stop_unit_number)
  if not storage.MTL.stops[train_stop_unit_number].lamp then
    return true
  end

  local lamp_id = storage.MTL.stops[train_stop_unit_number].lamp.unit_number

  if not storage.MTL.stops[train_stop_unit_number].lamp.destroy() then
    MTL_Log(LEVEL.ERROR, "failed to destroy lamp")
    return false
  end

  storage.MTL.reverse_lookup[lamp_id] = nil
  storage.MTL.stops[train_stop_unit_number].lamp = nil
  return true
end

function CreateAdditionalStopEntities(umbrella)
  CreateLamp(umbrella)
  CreateConstantCombinator(umbrella)
  CheckConstantCombinatorConfig(umbrella)
  ConnectConstantCombinatorAndLampCircuit(umbrella)
end

function CreateLamp(umbrella)
  if umbrella.lamp then
    MTL_Log(LEVEL.TRACE, "lamp was already created for \"" .. umbrella.train_stop.backer_name .. "\"")
    return
  end

  local lamp = umbrella.train_stop.surface.create_entity({
    name = ENTITY_TRAIN_STOP_LAMP_NAME,
    snap_to_grid = true,
    direction = umbrella.train_stop.direction,
    position = { umbrella.train_stop.position.x - 2, umbrella.train_stop.position.y - 1 },
    force = umbrella.train_stop.force
  })
  lamp.get_or_create_control_behavior().use_colors = true
  lamp.always_on = true

  storage.MTL.reverse_lookup[lamp.unit_number] = umbrella.train_stop.unit_number
  umbrella.lamp = lamp

  MTL_Log(LEVEL.TRACE, "created lamp for \"" .. umbrella.train_stop.backer_name .. "\"")
end

function CreateConstantCombinator(umbrella)
  if umbrella.cc then
    MTL_Log(LEVEL.TRACE, "constant combinator was already created for \"" .. umbrella.train_stop.backer_name .. "\"")
    return
  end
  local cc = umbrella.train_stop.surface.create_entity({
    name = ENTITY_TRAIN_STOP_CC_NAME,
    snap_to_grid = true,
    direction = umbrella.train_stop.direction,
    position = { umbrella.train_stop.position.x - 2, umbrella.train_stop.position.y },
    force = umbrella.train_stop.force
  })

  storage.MTL.reverse_lookup[cc.unit_number] = umbrella.train_stop.unit_number
  umbrella.cc = cc
  MTL_Log(LEVEL.TRACE, "created constant combinator for stop \"" .. umbrella.train_stop.backer_name .. "\"")
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
