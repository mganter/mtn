require("util")

local entity_stop = table.deepcopy(data.raw["train-stop"]["train-stop"])
entity_stop.name = ENTITY_TRAIN_STOP_NAME
entity_stop.minable = { mining_time = 0.2, result = ITEM_TRAIN_STOP_NAME }

local entity_lamp = table.deepcopy(data.raw["lamp"]["small-lamp"])
entity_lamp.name = ENTITY_TRAIN_STOP_LAMP_NAME
entity_lamp.energy_source = {type = "void", render_no_power_icon = false, render_no_network_icon = false}

local entity_cc = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
entity_cc.name = ENTITY_TRAIN_STOP_CC_NAME

local item = table.deepcopy(data.raw["item"]["train-stop"])
item.name = ITEM_TRAIN_STOP_NAME
item.place_result = ENTITY_TRAIN_STOP_NAME

local recipe = {
  type = "recipe",
  name = RECIPE_TRAIN_STOP_NAME,
  category = "basic-crafting",
  subgroup = "train-transport",
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  enabled = false,
  energy_required = 1,
  ingredients = {
    { type = "item", name = "train-stop", amount = 1 }
  },
  results = {
    { type = "item", name = ITEM_TRAIN_STOP_NAME, amount = 1 }
  },
} 

local technology = {
  type = "technology",
  name = TECHNOLOGY_MTN_NAME,
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  prerequisites = { "automated-rail-transportation" },
  unit =
  {
    count = 200,
    ingredients = { { "automation-science-pack", 1 }, { "logistic-science-pack", 1 } },
    time = 30
  },
  effects =
  {
    {
      type = "unlock-recipe",
      recipe = RECIPE_TRAIN_STOP_NAME
    }
  },
}

local signal_depot = {
    type = "virtual-signal",
    name = SIGNAL_DEPOT,
    icon = "__base__/graphics/technology/steel-processing.png",
    icon_size = 256,
    subgroup = "mtn-signal",
}

local signal_provide_threshold = {
  type = "virtual-signal",
  name = SIGNAL_PROVIDE_THRESHOLD,
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  subgroup = "mtn-signal",
}

local signal_provide_stack_threshold = {
  type = "virtual-signal",
  name = SIGNAL_PROVIDE_STACK_THRESHOLD,
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  subgroup = "mtn-signal",
}

local signal_request_threshold = {
  type = "virtual-signal",
  name = SIGNAL_REQUEST_THRESHOLD,
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  subgroup = "mtn-signal",
}

local signal_request_stack_threshold = {
  type = "virtual-signal",
  name = SIGNAL_REQUEST_STACK_THRESHOLD,
  icon = "__base__/graphics/technology/steel-processing.png",
  icon_size = 256,
  subgroup = "mtn-signal",
}

local subgroup = {
  type = "item-subgroup",
  name = "mtn-signal",
  group = "signals",
}

data:extend({
  entity_stop,
  entity_lamp,
  entity_cc,
  item,
  recipe,
  technology,
  subgroup,
  signal_depot,
  signal_provide_threshold,
  signal_provide_stack_threshold,
  signal_request_threshold,
  signal_request_stack_threshold,
})
