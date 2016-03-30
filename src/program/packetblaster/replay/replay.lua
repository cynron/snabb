-- Use of this source code is governed by the Apache 2.0 license; see COPYING.

module(..., package.seeall)

local engine    = require("core.app")
local config    = require("core.config")
local timer     = require("core.timer")
local pci       = require("lib.hardware.pci")
local intel10g  = require("apps.intel.intel10g")
local basic_apps = require("apps.basic.basic_apps")
local main      = require("core.main")
local PcapReader= require("apps.pcap.pcap").PcapReader
local LoadGen   = require("apps.intel.loadgen").LoadGen
local lib = require("core.lib")
local ffi = require("ffi")

local usage = require("program.packetblaster.replay.README_inc")

local long_opts = {
   duration     = "D",
   help         = "h"
}

function run (args)
   local opt = {}
   local mode = table.remove(args, 1)
   local duration
   local c = config.new()
   function opt.D (arg) 
      duration = assert(tonumber(arg), "duration is not a number!")  
   end
   function opt.h (arg)
      print(usage)
      main.exit(1)
   end

   args = lib.dogetopt(args, opt, "hD:", long_opts)
   local filename = table.remove(args, 1)
   config.app(c, "pcap", PcapReader, filename)
   config.app(c, "loop", basic_apps.Repeater)
   config.app(c, "source", basic_apps.Tee)
   config.link(c, "pcap.output -> loop.input")
   config.link(c, "loop.output -> source.input")

   local patterns = args
   local nics = 0
   pci.scan_devices()
   for _,device in ipairs(pci.devices) do
      if is_device_suitable(device, patterns) then
         nics = nics + 1
         local name = "nic"..nics
         config.app(c, name, LoadGen, device.pciaddress)
         config.link(c, "source."..tostring(nics).."->"..name..".input")
      end
   end
   assert(nics > 0, "<PCI> matches no suitable devices.")
   engine.busywait = true
   intel10g.num_descriptors = 32*1024
   engine.configure(c)
   local fn = function ()
                 print("Transmissions (last 1 sec):")
                 engine.report_apps()
              end
   local t = timer.new("report", fn, 1e9, 'repeating')
   timer.activate(t)
   if duration then engine.main({duration=duration})
   else             engine.main() end
end

function is_device_suitable (pcidev, patterns)
   if not pcidev.usable or pcidev.driver ~= 'apps.intel.intel_app' then
      return false
   end
   if #patterns == 0 then
      return true
   end
   for _, pattern in ipairs(patterns) do
      if pci.qualified(pcidev.pciaddress):gmatch(pattern)() then
         return true
      end
   end
end

