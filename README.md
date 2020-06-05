# Netatmo-QA-FIBARO-HC3
QuickApp module to integrate of Netatmo weather devices in FIBARO HC3 gateway.

It has support for Main module, Outdoor modules and Indoor modules, Rain gauge and Smart anemometer. It creates child devices (Temperature Sensors, Humidity Sensors, CO2 Sensors, Pressure Sensors, Noise sensors, Rain and Wind sensors) automatically based on information gathered from Netatmo API.

To use it you need to import attached .fqa file into HC3 and provide credentials from Netatmo:

username - username for your account on Netatmo
password - password for account on Netatmo
client_id - can be generated at dev.netatmo.com
client_secret - can be generated at dev.netatmo.com 
These values are in "Variables" tab on imported device. Click on Pencil, enter data for that four variables and click "Save". After that you need to create child devices. To do that you have to go to the "Edit & Preview" tab and click on "Get Devices" button.

If credentials are ok after few seconds you should have created all linked devices for found Netatmo modules. Values for these devices are refreshed every 5 minutes but QA also has a "Get Measurements" button to manually refresh data.

Important note: 5.030 or newer firmware version on HC3 is needed.
QA is available to download at https://marketplace.fibaro.com/items/netatmo-qa-for-hc3
