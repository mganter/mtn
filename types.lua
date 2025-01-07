do
    ---@class (exact) MaTrainNetwork.TrainStop.Umbrella
    ---@field id uint -- unit_number of train stop
    ---@field train_stop LuaEntity Train stop where trains can arrive
    ---@field cc LuaEntity Constant Combinator to control the status [lamp] and config of the train stop
    ---@field lamp LuaEntity Lamp to indicate status to player
    ---@field role? MaTrainNetwork.TrainStop.Roles
    ---@field assigned_train? LuaTrain Exists if role is depot and has a assigned train
    ---@field provider_config? MaTrainNetwork.TrainStop.ProviderConfig Exists if role is `Roles.PROVIDER`
    ---@field requester_config? MaTrainNetwork.TrainStop.RequesterConfig Exists if role is `Roles.REQUESTER`
    ---@field incoming_trains? {[uint]:MaTrainNetwork.Train.Order} Train.id to Order mapping
    local TrainStopUmbrella = {
    }

    ---@class (exact) MaTrainNetwork.TrainStop.ProviderConfig
    ---@field threshold int
    local ProviderConfig = {
    }
    
    ---@class (exact) MaTrainNetwork.TrainStop.RequesterConfig
    ---@field threshold int
    local RequesterConfig = {
    }
end

do
    ---@class (exact) MaTrainNetwork.Train.Order
    ---@field train LuaTrain
    ---@field requester uint -- unit_number of requested train
    ---@field provider uint -- unit_number of requested train
    ---@field depot uint -- unit_number of requested train
    ---@field resource MaTrainNetwork.ResourceTypeName 
    ---@field count uint -- amount of resource to be transported
    local Order = {
    }

    ---@class (exact) MaTrainNetwork.Train.AvailableTrains
    ---@field fluid MaTrainNetwork.Train.TrainInfo[]
    ---@field item MaTrainNetwork.Train.TrainInfo[]
    local AvailableTrains = {
    }

    ---@class (exact) MaTrainNetwork.Request
    ---@field type_name MaTrainNetwork.ResourceTypeName
    ---@field stop uint
    ---@field count uint
    local Request = {
    }

    ---@class (exact) MaTrainNetwork.Offer
    ---@field type_name MaTrainNetwork.ResourceTypeName
    ---@field stop uint
    ---@field count uint
    ---@field threshold_count uint
    local Offer = {
    }

    ---@class (exact) MaTrainNetwork.Train.TrainInfo
    ---@field train LuaTrain
    ---@field depot uint
    ---@field fluid_capacity uint 
    ---@field slot_capacity uint
    local TrainInfo = {
    }

    ---@class (exact) MaTrainNetwork.ResourceTypeName
    ---@field type CarriageType
    ---@field name string
    local ResourceTypeName = {
    } 
end

---@enum MaTrainNetwork.TrainStop.Roles 
Roles = {
    DEPOT = "role-depot",
    REQUESTER = "role-requester",
    PROVIDER = "role-provider",
}

---@enum CarriageType
CarriageType = {
    Item = "item",
    Fluid = "fluid"
}

---@enum MaTrainNetwork.TrainStop.Status
Status = {
    DEPOT_READY_TO_RECEIVE_TRAIN = { type = "virtual", name = "signal-cyan", quality = "normal" },
    DEPOT_WITH_READY_TRAIN = { type = "virtual", name = "signal-green", quality = "normal" },
    DEPOT_TRAIN_ERROR = { type = "virtual", name = "signal-red", quality = "normal" },
    
    REQUESTER_REQUESTING_RESOURCE = { type = "virtual", name = "signal-yellow", quality = "normal" },
    REQUESTER_WITH_INCOMING_TRAIN = { type = "virtual", name = "signal-green", quality = "normal" },
    
    RROVIDER_PROVIDING_RESOURECE = { type = "virtual", name = "signal-green", quality = "normal" },
    RROVIDER_WITH_INCOMING_TRAIN = { type = "virtual", name = "signal-yellow", quality = "normal" },
    
    TRAIN_STOP_ERROR = { type = "virtual", name = "signal-red", quality = "normal" },
    NEUTRAL = { type = "virtual", name = "signal-white", quality = "normal" },
}
