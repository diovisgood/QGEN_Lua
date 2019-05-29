local torch = require 'torch'

local Processor = {}

local Index_To_Offset = 1.4
local PRECISION = 0.00001

local Commands = {
  Nop   = true,
  I     = true,
  Hours = true,
  Days  = true,
  po    = true,
--  ['do']= true,
--  oo    = true,
  ph    = true,
--  dh    = true,
--  oh    = true,
  pl    = true,
--  dl    = true,
--  ol    = true,
  pc    = true,
--  dc    = true,
--  oc    = true,
  ptr   = true,
--  dtr   = true,
--  otr   = true,
  vwap  = true,
  vol   = true,
  time  = true,
--  hour  = true,
--  day   = true,
--  month = true,
  --nums  = true,
  --nume  = true,
  Val   = true,
  Delta = true,
  Min   = true,
  Max   = true,
  Sum   = true,
  Prod  = true,
  Rank  = true,
  iRank = true,
  Std   = true,
  SMA   = true,
  WMA   = true,
  fCos  = true,
  fUp   = true,
  fDown = true,
  --Pop   = true,
  Dup   = true,
  Neg   = true,
  Abs   = true,
  Sign  = true,
  Exp   = true,
  Log   = true,
  Swap  = true,
  Add   = true,
  Sub   = true,
  Mul   = true,
  Div   = true,
  Mod   = true,
  Pow   = true,
  Covar = true,
  Corr  = true,
  Min2  = true,
  Max2  = true,
  Rep   = true,
  RepN  = true,
  RepM  = true,
  Gt    = true,
  --Ge    = true,
  Lt    = true,
  --Le    = true,
  If    = true,
}

local Commands_Descriptions = {
  Delta = { nargs = 1, series = true,  stack = true,  index = true },
  Min   = { nargs = 1, series = true,  stack = true,  index = true },
  Max   = { nargs = 1, series = true,  stack = true,  index = true },
  Sum   = { nargs = 1, series = true,  stack = true,  index = true },
  Prod  = { nargs = 1, series = true,  stack = true,  index = true },
  Rank  = { nargs = 1, series = true,  stack = true,  index = true },
  iRank = { nargs = 1, series = true,  stack = true,  index = true },
  Std   = { nargs = 1, series = true,  stack = true,  index = true },
  SMA   = { nargs = 1, series = true,  stack = true,  index = true },
  WMA   = { nargs = 1, series = true,  stack = true,  index = true },
  Covar = { nargs = 1, series = true,  stack = true,  index = true },
  Corr  = { nargs = 1, series = true,  stack = true,  index = true },
  fCos  = { nargs = 1, series = true,  stack = true,  index = true },
  fUp   = { nargs = 1, series = true,  stack = true,  index = true },
  fDown = { nargs = 1, series = true,  stack = true,  index = true },
  
  Dup   = { nargs = 1, series = true,  stack = true,  index = true },
  Neg   = { nargs = 1, series = true,  stack = true,  index = true },
  Abs   = { nargs = 1, series = true,  stack = true,  index = true },
  Sign  = { nargs = 1, series = true,  stack = true,  index = true },
  Exp   = { nargs = 1, series = true,  stack = true,  index = true },
  Log   = { nargs = 1, series = true,  stack = true,  index = true },
  Swap  = { nargs = 1, series = true,  stack = true,  index = true },
  Add   = { nargs = 1, series = true,  stack = true,  index = true },
  Sub   = { nargs = 1, series = true,  stack = true,  index = true },
  Mul   = { nargs = 1, series = true,  stack = true,  index = true },
  Div   = { nargs = 1, series = true,  stack = true,  index = true },
  Mod   = { nargs = 1, series = true,  stack = true,  index = true },
  Pow   = { nargs = 1, series = true,  stack = true,  index = true },
  Min2  = { nargs = 1, series = true,  stack = true,  index = true },
  Max2  = { nargs = 1, series = true,  stack = true,  index = true },
  Rep   = { nargs = 1, series = true,  stack = true,  index = true },
  RepN  = { nargs = 1, series = false, stack = true,  index = true },
  RepM  = { nargs = 2, series = false, stack = true,  index = false },
  Lt    = { nargs = 2, series = false, stack = true,  index = true },
  Gt    = { nargs = 2, series = false, stack = true,  index = true },
  If    = { nargs = 3, series = false, stack = true,  index = false },
}


local Series_Commands = {
  Delta = true,
  Min   = true,
  Max   = true,
  Sum   = true,
  Prod  = true,
  Rank  = true,
  iRank = true,
  Std   = true,
  SMA   = true,
  WMA   = true,
  Covar = true,
  Corr  = true,
  fCos  = true,
  fUp   = true,
  fDown = true,
}

local Math_Commands = {
  Dup   = true,
  Neg   = true,
  Abs   = true,
  Sign  = true,
  Exp   = true,
  Log   = true,
  Swap  = true,
  Add   = true,
  Sub   = true,
  Mul   = true,
  Div   = true,
  Mod   = true,
  Pow   = true,
  Min2  = true,
  Max2  = true,
  Rep   = true,
  RepN  = true,
  RepM  = true,
  If    = true,
}

local function covariance(a, b, mean_a, mean_b)
  mean_a = mean_a or a:mean()
  mean_b = mean_b or b:mean()
  local da = torch.add(a, -mean_a)
  local db = torch.add(b, -mean_b)
  --local result = torch.cmul(da, db):sum() / a:nElement()
  local result = torch.dot(da, db) / a:nElement()
  return result
end -- function covariance

local function correlation(a, b, mean_a, mean_b)
  mean_a = mean_a or a:mean()
  mean_b = mean_b or b:mean()
  local da = torch.add(a, -mean_a)
  local db = torch.add(b, -mean_b)
  local norm = da:norm() * db:norm()
  if (norm == 0) then return 0 end
  --local result = torch.cmul(da, db):sum() / math.sqrt( torch.cmul(da,da):sum() * torch.cmul(db,db):sum() )
  local result = torch.dot(da, db) / norm
  return result
end -- function correlation

local Patterns = {}
Patterns.cos_cache = {}

function Patterns.getCos(N)
  if Patterns.cos_cache[N] then return Patterns.cos_cache[N] end
  local r = torch.Tensor(N)
  for i = 1, N do
    r[i] = math.cos(2*math.pi*i/N)
  end
  Patterns.cos_cache[N] = r
  return r, 0
end -- function Patterns.getCos

Patterns.up_cache = {}

function Patterns.getUp(N)
  if Patterns.up_cache[N] then return unpack(Patterns.up_cache[N], 1, 2) end
  local r = torch.Tensor(N)
  local mean = 0
  for i = 1, N do
    local x = 5*math.pi*i/(2*N)
    r[i] = - math.sin(x) / x
    mean = mean + r[i]
  end
  mean = mean / N
  Patterns.up_cache[N] = { r, mean }
  return r, mean
end -- function Patterns.getUp

Patterns.down_cache = {}

function Patterns.getDown(N)
  if Patterns.down_cache[N] then return unpack(Patterns.down_cache[N], 1, 2) end
  local r = torch.Tensor(N)
  local mean = 0
  for i = 1, N do
    local x = 5*math.pi*i/(2*N)
    r[i] = math.sin(x) / x
    mean = mean + r[i]
  end
  mean = mean / N
  Patterns.down_cache[N] = { r, mean }
  return r, mean
end -- function Patterns.getDown

local function shiftVector(x, offset)
  if offset <= 0 then return x end
  local n = x:nElement()
  local result = torch.Tensor(n)
  if offset < n then
    result:sub(offset+1,-1):copy( x:sub(1,-(offset+1)) )
    result:sub(1, offset):fill( x[1] )
  else
    result:fill( x[1] )
  end
  return result
end -- function shiftVector

local function stringToSequence(line, delimiter)
  delimiter = delimiter or '[;,%s]'
  local i, pos, result, v = 0, 0, {}
  -- for each divider found
  for st,sp in function() return string.find(line, delimiter, pos) end do
    v = string.sub(line, pos, st - 1)
    result[i + 1] = tonumber(v) or v
    pos = sp + 1
    i = i + 1
  end
  v = string.sub(line, pos)
  result[i + 1] = tonumber(v) or v
  return result
end

function Processor:execute(sequence, env, stack, flog)
  if type(sequence) == 'string' then
    sequence = stringToSequence(sequence)
  end
  assert(type(sequence) == 'table', 'Processor:execute: Invalid sequence!')
  assert(type(env) == 'table' and type(env.expand) == 'function',
    'Processor:execute: expand function not found in env!')
  local stat = {
    maxOffset = {},
    nOperations=0,
    nErrorInvalidArguments=0, nErrorsNotEnoughArguments=0,
    nErrorsStackOut=0, nErrorsOutOfBounds=0,
  }
  local exec = flog and ''
  local text = flog and ''
  local name, subset
  local index, offset
  local fenv, op
  local a, b, x
  
  local function reset()
		stat.nOperations = stat.nOperations + (op or 0)
    name, subset = nil, nil
    index, offset = nil, nil
    a, b, x = nil, nil, nil
    fenv = nil
    op = 0
  end
  
  local function getSeries(f_not_from_stack)
    local subset_name = subset and subset:lower() or 'frames'
    local tab = env[subset_name]
    local series = tab and tab[name]
    if series then series = series:clone() end
    if series or f_not_from_stack then return series, true end
    if #stack < 1 then
      stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      return
    end
    series = table.remove(stack)
    if not torch.isTensor(series) then
      stat.nErrorInvalidArguments = stat.nErrorInvalidArguments + 1
      series = nil
    end
    return series
  end -- function getSeries
  
  local function checkOffset(x)
    local n = x:nElement()
    index = index or 0
    offset = math.floor(index ^ Index_To_Offset)
    if offset >= n then
      stat.nErrorsOutOfBounds = stat.nErrorsOutOfBounds + 1
      return false
    end
    -- Update maxOffset
    local maxOffset = stat.maxOffset
    if (not maxOffset[n]) or (maxOffset[n] < offset) then maxOffset[n] = offset end
    return true
  end -- function checkOffset
  
  local function checkVectors(a, b)
    if a:nElement() ~= b:nElement() then
      a, b = env:expand(a, b)
      assert(a:nElement() == b:nElement(), 'Processor:execute: Failed to expand vectors!')
    end
    return a, b
  end -- function checkVectors
  
  local function log(cmd, cmd_text)
    local fmath = Math_Commands[cmd]
    local fseries = Series_Commands[cmd]
    -- Log text
    if cmd_text then
      text = text..cmd_text..' '
    elseif fmath then
      text = text..cmd..' '
    else
      text = text..cmd..'('
      if fenv then
        text = text..(subset and (subset~='frames') and subset..'.' or '')..tostring(name)..','
      end
      text = text..tostring(offset or 0)..') '
    end
    -- Log exec
    if fenv then
      exec = exec..string.rep('I ', index or 0)..(subset and (subset~='frames') and subset..' ' or '')..tostring(name)..' '
    elseif fseries then
      exec = exec..string.rep('I ', index or 0)
    end
    exec = exec..cmd..' '
  end -- function log
  
  for _, cmd in ipairs(sequence) do
    if type(cmd) == 'number' then
      table.insert(stack, cmd)
      if flog then
        exec = exec..tostring(cmd)..' '
        text = text..tostring(cmd)..' '
      end
    elseif cmd == 'Nop' then
      reset()
    elseif cmd == 'I' then
      index = (index or 0) + 1
    elseif cmd == 'Frames' then
      subset = cmd
    elseif cmd == 'Hours' then
      subset = cmd
    elseif cmd == 'Days' then
      subset = cmd
    elseif cmd:match('^[pdo][ohlc]$') then
      name = cmd
    elseif cmd:match('^[pdo]tr$') then
      name = cmd
    elseif (cmd == 'vwap') or (cmd == 'vol') then
      name = cmd
    elseif (cmd == 'time') or (cmd == 'hour') then
      name = cmd
    elseif (cmd == 'day') or (cmd == 'month') then
      name = cmd
    elseif cmd == 'Val' then
      a, fenv = getSeries(true)
      if a and checkOffset(a) then
        x = shiftVector(a, offset)
        table.insert(stack, x)
        if flog and fenv then log(cmd) end
      end
      reset()
    elseif cmd == 'Delta' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        b = shiftVector(a, offset)
        x = torch.csub(a, b)
        table.insert(stack, x)
        op = (offset > 0) and 1
        if flog then log((offset > 0) and cmd or 'Val') end
      end
      reset()
    elseif cmd == 'Min' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):min()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Min2' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.Tensor(a:nElement())
          for i = 1, a:nElement() do x[i] = math.min(a[i], b[i]) end
        elseif f_a_vector then
          x = torch.Tensor(a:nElement())
          for i = 1, a:nElement() do x[i] = math.min(a[i], b) end
        elseif f_b_vector then
          x = torch.Tensor(b:nElement())
          for i = 1, b:nElement() do x[i] = math.min(a, b[i]) end
        else
          x = math.min(a, b)
        end -- if vectors
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Max' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):max()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Max2' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.Tensor(a:nElement())
          for i = 1, a:nElement() do x[i] = math.max(a[i], b[i]) end
        elseif f_a_vector then
          x = torch.Tensor(a:nElement())
          for i = 1, a:nElement() do x[i] = math.max(a[i], b) end
        elseif f_b_vector then
          x = torch.Tensor(b:nElement())
          for i = 1, b:nElement() do x[i] = math.max(a, b[i]) end
        else
          x = math.max(a, b)
        end -- if vectors
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Sum' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):sum()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Prod' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):prod()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Rank' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.zeros(a:nElement())
          x[1] = 1
          for i = 2, x:nElement() do
            _, b = torch.sort( a:sub(math.max(1,i-offset), i) )
            for j = 1, b:nElement() do
              if b[j] == 1 then
                x[i] = j
                break
              end
            end
          end
          op = 1
          if flog then log(cmd) end
        else
          x = torch.ones(a:nElement())
          if flog then log(cmd, '(1)') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'iRank' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.zeros(a:nElement())
          x[1] = 1
          for i = 2, x:nElement() do
            _, b = torch.sort( a:sub(math.max(1,i-offset), i), true )
            for j = 1, b:nElement() do
              if b[j] == 1 then
                x[i] = j
                break
              end
            end
          end
          op = 1
          if flog then log(cmd) end
        else
          x = torch.ones(a:nElement())
          if flog then log(cmd, '(1)') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Std' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = 0
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):std(1, true)[1]
          end
          op = 1
          if flog then log(cmd) end
        else
          x = torch.zeros(a:nElement())
          if flog then log(cmd, '(0)') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'SMA' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, x:nElement() do
            x[i] = a:sub(math.max(1,i-offset), i):mean()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'WMA' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 0 then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          local k
          for i = 2, offset do
            k = torch.range(1, i):mul(2 / (i^2 + i))
            x[i] = torch.cmul( a:sub(math.max(1,i-offset), i), k ):sum()
          end
          k = torch.range(1, (offset+1)):mul(2 / ((offset+1)^2 + (offset+1)))
          for i = offset+1, x:nElement() do
            x[i] = torch.cmul( a:sub(math.max(1,i-offset), i), k ):sum()
          end
          op = 1
          if flog then log(cmd) end
        else
          x = a
          if flog and fenv then log('Val') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'fCos' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 10 then
          local filter, filter_mean = Patterns.getCos(offset)
          x = torch.Tensor(a:nElement())
          x:sub(1, math.min(x:nElement(), offset-1)):fill(0)
          for i = offset, x:nElement() do
            x[i] = correlation( filter, a:sub(math.max(1,i-offset+1), i), filter_mean )
          end
          op = 1
          if flog then log(cmd) end
        else
          x = 0
          if flog then log(cmd, '0') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'fUp' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 10 then
          local filter, filter_mean = Patterns.getUp(offset)
          x = torch.Tensor(a:nElement())
          x:sub(1, math.min(x:nElement(), offset-1)):fill(0)
          for i = offset, x:nElement() do
            x[i] = correlation( filter, a:sub(math.max(1,i-offset+1), i), filter_mean )
          end
          op = 1
          if flog then log(cmd) end
        else
          x = 0
          if flog then log(cmd, '0') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'fDown' then
      a, fenv = getSeries()
      if a and checkOffset(a) then
        if offset > 10 then
          local filter, filter_mean = Patterns.getDown(offset)
          x = torch.Tensor(a:nElement())
          x:sub(1, math.min(x:nElement(), offset-1)):fill(0)
          for i = offset, x:nElement() do
            x[i] = correlation( filter, a:sub(math.max(1,i-offset+1), i), filter_mean )
          end
          op = 1
          if flog then log(cmd) end
        else
          x = 0
          if flog then log(cmd, '0') end
        end
        table.insert(stack, x)
      end
      reset()
    elseif cmd == 'Dup' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = stack[#stack]
        if torch.isTensor(a) then
          x = a:clone()
        else
          x = a
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Rep' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.Tensor(a:nElement())
          x[1] = a[1]
          for i = 2, a:nElement() do
            x[i] = (a[i] == 0) and x[i-1] or a[i]
          end
          table.insert(stack, x)
          op = 1
          if flog then log(cmd) end
        end -- if vector
      end
      reset()
    elseif cmd == 'RepN' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then checkOffset(a) end
        if torch.isTensor(a) and (offset > 0) then
          x = torch.Tensor(a:nElement())
          local counter = 0
          x[1] = a[1]
          for i = 2, a:nElement() do
            if (a[i] == 0) and (counter < offset) then
              x[i] = x[i-1]
              counter = counter + 1
            else
              x[i] = a[i]
              counter = 0
            end
          end
          table.insert(stack, x)
          op = 1
          if flog then log(cmd) end
        end -- if vector
      end
      reset()
    elseif cmd == 'RepM' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.Tensor(a:nElement())
          local value
          for i = 1, a:nElement() do
            if (b[i] ~= 0) then
              if (a[i] ~= 0) or (not value) then
                value = a[i]
              end
              x[i] = value
            else
              x[i] = 0
              value = nil
            end
          end
          table.insert(stack, x)
          op = 1
          if flog then log(cmd) end
        end -- if vector
      end
      reset()
    elseif cmd == 'Neg' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.mul(a, -1)
        else
          x = -a
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Abs' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.abs(a)
        else
          x = math.abs(a)
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Sign' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.sign(a)
        else
          x = (a == 0 and 0) or (a > 0 and 1) or -1
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Exp' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.exp(a)
        else
          x = math.exp(a)
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Log' then
      if #stack < 1 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        if torch.isTensor(a) then
          x = torch.log(a)
        else
          x = math.log(a)
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Swap' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        a = table.remove(stack)
        b = table.remove(stack)
        table.insert(stack, a)
        table.insert(stack, b)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Add' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.add(a, b)
        elseif f_a_vector then
          x = torch.add(a, b)
        elseif f_b_vector then
          x = torch.add(b, a)
        else
          x = a + b
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Sub' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.add(a, -1, b)
        elseif f_a_vector then
          x = torch.add(a, -b)
        elseif f_b_vector then
          x = torch.mul(b, -1):add(a)
        else
          x = a - b
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Mul' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.cmul(a, b)
        elseif f_a_vector then
          x = torch.mul(a, b)
        elseif f_b_vector then
          x = torch.mul(b, a)
        else
          x = a * b
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Div' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.cdiv(a, b)
        elseif f_a_vector then
          x = torch.div(a, b)
        elseif f_b_vector then
          x = torch.pow(b,-1):mul(a)
        else
          x = a / b
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Mod' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.cfmod(a, b)
        elseif f_a_vector then
          x = torch.fmod(a, b)
        elseif f_b_vector then
          x = torch.Tensor(b:nElement())
          for i = 1, x:nElement() do x[i] = math.fmod(a, b[i]) end
          --x = torch.pow(b,-1):mul(a):floor():cmul(b):add(-a):mul(-1)
        else
          x = math.fmod(a, b)
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Pow' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = torch.cpow(a, b)
        elseif f_a_vector then
          x = torch.pow(a, b)
        elseif f_b_vector then
          x = torch.Tensor(b:nElement())
          for i = 1, x:nElement() do x[i] = math.pow(a, b[i]) end
        else
          x = math.pow(a, b)
        end
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    elseif cmd == 'Covar' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector or f_b_vector then
          if (not f_a_vector) then
            a = torch.Tensor(b:nElement()):fill(a)
          end
          if (not f_b_vector) then
            b = torch.Tensor(a:nElement()):fill(b)
          end
          a, b = checkVectors(a, b)
          if checkOffset(a) then
            x = torch.Tensor(a:nElement())
            for i = 1, offset do x[i] = 0 end
            for i = offset+1, x:nElement() do
              local sa = a:sub(offset > 0 and math.max(1,i-offset) or 1, i)
              local sb = b:sub(offset > 0 and math.max(1,i-offset) or 1, i)
              x[i] = covariance(sa, sb)
            end
            table.insert(stack, x)
            op = 1
            if flog then log(cmd) end
          end -- if offset
        else
          x = 0
          table.insert(stack, x)
          if flog then log(cmd, '0') end
        end -- if vectors
      end -- if stack
      reset()
    elseif cmd == 'Corr' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector or f_b_vector then
          if (not f_a_vector) then
            a = torch.Tensor(b:nElement()):fill(a)
          end
          if (not f_b_vector) then
            b = torch.Tensor(a:nElement()):fill(b)
          end
          a, b = checkVectors(a, b)
          if checkOffset(a) then
            x = torch.Tensor(a:nElement())
            for i = 1, offset do x[i] = 0 end
            for i = offset+1, x:nElement() do
              local sa = a:sub(offset > 0 and math.max(1,i-offset) or 1, i)
              local sb = b:sub(offset > 0 and math.max(1,i-offset) or 1, i)
              x[i] = correlation(sa, sb)
            end
            table.insert(stack, x)
            op = 1
            if flog then log(cmd) end
          end -- if offset
        else
          x = 0
          table.insert(stack, x)
          if flog then log(cmd, '0') end
        end -- if vectors
      end -- if stack
      reset()
    elseif cmd == 'Gt' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = (not index or index==0) and torch.gt(a, b) or torch.ge(a, b)
          x = x:type(torch.getdefaulttensortype())
        elseif f_a_vector then
          x = (not index or index==0) and torch.gt(a, b) or torch.ge(a, b)
          x = x:type(torch.getdefaulttensortype())
        elseif f_b_vector then
          x = (not index or index==0) and torch.lt(b, a) or torch.le(b, a)
          x = x:type(torch.getdefaulttensortype())
        else
          if (not index) or (index==0) then
            x = (a > b) and 1 or 0
          else
            x = (a >= b) and 1 or 0
          end
        end
        table.insert(stack, x)
        op = 1
        if flog then log((index and 'I Gt' or 'Gt'), (index and 'Ge' or 'Gt')) end
      end
      reset()
    elseif cmd == 'Lt' then
      if #stack < 2 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        b = table.remove(stack)
        a = table.remove(stack)
        local f_a_vector = torch.isTensor(a)
        local f_b_vector = torch.isTensor(b)
        if f_a_vector and f_b_vector then
          a, b = checkVectors(a, b)
          x = (not index or index==0) and torch.lt(a, b) or torch.le(a, b)
          x = x:type(torch.getdefaulttensortype())
        elseif f_a_vector then
          x = (not index or index==0) and torch.lt(a, b) or torch.le(a, b)
          x = x:type(torch.getdefaulttensortype())
        elseif f_b_vector then
          x = (not index or index==0) and torch.gt(b, a) or torch.ge(b, a)
          x = x:type(torch.getdefaulttensortype())
        else
          if (not index) or (index==0) then
            x = (a < b) and 1 or 0
          else
            x = (a <= b) and 1 or 0
          end
        end
        table.insert(stack, x)
        op = 1
        if flog then log((index and 'I Lt' or 'Lt'), (index and 'Le' or 'Lt')) end
      end
      reset()
    elseif cmd == 'If' then
      if #stack < 3 then
        stat.nErrorsNotEnoughArguments = stat.nErrorsNotEnoughArguments + 1
      else
        x = table.remove(stack)
        b = table.remove(stack)
        a = table.remove(stack)
        if torch.isTensor(x) then
          if torch.isTensor(a) then
            a, x = env:expand(a, x)
          else
            a = torch.Tensor(x:nElement()):fill(a)
          end
          if torch.isTensor(b) then
            b, x = env:expand(b, x)
            a, b = env:expand(a, b)
          else
            b = torch.Tensor(x:nElement()):fill(b)
          end
          assert(a:nElement() == b:nElement() and a:nElement() == x:nElement(),
            'Processor:execute: Failed to expand vectors!')
          for i = 1, x:nElement() do
            x[i] = (x[i] > 0) and a[i] or b[i]
          end
        else
          x = (x > 0) and a or b
        end -- if isTensor(x)
        table.insert(stack, x)
        op = 1
        if flog then log(cmd) end
      end
      reset()
    else
    end -- if
  end -- while
  -- Remove trailing space from strings
  if exec and exec:sub(-1) == ' ' then exec = exec:sub(1, -2) end
  if text and text:sub(-1) == ' ' then text = text:sub(1, -2) end
  return stat, exec, text
end -- function Processor:execute

-- Return if not running from console.
-- Continue to unit testing otherwise.
local info = debug.getinfo(2)
if info and (info.name or (info.what ~= 'C')) then
  return Processor
end

---------------------------------------------------------------------
------- UNIT TESTS
---------------------------------------------------------------------

local function test_env_reading()
  print('Testing env reading:')
  local env = {
    frames = {
      pc = torch.Tensor{1, 2, 3, 4, 5},
      ph = torch.Tensor{6, 7, 8, 9, 10},
    },
    hours = {
      pc = torch.Tensor{11, 12, 13, 14, 15},
    },
    days = {
      ph = torch.Tensor{16, 17, 18, 19, 20},
    },
    expand = function(a, b) end,
  }
  local function test(cmd, sequence, t, nops, index)
    t = torch.type(t)=='table' and torch.Tensor(t) or t
    local stack = {}
    local stat = Processor:execute(sequence, env, stack)
    local r = stack[#stack]
    print(tostring(cmd)..':')
    print(tostring(r))
    print(tostring(t))
    if torch.isTensor(r) then
      assert(r:ne(t):sum() <= 0, 'Failed '..tostring(cmd)..' result')
    else
      error('Failed '..tostring(cmd))
    end
    assert(stat.nOperations==nops and stat.maxOffset[5] and stat.maxOffset[5]==math.floor(index^Index_To_Offset),
      'Failed '..tostring(cmd)..' stat '..tostring(stat.maxOffset[5])..'=='..tostring(math.floor(index^Index_To_Offset)))
    print(tostring(cmd)..' passed.')
  end
  
  test('read env', {'pc','Val','I','I','ph','Val','Add'}, {7,8,9,11,13}, 1, 2)
  test('read hours env', {'I','Hours','I','pc','Val'}, {11,11,11,12,13}, 0, 2)
  test('read days env', {'Days','I','ph','Val'}, {16,16,17,18,19}, 0, 1)
end -- function test_env_reading

local function test_series()
  print('Testing series:')
  local env = {
    frames = {
      pc = torch.Tensor{1, 2, 3, 4, 5},
      ph = torch.Tensor{6, 7, 8, 9, 10},
    },
    expand = function(a, b) end,
  }
  local function test(sequence, t, index, f_dist)
    local cmd = sequence[#sequence]
    t = torch.type(t)=='table' and torch.Tensor(t) or t
    local stack = {}
    local stat = Processor:execute(sequence, env, stack)
    local r = stack[#stack]
    print(tostring(cmd)..':')
    print(tostring(r))
    print(tostring(t))
    if torch.isTensor(r) then
      if f_dist then
        assert(torch.dist(r, t) <= PRECISION, 'Failed '..tostring(cmd)..' result')
      else
        assert(r:ne(t):sum() <= 0, 'Failed '..tostring(cmd)..' result')
      end
    else
      error('Failed '..tostring(cmd))
    end
    assert(stat.nOperations==1 and stat.maxOffset[5] and stat.maxOffset[5]==math.floor(index^Index_To_Offset),
      'Failed '..tostring(cmd)..' stat')
    print(tostring(cmd)..' passed.')
  end
  
  test({'I','I','pc','Delta'}, {0,1,2,2,2}, 2)
  test({'I','I','pc','Min'}, {1,1,1,2,3}, 2)
  test({'I','I','pc','Max'}, {1,2,3,4,5}, 2)
  test({'I','I','pc','Sum'}, {1,3,6,9,12}, 2)
  test({'I','I','pc','Prod'}, {1,2,6,24,60}, 2)
  test({'I','I','pc','Std'},
    {0,math.sqrt(1/4),math.sqrt(2/3),math.sqrt(2/3),math.sqrt(2/3)}, 2, true)
  test({'I','I','pc','Rank'}, {1,1,1,1,1}, 2)
  test({'I','I','pc','iRank'}, {1,2,3,3,3}, 2)
  test({'I','I','pc','SMA'}, {1,(3/2),2,3,4}, 2)
  test({'I','I','pc','WMA'},
    {1,(1/3+2*2/3),(1*1/6+2*2/6+3*3/6),(2*1/6+3*2/6+4*3/6),(3*1/6+4*2/6+5*3/6)}, 2)
end

local function test_maths()
  print('Testing maths:')
  local env = {
    expand = function(a, b) end,
  }
  local function test(a, b, cmd, t)
    a = torch.type(a)=='table' and torch.Tensor(a) or a
    b = torch.type(b)=='table' and torch.Tensor(b) or b
    t = torch.type(t)=='table' and torch.Tensor(t) or t
    local stack = { a, b }
    local stat = Processor:execute({cmd}, env, stack)
    local r = stack[#stack]
    print(tostring(cmd)..':')
    print(tostring(a))
    print(tostring(b))
    print(tostring(r))
    print(tostring(t))
    if torch.isTensor(r) then
      assert(r:ne(t):sum() <= 0, 'Failed '..tostring(cmd)..' result')
    elseif torch.type(r) == 'number' then
      assert(r == t, 'Failed '..tostring(cmd)..' result')
    else
      error('Failed '..tostring(cmd))
    end
    assert(stat.nOperations==1, 'Failed '..tostring(cmd)..' stat')
    print(tostring(cmd)..' passed.')
  end
  
  test(3, 5, 'Neg', -5)
  test(3, {-2,-1,0,1,2}, 'Neg', {2,1,0,-1,-2})
  
  test(3, -5, 'Abs', 5)
  test(3, {-2,-1,0,1,2}, 'Abs', {2,1,0,1,2})
  
  test(3, -5, 'Sign', -1)
  test(3, {-2,-1,0,1,2}, 'Sign', {-1,-1,0,1,1})
  
  test(3, -5, 'Exp', math.exp(-5))
  test(3, {-2,-1,0,1,2}, 'Exp', {math.exp(-2),math.exp(-1),1,math.exp(1),math.exp(2)})
  
  test(3, 5, 'Log', math.log(5))
  test(3, {1,2,3,4}, 'Log', {math.log(1),math.log(2),math.log(3),math.log(4)})
  
  test(-25, 30, 'Add', 5)
  test({-2,-1,0,1,2}, 1, 'Add', {-1,0,1,2,3})
  test(1, {-2,-1,0,1,2}, 'Add', {-1,0,1,2,3})
  test({-2,-1,0,1,2}, {2,1,0,-1,-2}, 'Add', {0,0,0,0,0})
  
  test(-25, 30, 'Sub', -55)
  test({-2,-1,0,1,2}, 1, 'Sub', {-3,-2,-1,0,1})
  test(1, {-2,-1,0,1,2}, 'Sub', {3,2,1,0,-1})
  test({-2,-1,0,1,2}, {2,1,0,-1,-2}, 'Sub', {-4,-2,0,2,4})
  
  test(-2, 3, 'Mul', -6)
  test({-2,-1,0,1,2}, 2, 'Mul', {-4,-2,0,2,4})
  test(-2, {-2,-1,0,1,2}, 'Mul', {4,2,0,-2,-4})
  test({-2,-1,0,1,2}, {2,1,0,-1,-2}, 'Mul', {-4,-1,0,-1,-4})
  
  test(-6, 2, 'Div', -3)
  test({-4,-2,0,2,4}, 2, 'Div', {-2,-1,0,1,2})
  test(-4, {-4,-2,2,4}, 'Div', {1,2,-2,-1})
  test({-4,-2,2,4}, {-4,-2,2,4}, 'Div', {1,1,1,1})
  
  test(-5, 2, 'Mod', -1)
  test({-7,-5,0,5,7}, 2, 'Mod', {-1,-1,0,1,1})
  test(-7, {-3,-2,2,3}, 'Mod', {-1,-1,-1,-1})
  test({-7,-5,5,7}, {-3,-2,2,3}, 'Mod', {-1,-1,1,1})
  
  test(-5, 3, 'Pow', -125)
  test({-2,-1,0,1,2}, 2, 'Pow', {4,1,0,1,4})
  test(-2, {-3,-2,0,2,3}, 'Pow', {-0.125,0.25,1,4,-8})
  test({-3,-2,0,2,3}, {-3,-2,0,2,3}, 'Pow', {(-3)^(-3),(-2)^(-2),1,4,27})
end -- 

local function test_comparasion()
  print('Testing comparasion:')
  local env = {
    expand = function(a, b) end,
  }
end -- function test_comparasion

local function test_corr()
  print('Testing correlation:')
  local a = torch.Tensor{56, 56, 65, 65, 50, 25, 87, 44, 35}
  local b = torch.Tensor{87, 91, 85, 91, 75, 28, 122,66, 58}
  local covar, corr = covariance(a, b), correlation(a, b)
  print('Covariance='..tostring(covar))
  print('Correlation='..tostring(corr))
  assert(math.abs(corr-0.966) < 0.001, 'Correlation failed!')
  print('Correlation passed')
end -- function test_corr()

local function test_filters()
  print('Testing filters:')
  local env = {
    frames = {
      pc = torch.Tensor{1,1,1,1,1,1,1,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1},
      ph = torch.range(1, 22),
      pl = torch.range(22, 1, -1),
    },
    expand = function(a, b) end,
  }
  local function test(sequence, t, index, f_dist)
    local cmd = sequence[#sequence]
    t = torch.type(t)=='table' and torch.Tensor(t) or t
    local stack = {}
    local stat = Processor:execute(sequence, env, stack)
    local r = stack[#stack]
    print(tostring(cmd)..':')
    print('r=', tostring(r))
    print('t=', tostring(t))
    if torch.isTensor(r) then
      if f_dist then
        assert(torch.dist(r, t) <= PRECISION, 'Failed '..tostring(cmd)..' result')
      else
        assert(r:ne(t):sum() <= 0, 'Failed '..tostring(cmd)..' result')
      end
    else
      error('Failed '..tostring(cmd))
    end
    assert(stat.nOperations==1 and stat.maxOffset[22] and stat.maxOffset[22]==math.floor(index^Index_To_Offset),
      'Failed '..tostring(cmd)..' stat')
    print(tostring(cmd)..' passed.')
  end
  
  local t_cos = correlation(Patterns.getCos(21), env.frames.pc:sub(-21,-1))
  test({'I','I','I','I','I','I','I','I','I','pc','fCos'},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,t_cos,t_cos}, 9, true)
  local t_up = correlation(Patterns.getUp(21), env.frames.ph:sub(-21,-1))
  test({'I','I','I','I','I','I','I','I','I','ph','fUp'},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,t_up,t_up}, 9, true)
  local t_down = correlation(Patterns.getDown(21), env.frames.pl:sub(-21,-1))
  test({'I','I','I','I','I','I','I','I','I','pl','fDown'},
    {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,t_down,t_down}, 9, true)
end -- function test_filters

test_env_reading()
test_series()
test_maths()
test_comparasion()
test_corr()
test_filters()
