local lfs = require 'lfs'
local torch = require 'torch'

package.path = './?.lua;' .. package.path

local csv = require 'csv'

local Dataset = {}

local Months_Codes = 'FGHJKMNQUVXZ'

local TZ_Moscow = 3*60*60

local function unixtime(struct)
  if (not struct) then return os.time() end -- Return current unix datetime by system.
  local t_secs = os.time(struct) -- Get seconds if struct was in local time.
  local t = os.date("*t", t_secs) -- Find out if daylight savings was applied.
  local t_UTC = os.date("!*t", t_secs) -- Find out what UTC struct was converted to.
  t_UTC.isdst = t.isdst -- Apply DST to this time if necessary.
  local UTC_secs = os.time(t_UTC) -- Find out the converted time in seconds.
  return t_secs + os.difftime(t_secs, UTC_secs) -- The answer is our original answer plus the difference.
end -- function unixtime

local function calculateFrameStart(time, interval)
  -- Calculate start of frame
  local t = os.date('!*t', time)
  if (interval <= 24*60*60) then
    -- Get start of day
    t.hour, t.min, t.sec = 0, 0, 0
  else
    -- Get start of year
    t.yday, t.month, t.day, t.hour, t.min, t.sec = 1, 1, 1, 0, 0, 0
  end
  local s = unixtime(t)
  -- Calculate start of frame with respect to start time s and interval
  local frame_start_time = s + math.floor((time-s)/interval)*interval
  return frame_start_time
end -- function calculateFrameStart

function Dataset.findHistoryFiles(dir_path, file_prefix, sec_name)
  dir_path = dir_path or '.'
  file_prefix = file_prefix or '%a+.%a+'
  local sec_month, sec_year
  if sec_name then
    -- Decode month and year digit from sec_name
    sec_month = Months_Codes:find(sec_name:sub(-2,-2), 1, true)
    sec_year = tonumber(sec_name:sub(-1,-1))
    if (not sec_month) or (not sec_year) then
      return nil, 'Failed to decode month and year from sec_name!'
    end
  end
  -- Search filenames for given security name
  local files = {}
  print('Scanning '..tostring(dir_path)..' for history files...')
  local sec_file_pattern = '^'..file_prefix:gsub('%.','%%.')..'%-(%d+)%.(%d+)%.txt$'
  print('Pattern='..tostring(sec_file_pattern))
  for file_name in lfs.dir(dir_path) do
    local month, year = file_name:match(sec_file_pattern)
    month, year = tonumber(month), tonumber(year)
    if month and year and ((not sec_name) or ((month == sec_month) and ((year%10) == sec_year))) then
      file_name = dir_path .. '/' .. file_name
      table.insert(files, file_name)
    end
  end
  if #files <= 0 then return nil, 'History files not found!' end
  -- Sort files ascending by years and months
  table.sort(files, function(a,b)
      local a_month, a_year = a:match('-(%d+)%.(%d+)%.txt$')
      local b_month, b_year = b:match('-(%d+)%.(%d+)%.txt$')
      a_month, a_year = tonumber(a_month), tonumber(a_year)
      b_month, b_year = tonumber(b_month), tonumber(b_year)
      return (a_year == b_year) and (a_month < b_month) or (a_year < b_year)
    end)
  return files
end -- function Dataset.findHistoryFiles

local function env_updateFrame(self, frame, candle)
  if (not frame.H) or (frame.H < candle.H) then frame.H = candle.H end
  if (not frame.L) or (frame.L > candle.L) then frame.L = candle.L end
  frame.V = (frame.V or 0) + candle.V
  frame.N = (frame.N or 0) + 1
  frame.TC = candle.TC
  frame.C = candle.C
  -- Use typical price to update sum of price*volume
  local TP = candle.TP or ((candle.H + candle.L + candle.C)/3)
  frame.PV = (frame.PV or 0) + TP*candle.V
end -- function env_updateFrame

local function env_processFrame(self, frame, set, outer_frame)
  table.insert(set.po, frame.O)
  table.insert(set.ph, frame.H)
  table.insert(set.pl, frame.L)
  table.insert(set.pc, frame.C)
  table.insert(set.vol, frame.V)
  -- Calculate VWAP
  if set.vwap then
    local vwap = (frame.V ~= 0) and (frame.PV / frame.V) or (frame.C)
    table.insert(set.vwap, vwap)
  end
  -- Calculate true range
  if set.ptr then
    local ptr
    if set.N > 0 then
      local C1 = set.pc[set.N]
      ptr = math.max(frame.H, C1) - math.min(frame.L, C1)
    else ptr = frame.H - frame.L end
    table.insert(set.ptr, ptr)
  end
  --
  assert(frame.TO < frame.TC, 'Invalid frame time: TO='..tostring(frame.TO)..' TC='..tostring(frame.TC))
  table.insert(set.to, frame.TO)
  table.insert(set.tc, frame.TC)
  --
  if set.ol and set.oh and outer_frame then
    table.insert(set.oh, outer_frame.H)
    table.insert(set.ol, outer_frame.L)
  end
  --
  local t = os.date('!*t', frame.TC - TZ_Moscow)
  if set.time then
    local start_time = unixtime({year=t.year,month=t.month,day=t.day,hour=10,min=0,sec=0}) - TZ_Moscow
    local end_time = unixtime({year=t.year,month=t.month,day=t.day,hour=23,min=50,sec=0}) - TZ_Moscow
    local time = (frame.TC - start_time)/(end_time - start_time)
    time = math.max(0, math.min(1, time))
    table.insert(set.time, time)
    if time <= 0.018 then
      time = 0
    end
  end
  --
  if set.hour then
    table.insert(set.hour, t.hour)
  end
  --
  if set.day then
    table.insert(set.day, t.day)
  end
  --
  if set.month then
    table.insert(set.month, t.month)
  end
  --
  set.N = set.N + 1
end -- function env_processFrame

local function env_processCandle(self, candle)
  local frame_interval = self.frame_interval
  local t = os.date('!*t', candle.TC - TZ_Moscow)
  self.last_time = candle.TC
  
  -- Add candle to array
  if (self.frames.N > 0) and (self.hours.N > 0) and (self.days.N > 0) then
    self:processFrame(candle, self.candles)
    table.insert(self.index_candles_frames, self.frames.N)
    table.insert(self.index_candles_hours, self.hours.N)
    table.insert(self.index_candles_days, self.days.N)
    self.ncandles = #self.candles.pc
  end
  
  -- Update frame
  -- Check for frame completion
  if (not self.frame_start_time) or (candle.TC - self.frame_start_time >= frame_interval) then
    -- Process last frame
    if self.frame and (self.hours.N > 0) and (self.days.N > 0) then
      self:processFrame(self.frame, self.frames, self.hour)
      table.insert(self.index_frames_hours, self.hours.N)
      table.insert(self.index_frames_days, self.days.N)
      self.nframes = #self.frames.pc
    end
    -- Reset frame
    self.frame_start_time = calculateFrameStart(candle.TO, frame_interval)
    self.frame = { TO = self.frame_start_time, O = candle.O }
  end -- if interval
  self:updateFrame(self.frame, candle)
  
  -- Update hour frame
  if (not self.last_hour) or (self.last_hour ~= t.hour) then
    -- Process last hour frame
    if self.hour and (self.days.N > 0) then
      self:processFrame(self.hour, self.hours, self.day)
      table.insert(self.index_hours_days, self.days.N)
      self.nhours = #self.hours.pc
    end
    -- Reset hour frame
    self.hour = { TO = candle.TO, O = candle.O }
    self.last_hour = t.hour
  end
  self:updateFrame(self.hour, candle)
  
  -- Update day frame
  if (not self.last_day) or (self.last_day ~= t.yday) then
    -- Process last day frame
    if self.day and self.first_month and (self.first_month ~= t.month) then
      self:processFrame(self.day, self.days, self.month)
      self.ndays = #self.days.pc
    end
    -- Reset day frame
    self.day = { TO = candle.TO, O = candle.O }
    self.last_day = t.yday
  end
  self:updateFrame(self.day, candle)
  
  -- Update month frame
  if (not self.first_month) then self.first_month = t.month end
  if (not self.last_month) or (self.last_month ~= t.month) then
    -- Reset month frame
    self.month = { TO = candle.TO, O = candle.O }
    self.last_month = t.month
  end
  self:updateFrame(self.month, candle)
end -- function env_processCandle

local function convertArraysToTensors(dst, src)
  for k, v in pairs(src) do
    local t = type(v)
    if (t == 'table') then
      if (#v > 0) then
        if k:match('^index') then
          dst[k] = torch.LongTensor(v)
        else
          dst[k] = torch.Tensor(v)
        end
      else
        if (type(dst[k]) ~= 'table') then dst[k] = {} end
        convertArraysToTensors(dst[k], v)
      end
    elseif (t == 'number') then
      dst[k] = v
    end
  end -- for pairs(src)
end -- function convertArraysToTensors

local function expand(self, a, b)
  local na, nb = a:nElement(), b:nElement()
  assert(na == self.ncandles or na == self.nframes or na == self.nhours or na == self.ndays,
    'Dataset: invalid a-operand length: '..tostring(na)..' <> '..tostring(self.ncandles)
    ..', '..tostring(self.nframes)..', '..tostring(self.nhours)..', '..tostring(self.ndays))
  assert(nb == self.ncandles or nb == self.nframes or nb == self.nhours or nb == self.ndays,
    'Dataset: invalid b-operand length: '..tostring(nb)..' <> '..tostring(self.ncandles)
    ..', '..tostring(self.nframes)..', '..tostring(self.nhours)..', '..tostring(self.ndays))
  local xa, xb = a, b
  local n = math.max(na, nb)
  if n == self.ncandles then
    if na == self.nframes then
      xa = a:index( 1, self.index_candles_frames )
    elseif na == self.nhours then
      xa = a:index( 1, self.index_candles_hours )
    elseif na == self.ndays then
      xa = a:index( 1, self.index_candles_days )
    end
    if nb == self.nframes then
      xb = b:index( 1, self.index_candles_frames )
    elseif nb == self.nhours then
      xb = b:index( 1, self.index_candles_hours )
    elseif na == self.ndays then
      xb = b:index( 1, self.index_candles_days )
    end
  elseif n == self.nframes then
    if na == self.nhours then
      xa = a:index( 1, self.index_frames_hours )
    elseif na == self.ndays then
      xa = a:index( 1, self.index_frames_days )
    end
    if nb == self.nhours then
      xb = b:index( 1, self.index_frames_hours )
    elseif nb == self.ndays then
      xb = b:index( 1, self.index_frames_days )
    end
  elseif n == self.nhours then
    if na == self.ndays then
      xa = a:index( 1, self.index_hours_days )
    end
    if nb == self.ndays then
      xb = b:index( 1, self.index_hours_days )
    end
  end
  return xa, xb
end -- function expand

function Dataset.addExpand(dataset)
  for _, series in ipairs(dataset) do
    series.expand = expand
  end -- for ipairs dataset
end -- function Dataset.addExpand

local function env_exportSeries(self)
  local series = {}
  convertArraysToTensors(series, self)
  series.expand = expand
  return series
end -- function env_exportSeries

function Dataset.loadHistoryFile(file_name, frame_interval)
  local env = {
    frame_interval = frame_interval,
    updateFrame = env_updateFrame,
    processFrame = env_processFrame,
    processCandle = env_processCandle,
    exportSeries = env_exportSeries,
    ncandles = 0,
    nframes = 0,
    nhours = 0,
    ndays = 0,
    index_candles_frames = {},
    index_candles_hours = {},
    index_candles_days = {},
    index_frames_hours = {},
    index_frames_days = {},
    index_hours_days = {},
    candles = {
      po = {}, ph = {}, pl = {}, pc = {}, vol = {},
      to = {}, tc = {}, N = 0
    },
    frames = {
      po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
      ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
    },
    hours = {
      po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
      ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
    },
    days = {
      po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
      ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
    },
  }
  
  local candle_interval = 60
  
  -- Load file into table
  local file, reason = csv.CSVFile(file_name)
  if (not file) then return nil, reason end
  
  -- Cycle through records in a file
  for i, row in ipairs(file) do
    -- Print progress
    if (i % 100 == 0) or (i == #file) then
      io.write('\r'..tostring(i)..'/'..tostring(#file)); io.flush()
    end
    -- Process DATE
    local date = tonumber(row[1])
    if (type(date) ~= 'number') then
      return nil, 'loadHistoryFile: failed to parse DATE: '..tostring(date)
    end
    local year = math.floor(date/10000)
    local month = math.floor((date-year*10000)/100)
    local day = math.floor(date-year*10000-month*100)
    if year < 2000 then year = 2000 + year end
    -- Process TIME
    local time = row[2]
    if (type(time) ~= 'string') then
      return nil, 'loadHistoryFile: failed to parse TIME: '..tostring(time)
    end
    local hour, min = time:match("(%d+):(%d+)")
    hour, min = tonumber(hour), tonumber(min)
    if (not hour) or (not min) then
      return nil, 'loadHistoryFile: failed to parse hour and min: '..tostring(time)
    end
    -- Calculate TO and TC fields
    local candle = {}
    candle.TC = unixtime( { year=year, month=month, day=day, hour=hour, min=min, sec=0 } )
      - TZ_Moscow -- Moscow timezone
    if (candle_interval == 24*60*60) then
      candle.TO = row.TC
      candle.TC = (candle.TC + candle_interval)
    else
      candle.TO = (candle.TC - candle_interval)
    end
    candle.O = tonumber(row[3])
    candle.H = tonumber(row[4])
    candle.L = tonumber(row[5])
    candle.C = tonumber(row[6])
    candle.V = tonumber(row[7])
    if (not candle.O) or (not candle.H) or (not candle.L) or (not candle.C) or (not candle.V) then
      return nil, 'loadHistoryFile: failed to parse prices'
    end
    if (candle.TO >= candle.TC) then
      return nil, 'Invalid candle time: TO='..tostring(candle.TO)..' TC='..tostring(candle.TC)
    end
    -- Calculate typical price
    candle.TP = (candle.H + candle.L + candle.C)/3
    -- Process candle
    env:processCandle(candle)
  end -- for ipairs(file)
  
  return env
end -- function Dataset.loadHistory

--local function covariance(a, b, mean_a, mean_b)
--  mean_a = mean_a or a:mean()
--  mean_b = mean_b or b:mean()
--  local da = torch.add(a, -mean_a)
--  local db = torch.add(b, -mean_b)
--  --local result = torch.cmul(da, db):sum() / a:nElement()
--  local result = torch.dot(da, db) / a:nElement()
--  return result
--end -- function covariance

--local function correlation(a, b, mean_a, mean_b)
--  mean_a = mean_a or a:mean()
--  mean_b = mean_b or b:mean()
--  local da = torch.add(a, -mean_a)
--  local db = torch.add(b, -mean_b)
--  local norm = da:norm() * db:norm()
--  if (norm == 0) then return 0 end
--  --local result = torch.cmul(da, db):sum() / math.sqrt( torch.cmul(da,da):sum() * torch.cmul(db,db):sum() )
--  local result = torch.dot(da, db) / norm
--  return result
--end -- function correlation

--local function signedLog(x)
--  local sign = (x == 0) and 0 or (x > 0) and 1 or -1
--  local result = math.max(0, math.log(math.abs(x)))
--  return sign*result
--end -- function signedLog

--local function convertArraysToTensors(tab)
--  for k, v in pairs(tab) do
--    if type(v) == 'table' then
--      if (k == 'to') or (k == 'tc') then
--        tab[k] = torch.LongTensor(v)
--      else
--        tab[k] = torch.Tensor(v)
--      end
--    end
--  end
--end -- function convertArraysToTensors

--local function removePriceTrend(tab, slope, x1)
--  local n = tab.pc:nElement()
--  for i = 2, n do
--    local dyO = slope*(tab.to[i] - x1)
--    local dyC = slope*(tab.tc[i] - x1)
--    local dyM = (dyO + dyC) / 2
--    tab.po[i] = tab.po[i] - dyO
--    tab.ph[i] = tab.ph[i] - dyM
--    tab.pl[i] = tab.pl[i] - dyM
--    tab.pc[i] = tab.pc[i] - dyC
--    if tab.vwap then
--      tab.vwap[i] = tab.vwap[i] - dyM
--    end
--  end
--end -- function removePriceTrend

--local function trimVectorsLeft(tab, n)
--  for k, v in pairs(tab) do
--    if torch.isTensor(v) then
--      tab[k] = v:sub(n + 1, -1)
--    end
--  end
--end -- function trimVectorsLeft

--local function loadHistoryFile(file_name, frame_interval)
--  local candle_interval = 60
--  print('Processing '..tostring(file_name)..' with frame_interval='..tostring(frame_interval)..' ...')
  
--  local file, reason = csv.CSVFile(file_name)
--  if (not file) then return nil, reason end
  
--  local frame, hour, day, month
--  local frame_start_time, last_hour, last_day, last_month, first_month
  
--  -- Resulting vectors
--  local index_candles_frames, index_candles_hours, index_candles_days = {}, {}, {}
--  local index_frames_hours, index_frames_days = {}, {}
--  local index_hours_days = {}
--  local candles = {
--    po = {}, ph = {}, pl = {}, pc = {}, vol = {},
--    to = {}, tc = {}, N = 0
--  }
--  local frames = {
--    po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
--    ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
--  }
--  local hours = {
--    po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
--    ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
--  }
--  local days = {
--    po = {}, ph = {}, pl = {}, pc = {}, ptr = {}, vwap = {}, vol = {},
--    ol = {}, oh = {}, to = {}, tc = {}, time = {}, N = 0
--  }
  
--  local function updateFrame(frame, candle)
--    if (not frame.H) or (frame.H < candle.H) then frame.H = candle.H end
--    if (not frame.L) or (frame.L > candle.L) then frame.L = candle.L end
--    frame.V = (frame.V or 0) + candle.V
--    frame.N = (frame.N or 0) + 1
--    frame.TC = candle.TC
--    frame.C = candle.C
--    -- Use typical price to update sum of price*volume
--    local TP = candle.TP or ((candle.H + candle.L + candle.C)/3)
--    frame.PV = (frame.PV or 0) + TP*candle.V
--  end -- function updateFrame
  
--  local function processFrame(frame, set, outer_frame)
--    table.insert(set.po, frame.O)
--    table.insert(set.ph, frame.H)
--    table.insert(set.pl, frame.L)
--    table.insert(set.pc, frame.C)
--    table.insert(set.vol, frame.V)
--    -- Calculate VWAP
--    if set.vwap then
--      local vwap = (frame.V ~= 0) and (frame.PV / frame.V) or (frame.C)
--      table.insert(set.vwap, vwap)
--    end
--    -- Calculate true range
--    if set.ptr then
--      local ptr
--      if set.N > 0 then
--        local C1 = set.pc[set.N]
--        ptr = math.max(frame.H, C1) - math.min(frame.L, C1)
--      else ptr = frame.H - frame.L end
--      table.insert(set.ptr, ptr)
--    end
--    --
--    assert(frame.TO < frame.TC, 'Invalid frame time: TO='..tostring(frame.TO)..' TC='..tostring(frame.TC))
--    table.insert(set.to, frame.TO)
--    table.insert(set.tc, frame.TC)
--    --
--    if set.ol and set.oh and outer_frame then
--      table.insert(set.oh, outer_frame.H)
--      table.insert(set.ol, outer_frame.L)
--    end
--    --
--    local t = os.date('!*t', frame.TC)
--    if set.time then
--      local start_time = os.time({year=t.year,month=t.month,day=t.day,hour=10,min=0,sec=0})
--      local end_time = os.time({year=t.year,month=t.month,day=t.day,hour=23,min=50,sec=0})
--      local time = (frame.TC - start_time)/(end_time - start_time)
--      time = math.max(0, math.min(1, time))
--      table.insert(set.time, time)
--      if time <= 0.018 then
--        time = 0
--      end
--    end
--    --
--    if set.hour then
--      table.insert(set.hour, t.hour)
--    end
--    --
--    if set.day then
--      table.insert(set.day, t.day)
--    end
--    --
--    if set.month then
--      table.insert(set.month, t.month)
--    end
--    --
--    set.N = set.N + 1
--  end -- function processFrame
  
--  local function processCandle(candle)
--    local t = os.date('!*t', candle.TC)
--    assert(candle.TO < candle.TC, 'processCandle: Invalid candle time: TO='..tostring(candle.TO)..' TC='..tostring(candle.TC))
    
--    -- Add candle to array
--    if (frames.N > 0) and (hours.N > 0) and (days.N > 0) then
--      table.insert(index_candles_frames, frames.N)
--      table.insert(index_candles_hours, hours.N)
--      table.insert(index_candles_days, days.N)
--    end
    
--    -- Update frame
--    -- Check for frame completion
--    if (not frame_start_time) or (candle.TC - frame_start_time >= frame_interval) then
--      -- Process last frame
--      if frame and (hours.N > 0) and (days.N > 0) then
--        processFrame(frame, frames, hour)
--        table.insert(index_frames_hours, hours.N)
--        table.insert(index_frames_days, days.N)
--      end
--      -- Reset frame
--      frame_start_time = math.floor(candle.TO/frame_interval)*frame_interval
--      frame = { TO = frame_start_time, O = candle.O }
--    end -- if frame_interval
--    updateFrame(frame, candle)
    
--    -- Update hour frame
--    if (not last_hour) or (last_hour ~= t.hour) then
--      -- Process last hour frame
--      if hour and (days.N > 0) then
--        processFrame(hour, hours, day)
--        table.insert(index_hours_days, days.N)
--      end
--      -- Reset hour frame
--      hour = { TO = candle.TO, O = candle.O }
--      last_hour = t.hour
--    end
--    updateFrame(hour, candle)
    
--    -- Update day frame
--    if (not last_day) or (last_day ~= t.yday) then
--      -- Process last day frame
--      if day and first_month and (first_month ~= t.month) then processFrame(day, days, month) end
--      -- Reset day frame
--      day = { TO = candle.TO, O = candle.O }
--      last_day = t.yday
--    end
--    updateFrame(day, candle)
    
--    -- Update month frame
--    if not first_month then first_month = t.month end
--    if (not last_month) or (last_month ~= t.month) then
--      -- Reset month frame
--      month = { TO = candle.TO, O = candle.O }
--      last_month = t.month
--    end
--    updateFrame(month, candle)
--  end -- function processCandle
  
--  -- Cycle through records in a file
--  for i, row in ipairs(file) do
--    -- Print progress
--    if (i % 100 == 0) or (i == #file) then
--      io.write('\r'..tostring(i)..'/'..tostring(#file)); io.flush()
--    end
--    -- Process DATE
--    local date = tonumber(row[1])
--    assert(type(date)=='number', 'loadHistoryFile: failed to parse DATE: '..tostring(row[1]))
--    local year = math.floor(date/10000)
--    local month = math.floor((date-year*10000)/100)
--    local day = math.floor(date-year*10000-month*100)
--    if year < 2000 then year = 2000 + year end
--    -- Process TIME
--    local time = row[2]
--    assert(type(time)=='string', 'loadHistoryFile: failed to parse TIME: '..tostring(row[2]))
--    local hour, min = time:match("(%d+):(%d+)")
--    hour, min = tonumber(hour), tonumber(min)
--    assert(hour and min, 'loadHistoryFile: failed to parse hour and min: '..tostring(time))
--    -- Calculate TO and TC fields
--    local candle = {}
--    candle.TC = os.time( { year=year, month=month, day=day, hour=hour, min=min, sec=0 } )
--    if (candle_interval == 24*60*60) then
--      candle.TO = row.TC
--      candle.TC = (candle.TC + candle_interval)
--    else
--      candle.TO = (candle.TC - candle_interval)
--    end
--    candle.O = tonumber(row[3])
--    candle.H = tonumber(row[4])
--    candle.L = tonumber(row[5])
--    candle.C = tonumber(row[6])
--    candle.V = tonumber(row[7])
--    assert(candle.O and candle.H and candle.L and candle.C and candle.V,
--      'loadHistoryFile: failed to parse prices')
--    assert(candle.TO < candle.TC, 'Invalid candle1 time: TO='..tostring(candle.TO)..' TC='..tostring(candle.TC))
--    -- Process candle
--    processFrame(candle, candles)
--  end -- for ipairs(file)
--  io.write('\n')
  
--  for i = 1, candles.N do
--    local to, tc = candles.to[i], candles.tc[i]
--    assert(to < tc, 'Invalid candle2 time: TO='..tostring(to)..' TC='..tostring(tc))
--  end
  
--  convertArraysToTensors(candles)
  
--  for i = 1, candles.N do
--    local to, tc = candles.to[i], candles.tc[i]
--    assert(to < tc, 'Invalid candle3 time: TO='..tostring(to)..' TC='..tostring(tc))
--  end
  
--  -- Remove trends
--  if f_remove_trend then
--    -- Calculate slope of line of linear regression
--    local slope = covariance(candles.tc:double(), candles.pc:double()) / ((candles.tc:double():std(1, true)[1])^2)
--    removePriceTrend(candles, slope, candles.tc[1])
--  end
  
--  for i = 1, candles.N do
--    local to, tc = candles.to[i], candles.tc[i]
--    assert(to < tc, 'Invalid candle4 time: TO='..tostring(to)..' TC='..tostring(tc))
--  end
  
--  -- Process candles to fill in frames, hours and days
--  for i = 1, candles.N do
--    local candle = { O=candles.po[i], H=candles.ph[i], L=candles.pl[i], C=candles.pc[i],
--      V=candles.vol[i], TO=candles.to[i], TC=candles.tc[i] }
--    candle.TP = (candle.H + candle.L + candle.C)/3
--    assert(candle.TO < candle.TC, 'Invalid candle5 time: TO='..tostring(candle.TO)..' TC='..tostring(candle.TC))
--    processCandle(candle)
--  end -- for candles
--  -- Process last frame, hour and day
--  if frame.N and (frame.N > 0) then
--    processFrame(frame, frames, hour)
--    table.insert(index_frames_hours, hours.N)
--    table.insert(index_frames_days, days.N)
--  end
--  if hour.N and (hour.N > 0) then
--    processFrame(hour, hours, day)
--    table.insert(index_hours_days, days.N)
--  end
--  if day.N and (day.N > 0) then
--    processFrame(day, days, month)
--  end
  
--  -- Remove excess candles
--  local ncandles = #index_candles_frames
--  trimVectorsLeft(candles, candles.pc:nElement() - ncandles)
--  candles.N = ncandles
  
--  -- Prepare result
--  convertArraysToTensors(frames)
--  convertArraysToTensors(hours)
--  convertArraysToTensors(days)
  
--  local nframes = #index_frames_hours
--  local nhours = #index_hours_days
--  local ndays = days.pc:nElement()
  
--  local inputs = { candles=candles, frames=frames, hours=hours, days=days }
--  inputs.index_candles_frames = torch.LongTensor(index_candles_frames)
--  inputs.index_candles_hours = torch.LongTensor(index_candles_hours)
--  inputs.index_candles_days = torch.LongTensor(index_candles_days)
--  inputs.index_frames_hours = torch.LongTensor(index_frames_hours)
--  inputs.index_frames_days = torch.LongTensor(index_frames_days)
--  inputs.index_hours_days = torch.LongTensor(index_hours_days)
  
--  inputs.ncandles = ncandles
--  inputs.nframes = nframes
--  inputs.nhours = nhours
--  inputs.ndays = ndays
  
--  return inputs
--end -- function loadHistoryFile

-- Perform unit testing if running from console
local info = debug.getinfo(2)
if info and (info.name or (info.what ~= 'C')) then
  return Dataset
end


local function loadSeries(file_name, frame_interval)
  print('Loading '..tostring(file_name)..'...')
  
  local env = assert( Dataset.loadHistoryFile(file_name, frame_interval) )
  
  -- Process last frame, hour and day
  if env.frame.N and (env.frame.N > 0) then
    env:processFrame(env.frame, env.frames, env.hour)
    table.insert(env.index_frames_hours, env.hours.N)
    table.insert(env.index_frames_days, env.days.N)
    env.nframes = #env.frames.pc
  end
  if env.hour.N and (env.hour.N > 0) then
    env:processFrame(env.hour, env.hours, env.day)
    table.insert(env.index_hours_days, env.days.N)
    env.nhours = #env.hours.pc
  end
  if env.day.N and (env.day.N > 0) then
    env:processFrame(env.day, env.days, env.month)
    env.ndays = #env.days.pc
  end
  
  return env:exportSeries()
end -- function loadSeries

local function main()
  local Env = dofile('env.lua')
  assert(type(Env) == 'table' and  type(Env.universalSave) == 'function',
    'env is not loaded')
  
  local work_dir = arg[1]
  if work_dir then
    assert( lfs.chdir(work_dir) )
    print('Changed dir to '..work_dir)
  end
  require 'config'
  assert(History_File_Prefix and Dataset_File and Frame_Interval,
    'Invalid config file!')
  
  -- Initialize Torch
  math.randomseed( os.time() )
  --torch.manualSeed(1)
  torch.setdefaulttensortype('torch.FloatTensor')
  torch.setnumthreads(2)
  
  print('Searching for history files...')
  local files, reason = Dataset.findHistoryFiles('../history', History_File_Prefix)
  if (not files) or (#files <= 0) then error(reason) end
  print('Found '..tostring(#files)..' files:')
  for _, file_name in ipairs(files) do print(' '..tostring(file_name)) end
  
  local limit = 24
  print('Loading latest '..tostring(limit)..' files...')
  
  local dataset = {}
  for i = math.max(1, #files-limit+1), #files do
    local file_name = files[i]
    local series = assert( loadSeries(file_name, Frame_Interval) )
    print(' loaded '..tostring(series.ncandles)..' candles, '..tostring(series.nframes)..' frames, '
      ..tostring(series.nhours)..' hours, '..tostring(series.ndays)..' days')
    table.insert(dataset, series)
  end
  
  print('Saving dataset to '..tostring(Dataset_File)..' file...')
  Env.universalSave(dataset, Dataset_File, 'binary')
end -- function main

main()
