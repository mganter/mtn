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
item.icon = "__MaTrainNetwork__/graphics/train-stop-requester.png"

local recipe = table.deepcopy(data.raw["recipe"]["train-stop"])
recipe.name = RECIPE_TRAIN_STOP_NAME
recipe.icon = "__MaTrainNetwork__/graphics/train-stop-requester.png"
recipe.icon_size = 64
recipe.enabled = false
recipe.energy_required = 1
recipe.ingredients = {{ type = "item", name = "train-stop", amount = 1 }}
recipe.results = {{ type = "item", name = ITEM_TRAIN_STOP_NAME, amount = 1 }}

local technology = {
  type = "technology",
  name = TECHNOLOGY_MTN_NAME,
  icon = "__MaTrainNetwork__/graphics/train-stop-requester.png",
  icon_size = 64,
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
    icon = "__MaTrainNetwork__/graphics/train-stop-depot.png",
    icon_size = 64,
    subgroup = "mtn-signal",
}

local signal_provide_threshold = {
  type = "virtual-signal",
  name = SIGNAL_PROVIDE_THRESHOLD,
  icon = "__MaTrainNetwork__/graphics/train-stop-provider-signal.png",
  icon_size = 64,
  subgroup = "mtn-signal",
}

local signal_provide_stack_threshold = {
  type = "virtual-signal",
  name = SIGNAL_PROVIDE_STACK_THRESHOLD,
  icon = "__MaTrainNetwork__/graphics/train-stop-provider-stack-signal.png",
  icon_size = 64,
  subgroup = "mtn-signal",
}

local signal_request_threshold = {
  type = "virtual-signal",
  name = SIGNAL_REQUEST_THRESHOLD,
  icon = "__MaTrainNetwork__/graphics/train-stop-requester-signal.png",
  icon_size = 64,
  subgroup = "mtn-signal",
}

local signal_request_stack_threshold = {
  type = "virtual-signal",
  name = SIGNAL_REQUEST_STACK_THRESHOLD,
  icon = "__MaTrainNetwork__/graphics/train-stop-requester-stack-signal.png",
  icon_size = 64,
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
