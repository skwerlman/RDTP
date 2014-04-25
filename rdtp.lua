function noCustom(m)
  error("No custom code handler has been defined",0)
end

-- Globals
version = "RDTP alpha r3"
author = "skwerlman"
customRef = noCustom -- use rdtp.setCustomHandler(function) to define a handler for custom CODEs
debug = false
local depth = -2

-- parseCode statuses
ok = 0
wait = 1
get = 2
err = 3
custom = 4

-- General functions

function warning(msg)
  if term.isColor() then
    term.setTextColor(colors.orange)
  end
  local s = ''
  if debug then
    for i=0,depth do
      s = s..' '
    end
  end
  print(s..tostring(msg))
  if term.isColor() then
    term.setTextColor(colors.white)
  end
end

function wrapAllModems() -- returns table { string, ... }
  if debug then
    depth = depth + 1
    warning("wrapAllModems()")
  end
  local t=peripheral.getNames()
  local d = { "right", "left", "front", "back", "top", "bottom" }
  local p={}
  local c=0
  local j,k,s
  for j=1,#t do
    s=t[j]
    if s:find("modem") then
      c=c+1
      p[c]=s
    end
  end
  for j=1,#t do
    s=t[j]
    for k=1,6 do
      if s == d[k] then
        if string.find(peripheral.getType(d[k]), "modem") then
          c=c+1
          p[c]=d[k]
        end
      end
    end
  end
  if not p[1] then
    warning("no modems; might cause errors")
  end
  if debug then
    warning(p)
    depth = depth - 1
  end
  return p
end

local function open() -- returns bool
  if debug then
    depth = depth + 1
    warning("open()")
  end
  if not rednet.isOpen(modem) then
    modem = wrapAllModems()[1] or 'top'
  end
  if not string.find(tostring(peripheral.getType(modem)), "modem") then
    if debug then
      warning(false)
      depth = depth - 1
    end
    return false
  end
  rednet.open(modem)
  if debug then
    warning(true)
    depth = depth - 1
  end
  return true
end

local function close() -- returns nil
  if debug then
    depth = depth + 1
    warning("close()")
  end
  rednet.close(modem)
  if debug then
    warning('nil')
    depth = depth - 1
  end
end

function parseCode(msg) -- returns int, string or nil
  if debug then
    depth = depth + 1
    warning("parseCode()")
  end
  if msg == nil then
    return 3, "ERROR 09: The connection timed out"
  end
  local code = msg.code or "10" -- CODE 10: BADRESP (invalid format)
  local data = msg.data or "Invalid Response"
  local c,d
  if #code == 2 then
    if code == "00" then
      c, d = 2 -- should process a GET
    elseif code == "01" then
      c, d = 1 -- should wait for a response again, and possibly notify user
    elseif code == "02" or code == "0a" then
      c, d = 0 -- should return
    elseif code == "03" or code == "04" or code == "05" or code == "07" or code == "08" or code == "10" or code =="20" then
      c, d = 3, "ERROR "..code..": "..data -- should print the supplied error message
    elseif code == "06" then
      c, d = 3, "ERROR 06: Server failed to process request for an unknown reason." -- should print the supplied error message
    else
      c, d = 3, "ERROR "..code..": Unknown code. Please ensure that your API version is current." -- will handle all codes implemented by newer versions
    end
  else
    c, d = 4 -- someone is likely using a custom code, and we don't want to step on their toes
  end
  if debug then
    warning(c)
    warning(d)
    depth = depth - 1
  end
  return c, d
end

function setCustomHandler(func)
  customRef = func or noCustom
end

-- Client functions

-- Sends a message to a server, then waits 10s for a reply
-- If none is given, we give up. Servers should reply with
--  CODE "01" if they need us to wait longer.
function send(targetID, c, f, d, l, s) -- returns table { string, string, string, string, int }
  if debug then
    depth = depth + 1
    warning("send()")
  end
  if not open() then
    error("no modem")
  end
  local id
  local msg = { code = c, format = f, data = d, label = l, srcid = s }
  rednet.send(targetID, textutils.serialize(msg))
  msg = nil
  local continue = true
  local continue2 = true
  while continue do
    local timer = os.startTimer(10)
    while continue2 do
      os.queueEvent("null")
  		local e, p1, p2 = os.pullEvent()
  		if e == "rednet_message" then
  			id, msg = p1, p2
  			if id == targetID then
  			  continue2 = false
  			  msg = textutils.unserialize(msg)
  			end
  		elseif e == "timer" and p1 == timer then
  			continue2 = false
  		end
  	end
    local status, data = parseCode(msg)
  	if status == custom then
  	  local t = { customRef(msg) }
  		status = t[1]
  		data = t[2] or data
  	end
  	if status == ok then
 		  continue = false
 		elseif status == wait then
		  continue2 = true
 		elseif status == get then
 		  printError("The server attempted to request information from us as though we're a server!")
 		  if debug then
        warning('nil')
        depth = depth - 1
      end
 		  return nil
    else
      error(data,0) -- will be handled better later
    end
	end
  close()
  if debug then
    warning(msg)
    depth = depth - 1
  end
  return msg
end

-- Server functions

function receive(t) -- returns int or false, table { string, string, string, string, int }
  if debug then
    depth = depth + 1
    warning("receive()")
  end
  if not open() then
    error("no modem")
  end
  local id, msg = rednet.receive(t)
  if not msg then msg = "{ nil }" end
  close()
  if debug then
    warning(id or false)
    warning(textutils.unserialize(msg))
    depth = depth - 1
  end
  return id or false, textutils.unserialize(msg)
end

function replyTo(targetID, c, f, d, l, s) -- returns nil
  if debug then
    depth = depth + 1
    warning("relyTo()")
  end
  if not open() then
    error("no modem")
  end
  local msg = { code = c, format = f, data = d, label = l, srcid = s }
  rednet.send(targetID, textutils.serialize(msg))
  close()
  if debug then
    warning('nil')
    depth = depth - 1
  end
end

-- Setup

-- We use 'top' so that rednet.isOpen() won't error.
-- Even if 'top' isn't a modem, send() will just return 'false' and re-check.
modem = wrapAllModems()[1] or 'top'

