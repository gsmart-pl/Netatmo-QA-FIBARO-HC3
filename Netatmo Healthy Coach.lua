-- HC3 QuickApp for Netatmo Smart Indoor Air Quality Monitor v1.1
-- (c) 2020 GSmart Grzegorz Barcicki
-- For questions and debug: grzegorz@gsmart.pl

function QuickApp:onInit()
--    self:debug("QuickApp: onInit")

    self.username       = self:getVariable("username")
    self.password       = self:getVariable("password")
    self.client_id      = self:getVariable("client_id")
    self.client_secret  = self:getVariable("client_secret")
    self.refresh        = 300   -- refresh time in seconds

    -- Setup classes for child devices.
    self:initChildDevices({
        ["com.fibaro.temperatureSensor"] = MyNetatmoSensor,
        ["com.fibaro.humiditySensor"] = MyNetatmoSensor,
        ["com.fibaro.multilevelSensor"] = MyNetatmoSensor,        
    })

    -- Supported Netatmo datatypes mapped to HC3 device type
    self.NetatmoTypesToHC3 = {
        Temperature = {
            type = "com.fibaro.temperatureSensor",
        },
        Humidity = {
            type = "com.fibaro.humiditySensor",
        },
        CO2 = {
            type = "com.fibaro.multilevelSensor",
            unit = "ppm"
        },
        Pressure = {
            type = "com.fibaro.multilevelSensor",
            unit = "mb"
        },
        Noise = {
            type = "com.fibaro.multilevelSensor",
            unit = "dB"
        },
        health_idx = {
            type = "com.fibaro.multilevelSensor",
            unit = ""
        },
    }

    -- Icons assigned for device with health index
    self.health_idx_icons = {
        [0] = 1040,   -- Healthy
        [1] = 1041,   -- Fine
        [2] = 1039,   -- Fair
        [3] = 1042,   -- Poor
        [4] = 1043    -- unhealthy
    }

    -- Main loop
    self:loop(self.refresh)
end

function QuickApp:loop(refresh)
    self.devicesMap = self:buildDevicesMap()

    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token)
    end)
 
    fibaro.setTimeout(refresh * 1000, function() 
        self:loop(refresh)
    end)
end 

function QuickApp:buildDevicesMap()
    local DM = {}
    for hcID,child in pairs(self.childDevices) do
        local module_id = child:getVariable("module_id")
        local device_id = child:getVariable("device_id")
        local data_type = child:getVariable("data_type")

        if (type(DM[module_id]) ~= "table") then
            DM[module_id] = {
                module_id = module_id,
                device_id = device_id,
                devices_map = {}
            }
        end

        DM[module_id].devices_map[data_type] = hcID
    end

    -- self:debug("DevicesMap built from childs: "..json.encode(DM))
    return(DM)
end

-- Getting Data based on one request: "getstationsdata"
function QuickApp:getNetatmoDevicesData(token, mode)
    local request_body = "access_token=".. token

    self:getNetatmoResponseData("https://api.netatmo.net/api/gethomecoachsdata", request_body, 
        function(getData) 
            -- self:debug("Getting stations data")

            if (getData.error) then
                self:error("Response error: " .. getData.error.message)
            elseif (getData.status == "ok" and getData.body) then
                local Devices = {}

                for _, device in pairs(getData.body.devices) do
                    local StationName = device.station_name
                    local last_status_store = os.date ("%d.%m.%Y %H:%M:%S", device.last_status_store)
                    local noOfModules = 1

                    self:trace("Found device: "..device._id.."; station_name: "..device.station_name.."; type: "..device.type)

                    self:UpdateHCDevice(mode, {
                        id = device._id,
                        device_id = device._id,
                        name = device.station_name,
                        station_name = device.station_name,
                        reachable = device.reachable,
                        last_status_store = last_status_store,
                    }, device.dashboard_data or {})

                    Devices[StationName] = {
                        place = device.place.city..", "..device.place.country,
                        modules = noOfModules,
                        last_status_store = last_status_store
                    }
                end

                local label, status = "", ""
                for station_name, data in pairs(Devices) do
                    label = label..station_name.." ("..data.place.."): "..data.modules.."; "
                    status = status..station_name..": "..data.last_status_store.."; "
                end

                if (label ~= "") then
                    label = "Found devices: "..label
                else
                    label = "No devices found."
                end

                if (status ~= "") then
                    status = "Devices last seen: "..status
                else
                    status = "-"
                end

                self:updateView("label", "text", label)
                self:updateView("status", "text", status)
            else
                self:error("Unknown error")
            end
        end 
    )
end

function QuickApp:CreateChilds(module, dashboard_data)
    for data_type, value in pairs(dashboard_data) do
        if (type(self.devicesMap[module.id]) == "table" and self.devicesMap[module.id].devices_map[data_type] and
            self.childDevices[self.devicesMap[module.id].devices_map[data_type]]) then
            local hcID = self.devicesMap[module.id].devices_map[data_type]
            child = self.childDevices[hcID]
            self:trace("HC3 child device for '"..data_type.."' module EXISTS. Name: '"..child.name.."', id: '"..child.id.."', type: '"..child.type.."'")
        else
            local sensor_type = ""
            local sensor_unit = ""

            if (self.NetatmoTypesToHC3[data_type]) then
                sensor_type = self.NetatmoTypesToHC3[data_type].type
                if (self.NetatmoTypesToHC3[data_type].unit) then
                    sensor_unit = self.NetatmoTypesToHC3[data_type].unit
                end
            end

            if (sensor_type ~= "") then
                local name = data_type.." "..module.name
                local child = self:createChildDevice({
                    name = name,
                    type = sensor_type
                }, MyNetatmoSensor)

                if (child) then
                    if (sensor_unit ~= "") then
                        child:updateProperty("unit", sensor_unit)
                    end

                    child:setVariable("module_id", module.id)
                    child:setVariable("device_id", module.device_id)
                    child:setVariable("data_type", data_type)

                    value = self:valueConversion(value, data_type)
                    child:setValue(value)
                    self:trace("HC3 child device for '"..data_type.."' module created. Name: '"..name.."', id: '"..child.id.."', type: '"..child.type.."'")
                end
            else
                -- self:warning("Unsupported Netatmo sensor type: "..data_type)
            end
        end
    end
end

function QuickApp:parseDashboardData(module, dashboard_data)
    for data_type, value in pairs(dashboard_data) do
        if (type(self.devicesMap[module.id]) == "table" and self.devicesMap[module.id].devices_map[data_type]) then
            local hcID = self.devicesMap[module.id].devices_map[data_type]
            
            if (self.childDevices[hcID]) then
                child = self.childDevices[hcID]
                value = self:valueConversion(value, data_type)
                child:setValue(value)

                if (data_type == "health_idx") then
                    local icon = self.health_idx_icons[value]
                    self:debug("Setting icon for health_idx: "..value.." -> "..icon)
                    child:setIcon(icon)
                end

                self:debug("SetValue '"..data_type.."' from module '"..module.station_name.."'/'"..module.name.."' on hcID: "..hcID.."; value: "..value)
            else
                self:error("Child "..hcID.." not exists!")
            end
        else
            -- self:debug("Nothing to do with '"..data_type.."' from module '"..module.station_name.."'/'"..module.name.."'")
        end
    end
end

function QuickApp:UpdateHCDevice(mode, device_info, dashboard_data)
    if (device_info.reachable == true) then
        if (mode == "create") then
            self:CreateChilds(device_info, dashboard_data or {})
        else
            self:parseDashboardData(device_info, dashboard_data or {})
        end
    else
        self:warning("Module '"..device_info.name.."' isn't connected! Status was last updated on: "..device_info.last_status_store)
    end
end

function QuickApp:oAuthNetatmo(func)
    if (self.username == "" or self.password == "" or self.client_id == "" or self.client_secret == "" or
        self.username == "-" or self.password == "-" or self.client_id == "-" or self.client_secret == "-") then
        self:error ("Credentials data is empty!")
        self:updateView("status", "text", "Credentials data is empty!")
        return 0
    end

    local request_body = "grant_type=password&client_id="..self.client_id.."&client_secret="..self.client_secret.."&username="..self.username.."&password="..self.password.."&scope=read_homecoach"

    self:getNetatmoResponseData("https://api.netatmo.net/oauth2/token", request_body, 
        function(data) 
            if (data.access_token ~= nil) then
                self:debug("netatmo-oAuth ok, token: "..data.access_token)
                func(data.access_token)
            else
                self:error("Can't get token")
            end
        end
    )
end

function QuickApp:getNetatmoResponseData(url, body, func)
    -- self:debug("HTTP url: "..url.."; body: "..body)
    local http = net.HTTPClient()
    http:request(url, { 
        options = { 
            method = "POST", 
            headers = {
                ['Content-Type'] = "application/x-www-form-urlencoded;charset=UTF-8"
            },
            data = body
        },
        success = function(response)
            if (response.status == 200) then
                -- self:debug("Response: "..json.encode(response))
                func(json.decode(response.data))
            else
                -- self:debug("Response: "..json.encode(response))
                self:error("Wrong status '"..response.status.."' in response!")
            end
        end,
        error = function(message)
            self:error("Connection error: " .. message)
        end
    })   
end


-- Actions for buttons
function QuickApp:GetDevices()
    self.devicesMap = self:buildDevicesMap()
    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token, "create")
    end)
end

function QuickApp:GetMeasurements()
    self.devicesMap = self:buildDevicesMap()
    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token)
    end)
end


-- Classes
class 'MyNetatmoSensor' (QuickAppChild)

function MyNetatmoSensor:__init(device)
    QuickAppChild.__init(self, device) 
end

function MyNetatmoSensor:setValue(value)
    -- self:debug("child "..self.id.." updated value: "..value)
    self:updateProperty("value", tonumber(value))
end

function MyNetatmoSensor:setIcon(icon)
    -- self:debug("child "..self.id.." updated value: "..value)
    self:updateProperty("deviceIcon", icon)
end

function MyNetatmoSensor:getProperty(name) -- get value of property 'name'
    local value = fibaro.getValue(self.id, name)
    -- self:debug("child "..self.id.." unit value: "..unit)
    return value
end


-- Tools
function QuickApp:valueConversion(value, data_type)
    if (data_type and self.NetatmoTypesToHC3[data_type] and self.NetatmoTypesToHC3[data_type].conversion) then
        conv_func = self.NetatmoTypesToHC3[data_type].conversion

        value = conv_func(value)
    end

    return tonumber(value)
end
