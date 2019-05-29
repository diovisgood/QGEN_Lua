local torch = require 'torch'

local Processor = require 'processor'
local Account = require 'account'

require 'env'

local Score = {
  prototypes = {},
  signal_invariance_max = 0.95,
  prototype_corr_max = 0.9,
  sequence_max = 1000,
  n_trades_min = 25,
  n_trades_max = 500,
  n_trades_std = 5,
  n_operations_min = 10,
  n_operations_max = 100,
  n_operations_std = 20,
  max_offset_frames_mean = 2500,
  max_offset_frames_std = 1500,
  max_offset_hours_mean = 400,
  max_offset_hours_std = 300,
  max_offset_days_mean = 25,
  max_offset_days_std = 15,
  average_function = 'rma', -- 'sma', 'wma' or 'rma'
  profile_result_threshold = 0.15,
}

local Score_Huge = 1000000
local Score_Crucial = 3500
local Score_Important = 100
local Score_Regular = 10
local Score_Minor = 2

local function correlation(a, b)
  local mean_a, mean_b = a:mean(), b:mean()
  local da = torch.add(a, -mean_a)
  local db = torch.add(b, -mean_b)
  local norm = da:norm() * db:norm()
  if (norm == 0) then return 0 end
  --local result = torch.cmul(da, db):sum() / math.sqrt( torch.cmul(da,da):sum() * torch.cmul(db,db):sum() )
  local result = torch.dot(da, db) / norm
  return result
end -- function correlation

local function sigmoid(x, half, std)
  return 1 / (1 + math.exp( 5*(half-x)/std ))
end -- function sigmoid

local function gaussian(x, mean, std)
  return math.exp(- ((x - mean)^2) / (2*std^2))
end -- function gaussian

local function linearToParabola(x, border, k)
  if (x < border) then return (k*x) end
  return (k*(x^2)) / border
end -- function linearToParabola

local function leftLimit(x, limit, std)
  if (x <= limit) then return math.huge end
  return (std/(x - limit) - 1)
end -- function leftLimit

local function rightLimit(x, limit, std)
  if (x >= limit) then return math.huge end
  return (std/(limit - x) - 1)
end -- function rightLimit

local function plato(x, min, max, std)
  return (x < ((min+max)/2)) and sigmoid(x, min, std) or (1 - sigmoid(x, max, std))
end -- function plato

local function range(x, min, max, std)
  if (x < min + std) then
    return -((x - min - std)^2) / (std^2)
  elseif (x > max - std) then
    return -((x - max + std)^2) / (std^2)
  end
  return 0
end -- function range

local function isNaNorInf(x)
  return (x ~= x) or (math.abs(x) == math.huge)
end -- function isNaNorInf

local function addTableValues(dst, src, m)
  for k, v in pairs(src) do
    if type(v) == 'number' then
      dst[k] = (dst[k] or 0) + v*m
    end
  end
end -- function addTableValues

--local function uniteProfiles(dst, src, k)
--  for i, src_profile in ipairs(src) do
--    if not dst[i] then dst[i] = {} end
--    local dst_profile = dst[i]
--    for _, v in ipairs(src_profile) do table.insert(dst_profile, v * k) end
--  end
--end -- function uniteProfiles

--local function init()
--  require 'config'
--  assert(Dataset_File, 'Score:init: Invalid config file!')
  
--  print('Loading Dataset...')
--  Dataset = universalLoad(Dataset_File, 'binary')
--  assert(Dataset, 'Score:init: Failed to load Dataset from '..tostring(Dataset_File))
--  print('Loaded Dataset from '..tostring(Dataset_File))
--  printInfo('Dataset', Dataset)
--  Data.addExpand(Dataset)
--end -- function init

--local function profileTest(x, series)
--  local last_day
--  local n = series.ncandles
--  local position = 0
--  local position_price, position_time
--  local profile_longs, profile_shorts = {}, {}
--  local candles = series.candles
--  local last_signal
  
--  if (x:nElement() ~= n) then
--    x = series:expand(x, candles.pc)
--    assert(x:nElement() == series.ncandles, 'Score:profileTest: Failed to expand vectors!')
--  end
  
--  for i = 2, n do
--    local signal = x[i-1]
--    if last_signal and (last_signal*signal > 0) then signal = 0 end
--    local t = os.date('*t', candles.tc[i])
--    if last_day and (last_day ~= t.yday) then
--      position = 0
--      position_time = nil
--      last_signal = nil
--    else
--      if (signal ~= 0) and (signal*position <= 0) then
--        position = (signal > 0 and 1 or -1)
--        position_price = candles.po[i]
--        position_time = candles.to[i]
--        last_signal = signal
--      end
--    end
--    if position_time and (position ~= 0) then
--      local duration = math.floor(0.5 + (candles.tc[i] - position_time)/60)
--      assert(duration > 0, 'profileTest: Invalid duration: '..tostring(duration)..' tc='..tostring(candles.tc[i])..' to='..tostring(candles.to[i])..' i='..tostring(i))
--      assert(duration < 14*60*60, 'profileTest: Invalid duration: '..tostring(duration)..' tc='..tostring(candles.tc[i])..' pos='..tostring(position_time)..' i='..tostring(i))
--      local profile = (position > 0) and profile_longs or profile_shorts
--      for d = #profile+1, duration do profile[d] = {} end
--      if (duration <= #profile + 1) then
--        if not profile[duration] then profile[duration] = {} end
--        local r = position * 100 * (candles.pc[i] - position_price) / position_price
--        table.insert(profile[duration], r)
--      end
--    end
--    last_day = t.yday
--  end -- for
  
--  return profile_longs, profile_shorts
--end -- function profileTest

--local Gaussian_Kernels = {}

--local function getGaussianKernel(range)
--	range = math.ceil(range)	-- kernel will have a middle cell, and range cells on either side
--  local matrix = Gaussian_Kernels[range]
--  if matrix then return matrix end
  
--	matrix = {}
--	local sigma = range/2  -- apparently this is all you need to get a good approximation
--	local norm = 1.0 / (math.sqrt(2*math.pi) * sigma)	-- normalization constant makes sure total of matrix is 1
--	local coeff = 2*sigma*sigma	-- the bit you divide x^2 by in the exponential
--	local total = 0
--	for x = -range, range do
--		local g = norm * math.exp( -x*x / coeff )
--		matrix[x + range + 1] = g
--		total = total + g
--	end
--	for i = 1, 2*range+1	do --rescale things to get a total of 1, because of discretisation error
--		matrix[i] = matrix[i] / total
--	end
--  Gaussian_Kernels[range] = matrix
--	return matrix
--end -- function getGaussianKernel

--local function applyGaussianFilterToStat(stat, min, max, range, step)
--  -- Get smoothing kernel
--  local kernel = getGaussianKernel(range)
--  -- Apply filter
--  min = min or 1
--  max = max or #stat
--  step = step or 1
--  local output = {}
--  local maxv
--  for x = min, max, step do
--    local sum = 0
--    for j = -range, range do
--      local xj = x + j*step
--      local v = stat[xj] or 0
--      sum = sum + v * kernel[j+range+1]
--    end
--    output[x] = sum
--    if (not maxv) or (maxv < sum) then maxv = sum end
--  end
--  return output, maxv
--end -- function applyGaussianFilterToStat

---- Find local minimums and maximums in statistics
--local function calculateStatExtremums(stat, min, max, step, threshold, sign)
--  local levels = {}
--  local lowest_v, lowest_x = (stat[min] or 0), min
--  local highest_v, highest_x = lowest_v, min
--  -- Scan price diapazone from minp to maxp and find local minimums and maximums
--  for x = min, max, step do
--    local v = (stat[x] or 0)
--    -- Check for new max level
--    if highest_v and (highest_v - v >= highest_v*threshold) then
--      -- Local maximum
--      if (not sign) or (sign > 0) then
--        local level = { x=highest_x, max=x, v=highest_v, sign=1 }
--        table.insert(levels, level)
--        -- Find left border for level and calculate area
--        local area = v*step
--        for p = highest_x-step, min, -step do
--          local vp = stat[p]
--          area = area + vp*step
--          if (highest_v - vp >= highest_v*threshold) then
--            level.min = p
--            break
--          end
--        end -- for p
--        level.area = area
--        if not level.min then level.min = min end
--      end -- if sign
--      -- Reset lowest
--      lowest_v, lowest_x = v, x
--      highest_v, highest_x = nil, nil
--    end
--    -- Check for new min level
--    if lowest_v and (v - lowest_v >= lowest_v*threshold) then
--      -- Local minimum
--      if (not sign) or (sign < 0) then
--        local level = { x=lowest_x, max=x, v=lowest_v, sign=-1 }
--        table.insert(levels, level)
--        -- Find left border for level and calculate area
--        local area = v*step
--        for p = lowest_x-step, min, -step do
--          local vp = stat[p]
--          area = area + vp*step
--          if (vp - lowest_v >= lowest_v*threshold) then
--            level.min = p
--            break
--          end
--        end -- for p
--        level.area = area
--        if not level.min then level.min = min end
--      end -- if sign
--      -- Reset highest
--      highest_v, highest_x = v, x
--      lowest_v, lowest_x = nil, nil
--    end
--    -- Update highest and lowest
--    if lowest_v and (lowest_v > v) then
--      lowest_v, lowest_x = v, x
--    end
--    if highest_v and (highest_v < v) then
--      highest_v, highest_x = v, x
--    end
--  end -- for
--  return levels
--end -- function calculateStatExtremums

--local function analyzeProfile(profile, threshold, file_name)
--  local file
--  if file_name then
--    file = io.open(file_name, 'a')
--    if not file then file = io.open(file_name, 'w') end
--    if file then file:write('mean;std;min\r\n') end
--  end
--  local mean, std, min = {}, {}, {}
--  for i, results in ipairs(profile) do
--    if (#results > 1) then
--      local x = torch.Tensor(results)
--      mean[i] = x:mean()
--      std[i] = x:std(1, true)[1]
--      min[i] = mean[i] - std[i]
--    end
--    if file then file:write(tostring(mean[i] or 0)..';'..tostring(std[i] or 0)..';'..tostring(min[i] or 0)..'\r\n') end
--  end -- for profile
--  if file then file:close() end
--  local filtered_mean = applyGaussianFilterToStat(mean, 1, #mean, 2)
--  local filtered_min = applyGaussianFilterToStat(min, 1, #min, 2)
  
--  local mean_extremumus = calculateStatExtremums(filtered_mean, 1, #filtered_mean, 1, threshold, 1)
--  local min_extremumus = calculateStatExtremums(filtered_min, 1, #filtered_min, 1, threshold, 1)
--  if (#mean_extremumus + #min_extremumus <= 0) then return end
  
--  table.sort(mean_extremumus, function(a,b) return a.area > b.area end)
--  table.sort(min_extremumus, function(a,b) return a.area > b.area end)
  
--  local result = {}
--  local x
--  if min_extremumus[1] then
--    x = min_extremumus[1].x
--    result[x] = min[x]
--  end
--  if mean_extremumus[1] then
--    x = mean_extremumus[1].x
--    if not result[x] then result[x] = mean[x] end
--  end
--  return result
--end -- function analyzeProfile

local function tradeTestOld(x, series, duration)
  local n = series.nframes
  local candles = series.frames
  local account = Account.init()
  
  if (x:nElement() ~= n) then
    x = series:expand(x, candles.pc)
    assert(x:nElement() == n, 'Score:tradeTest: Failed to expand vectors!')
  end
  
  for i = 2, n do
    local signal = x[i-1]
    signal = (signal > 0) and 1 or (signal < 0) and -1 or 0
    local po, pc, pc1 = candles.po[i], candles.pc[i], candles.pc[i-1]
    local to, tc, tc1 = candles.to[i], candles.tc[i], candles.tc[i-1]
    if account.last_signal and (account.last_signal*signal > 0) then signal = 0 end
    local t = os.date('*t', tc)
    if account.last_day and (account.last_day ~= t.yday) then
      if (account.position ~= 0) then
        account:closePosition(pc1, tc1)
      end
      account.last_signal = nil
    else
      if (signal ~= 0) and (signal*account.position <= 0) then
        if (signal > 0) then
          account:longPosition(po, to)
        else
          account:shortPosition(po, to)
        end
        account.last_signal = signal
      end
    end
    if duration and (duration > 0) and (account.position ~= 0)
    and (math.floor(0.5 + (tc - account.enter_date)/60) >= duration) then
      account:closePosition(pc, tc)
    end
    account.last_day = t.yday
  end -- for
  account:closePosition(candles.pc[n], candles.tc[n])
  
  return account:makeReport(candles.to[1], candles.tc[n])
end -- function tradeTest

local function tradeTest2(x, series)
  local n = series.nframes
  local candles = series.frames
  local account = Account.init()
  
  if (x:nElement() ~= n) then
    x = series:expand(x, candles.pc)
    assert(x:nElement() == n, 'Score:tradeTest: Failed to expand vectors!')
  end
  
  for i = 1, n do
    local signal = x[i]
    signal = (signal > 0) and 1 or (signal < 0) and -1 or 0
    if (account.position ~= signal) then
      account:trade(signal - account.position, candles.pc[i], candles.tc[i])
    end
  end -- for
  account:closePosition(candles.pc[n], candles.tc[n])
  
  return account:makeReport(candles.to[1], candles.tc[n])
end -- function tradeTest2

local function tradeTest(x, series)
  local n = series.ncandles
  local candles = series.candles
  local account = Account.init()
  
  if (x:nElement() ~= n) then
    x = series:expand(x, candles.pc)
    assert(x:nElement() == n, 'Score:tradeTest: Failed to expand vectors!')
  end
  
  for i = 2, n do
    local signal = x[i-1]
    signal = (signal > 0) and 1 or (signal < 0) and -1 or 0
    local t = os.date('!*t', candles.tc[i])
    --if account.last_day and (account.last_day ~= t.yday) then
    if (t.hour >= 20) and (t.min >= 49) then
      if (account.position ~= 0) then
        account:closePosition(candles.pc[i-2], candles.tc[i-2])
      end
    elseif (t.hour >= 07) and (t.min >= 10) then
      if (account.position ~= signal) then
        account:trade(signal - account.position, candles.pc[i], candles.tc[i])
      end
    end
    account.last_day = t.yday
  end -- for
  account:closePosition(candles.pc[n], candles.tc[n])
  return account:makeReport(candles.to[1], candles.tc[n])
end -- function tradeTest

local function tradeTestDurations(x, series, durations)
  local last_day
  local n = series.nframes
  local candles = series.frames
  local accounts = {}
  
  for d, _ in pairs(durations) do
    accounts[d] = Account.new()
  end
  
  if (x:nElement() ~= n) then
    x = series:expand(x, candles.pc)
    assert(x:nElement() == n, 'Score:tradeTestDurations: Failed to expand vectors!')
  end
  
  for i = 2, n do
    local signal = x[i-1]
    local po, pc, pc1 = candles.po[i], candles.pc[i], candles.pc[i-1]
    local to, tc, tc1 = candles.to[i], candles.tc[i], candles.tc[i-1]
    local t = os.date('*t', tc)
    if last_day and (last_day ~= t.yday) then
      -- Reset position at the end of a day
      for d, account in pairs(accounts) do
        if (account.position ~= 0) then
          account:closePosition(pc1, tc1)
        end
        account.last_signal = nil
      end -- for accounts
    else
      -- Enter position
      for d, account in pairs(accounts) do
        local s = signal
        if account.last_signal and (account.last_signal*signal > 0) then s = 0 end
        if (s ~= 0) and (s*account.position <= 0) then
          if (s > 0) then
            account:longPosition(po, to)
          else
            account:shortPosition(po, to)
          end
          account.last_signal = s
        end
      end -- for accounts
    end
    -- Close position due to limited duration
    for d, account in pairs(accounts) do
      if (d > 0) and (account.position ~= 0)
      and (math.floor(0.5 + (tc - account.enter_date)/60) >= d) then
        account:closePosition(pc, tc)
      end
    end -- for accounts
    last_day = t.yday
  end -- for candles
  
  -- Prepase trade reports for different durations
  local reports = {}
  for d, account in pairs(accounts) do
    account:closePosition(candles.pc[n], candles.tc[n])
    reports[d] = account:makeReport(candles.to[1], candles.tc[n])
  end
  
  return reports
end -- function tradeTestDurations

function Score:getPrototypesCorrelationMatrix()
  local n = #(self.prototypes)
  local M = torch.zeros(n, n)
  for i, prototypeA in ipairs(self.prototypes) do
    for j = i, #(self.prototypes) do
      if i == j then
        M[i][j] = 1
      elseif (type(prototypeA.vectors) == 'table') then
        local prototypeB = self.prototypes[j]
        if (type(prototypeB.vectors) == 'table') then
          local corr, mean_corr, max_corr = 0, 0, nil
          for d, series in ipairs(self.dataset) do
            local a, b = prototypeA.vectors[d], prototypeB.vectors[d]
            if a:nElement() ~= b:nElement() then
              a, b = series:expand(a, b)
              assert(a:nElement() == b:nElement(),
                'Score:getPrototypesCorrelationMatrix: Failed to expand vectors!')
            end
            corr = correlation(a, b)
            mean_corr = mean_corr + corr
            if (not max_corr) or (max_corr < corr) then max_corr = corr end
          end -- for dataset
          mean_corr = mean_corr / #self.dataset
          M[i][j], M[j][i] = max_corr, max_corr
        end -- if vectors
      end -- if i == j
    end -- for prototypes
  end -- for prototypes
  return M
end -- function Score:getPrototypesCorrelationMatrix

function Score:tradeTestPrototypes()
  local result = {}
  for s, series in ipairs(self.dataset) do
    local n = series.nframes
    local candles = series.frames
    local account = Account.new { position = 0 }
    local states = {}
    local last_day
    
    -- Preload signal vectors
    local vectors = {}
    for p, entity in ipairs(self.prototypes) do
      local x = entity.vectors and entity.vectors[s] or torch.zeros(n)
      if (x:nElement() ~= n) then
        x = series:expand(x, candles.pc)
        assert(x:nElement() == n, 'Score:tradePrototypes: Failed to expand vectors!')
      end
      vectors[p] = x
      states[p] = { position = 0 }
    end -- for Prototypes
    
    -- Cycle through candles
    for i = 1, n do
      local tc = candles.tc[i]
      local t = os.date('*t', tc)
      if last_day and (last_day ~= t.yday) then
        -- Reset states at the end of a day
        for p, _ in ipairs(self.prototypes) do
          local state = states[p]
          state.position = 0
          state.enter_date = nil
          state.last_signal = nil
        end
        -- Reset position
        if (account.position ~= 0) then
          account:closePosition(candles.pc[i-1], candles.tc[i-1])
        end
      else
        -- Construct united signal
        local desired_position = 0
        for p, entity in ipairs(self.prototypes) do
          -- Get prototype signal
          local state = states[p]
          local signal = vectors[p][i]
          signal = (signal == 0) and 0 or (signal > 0) and 1 or -1
          if state.last_signal and (state.last_signal*signal > 0) then signal = 0 end
          -- Calculate prototype position based on duration
          if entity.best_duration and (entity.best_duration > 0) and (state.position ~= 0)
          and (math.floor(0.5 + (tc - state.enter_date)/60) >= entity.best_duration) then
            state.position = 0
            state.enter_date = nil
          end
          -- Calculate prototype position based on signal
          if (signal ~= 0) and (signal*state.position <= 0) then
            state.position = signal
            state.enter_date = tc
            state.last_signal = signal
          end
          desired_position = desired_position + state.position
        end -- for Prototypes
        -- Update position at the beginning of a candle
        if (account.position ~= desired_position) then
          account:trade(desired_position - account.position, candles.pc[i], tc)
        end
--        -- Construct united signal
--        local desired_position_open, desired_position_close = 0, 0
--        for p, entity in ipairs(self.prototypes) do
--          -- Get prototype signal
--          local state = states[p]
--          local signal = vectors[p][i-1]
--          signal = (signal == 0) and 0 or (signal > 0) and 1 or -1
--          if state.last_signal and (state.last_signal*signal > 0) then signal = 0 end
--          -- Calculate prototype position at the beginning of a candle
--          if (signal ~= 0) and (signal*state.position <= 0) then
--            state.position = signal
--            state.enter_date = to
--            state.last_signal = signal
--          end
--          desired_position_open = desired_position_open + state.position
--          -- Calculate prototype position at the end of a candle
--          if entity.best_duration and (entity.best_duration > 0) and (state.position ~= 0)
--          and (math.floor(0.5 + (tc - state.enter_date)/60) >= entity.best_duration) then
--            state.position = 0
--            state.enter_date = nil
--          end
--          desired_position_close = desired_position_close + state.position
--        end -- for Prototypes
--        -- Update position at the beginning of a candle
--        if (account.position ~= desired_position_open) then
--          account:trade(desired_position_open - account.position, candles.po[i], to)
--        end
--        -- Update position at the end of a candle
--        if (account.position ~= desired_position_close) then
--          account:trade(desired_position_close - account.position, candles.pc[i], tc)
--        end
      end
      last_day = t.yday
    end -- for candles
    account:closePosition(candles.pc[n], candles.tc[n])
    -- Construct report
    result[s] = account:makeReport(candles.to[1], candles.tc[n])
  end -- for dataset
  return result
end -- function Score:tradeTestPrototypes

local SMA_Tables = {}
local WMA_Tables = {}
local RMA_Tables = {}

function Score:getAverageCoefficients(n)
  local k
  if self.average_function and (self.average_function:lower() == 'wma') then
    -- WMA:
    k = WMA_Tables[n]
    if not k then
      k = {}
      for i = 1, n do k[i] = i * (2 / (n^2 + n)) end
      WMA_Tables[n] = k
    end
    return k
  elseif self.average_function and (self.average_function:lower() == 'rma') then
    -- RMA:
    k = RMA_Tables[n]
    if not k then
      k = {}
      local sum = 0
      for i = 1, n do
        k[i] = math.pow(i + 10, 1 / 1.50) -- 1 / 1.20
        sum = sum + k[i]
      end
      for i = 1, n do k[i] = k[i] / sum end
      RMA_Tables[n] = k
    end
    return k
  end
  -- SMA:
  k = SMA_Tables[n]
  if not k then
    k = {}
    for i = 1, n do k[i] = (1 / n) end
    SMA_Tables[n] = k
  end
  return k
end -- function Score:getAverageCoefficients

function Score:calculate(entity)
  assert(type(entity) == 'table' and type(entity.sequence) == 'table',
    'Score:calculate: Invalid entity specified!')
  
  local score = 0
  local annual_rates = {}
  local avg_stat, avg_report = {}, {}
  local max_proto_corr
  local max_offset_frames, max_offset_hours, max_offset_days, si
  local signal_pos, signal_neg, signal_zero = 0, 0, 0
  local total_profile_longs, total_profile_shorts = {}, {}
  local vectors = {}
  
  -- Prepare coefficients to calculate WMA
  local xMA = self:getAverageCoefficients(#self.dataset)
  
  for i, series in ipairs(self.dataset) do
    -- Execute entity using Processor and inputs
    local stack = {}
    local stat, exec, text = Processor:execute(entity.sequence, series, stack, (i == 1))
    if not stat then return -Score_Huge, 'No stat after Processor:execute()' end
    if i == 1 then
      entity.exec = exec
      entity.text = text
    end
    
    -- Check for result
    if #stack <= 0 then return -Score_Huge, 'No result in stack after Processor:execute()' end
    if #stack > 1 then score = score - Score_Important*(#stack - 1) end
    
    -- Read value
    local x = stack[#stack]
    if not torch.isTensor(x) then return -Score_Huge, 'Result is not a vector' end
    
    -- Update max offsets
    max_offset_frames = max_offset_frames or stat.maxOffset[ series.nframes ]
    max_offset_hours = max_offset_hours or stat.maxOffset[ series.nhours ]
    max_offset_days = max_offset_days or stat.maxOffset[ series.ndays ]
    
    -- Calculate starting index si
    local n = x:nElement()
    if not si then
      si = math.max(2, (stat.maxOffset[n] or 0) + 1)
      -- Update max offsets and starting index accordingly
      if n == series.nframes then
        if max_offset_hours then
          while (si < series.nframes) and (series.index_frames_hours[si] <= max_offset_hours) do
            si = si + 1
          end
        end
        if max_offset_days then
          while (si < series.nframes) and (series.index_frames_days[si] <= max_offset_days) do
            si = si + 1
          end
        end
      elseif n == series.nhours then
        if max_offset_days then
          while (si < series.nhours) and (series.index_hours_days[si] <= max_offset_days) do
            si = si + 1
          end
        end
      elseif n == series.ndays then
      else
        error('Score:calculate: Invalid argument size: '..tostring(x:nElement()))
      end
    end -- if not si
    
    -- Clear unreliable signals from x up to starting index si
    x:sub(1, math.min(x:nElement(), si-1)):zero()
    local type_x = torch.type(x)
    local sign_x = torch.sign(x)
    
    -- Check x for NaN of Inf
    -- Analyze min, max and mean values in x
    local min, max
    local pos, neg, zero = 0, 0, 0
    for j = si, n do
      local v = x[j]
      if (v ~= v) then -- isNaNorInf(v) then
        return -Score_Huge, 'Result contains NaN' -- or Inf'
      end
      if (not min) or (min > v) then min = v end
      if (not max) or (max < v) then max = v end
      if (v == 0) then zero = zero + 1 end
      if (v > 0) then pos = pos + 1 end
      if (v < 0) then neg = neg + 1 end
    end
    pos = pos / (n-si+1)
    neg = neg / (n-si+1)
    zero = zero / (n-si+1)
    signal_pos = signal_pos + pos*xMA[i]
    signal_neg = signal_neg + neg*xMA[i]
    signal_zero = signal_zero + zero*xMA[i]
    
    -- Check min, max, pos, neg values for variance
    if (not min) or (not max) or (min == 0 and max == 0) or (min*max > 0)
    or (pos > self.signal_invariance_max) or (neg > self.signal_invariance_max) then
      return -Score_Huge, 'Result is not variative: min='..tostring(min)..' max='..tostring(max)..' pos='..tostring(pos)..' neg='..tostring(neg)
    end
    
    -- Save signal vector sign_x
    vectors[i] = sign_x
    
    -- Estimate maximum correlation (positive or negative) with prototype vectors
    for _, entity in ipairs(self.prototypes) do
      local b = (type(entity.vectors) == 'table') and entity.vectors[i]
      if (type_x == torch.type(b)) then
        local a = sign_x
        if a:nElement() ~= b:nElement() then
          a, b = series:expand(a, b)
          assert(a:nElement() == b:nElement(), 'Score:calculate: Failed to expand vectors!')
        end
        local corr = math.abs( correlation(a, b) )
        if (not isNaNorInf(corr)) and ((not max_proto_corr) or (max_proto_corr < corr)) then
          max_proto_corr = corr
        end
      end
    end -- for self.prototypes
    -- Penalty for entities that are already present in Prototypes
    if max_proto_corr
    and (isNaNorInf(max_proto_corr) or (max_proto_corr > self.prototype_corr_max)) then
      return -Score_Huge, 'Correlation with prototypes: max_proto_corr: '..tostring(max_proto_corr)
    end
    
    -- Update avg_stat
    addTableValues(avg_stat, stat, xMA[i])
    
    -- Perform trade test for best duration
    local report = tradeTest(sign_x, series)
    if (not report) or (not report.annual_rate) or isNaNorInf(report.annual_rate)
    or (not report.max_drawdown_percent) or isNaNorInf(report.max_drawdown_percent) then
      return -Score_Huge, 'Failed tradeTest'
    end
    -- Update average report
    addTableValues(avg_report, report, xMA[i])
    -- Store annual rate
    annual_rates[i] = report.annual_rate
    -- Update max drawdown percent
    if (not avg_report.max_drawdown_percent)
    or (avg_report.max_drawdown_percent < report.max_drawdown_percent) then
      avg_report.max_drawdown_percent = report.max_drawdown_percent
    end
    
--    -- Perform trade test for all durations at once
--    local reports = tradeTestDurations(sign_x, series, durations)
--    if not reports then return -Score_Huge, 'Failed to tradeTestDurations' end
    
--    -- Combine trade reports of different durations
--    for d, duration in pairs(durations) do
--      -- Get report for current duration
--      local report = reports[d]
--      if (not report) or (not report.annual_rate) or isNaNorInf(report.annual_rate)
--      or (not report.max_drawdown_percent) or isNaNorInf(report.max_drawdown_percent) then
--        return -Score_Huge, 'Failed tradeTestDurations'
--      end
--      report.trades = nil
--      -- Store annual rate
--      if not duration.annual_rates then duration.annual_rates = {} end
--      duration.annual_rates[i] = report.annual_rate
--      -- Update average report
--      if not duration.report then duration.report = {} end
--      addTableValues(duration.report, report, xMA[i])
--      -- Update max drawdown percent
--      if (not duration.max_drawdown_percent) or (duration.max_drawdown_percent < report.max_drawdown_percent) then
--        duration.max_drawdown_percent = report.max_drawdown_percent
--      end
--    end -- for durations
  
  end -- for series in dataset
  
  -- Calculate std of annual_rate
  local annual_rate_std = 0
  local avg_annual_rate = avg_report.annual_rate
  for i, rate in ipairs(annual_rates) do
    annual_rate_std = annual_rate_std + xMA[i] * (rate - avg_annual_rate)^2
  end
  annual_rate_std = math.sqrt(annual_rate_std)
  avg_report.annual_rate_std = annual_rate_std
  avg_report.rate = (avg_annual_rate - annual_rate_std)
  avg_report.profit_factor = (avg_report.gross_loss>0 and (avg_report.gross_profit/avg_report.gross_loss))

--  -- Analyze average trade reports for different durations
--  for d, duration in pairs(durations) do
--    local report = duration.report
--    -- Calculate std of annual_rate
--    local std = 0
--    local avg_annual_rate = report.annual_rate
--    for i, rate in ipairs(duration.annual_rates) do
--      std = std + xMA[i] * (rate - avg_annual_rate)^2
--    end
--    std = math.sqrt(std)
--    --local r = torch.Tensor(duration.report.annual_rates)
--    report.annual_rate_std = std -- r:std(1, true)[1]
--    report.rate = (avg_annual_rate - std)
--    report.profit_factor = (report.gross_loss>0 and (report.gross_profit/report.gross_loss))
--    report.recovery_factor = (report.annual_rate/(duration.max_drawdown_percent+1e-5))
--    report.max_drawdown_percent = duration.max_drawdown_percent
    
--    if (not avg_report.rate) or (avg_report.rate < report.rate) then
--      avg_report = report
--      best_duration = d
--    end
--  end -- for durations
  
  -- Calculate final score
  score = score + Score_Crucial*100*avg_report.rate
  score = score - Score_Crucial*20*avg_report.max_drawdown_percent
  
  -- y=2500*(1/(1-x) - 1)
  --score = score - Score_Important*25*(1/(1 - math.abs(max_proto_corr or 0)) - 1)
  score = score - Score_Important*25* rightLimit(math.abs(max_proto_corr or 0), 1, 1)
  
  score = score - Score_Important*25* leftLimit(avg_report.profit_factor or 1, 0.2, 3.8)
  
  --score = score + Score_Regular*avg_stat.nOperations
  --if (avg_stat.nOperations <= 0) then
  --  score = score - Score_Crucial
  --end
  score = score + Score_Regular*
    range(avg_stat.nOperations, self.n_operations_min, self.n_operations_max, self.n_operations_std)
  
  score = score - Score_Important*avg_stat.nErrorsStackOut
  score = score - Score_Regular*avg_stat.nErrorsOutOfBounds
  score = score - Score_Regular*avg_stat.nErrorInvalidArguments
  score = score - Score_Regular*avg_stat.nErrorsNotEnoughArguments
  
  local avg_n_trades = avg_report.n_trades or 0
  score = score + Score_Important*self.n_trades_std*
    range(avg_n_trades, self.n_trades_min, self.n_trades_max, self.n_trades_std)
  
  local len = #(entity.sequence)
  score = score - Score_Minor*linearToParabola(len, self.sequence_max, 1)
  
  if max_offset_frames then
    score = score - Score_Important*10*sigmoid(max_offset_frames,
      self.max_offset_frames_mean, self.max_offset_frames_std)
  end
  if max_offset_hours then
    score = score - Score_Important*10*sigmoid(max_offset_hours,
      self.max_offset_hours_mean, self.max_offset_hours_std)
  end
  if max_offset_days then
    score = score - Score_Important*10*sigmoid(max_offset_days,
      self.max_offset_days_mean, self.max_offset_days_std)
  end
  if isNaNorInf(score) then
    return -Score_Huge, 'Failed to calculate score: '..tostring(score)
  end
  
  entity.score = score
  entity.rate = avg_report.rate
  entity.avg_stat = avg_stat
  entity.avg_report = avg_report
  entity.annual_rate = avg_report.annual_rate
  entity.annual_rate_std = avg_report.annual_rate_std
  entity.max_drawdown_percent = avg_report.max_drawdown_percent
  entity.profit_factor = avg_report.profit_factor
  entity.max_proto_corr = max_proto_corr
  entity.max_offset_frames = max_offset_frames
  entity.max_offset_hours = max_offset_hours
  entity.max_offset_days = max_offset_days
  entity.start_index = si
  entity.signal_pos = signal_pos
  entity.signal_neg = signal_neg
  entity.signal_zero = signal_zero
  entity.vectors = vectors
  
  return score
end -- function Score:calculate

--init()

return Score
