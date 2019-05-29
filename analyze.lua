local torch = require 'torch'

package.path = './?.lua;' .. package.path

local Env = dofile 'env.lua'
local Data = dofile 'data.lua'
local Syntax = dofile 'syntax.lua'
local Account = dofile 'account.lua'
local Processor = dofile 'processor.lua'
local Species = dofile 'species.lua'

local Prototypes = {}

function Prototypes:load()
  local index = assert( Species.getIndex() )
  print('Index has '..tostring(#index)..' records')
  index:close()
  self.weight_sum = 0
  self.long_weight_sum = 0
  self.short_weight_sum = 0
  for i, info in ipairs(index) do
    local specie, name
    io.write('Loading '..tostring(info.name)..'...')
    if (type(info.annual_rate) == 'number') and (info.annual_rate > 0)
    --and (type(info.profit_factor) == 'number') and (info.profit_factor >= 1.5)
    and (i <= 50) then
      local entity = Syntax:entity(info.best_code)
      if entity.sequence then
        entity.weight = (info.profit_factor or 1)^3
        self.weight_sum = self.weight_sum + entity.weight
        if (info.signal_pos or 0) > 0 then
          self.long_weight_sum = self.long_weight_sum + entity.weight
        end
        if (info.signal_neg or 0) > 0 then
          self.short_weight_sum = self.short_weight_sum + entity.weight
        end
        table.insert(self, entity)
        print('Yes')
      else
        print('Err')
      end
    else
      print('Neg')
    end
  end -- for files
  if #self <= 0 then return nil, 'Failed to load any file!' end
  for _, entity in ipairs(self) do
    entity.weight = (entity.weight / self.weight_sum)
  end
  return self
end -- function Prototypes:load

function Prototypes:tradeSeries(series, trading_amount)
  trading_amount = trading_amount or #self
  local n = series.ncandles
  local candles = series.candles
  local account = Account.init { position = 0 }
  local states = {}
  local last_day
  
  -- Execute prototypes and get signal vectors
  local vectors = {}
  for p, entity in ipairs(self) do
    local stack = {}
    local stat = Processor:execute(entity.sequence, series, stack)
    local x = stack[#stack]
    if stat and x and torch.isTensor(x) then
      x = torch.sign(x)
    else
      x = torch.zeros(n)
    end -- if stat
    
    if (x:nElement() ~= n) then
      x = series:expand(x, candles.pc)
      assert(x:nElement() == n, 'Prototypes:tradeSeries: Failed to expand vectors!')
    end
    vectors[p] = x
    states[p] = { position = 0 }
  end -- for Prototypes
  
  -- Cycle through candles
  for i = 1, n do
    local tc = candles.tc[i]
    local t = os.date('!*t', tc)
    --if last_day and (last_day ~= t.yday) then
    if (t.hour >= 20) and (t.min >= 49) then
      -- Reset states at the end of a day
      for p, _ in ipairs(self) do
        local state = states[p]
        state.position = 0
      end
      -- Reset position
      if (account.position ~= 0) then
        account:closePosition(candles.pc[i-1], candles.tc[i-1])
      end
    elseif (t.hour >= 07) and (t.min >= 10) then
      -- Construct united signal
      local desired_position = 0
      for p, entity in ipairs(self) do
        -- Get prototype signal
        local state = states[p]
        local signal = vectors[p][i]
        signal = (signal == 0) and 0 or (signal > 0) and 1 or -1
        -- Calculate prototype position based on signal
        if (signal ~= state.position) then
          state.position = signal
        end
        desired_position = desired_position + state.position * (entity.weight or 1)
      end -- for Prototypes
      -- Apply trading amount
      desired_position = math.floor(trading_amount*desired_position + 0.5)
      -- Update position at the end of a candle
      if (account.position ~= desired_position) then
        account:trade(desired_position - account.position, candles.pc[i], tc)
      end
    end
    last_day = t.yday
  end -- for candles
  -- Construct report
  return account
end -- function Prototypes:tradeSeries

function Prototypes:tradeSeries2(series, trading_amount)
  trading_amount = trading_amount or #self
  local n = series.nframes
  local candles = series.frames
  local account = Account.init { position = 0 }
  local states = {}
  
  -- Execute prototypes and get signal vectors
  local vectors = {}
  for p, entity in ipairs(self) do
    local stack = {}
    local stat = Processor:execute(entity.sequence, series, stack)
    local x = stack[#stack]
    if stat and x and torch.isTensor(x) then
      x = torch.sign(x)
    else
      x = torch.zeros(n)
    end -- if stat
    
    if (x:nElement() ~= n) then
      x = series:expand(x, candles.pc)
      assert(x:nElement() == n, 'Prototypes:tradeSeries: Failed to expand vectors!')
    end
    vectors[p] = x
    states[p] = { position = 0 }
  end -- for Prototypes
  
  -- Cycle through candles
  for i = 1, n do
    local tc = candles.tc[i]
    -- Construct united signal
    local desired_position = 0
    for p, entity in ipairs(self) do
      -- Get prototype signal
      local state = states[p]
      local signal = vectors[p][i]
      signal = (signal > 0) and 1 or (signal < 0) and -1 or 0
      -- Calculate prototype position based on signal
      if (signal ~= state.position) then
        state.position = signal
        state.enter_date = tc
      end
      desired_position = desired_position + state.position * (entity.weight or 1)
    end -- for Prototypes
    -- Apply trading amount
    desired_position = math.floor(trading_amount*desired_position + 0.5)
    -- Update position at the end of a candle
    if (account.position ~= desired_position) then
      account:trade(desired_position - account.position, candles.pc[i], tc)
    end
  end -- for candles
  -- Construct report
  return account
end -- function Prototypes:tradeSeries2

function Prototypes:getSimilarityMatrix()
  local n = #self
  local M = torch.zeros(n, n)
  for i, prototypeA in ipairs(self) do
    for j = i, #self do
      if i == j then
        M[i][j] = 1
      else
        local prototypeB = self[j]
        local similarity = Syntax:similarity(prototypeA.mishmash, prototypeB.mishmash)
        M[i][j], M[j][i] = similarity, similarity
      end -- if i == j
    end -- for prototypes
  end -- for prototypes
  return M
end -- function Prototypes:getSimilarityMatrix

local function main()
  local work_dir = arg[1]
  if work_dir then
    assert( lfs.chdir(work_dir) )
    print('Changed dir to '..work_dir)
  end
  local robot = dofile 'config.lua'
  assert(Dataset_File and Iterations_In_Epoch and robot,
    'Invalid config file!')
  
  -- Initialize Torch
  math.randomseed( os.time() )
  --torch.manualSeed(1)
  torch.setdefaulttensortype('torch.FloatTensor')
  torch.setnumthreads(2)
  
  print('Loading Dataset...')
  Dataset = Env.universalLoad(Dataset_File, 'binary')
  assert(Dataset, 'Failed to load Dataset from '..tostring(Dataset_File))
  print('Loaded Dataset from '..tostring(Dataset_File))
  Env.printInfo('Dataset', Dataset)
  Data.addExpand(Dataset)
  
  -- Load profitable species
  Prototypes:load()
  if (#Prototypes <= 0) then
    error('Failed to load any profitable algorithms!')
  end
  print('Loaded '..tostring(#Prototypes)..' prototypes')
  
  local result = {}
  for s, series in ipairs(Dataset) do
    local n = series.ncandles
    local candles = series.candles
    io.write('\rProcessing '..tostring(s)..'/'..tostring(#Dataset))
    io.flush()
    local account = Prototypes:tradeSeries(series, robot.trading_amount)
    if account and account.position then
      account:closePosition(candles.pc[n], candles.tc[n])
      -- Construct report
      result[s] = account:makeReport(candles.to[1], candles.tc[n])
    end
  end
  print('')
  
  local avg_rate = 0
  local NA = 'N/A'
  print('##\t#trades\tRate%\tDDown%\tPF\tRF')
  for i, report in ipairs(result) do
    print(string.format('%02d', i)..'\t'..
      (report.n_trades             and string.format('%d', report.n_trades) or NA)..'\t'..
      (report.annual_rate          and string.format('%.2f', 100*report.annual_rate) or NA)..'\t'..
      (report.max_drawdown_percent and string.format('%.2f', 100*report.max_drawdown_percent) or NA)..'\t'..
      (report.profit_factor        and string.format('%.2f', report.profit_factor) or NA)..'\t'..
      (report.recovery_factor      and string.format('%.2f', report.recovery_factor) or NA))
    --Env.printInfo('Report '..tostring(i), report)
    avg_rate = avg_rate + (report.annual_rate or 0)
  end
  
  avg_rate = avg_rate / #result
  print('Average rate: '..string.format('%.2f', 100*avg_rate))
  
  if false then
    local M = Prototypes:getSimilarityMatrix()
    print(M)
    local result = {}
    local processed = {}
    
    local i = 1
    while true do
      local a = Prototypes[i]
      table.insert(result, a)
      processed[a] = true
      
      local max_similarity, next_i
      for j = 1, #Prototypes do
        local b = Prototypes[j]
        if (not processed[b]) and (i ~= j) then
          if (not max_similarity) or (M[i][j] > max_similarity) then
            max_similarity = M[i][j]
            next_i = j
          end
        end
      end -- for
      if not next_i then break end
      i = next_i
    end
  end
  
end -- function main

main()

--local function update()
--  local work_dir = arg[1] or '.'
--  if (work_dir ~= '.') then
--    assert( lfs.chdir(work_dir) )
--    print('Changed dir to', work_dir)
--  end
--  require 'config'
--  assert(Dataset_File, 'Invalid config file!')
  
--  -- Initialize Torch
--  math.randomseed( os.time() )
--  --torch.manualSeed(1)
--  torch.setdefaulttensortype('torch.FloatTensor')
--  torch.setnumthreads(4)
  
--  print('Loading Dataset...')
--  Dataset = Env.universalLoad(Dataset_File, 'binary')
--  assert(Dataset, 'Failed to load Dataset from '..tostring(Dataset_File))
--  print('Loaded Dataset from '..tostring(Dataset_File))
--  Env.printInfo('Dataset', Dataset)
--  Data.addExpand(Dataset)
  
--  for _, specie in ipairs(Env) do
--    print('Exporting', tostring(specie.name))
--    assert( Species.saveSpecie(specie) )
--    local s = assert( Species.openSpecie(specie.name) )
--    s:export()
--    s:close()
--  end
  
--  print('Rebuilding index')
--  local index = assert( Species.getIndex() )
--  index:sort()
--  print('Index has:')
--  for k, info in pairs(index) do
--    print(k,'=',info.name)
--  end
--  index:save()
--  index:close()
--end -- function update

--update()

--local function update()
--  local work_dir = arg[1] or '.'
--  if (work_dir ~= '.') then
--    assert( lfs.chdir(work_dir) )
--    print('Changed dir to', work_dir)
--  end
--  require 'config'
--  assert(Dataset_File, 'Invalid config file!')
  
--  -- Initialize Torch
--  math.randomseed( os.time() )
--  --torch.manualSeed(1)
--  torch.setdefaulttensortype('torch.FloatTensor')
--  torch.setnumthreads(4)
  
--  -- Aquire and lock index
--  print('Aquiring index...')
--  local Index = assert( Species.getIndex() )
--  print('Index has '..tostring(#Index)..' records')
  
--  local specie = Species.importSpecieFromFile('hemera.export.dat')
--  local info = assert( Species.getSpecieInfo(specie) )
--  Index:update(info.name, info)
  
--  -- Save specie
--  print('Saving specie '..tostring(specie.name))
--  assert( specie:save() )
--  specie:export()
--  specie:close()
  
--  print('Saving index')
--  assert( Index:save() )
--  Index:close()
--end -- function update

--update()
