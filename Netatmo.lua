-- Netatmo Weather Station QuickApp
-- (c) 2020-2022 GSmart Grzegorz Barcicki
-- For questions and debug, email me: grzegorz@gsmart.pl
-- To generate access tokens please visit my site: https://gsmart.pl/netatmo/
--
-- Changelog:
--  v2.6 - 09/2022 (GSmart)
--    - changed authorization method with Netatmo API (required by Netatmo servers)
--  v2.5.1 - 03/2021 (GSmart+Lazer)
--    - FIX QuickApp hang after HC3's upgrade to 5.063 (http:request closed in pcall)
--    - Added Czech translation (thanks to petrkl12)
--    - Minor fixes & enhancements
--  v2.5 - 07/2020 (Lazer)
--    - Fix QuickApp crash in case weather station has no additional module
--  v2.4 - 07/2020 (Lazer)
--    - Add variable to choose between battery interface on dedicated child devices or directly on child devices
--  v2.3 - 06/2020 (Lazer)
--    - New device types (Rain, Wind, Gust)
--    - Add battery levels monitoring (use dedicated child devices)
--    - Add alive module monitoring (use Netatmo reachable property to make Fibaro devices appearing dead in the interface)
--    - Optimized 10 minutes query interval 10s after Netatmo cloud update
--    - Minor fixes & enhancements
--  v2.2 - 06/2020 (GSmart)
--    - FIX: prevent crash when we doesn't get any data from Netatmo API
--    - Added status info on main QA device
--  v2.1 - 05/2020 (GSmart)
--    - Added support for unit conversion, eg. km/h to m/s
--    - Further enhancements in code
--  v2.0 - 04/2020 (GSmart)
--    - Completely redesigned
--    - Getting all data in one request to Netatmo API
--  v1.1 - 04/2020 (GSmart)
--    - Added support for Wind and Rain modules
--  v1.0 - 04/2020 (GSmart)
--    - Initial release
--    - Supported devices: Base station, Outdoor module, Indoor module

local QA_NAME = "Netatmo Weather Station QuickApp v2.6"

function QuickApp:onInit()
    __TAG = "QA_NETATMO_" .. plugin.mainDeviceId
    self:trace(QA_NAME.." - Initialization")

    -- If you would like to view full response from Netatmo API change this value to true
    self.api_response_debug = true

    -- Get QuickApp variables
    self.access_token  = self:getVariable("access_token")
    self.refresh_token = self:getVariable("refresh_token")
    if string.lower(self:getVariable("battery_alone")) == "true" then
        self.battery_alone = true
    end

    -- Update main device properties
    self:updateProperty("manufacturer", "Netatmo")
    self:updateProperty("model", "Weather Station")

    -- Setup classes for child devices.
    self:initChildDevices({
        ["com.fibaro.temperatureSensor"] = MyNetatmoSensor,
        ["com.fibaro.humiditySensor"] = MyNetatmoSensor,
        ["com.fibaro.multilevelSensor"] = MyNetatmoSensor,
        ["com.fibaro.windSensor"] = MyNetatmoSensor,
        ["com.fibaro.rainSensor"] = MyNetatmoSensor,
        ["com.fibaro.genericDevice"] = MyNetatmoSensor,
    })

    -- International language traduction
    self.traduction = {
        en = {
            temperature = "Temperature",
            humidity = "Humidity",
            co2 = "CO2",
            pressure = "Pressure",
            noise = "Noise",
            wind = "Wind",
            gust = "Gusts",
            rain = "Rain",
            module = "Module",
        },
        pl = {
            temperature = "Temperatura",
            humidity = "Wilgotność",
            co2 = "CO2",
            pressure = "Ciśnienie",
            noise = "Hałas",
            wind = "Wiatr",
            gust = "Poryw",
            rain = "Deszcz",
            module = "Moduł",
        },
        fr = {
            temperature = "Température",
            humidity = "Humidité",
            co2 = "CO2",
            pressure = "Pression",
            noise = "Bruit",
            wind = "Vent",
            gust = "Rafales",
            rain = "Pluie",
            module = "Module",
        },
        cz = {
            temperature = "Teplota",
            humidity = "Vlhkost",
            co2 = "CO2",
            pressure = "Tlak",
            noise = "Hluk",
            wind = "Vítr",
            gust = "Nárazový vítr",
            rain = "Déšť",
            module = "Modul"
        },
    }

    self.language = api.get("/settings/info").defaultLanguage or nil
    if not self.traduction[self.language] then self.language = "en" end
    self.trad = self.traduction[string.lower(self.language)]

    -- Supported Netatmo datatypes mapped to HC3 device type
    self.NetatmoTypesToHC3 = {
        -- Last temperature measure @ time_utc (in °C)
        Temperature = {
            type = "com.fibaro.temperatureSensor",
            defaultName = self.trad.temperature,
            value = "value",
        },
        -- Last humidity measured @ time_utc (in %)
        Humidity = {
            type = "com.fibaro.humiditySensor",
            defaultName = self.trad.humidity,
            value = "value",
        },
        -- Last Co2 measured @ time_utc (in ppm)
        CO2 = {
            type = "com.fibaro.multilevelSensor",
            defaultName = self.trad.co2,
            value = "value",
            unit = "ppm",
        },
        -- Last Sea level pressure measured @ time_utc (in mbar)
        Pressure = {
            type = "com.fibaro.multilevelSensor",
            defaultName = self.trad.pressure,
            value = "value",
            unit = "mbar",
        },
        -- Last noise measured @ time_utc (in db)
        Noise = {
            type = "com.fibaro.multilevelSensor",
            defaultName = self.trad.noise,
            value = "value",
            unit = "dB",
        },
        -- Current 5 min average wind speed measured @ time_utc (in km/h)
        WindStrength = {
            type = "com.fibaro.windSensor",
            defaultName = self.trad.wind,
            value = "value",
            unit = "km/h",
--[[        -- if you would like to have 'm/s', rather than 'km/h', you need to uncomment these lines
            unit = "m/s",
            conversion = function(value)
                return value/3.6
            end
]]--
        },
        -- Current 5 min average wind direction measured @ time_utc (in °)
        WindAngle = {
            type = "com.fibaro.multilevelSensor",
            defaultName = self.trad.wind,
            value = "value",
            unit = "°",
        },
        -- Speed of the last 5 min highest gust wind (in km/h)
        GustStrength = {
            type = "com.fibaro.windSensor",
            defaultName = self.trad.gust,
            value = "value",
            unit = "km/h",
        },
        -- Direction of the last 5 min highest gust wind (in °)
        GustAngle = {
            type = "com.fibaro.multilevelSensor",
            defaultName = self.trad.gust,
            value = "value",
            unit = "°",
        },
        -- Last rain measured (in mm)
        Rain = {
            type = "com.fibaro.rainSensor",
            defaultName = self.trad.rain .. " 5m",
            value = "value",
            unit = "mm",
        },
        -- Amount of rain in last hour
        sum_rain_1 = {
            type = "com.fibaro.rainSensor",
            defaultName = self.trad.rain .. " 1h",
            value = "value",
            unit = "mm/h",
        },
        -- Amount of rain today
        sum_rain_24 = {
            type = "com.fibaro.rainSensor",
            defaultName = self.trad.rain .. " 24h",
            value = "value",
            unit = "mm",
        },
        -- Measured rain in last 24 hours
        sum_rain_last_24 = {
            type = "com.fibaro.rainSensor",
            defaultName = self.trad.rain .. " last 24h",
            value = "value",
            unit = "mm",
        },
        -- Battery level (used only if battery_alone set to true)
        battery_percent = {
            type = "com.fibaro.genericDevice",
            defaultName = self.trad.module,
            value = "batteryLevel",
            interface = "battery",
        },
    }

    self.measurements = {
        sum_rain_last_24 = {}
    }
    self.http = net.HTTPClient({timeout=10000})
    self.max_status_store = 0 -- Last data update timestamp

    -- Main loop
    self:loop()
end

function QuickApp:loop()
    self:trace("QuickApp:loop()")
    self.devicesMap = self:buildDevicesMap()
    self:GetMeasurements()
--[[    
    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token)
    end)
--]]
    -- Next refresh is 10s after last measurement
    local currentTime = os.time()
    local estimatedTime = tonumber(self.max_status_store) + 600 + 10
    local optimizedDelay = estimatedTime - currentTime
    local waitDelay = (optimizedDelay > 0) and optimizedDelay or 30
    self:trace("Current time : "..os.date("%H:%M:%S", currentTime).." - Last updated values : "..os.date("%H:%M:%S", self.max_status_store).." - Next loop in "..waitDelay.." seconds at "..os.date("%H:%M:%S", currentTime+waitDelay).."...")
    fibaro.setTimeout(math.floor(waitDelay*1000), function() self:loop() end)
end

function QuickApp:buildDevicesMap()
    --self:debug("QuickApp:buildDevicesMap()")
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
    self:debug("DevicesMap built from childs: "..json.encode(DM))
    return(DM)
end

-- Getting Data based on one request: "getstationsdata"
function QuickApp:getNetatmoDevicesData(token, mode)
    --self:debug("QuickApp:getNetatmoDevicesData()")
    local request_body = "access_token=".. token

    self:getNetatmoResponseData("https://api.netatmo.com/api/getstationsdata", request_body, 
        function(getData) 
            self:debug("Getting stations data")
            self:debug("Netatmo API Response: "..json.encode(getData))
            if (getData.error) then
                self:error("Response error: " .. getData.error.message)
            elseif (getData.status == "ok" and getData.body) then
                local Devices = {}

                for _, device in pairs(getData.body.devices) do
                    local station_name = device.station_name or ""
                    local last_status_store = os.date ("%d.%m.%Y %H:%M:%S", device.last_status_store or 0)
                    local noOfModules = 1

                    --self:debug("Found device: '"..device._id.."'; station_name: '"..(device.station_name or "???").."'; module_name: '"..(device.module_name or "???").."'; type: '"..device.type.."'; last_status_store: '"..last_status_store.."'")

                    -- Last data update timestamp
                    if device.last_status_store > self.max_status_store then
                        self.max_status_store = device.last_status_store
                    end

                    self:UpdateHCDevice(mode, {
                        id = device._id,
                        device_id = device._id,
                        name = device.module_name or "",
                        station_name = station_name,
                        reachable = device.reachable,
                        last_status_store = last_status_store,
                    }, device.dashboard_data or {})

                    for _, module in pairs(device.modules or {}) do
                        noOfModules = noOfModules + 1
                        local module_last_seen = os.date ("%d.%m.%Y %H:%M:%S", module.last_seen or 0)
                        --self:debug("Found module: '"..module._id.."'; station_name: '"..(device.station_name or "???").."'; module_name: '"..(module.module_name or "???").."'; type: '"..module.type.."'; last_seen: '"..module_last_seen.."'")

                        -- Last data update timestamp
                        if module.last_seen > self.max_status_store then
                            self.max_status_store = module.last_seen
                        end
                        if module.last_message > self.max_status_store then
                            self.max_status_store = module.last_message
                        end

                        -- Prepare data
                        local device_info = {
                            id = module._id,
                            device_id = device._id,
                            name = module.module_name or "",
                            station_name = station_name,
                            reachable = module.reachable,
                            last_status_store = module_last_seen,
                        }

                        local dashboard_data = module.dashboard_data or {}
                        if module.type == "NAModule3" then -- Rain; add measured data
                            local curr_time = os.time()
                            local tm_begin = curr_time - 24 * 60 * 60
                            dashboard_data.sum_rain_last_24 = 0;
                            self:getRainMeasurements(token, tm_begin, curr_time, device._id, module._id)
                            self.measurements.sum_rain_last_24 = {
                                device_id = device._id,
                                module_id = module._id
                            }
                        end

                        if module.battery_percent then
                            if self.battery_alone then
                                -- Battery interface on dedicated child devices
                                self:UpdateHCDevice(mode, device_info, {battery_percent=module.battery_percent})
                            elseif module.battery_percent then
                                -- Battery interface directly on child devices
                                device_info.battery_percent = module.battery_percent
                            end
                        end
                        self:UpdateHCDevice(mode, device_info, dashboard_data or {})

                    end

                    Devices[station_name] = {
                        place = (device.place.city or "?")..", "..(device.place.country or "?"),
                        modules = noOfModules,
                        last_status_store = last_status_store
                    }
                end

                local label = "Found devices: "
                local status = "Devices last seen: "
                for station_name, data in pairs(Devices) do
                    label = label..station_name.." ("..data.place.."): "..data.modules.."; "
                    status = status..station_name..": "..data.last_status_store.."; "
                end
                self:updateView("label", "text", label)
                self:updateView("status", "text", status)
            else
                self:error("Unknown error")
            end
        end 
    )
end

-- Getting Measurements
function QuickApp:getRainMeasurements(token, tm_begin, tm_end, device_id, module_id)
    self:debug("QuickApp:getNetatmoMeasurements()")
    local request_body = 'access_token='..token..'&device_id='..device_id..'&module_id='..module_id..'&scale=1hour&type=sum_rain&real_time=true&date_begin='..tm_begin
    self:debug("getRainMeasurements: "..request_body)

    self:getNetatmoResponseData("https://api.netatmo.net/api/getmeasure", request_body, 
        function(getData)
            if (getData.error) then
                self:error("Response error: " .. getData.error.message)
            elseif (getData.status == "ok" and getData.body) then
                local sum_rain = 0

                for k, v in ipairs(getData.body) do
                    local values = getData.body[k].value or {}

                    for _,val in ipairs(values) do
                        self:debug("sum_rain value: "..val[1])
                        sum_rain = sum_rain + tonumber(val[1])
                    end
                end

                local device_info = {
                    id = module_id,
                    device_id = device_id,
                    reachable = true,
                    last_status_store = os.time()
                }

                local dashboard_data = {
                    sum_rain_last_24 = sum_rain,
                }

                self:debug("sum_rain: "..sum_rain)
                self:UpdateHCDevice("update", device_info, dashboard_data)
            end
        end
    )
--    return sum_rain
end

function QuickApp:addInterface(child, param)
    local device = api.get('/devices/' .. tostring(child.id))
    local found = false
    for _, interface in ipairs(device.interfaces) do
        if interface == param then
            found = true
            break
        end
    end
    if not found then
        self:debug("Add '" .. param .. "' interface to device #" .. tostring(device.id))
        child:addInterfaces({param})
    end
end

function QuickApp:CreateChilds(module, dashboard_data)
    --self:debug("QuickApp:CreateChilds(...)")
    for data_type, value in pairs(dashboard_data) do
        --self:debug("data_type :", data_type, "- value :", value)
        if (type(self.devicesMap[module.id]) == "table" and self.devicesMap[module.id].devices_map[data_type] and self.childDevices[self.devicesMap[module.id].devices_map[data_type]]) then
            local hcID = self.devicesMap[module.id].devices_map[data_type]
            child = self.childDevices[hcID]
            self:warning("HC3 child device for '"..data_type.."' module already EXISTS. Name: '"..child.name.."', id: '"..child.id.."', type: '"..child.type.."'")
            -- Set unit if not already done
            if (sensor_unit ~= "") then
                child:updateProperty("unit", sensor_unit)
            end
            -- Add battery interface if not already done
            if self.NetatmoTypesToHC3[data_type] and self.NetatmoTypesToHC3[data_type].interface then -- dedicated device
                self:addInterface(child, self.NetatmoTypesToHC3[data_type].interface)
            end
            if module.battery_percent then -- current device
                self:addInterface(child, "battery")
                child:setValue("batteryLevel", module.battery_percent)
            end
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
                local name = (self.NetatmoTypesToHC3[data_type].defaultName or data_type) .. " " .. (module.station_name or "") .. " " .. (module.name or "") -- User friendly name
                local child = self:createChildDevice({
                    name = name,
                    type = sensor_type
                }, MyNetatmoSensor)

                if (child) then

                    -- Set unit
                    if (sensor_unit ~= "") then
                        child:updateProperty("unit", sensor_unit)
                    end

                    -- Set child variables
                    child:setVariable("module_id", module.id)
                    child:setVariable("device_id", module.device_id)
                    child:setVariable("data_type", data_type)

                    -- Add battery interface to dedicated device
                    if self.NetatmoTypesToHC3[data_type].interface then
                        self:addInterface(child, self.NetatmoTypesToHC3[data_type].interface)
                    end

                    -- Add battery interface to current device
                    if module.battery_percent then
                        self:addInterface(child, "battery")
                        child:setValue("batteryLevel", module.battery_percent)
                    end

                    value = self:valueConversion(value, data_type)
                    self:debug("HC3 child device for '"..data_type.."' module created. Name: '"..name.."', id: '"..child.id.."', type: '"..child.type.."'")
                    child:setValue(self.NetatmoTypesToHC3[data_type].value, value)
                end
            else
                --self:warning("Unsupported Netatmo sensor type: "..data_type)
            end
        end
    end
end

function QuickApp:parseDashboardData(module, dashboard_data)
    self:debug("QuickApp:parseDashboardData(...)")
    for data_type, value in pairs(dashboard_data) do
        --self:debug("data_type :", data_type, "- value :", value, "- module :", module.id)
        if (type(self.devicesMap[module.id]) == "table" and self.devicesMap[module.id].devices_map[data_type]) then
            local hcID = self.devicesMap[module.id].devices_map[data_type]
            --self:debug("hcID: "..hcID)

            if (self.childDevices[hcID]) then
                --self:debug("in parsedashboard data_type: "..data_type..", value: "..value..", module: "..module.id)
                local child = self.childDevices[hcID]
                value = self:valueConversion(value, data_type)
                child:setValue("dead", not module.reachable)
                --self:debug("SetValue '"..data_type.."' from module '"..(module.station_name or "???").."'/'"..(module.name or "???").."' on hcID: "..hcID.."; "..self.NetatmoTypesToHC3[data_type].value..": "..value)
                child:setValue(self.NetatmoTypesToHC3[data_type].value, value)
                if module.battery_percent then
                    child:setValue("batteryLevel", module.battery_percent)
                end
            else
                self:error("Child "..hcID.." not exists!")
            end
        else
            self:debug("Nothing to do with '"..data_type.."' from module '"..(module.station_name or "???").."'/'"..module.name.."'")
        end
    end
end

function QuickApp:UpdateHCDevice(mode, device_info, dashboard_data)
    --self:debug('QuickApp:UpdateHCDevice("' .. (mode or "nil") .. '", ...)')
    if (mode == "create") then
        if (device_info.reachable == true) then
            local ok,msg = pcall(function() self:CreateChilds(device_info, dashboard_data or {}) end)
            if not ok then self:error("CreateChilds() error: "..msg) end
        else
            self:warning("Module '" .. (device_info.name or "???") .. "' isn't connected! Status was last updated on: " .. device_info.last_status_store)
        end
    else
        if (device_info.reachable == true) then
            local ok,msg = pcall(function() self:parseDashboardData(device_info, dashboard_data or {}) end)
            if not ok then self:error("parseDashboardData() error: "..msg) end
        else    
            self:warning("Module '" .. (device_info.name or "???") .. "' isn't connected! Status was last updated on: " .. device_info.last_status_store)
            local ok,msg = pcall(function () self:setDeadDevices(device_info) end)
            if not ok then self:error("setDeadDevices() error: "..msg) end
        end
    end
end

function QuickApp:setDeadDevices(module)
    --self:debug("setDeadDevices()")
    if type(self.devicesMap[module.id]) == "table" and self.devicesMap[module.id].devices_map then
        for _, hcID in pairs(self.devicesMap[module.id].devices_map) do
            if (self.childDevices[hcID]) then
                local child = self.childDevices[hcID]
                child:setValue("dead", not module.reachable)
            end
        end
    else
        --self:debug("setDeadDevices(): devicesMap empty")
    end
end

function QuickApp:oAuthNetatmo(func)
    self:debug("QuickApp:oAuthNetatmo()")
    if (self.access_token == "" or self.refresh_token == "" or
        self.access_token == "-" or self.refresh_token == "-") then
        self:error("Credentials data is empty!")
        self:updateView("status", "text", "Credentials data is empty!")
        return 0
    end

    self.client_id = "63309dd3efa656fec30b3e84"
    self.client_secret = "UQjuVwQ0mZJn7u1KdtBwXgwlgM2C0"

    local request_body = "grant_type=refresh_token&client_id="..self.client_id.."&client_secret="..self.client_secret.."&refresh_token="..self.refresh_token

    self:debug("Current access_token: "..self.access_token..", refresh_token: "..self.refresh_token)

    self:getNetatmoResponseData("https://api.netatmo.net/oauth2/token", request_body,
        function(data)
            if (data.access_token ~= nil) then    
                if (self.access_token ~= data.access_token) then
                    self:setVariable("access_token", data.access_token) 
                    self.access_token = data.access_token
                    self:warning("access_token has changed")
                end

                if (self.refresh_token ~= data.refresh_token) then
                    self:setVariable("refresh_token", data.refresh_token) 
                    self.refresh_token = data.refresh_token
                    self:warning("refresh_token has changed")
                end

                self:debug("netatmo-oAuth ok, access_token: "..data.access_token..", refresh_token: "..data.refresh_token)
                func(data.access_token)
            else
                self:error("Can't get token")
            end
        end
    )
end

function QuickApp:getNetatmoResponseData(url, body, func)
    --self:debug('QuickApp:getNetatmoResponseData("'..url..'", "'..body..'", ...)')

    ok,msg = pcall(function() self.http:request(url, {
        options = {
            method = "POST",
            headers = {
                ['Content-Type'] = "application/x-www-form-urlencoded;charset=UTF-8"
            },
            data = body
        },
        success = function(response)
            if (self.api_response_debug) then self:debug("Response: "..json.encode(response)) end
            if (response.status == 200) then
                local status,data = pcall(function() return json.decode(response.data) end)
                if status then
                    func(data)
                else
                    self:error("json.decode() failed")
                end
            else
                self:error("Wrong status '"..response.status.."' in response! Check credentials.")
            end
        end,
        error = function(message)
            self:error("Connection error: " .. message)
        end
    }) end )

    if (not ok) then
        self:error("getNetatmoResponseData ERROR: "..msg.." - url: "..url)
    end
end


-- Actions for buttons
function QuickApp:GetDevices()
    --self:debug("QuickApp:GetDevices()")
    self.devicesMap = self:buildDevicesMap()
    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token, "create")
    end)
end

function QuickApp:GetMeasurements()
    self:debug("QuickApp:GetMeasurements()")
    self.devicesMap = self:buildDevicesMap()
    self:oAuthNetatmo(function(token)
        self:getNetatmoDevicesData(token)
    end)
--[[
    if (type(self.measurements.sum_rain_last_24) == "table" and self.measurements.sum_rain_last_24.device_id) then
        local device_id = self.measurements.sum_rain_last_24.device_id
        local module_id = self.measurements.sum_rain_last_24.module_id

        local curr_time = os.time()
        local tm_begin = curr_time - 24 * 60 * 60
        
        self:oAuthNetatmo(function(token)
            self:getRainMeasurements(token, tm_begin, curr_time, device_id, module_id)
        end)
    else
        self:warning("Can't find Rain module")
    end
--]]
end


-- Classes
class 'MyNetatmoSensor' (QuickAppChild)

function MyNetatmoSensor:__init(device)
    QuickAppChild.__init(self, device)
end

function MyNetatmoSensor:setValue(name, value)
    --self:debug("child "..self.id.." updated value: "..value)
    local oldValue = self.properties[name]
    if value ~= oldValue then
        --self:debug("Update child #" .. self.id .. " '" .. self.name .. "' property '" .. name .. "' : old value = " .. tostring(oldValue) .. " => new value = " .. tostring(value))
        self:updateProperty(name, value)
        self:updateProperty("log", "Transfer_was_OK")
        fibaro.setTimeout(2000, function() self:updateProperty("log", "") end)
    end
end

function MyNetatmoSensor:setIcon(icon)
    --self:debug("child "..self.id.." updated value: "..value)
    self:updateProperty("deviceIcon", icon)
end

function MyNetatmoSensor:getProperty(name) -- get value of property 'name'
    local value = fibaro.getValue(self.id, name)
    --self:debug("child "..self.id.." unit value: "..unit)
    return value
end


-- Tools
function QuickApp:valueConversion(value, data_type)
    if (data_type and self.NetatmoTypesToHC3[data_type] and self.NetatmoTypesToHC3[data_type].conversion) then
        conv_func = self.NetatmoTypesToHC3[data_type].conversion
        value = conv_func(value)
    end
    return value
end

function QuickApp.getWindDirection(sValue)
    if ((sValue >= 0) and (sValue <= 11)) then
        return "N"
    elseif ((sValue > 11) and (sValue <= 34)) then
        return "NNE"
    elseif ((sValue > 34) and (sValue <= 56)) then
        return "NE"
    elseif ((sValue > 56) and (sValue <= 79)) then
        return "ENE"
    elseif ((sValue > 79) and (sValue <= 101)) then
        return "E"
    elseif ((sValue > 101) and (sValue <= 124)) then
        return "ESE"
    elseif ((sValue > 124) and (sValue <= 146)) then
        return "SE"
    elseif ((sValue > 146) and (sValue <= 169)) then
        return "SSE"
    elseif ((sValue > 169) and (sValue <= 191)) then
        return "S"
    elseif ((sValue > 191) and (sValue <= 214)) then
        return "SSW"
    elseif ((sValue > 214) and (sValue <= 236)) then
        return "SW"
    elseif ((sValue > 236) and (sValue <= 259)) then
        return "WSW"
    elseif ((sValue > 259) and (sValue <= 281)) then
        return "W"
    elseif ((sValue > 281) and (sValue <= 304)) then
        return "WNW"
    elseif ((sValue > 304) and (sValue <= 326)) then
        return "NW"
    elseif ((sValue > 326) and (sValue <= 349)) then
        return "NNW"
    elseif ((sValue > 349) and (sValue <= 360)) then
        return "N"
    else
        return "-"
    end
end