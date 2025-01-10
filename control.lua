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

script.on_event(defines.events.on_surface_created, function (event) OnSurfaceCreated(event) end)
script.on_event(defines.events.on_surface_deleted, function (event) OnSurfaceDeleted(event) end)

function init()
  ---@type MaTrainNetwork.BaseObject
  storage.MTL = storage.MTL or {
    surfaces = {}
  }
  storage.MTL.current_surface_index = storage.MTL.current_surface_index or 0

  storage.MTL.existing_surfaces = {}
  for _, surface in pairs(game.surfaces) do
    table.insert(storage.MTL.existing_surfaces, surface)
  end

  ---@type {[uint]:uint}
  storage.MTL.reverse_lookup = storage.MTL.reverse_lookup or {}
  for _, surface in pairs(game.surfaces) do
    storage.MTL.surfaces[surface.index] = {
      stops = {},
      role_depot = {},
      role_provider = {},
      role_requester = {},
      train_orders = {},
    }
  end
end

---@param event EventData.on_built_entity | EventData.on_robot_built_entity | EventData.on_cancelled_deconstruction
function RegisterStop(event)
  -- is not a train stop
  if event == nil or event.entity == nil or event.entity.name ~= ENTITY_TRAIN_STOP_NAME then
    return
  end

  local surface = event.entity.surface

  local train_stop = event.entity
  if not storage.MTL.surfaces[surface.index].stops[event.entity] then
    local lamp = CreateLamp(train_stop)
    if not lamp then
      train_stop.destroy()
      MTN_Log(LEVEL.ERROR, "could not create lamp for train stop " .. train_stop.backer_name)
      return
    end

    local cc = CreateConstantCombinator(train_stop)
    if not cc then
      lamp.destroy()
      train_stop.destroy()
      MTN_Log(LEVEL.ERROR, "could not create lamp for train stop " .. train_stop.backer_name)
      return
    end

    ---@type MaTrainNetwork.TrainStop.Umbrella
    local umbrella = {
      id = event.entity.unit_number,
      train_stop = event.entity,
      lamp = lamp,
      cc = cc,
    }

    ConnectConstantCombinatorAndLampCircuit(umbrella)

    storage.MTL.reverse_lookup[lamp.unit_number] = umbrella.train_stop.unit_number
    storage.MTL.reverse_lookup[cc.unit_number] = umbrella.train_stop.unit_number
    storage.MTL.surfaces[surface.index].stops[train_stop.unit_number] = umbrella
    script.register_on_object_destroyed(train_stop) -- so that we can react on destruction of the train stop
  end

  if not ReadConfig(storage.MTL.surfaces[surface.index].stops[train_stop.unit_number]) then
    SetStatus(storage.MTL.surfaces[surface.index].stops[train_stop.unit_number], Status.TRAIN_STOP_ERROR)
    return
  end
end

function UpdateConstantCombinatorConfig(event)
  if event == nil or event.entity == nil or event.entity.name ~= ENTITY_TRAIN_STOP_CC_NAME or not event.player_index then
    return
  end

  local surface = event.entity.surface
  local train_stop_number = storage.MTL.reverse_lookup[event.entity.unit_number]
  local umbrella = storage.MTL.surfaces[surface.index].stops[train_stop_number]
  MTN_Log(LEVEL.DEBUG, "got constant combinator update for " .. umbrella.train_stop.backer_name)

  CheckConstantCombinatorConfig(umbrella.cc)
  if not ReadConfig(umbrella) then
    SetStatus(umbrella, Status.TRAIN_STOP_ERROR)
    -- todo deregister
    return
  end

  SetStatus(umbrella, Status.NEUTRAL)
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
---@return boolean -- successful or not
function DeregisterStop(umbrella)
  local surface = umbrella.lamp.surface
  if umbrella.role then
    storage.MTL.surfaces[surface.index][umbrella.role][umbrella.id] = nil
    umbrella.role = nil
  end
  return true
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
    MTN_Log(LEVEL.ERROR, "train stop \"" .. umbrella.train_stop.backer_name .. "\" has multiple roles " .. dump(role))
    DeregisterStop(umbrella)
    return false
  end

  if #role == 0 then
    MTN_Log(LEVEL.DEBUG, "no role found for stop " .. umbrella.train_stop.backer_name)
    DeregisterStop(umbrella)
    return false
  end

  MTN_Log(LEVEL.INFO, "train stop \"" .. umbrella.train_stop.backer_name .. "\" assumed role " .. dump(role))
  -- remove stop from role list
  if role[1] ~= umbrella.role and umbrella.role then
    storage.MTL[umbrella.role][umbrella.train_stop.unit_number] = nil
  end
  umbrella.role = role[1]
  umbrella.provider_config = provider_config
  umbrella.requester_config = requester_config
  umbrella.incoming_trains = {}

  local surface = umbrella.train_stop.surface
  storage.MTL.surfaces[surface.index][umbrella.role] = storage.MTL[umbrella.role] or {}
  storage.MTL.surfaces[surface.index][umbrella.role][umbrella.train_stop.unit_number] = true

  return true
end

---@param event EventData.on_object_destroyed|EventData.on_marked_for_deconstruction
function DeconstructStop(event)
  MTN_Log(LEVEL.ERROR, "starting stop deconstruction of "..event.useful_id)

  if event.name ~= defines.events.on_object_destroyed then
    MTN_Log(LEVEL.ERROR, "invalid event called function DeconstructStop(event)")
    return
  end


  ---@type MaTrainNetwork.TrainStop.Umbrella?
  local umbrella = nil
  for index, surface in pairs(storage.MTL.surfaces) do
    if surface.stops[event.useful_id] then
      umbrella = surface.stops[event.useful_id]
      break
    end
  end

  if umbrella == nil then
    MTN_Log(LEVEL.ERROR, "could not find train stop for deconstruction request")
    return
  end

  local surface = umbrella.cc.surface
  
  MTN_Log(LEVEL.ERROR, tostring(event.useful_id) .. type(umbrella))
  if not umbrella or not DeregisterStop(umbrella) then
    MTN_Log(LEVEL.ERROR, "could not deregister stop")
  end
  if not umbrella or not DeconstructConstantCombinator(umbrella) then
    MTN_Log(LEVEL.ERROR, "could not destroy constant combinator")
  end
  if not umbrella or not DeconstructLamp(umbrella) then
    MTN_Log(LEVEL.ERROR, "could not destory lamp")
  end

  storage.MTL.surfaces[surface.index].stops[event.useful_id] = nil
end

---@param surface LuaSurface
---@return MaTrainNetwork.Train.AvailableTrains
function GetAvaiableTrains(surface)
  ---@type MaTrainNetwork.Train.AvailableTrains
  local available_trains = {
    fluid = {},
    item = {},
  }

  for stop_id, _ in pairs(storage.MTL.surfaces[surface.index][Roles.DEPOT]) do
    local umbrella = storage.MTL.surfaces[surface.index].stops[stop_id]
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
        MTN_Log(LEVEL.INFO, "train in stop \"" .. umbrella.train_stop.backer_name .. "\" has too few carriages")
        goto continue
      end

      if train.carriages[2].prototype.type ~= "cargo-wagon" and train.carriages[2].prototype.type ~= "fluid-wagon" then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTN_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" has to have cargo wagon or fluid wagon on 2nd place")
        goto continue
      end

      carriage_type = (train.carriages[2].prototype.type == "fluid-wagon" and "fluid") or "item"

      if carriage_type == "item" and #train.carriages[2].get_output_inventory().get_contents() ~= 0 then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTN_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not empty and therefor not listed as available train")
        goto continue
      end

      if carriage_type == "fluid" and not train.carriages[2].get_fluid_contents() then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTN_Log(LEVEL.INFO,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not empty and therefor not listed as available train")
        goto continue
      end

      if not umbrella.assigned_train then
        umbrella.assigned_train = train
      end

      if umbrella.assigned_train.id ~= train.id then
        SetStatus(umbrella, Status.DEPOT_TRAIN_ERROR)
        MTN_Log(LEVEL.ERROR,
          "train in stop \"" .. umbrella.train_stop.backer_name ..
          "\" is not the train assigned to this depot")
        goto continue
      end

      local fluid_capacity = (carriage_type == "fluid" and train.carriages[2].prototype.fluid_capacity) or 0
      local slot_capacity = (carriage_type == "item" and train.carriages[2].get_output_inventory().get_bar() - 1) or 0

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

---@param surface LuaSurface
---@return { [string]: MaTrainNetwork.Request[] }
function GetReqests(surface)
  ---@type {[string]:MaTrainNetwork.Request[]}
  local all_requests = {}
  storage.MTL.surfaces[surface.index][Roles.REQUESTER] = storage.MTL.surfaces[surface.index][Roles.REQUESTER] or {}

  for stop_id, _ in pairs(storage.MTL.surfaces[surface.index][Roles.REQUESTER]) do
    local umbrella = storage.MTL.surfaces[surface.index].stops[stop_id]

    if not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    local signals = umbrella.lamp.get_signals(defines.wire_connector_id.circuit_red)
    if not signals then
      MTN_Log(LEVEL.TRACE, "no signals found for " .. umbrella.train_stop.backer_name)
      goto continue
    end

    ---@type {[string]:uint} -- type_name to count map
    local requests = {}
    for _, value in ipairs(signals) do
      -- not value.signal.type is equivalent to "item" as of api docs
      if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
        if value.count < 0 then
          local type = value.signal.type or "item"
          local name = value.signal.name
          requests[type .. "/" .. name] = value.count
        end
      end
    end

    umbrella.incoming_trains = umbrella.incoming_trains or {}
    for _, order in pairs(umbrella.incoming_trains) do
      requests[to_slash_notation(order.resource)]
      = requests[to_slash_notation(order.resource)] + order.count
    end

    for type_name, count in pairs(requests) do
      if -umbrella.requester_config.threshold < count then
        requests[type_name] = nil
        goto continue
      end

      all_requests[type_name] = all_requests[type_name] or {}

      ---@type MaTrainNetwork.Request
      local request = {
        type_name = from_slash_notation(type_name),
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

---@param surface LuaSurface
---@return { [string]: MaTrainNetwork.Offer[] }
function GetOffers(surface)
  ---@type {[string]:MaTrainNetwork.Offer[]}
  local all_offers = {}
  storage.MTL[Roles.PROVIDER] = storage.MTL[Roles.PROVIDER] or {}
  for stop_id, _ in pairs(storage.MTL[Roles.PROVIDER]) do
    local umbrella = storage.MTL.surfaces[surface.index].stops[stop_id]
    if not umbrella.lamp or not umbrella.cc then
      goto continue
    end

    local signals = umbrella.lamp.get_signals(defines.wire_connector_id.circuit_red)
    if not signals then
      MTN_Log(LEVEL.TRACE, "no signals found for " .. umbrella.train_stop.backer_name)
      goto continue
    end

    ---@type {[string]:integer}
    local offers = {}
    for _, value in ipairs(signals) do
      -- not value.signal.type is equivalent to "item" as of api docs
      if not value.signal.type or value.signal.type == "item" or value.signal.type == "fluid" then
        if umbrella.provider_config.threshold <= value.count then
          local type = value.signal.type or "item"
          local type_name = type .. "/" .. value.signal.name
          offers[type_name] = value.count
        end
      end
    end

    for train_id, order in pairs(umbrella.incoming_trains) do
      offers[order.resource.type .. "/" .. order.resource.name] =
          (offers[order.resource.type .. "/" .. order.resource.name] or 0) - order.count
    end

    MTN_Log(LEVEL.DEBUG, dump(offers))

    for type_name, count in pairs(offers) do
      if umbrella.provider_config.threshold > count then
        offers[type_name] = nil
        goto continue
      end

      all_offers[type_name] = all_offers[type_name] or {}

      ---@type MaTrainNetwork.Offer
      local offer = {
        type_name = from_slash_notation(type_name),
        stop = umbrella.train_stop.unit_number,
        count = count,
        threshold_count = umbrella.provider_config.threshold,
      }
      table.insert(all_offers[type_name], offer)
      ::continue::
    end

    ::continue::
  end

  return all_offers
end

function Tick()
  local surface = GetNextSurface()

  local available_trains = GetAvaiableTrains(surface)
  local all_requests = GetReqests(surface)
  local all_offers = GetOffers(surface)
  MTN_Log(LEVEL.DEBUG, "============")
  MTN_Log(LEVEL.DEBUG,
    "#available_trains: item: " .. #available_trains["item"] .. "  fluid: " .. #available_trains["fluid"]
  )
  MTN_Log(LEVEL.DEBUG, "all_requests: " .. dump(all_requests))
  MTN_Log(LEVEL.DEBUG, "all_offers: " .. dump(all_offers))
  MTN_Log(LEVEL.DEBUG, "current orders: " .. dump(storage.MTL.surfaces[surface.index].train_orders))

  for type_name, requests_list in pairs(all_requests) do
    for _, request in pairs(requests_list) do
      if not all_offers[type_name] then
        goto continue
      end
      for _, offer in pairs(all_offers[type_name]) do
        if offer.count < offer.threshold_count then
          goto continue
        end

        local sent_amount = (request.count > offer.count and offer.count) or request.count
        local carriage_type = from_slash_notation(type_name).type

        MTN_Log(LEVEL.DEBUG, "type is " .. carriage_type)
        if #available_trains[carriage_type] == 0 then
          MTN_Log(LEVEL.DEBUG, "no available train for " .. carriage_type .. " found")
          goto continue
        end
        ---@type MaTrainNetwork.Train.TrainInfo
        local train_info = available_trains[carriage_type][#available_trains[carriage_type]]
        table.remove(available_trains[carriage_type])

        offer.count = offer.count - sent_amount

        MTN_Log(LEVEL.DEBUG, "train info" .. dump(train_info))
        MTN_Log(LEVEL.DEBUG, dump(type_name))
        storage.MTL.surfaces[surface.index].stops[request.stop].incoming_trains = storage.MTL.surfaces[surface.index].stops[request.stop].incoming_trains or {}
        ---@type MaTrainNetwork.Train.Order
        train_order = {
          train = train_info.train,
          resource = from_slash_notation(type_name),
          count = sent_amount,
          depot = train_info.depot,
          provider = offer.stop,
          requester = request.stop,
        }
        storage.MTL.surfaces[surface.index].stops[request.stop].incoming_trains[train_order.train.id] = train_order
        storage.MTL.surfaces[surface.index].stops[offer.stop].incoming_trains[train_order.train.id] = train_order
        storage.MTL.surfaces[surface.index].train_orders[train_info.train.id] = train_order

        CreateTrainSchedule(surface, train_order)

        ::continue::
      end
      ::continue::
    end
  end
  ::jump_return::
end

---@param umbrella MaTrainNetwork.TrainStop.Umbrella
function DeconstructConstantCombinator(umbrella)
  if not umbrella.cc then
    return true
  end

  local cc_id = umbrella.cc.unit_number

  if not umbrella.cc.destroy() then
    MTN_Log(LEVEL.ERROR, "failed to destroy constant combinator")
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
    MTN_Log(LEVEL.ERROR, "failed to destroy lamp")
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
    MTN_Log(LEVEL.ERROR, "Could not create lamp for stop: " .. train_stop.backer_name)
    return nil
  end
  ---@diagnostic disable-next-line: inject-field
  lamp.get_or_create_control_behavior().use_colors = true
  lamp.always_on = true

  -- disable interaction with lamp
  lamp.destructible = false
  lamp.minable_flag  = false
  lamp.operable = false

  MTN_Log(LEVEL.TRACE, "created lamp for \"" .. train_stop.backer_name .. "\"")
  return lamp
end

---comment
---@param train_stop LuaEntity
---@return LuaEntity? -- constant combinator created
function CreateConstantCombinator(train_stop)
  local cc = train_stop.surface.create_entity({
    name = ENTITY_TRAIN_STOP_CC_NAME,
    snap_to_grid = true,
    direction = train_stop.direction,
    position = { train_stop.position.x - 2, train_stop.position.y },
    force = train_stop.force
  })
  if not cc then
    MTN_Log(LEVEL.ERROR, "Could not create constant combinator for stop: " .. train_stop.backer_name)
    return nil
  end

  cc.destructible = false
  cc.minable_flag  = false
  cc.operable = true

  CheckConstantCombinatorConfig(cc)

  MTN_Log(LEVEL.TRACE, "created constant combinator for stop \"" .. train_stop.backer_name .. "\"")
  return cc
end

---@param cc LuaEntity constant combinator
function CheckConstantCombinatorConfig(cc)
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

  MTN_Log(LEVEL.TRACE,
    "created circuit connection betweend constant combinator and lamp for \"" .. umbrella.train_stop.backer_name .. "\"")
end

---@param event EventData.on_train_changed_state
function OnTrainStateChanged(event)
  ---@type LuaSurface
  local surface = event.train.get_rails()[1].surface
  local order = storage.MTL.surfaces[surface.index].train_orders[event.train.id]
  if not order then
    return
  end


  if event.old_state == defines.train_state.arrive_station and event.train.state == defines.train_state.wait_station then
    OnTrainArrival(event, surface, order)
  end

  if event.old_state == defines.train_state.wait_station then
    OnTrainDeparturevent(event, surface, order)
  end
end

---@param event EventData.on_train_changed_state
---@param surface LuaSurface
---@param order MaTrainNetwork.Train.Order
function OnTrainDeparturevent(event, surface, order)
  if not order.current_stop then
    return
  end

  local departed_stop = storage.MTL.surfaces[surface.index].stops[order.current_stop]
  if departed_stop.role == Roles.PROVIDER or departed_stop.role == Roles.REQUESTER then
    departed_stop.incoming_trains[event.train.id] = nil
  end
end

---@param event EventData.on_train_changed_state
---@param surface LuaSurface
---@param order MaTrainNetwork.Train.Order
function OnTrainArrival(event, surface, order)
  MTN_Log(LEVEL.DEBUG, "Train " .. event.train.id .. " arrived at " .. event.train.station.backer_name)

  ---@type MaTrainNetwork.TrainStop.Umbrella
  local umbrella = storage.MTL.surfaces[surface.index].stops[event.train.station.unit_number]
  if umbrella.id == order.depot or umbrella.id == order.provider or umbrella.id == order.requester then
    order.current_stop = umbrella.id
  end

  if umbrella.role == Roles.DEPOT then
    MTN_Log(LEVEL.INFO, "Train " .. event.train.id .. " successfuly carried out order " .. dump(order))
    SendTrainToDepot(train_order.train, umbrella)
    storage.MTL.surfaces[surface.index].train_orders[train_order.train.id] = nil
  end
end

---@param order MaTrainNetwork.Train.Order
function CreateTrainSchedule(surface, order)
  order.train.schedule = {
    current = 1,
    records = {
      {
        station = storage.MTL.surfaces[surface.index].stops[order.provider].train_stop.backer_name,
        wait_conditions = {
          {
            compare_type = "or",
            type = (order.resource.type == "item" and "item_count") or "fluid_count",
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
        station = storage.MTL.surfaces[surface.index].stops[order.requester].train_stop.backer_name,
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
        station = storage.MTL.surfaces[surface.index].stops[order.depot].train_stop.backer_name,
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

---@param train LuaTrain
---@param depot MaTrainNetwork.TrainStop.Umbrella
function SendTrainToDepot(train, depot)
  train.schedule = {
    current = 1,
    records = {
      {
        station = depot.train_stop.backer_name,
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

---@return LuaSurface
function GetNextSurface()
  storage.MTL.current_surface_index = (storage.MTL.current_surface_index % (#storage.MTL.existing_surfaces)) + 1
  return game.surfaces[storage.MTL.current_surface_index]
end

---@param event EventData.on_surface_created
function OnSurfaceCreated(event)
  local surface = game.get_surface(event.surface_index)
  if not surface then
    MTN_Log(LEVEL.ERROR, "failed to process event on_surface_created")
    return
  end

  table.insert(storage.MTL.existing_surfaces, surface)
end

---@param event EventData.on_surface_deleted
function OnSurfaceDeleted(event)
  local surface = game.get_surface(event.surface_index)
  if not surface then
    MTN_Log(LEVEL.ERROR, "failed to process event on_surface_deleted")
    return
  end

  for list_index, ex_surface in ipairs(storage.MTL.existing_surfaces) do
    if ex_surface.index == surface.index then
      table.remove(storage.MTN.existing_surfaces, list_index)
      return
    end
  end
end