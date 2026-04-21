---------------------------------------------------------------------------
-- NetInfo.lua -- Network Information and Monitoring for IARG-OS
-- Launch with: run net
-- Shows network status, connection info, and simulated network monitoring
---------------------------------------------------------------------------

-- BD, Utils are globals loaded by IARG-OS.lua

NetInfo = {
    name = "NetInfo",
    version = "1.0"
}

---------------------------------------------------------------------------
-- Network information and monitoring data
---------------------------------------------------------------------------

local _video = nil
local _font = nil
local _theme = nil
local _onClose = nil

-- Simulated network data
local networkData = {
    -- Connection status
    connection = {
        active = false,
        protocol = "WiFi 802.11b/g",
        ssid = "IARG-Network",
        signal = 0, -- Percentage
        ip = "192.168.1.100",
        gateway = "192.168.1.1",
        dns = "8.8.8.8",
        port = 80 -- HTTP
    },
    
    -- Network interfaces
    interfaces = {
        {
            name = "WiFi0",
            type = "Wireless",
            status = "Connected",
            mac = "AA:BB:CC:DD:EE:FF:00",
            ip = "192.168.1.100",
            subnet = "255.255.255.0",
            gateway = "192.168.1.1",
            dns = "8.8.8.8"
        },
        {
            name = "Serial0",
            type = "Serial",
            status = "Active",
            port = "COM3",
            baud = 9600,
            dataBits = 8,
            parity = "None",
            stopBits = 1
        },
        {
            name = "Loopback",
            type = "Virtual",
            status = "Active",
            ip = "127.0.0.1"
        },
        {
            name = "Ethernet0",
            type = "Wired",
            status = "Disconnected"
        }
    },
    
    -- Network statistics
    stats = {
        packetsSent = 0,
        packetsReceived = 0,
        bytesTransmitted = 0,
        errors = 0,
        connections = 0,
        uptime = 0
    }
}

-- Monitoring data
local monitoringHistory = {}
local maxHistory = 50
local updateCounter = 0

---------------------------------------------------------------------------
-- Helper functions
---------------------------------------------------------------------------

local function formatBytes(bytes)
    if bytes < 1024 then
        return bytes .. " B"
    elseif bytes < 1024 * 1024 then
        return math.floor(bytes / 1024) .. " KB"
    else
        return math.floor(bytes / (1024 * 1024)) .. " MB"
    end
end

local function drawProgressBar(x, y, width, height, percentage, color)
    local fillWidth = math.floor((width - 2) * percentage / 100)
    _video:DrawRect(vec2(x, y), vec2(x + width - 1, y + height - 1), _theme.dim)
    if fillWidth > 0 then
        _video:FillRect(vec2(x + 1, y + 1), vec2(x + fillWidth, y + height - 2), color)
    end
end

local function drawBarChart(x, y, width, height, data, maxValue, color)
    local barWidth = math.floor(width / #data)
    for i, value in ipairs(data) do
        local barHeight = math.floor((height - 2) * value / maxValue)
        local barX = x + (i - 1) * barWidth
        if barHeight > 0 then
            _video:FillRect(vec2(barX, y + height - barHeight - 1), 
                           vec2(barX + barWidth - 2, y + height - 2), color)
        end
    end
end

---------------------------------------------------------------------------
-- Network simulation
---------------------------------------------------------------------------

local function updateNetworkSimulation()
    updateCounter = updateCounter + 1
    
    -- Update connection signal (fluctuates between 60-95%)
    networkData.connection.signal = math.floor(75 + math.sin(updateCounter * 0.05) * 20)
    networkData.connection.active = networkData.connection.signal > 50
    
    -- Update statistics
    networkData.stats.packetsSent = networkData.stats.packetsSent + math.random(10, 50)
    networkData.stats.packetsReceived = networkData.stats.packetsReceived + math.random(8, 45)
    networkData.stats.bytesTransmitted = networkData.stats.bytesTransmitted + math.random(100, 500)
    networkData.stats.errors = networkData.stats.errors + (math.random(1, 10) == 1 and 1 or 0)
    networkData.stats.connections = math.max(1, networkData.stats.connections + (math.random(1, 5) == 3 and 1 or 0))
    networkData.stats.uptime = updateCounter
    
    -- Add to monitoring history
    if updateCounter % 30 == 0 then -- Every 30 frames
        local historyEntry = {
            signal = networkData.connection.signal,
            packetsPerSec = math.random(100, 300),
            errorsPerSec = math.random(0, 5),
            bandwidthUsage = math.random(20, 80)
        }
        table.insert(monitoringHistory, historyEntry)
        if #monitoringHistory > maxHistory then
            table.remove(monitoringHistory, 1)
        end
    end
end

---------------------------------------------------------------------------
-- Drawing functions
---------------------------------------------------------------------------

-- REAL hardware references for network
local _wifi = nil
local _serial = nil

local function getNetworkDeviceInfo()
    -- Get REAL WiFi information
    _wifi = gdt.Wifi0
    networkData.interfaces[1].status = _wifi and "Connected" or "Not Available"
    
    -- Get REAL Serial information (simulate Serial0)
    _serial = gdt.Serial0
    if _serial then
        networkData.interfaces[2].status = "Active"
        networkData.interfaces[2].baud = _serial.BaudRate or 9600
        networkData.interfaces[2].dataBits = _serial.DataBits or 8
        -- Convert userdata to string safely
        local parityValue = _serial.Parity
        if type(parityValue) == "string" then
            networkData.interfaces[2].parity = parityValue
        else
            networkData.interfaces[2].parity = tostring(parityValue) or "None"
        end
    else
        networkData.interfaces[2].status = "Not Available"
    end
end

local function tp(x, y, txt, color)
    -- In IARG-OS, text is drawn using DrawSprite character by character
    if not _font then return end
    local bgColor = _theme.bg or color.black
    for i = 1, #txt do
        local ch = txt:sub(i, i)
        _video:DrawSprite(
            vec2(x + (i-1) * BD.CHAR_W, y),
            _font,
            ch:byte() % 32,
            math.floor(ch:byte() / 32),
            color,
            bgColor
        )
    end
end

local function drawNetworkInfo()
    local y = BD.CONTENT_Y + 2
    
    -- Update REAL device info
    getNetworkDeviceInfo()
    
    -- Title
    tp(10, y, "NETWORK INFORMATION", _theme.success)
    y = y + BD.CHAR_H + 2
    
    -- REAL WiFi Information
    tp(10, y, "WIFI STATUS", _theme.success)
    y = y + BD.CHAR_H + 1
    
    if _wifi then
        tp(15, y, "Device: Wifi0", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Status: Connected", _theme.success)
        y = y + BD.CHAR_H
        tp(15, y, "Signal: " .. networkData.connection.signal .. "%", _theme.text)
        drawProgressBar(120, y - 2, 80, 8, networkData.connection.signal, _theme.success)
        y = y + BD.CHAR_H
        tp(15, y, "Protocol: " .. networkData.connection.protocol, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "SSID: " .. networkData.connection.ssid, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "IP: " .. networkData.connection.ip, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Gateway: " .. networkData.connection.gateway, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "DNS: " .. networkData.connection.dns, _theme.text)
    else
        tp(15, y, "Device: Wifi0", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Status: Not Available", _theme.dim)
    end
    
    y = y + BD.CHAR_H + 2
    
    -- REAL Serial Information
    tp(10, y, "SERIAL STATUS", _theme.success)
    y = y + BD.CHAR_H + 1
    
    if _serial then
        tp(15, y, "Device: Serial0", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Status: Active", _theme.success)
        y = y + BD.CHAR_H
        tp(15, y, "Port: " .. networkData.interfaces[2].port, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Baud Rate: " .. networkData.interfaces[2].baud, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Data Bits: " .. networkData.interfaces[2].dataBits, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Parity: " .. networkData.interfaces[2].parity, _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Stop Bits: " .. networkData.interfaces[2].stopBits, _theme.text)
    else
        tp(15, y, "Device: Serial0", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Status: Not Available", _theme.dim)
        y = y + BD.CHAR_H
        tp(15, y, "Simulated Mode", _theme.dim)
        y = y + BD.CHAR_H
        tp(15, y, "Port: COM3", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Baud Rate: 9600", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Data Bits: 8", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Parity: None", _theme.text)
        y = y + BD.CHAR_H
        tp(15, y, "Stop Bits: 1", _theme.text)
    end
    
    y = y + BD.CHAR_H + 2
    
    -- Network Statistics
    tp(10, y, "NETWORK STATISTICS", _theme.success)
    y = y + BD.CHAR_H + 1
    
    tp(15, y, "Packets Sent: " .. networkData.stats.packetsSent, _theme.text)
    y = y + BD.CHAR_H
    tp(15, y, "Packets Received: " .. networkData.stats.packetsReceived, _theme.text)
    y = y + BD.CHAR_H
    tp(15, y, "Bytes Transmitted: " .. formatBytes(networkData.stats.bytesTransmitted), _theme.text)
    y = y + BD.CHAR_H
    tp(15, y, "Errors: " .. networkData.stats.errors, _theme.text)
    y = y + BD.CHAR_H
    tp(15, y, "Connections: " .. networkData.stats.connections, _theme.text)
    y = y + BD.CHAR_H
    tp(15, y, "Uptime: " .. math.floor(networkData.stats.uptime / 60) .. "s", _theme.text)
end

local function drawNetworkMonitoring()
    local y = BD.CONTENT_Y + 2
    
    -- Title
    tp(10, y, "NETWORK MONITORING", _theme.success)
    y = y + BD.CHAR_H + 2
    
    -- Current status
    tp(10, y, "Current Status", _theme.text)
    y = y + BD.CHAR_H + 1
    
    tp(15, y, "Signal Strength: " .. networkData.connection.signal .. "%", _theme.text)
    drawProgressBar(150, y - 2, 100, 8, networkData.connection.signal, _theme.success)
    y = y + BD.CHAR_H
    
    local packetsPerSec = #monitoringHistory > 0 and monitoringHistory[#monitoringHistory].packetsPerSec or 0
    tp(15, y, "Packets/sec: " .. packetsPerSec, _theme.text)
    y = y + BD.CHAR_H
    
    local bandwidthUsage = #monitoringHistory > 0 and monitoringHistory[#monitoringHistory].bandwidthUsage or 0
    tp(15, y, "Bandwidth Usage: " .. bandwidthUsage .. "%", _theme.text)
    drawProgressBar(150, y - 2, 100, 8, bandwidthUsage, _theme.output)
    y = y + BD.CHAR_H + 2
    
    -- History charts
    tp(10, y, "History (Last " .. #monitoringHistory .. " entries)", _theme.text)
    y = y + BD.CHAR_H + 1
    
    if #monitoringHistory > 0 then
        -- Signal history
        tp(15, y, "Signal", _theme.dim)
        y = y + BD.CHAR_H
        local signalData = {}
        for i = math.max(1, #monitoringHistory - 10), #monitoringHistory do
            table.insert(signalData, monitoringHistory[i].signal)
        end
        drawBarChart(15, y, 100, 20, signalData, 100, _theme.success)
        
        -- Bandwidth history
        y = y + 22
        tp(15, y, "Bandwidth", _theme.dim)
        y = y + BD.CHAR_H
        local bandwidthData = {}
        for i = math.max(1, #monitoringHistory - 10), #monitoringHistory do
            table.insert(bandwidthData, monitoringHistory[i].bandwidthUsage)
        end
        drawBarChart(15, y, 100, 20, bandwidthData, 100, _theme.output)
    end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function NetInfo:Init(video, font, theme, onClose)
    _video = video
    _font = font
    _theme = theme
    _onClose = onClose
    
    -- Initialize network data
    networkData.connection.active = true
    networkData.connection.signal = 75
    updateCounter = 0
    monitoringHistory = {}
end

function NetInfo:HandleKey(name, shift, ctrl)
    if name == "Escape" then
        if _onClose then _onClose() end
    elseif name == "M" then
        -- Toggle monitoring mode (placeholder for future enhancement)
        networkData.connection.active = not networkData.connection.active
    elseif name == "R" then
        -- Reset statistics
        networkData.stats.packetsSent = 0
        networkData.stats.packetsReceived = 0
        networkData.stats.bytesTransmitted = 0
        networkData.stats.errors = 0
        networkData.stats.connections = 0
        networkData.stats.uptime = 0
        monitoringHistory = {}
        updateCounter = 0
    elseif name == "C" then
        -- Clear history
        monitoringHistory = {}
    end
end

function NetInfo:HandleMouse(button, x, y, buttonDown)
    -- Mouse handling for future enhancements
end

function NetInfo:Update()
    updateNetworkSimulation()
end

function NetInfo:Draw()
    if not _video or not _theme then return end
    
    -- Background
    _video:FillRect(vec2(0, BD.CONTENT_Y), vec2(_video.Width - 1, _video.Height - 1), _theme.bg)
    
    -- Draw network information
    drawNetworkInfo()
    
    -- Draw monitoring section on the right side
    local monitoringX = math.floor(_video.Width / 2) + 10
    local monitoringY = BD.CONTENT_Y + 2
    
    tp(monitoringX, monitoringY, "MONITORING", _theme.success)
    monitoringY = monitoringY + BD.CHAR_H + 2
    
    -- Current monitoring data
    tp(monitoringX, monitoringY, "Signal: " .. networkData.connection.signal .. "%", _theme.text)
    drawProgressBar(monitoringX + 80, monitoringY - 2, 80, 8, networkData.connection.signal, _theme.success)
    monitoringY = monitoringY + BD.CHAR_H
    
    local packetsPerSec = #monitoringHistory > 0 and monitoringHistory[#monitoringHistory].packetsPerSec or 0
    tp(monitoringX, monitoringY, "Packets/s: " .. packetsPerSec, _theme.text)
    monitoringY = monitoringY + BD.CHAR_H
    
    local bandwidthUsage = #monitoringHistory > 0 and monitoringHistory[#monitoringHistory].bandwidthUsage or 0
    tp(monitoringX, monitoringY, "Bandwidth: " .. bandwidthUsage .. "%", _theme.text)
    drawProgressBar(monitoringX + 80, monitoringY - 2, 80, 8, bandwidthUsage, _theme.output)
    monitoringY = monitoringY + BD.CHAR_H + 2
    
    -- Controls
    tp(monitoringX, monitoringY, "CONTROLS", _theme.success)
    monitoringY = monitoringY + BD.CHAR_H + 1
    tp(monitoringX, monitoringY, "M - Toggle connection", _theme.dim)
    monitoringY = monitoringY + BD.CHAR_H
    tp(monitoringX, monitoringY, "R - Reset statistics", _theme.dim)
    monitoringY = monitoringY + BD.CHAR_H
    tp(monitoringX, monitoringY, "C - Clear history", _theme.dim)
    monitoringY = monitoringY + BD.CHAR_H
    tp(monitoringX, monitoringY, "Esc - Exit to CLI", _theme.dim)
    
    -- History chart (small)
    if #monitoringHistory > 1 then
        monitoringY = monitoringY + 2
        tp(monitoringX, monitoringY, "HISTORY", _theme.success)
        monitoringY = monitoringY + BD.CHAR_H + 1
        
        local chartWidth = 80
        local chartHeight = 30
        local signalData = {}
        for i = math.max(1, #monitoringHistory - 8), #monitoringHistory do
            table.insert(signalData, monitoringHistory[i].signal)
        end
        drawBarChart(monitoringX, monitoringY, chartWidth, chartHeight, signalData, 100, _theme.success)
    end
end

-- Return the module for require()
return NetInfo
