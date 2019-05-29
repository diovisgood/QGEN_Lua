local hash = require 'luaxxhash'

local Syntax = {
  random_numbers_min = -10,
  random_numbers_max = 10,
  random_to_library_ratio = 0.6, -- 0...1
  substitute_numbers_ratio = 0.2,
}

local Command_Probabilities = {
  ['#'] = 15,
  Nop   = 5,
  I     = 10,
  Hours = 5,
  Days  = 5,
  po    = 10,
  ph    = 10,
  pl    = 10,
  pc    = 10,
  ptr   = 10,
  vwap  = 10,
  vol   = 10,
  time  = 10,
  Val   = 10,
  Delta = 10,
  Min   = 5,
  Min2  = 5,
  Max   = 5,
  Max2  = 5,
  Sum   = 5,
  Prod  = 5,
  Rank  = 5,
  iRank = 5,
  fCos  = 5,
  fUp   = 5,
  fDown = 5,
  Std   = 5,
  SMA   = 5,
  WMA   = 5,
  Dup   = 5,
  Rep   = 5,
  RepN  = 5,
  RepM  = 5,
  Neg   = 5,
  Abs   = 5,
  Sign  = 5,
  Exp   = 5,
  Log   = 5,
  Swap  = 5,
  Add   = 5,
  Sub   = 5,
  Mul   = 5,
  Div   = 5,
  Mod   = 5,
  Pow   = 5,
  Covar = 5,
  Corr  = 5,
  Gt    = 5,
  Lt    = 5,
  If    = 5,
}
local Probabilities_Sum = 0

local Commands = {}
for cmd, p in pairs(Command_Probabilities) do
  table.insert(Commands, cmd)
  Probabilities_Sum = Probabilities_Sum + p
end

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

local function LevenshteinDistanceArray(s, t)
  -- Check for degenerate cases
  local len_s, len_t = #s, #t
  if (len_s <= 0) then return len_t, 0 end
  if (len_t <= 0) then return len_s, 0 end
  
  -- Create two work vectors of integer distances
  local v0, v1 = {}, {}
  
  -- Initialize v0 (the previous row of distances)
  -- this row is A[0][i]: edit distance for an empty s
  -- the distance is just the number of characters to delete from t
  for j = 0, len_t do
    v0[j] = j
  end
  
  for i = 1, len_s do
    -- Calculate v1 (current row distances) from the previous row v0
    
    -- First element of v1 is A[i+1][0]
    --   edit distance is delete i chars from s to match empty t
    v1[0] = i
    
    -- Use formula to fill in the rest of the row
    local ss = s[i]
    for j = 1, len_t do
      local tt = t[j]
      local substitution_cost
      if (type(ss) == type(tt)) then
        if (type(ss) == 'number') then
          substitution_cost = math.min(1, math.abs(ss - tt) / math.max(math.abs(ss), math.abs(tt)))
        else
          substitution_cost = (ss == tt) and 0 or 1
        end
      else
        substitution_cost = 1
      end
      assert(substitution_cost <= 1, 'Invalid cost!')
      v1[j] = math.min(v1[j-1] + 1, v0[j] + 1, v0[j-1] + substitution_cost)
    end
    
    -- Copy v1 (current row) to v0 (previous row) for next iteration
    --for j = 0, #v0 do v0[j] = v1[j] end
    v0, v1 = v1, v0
  end -- for s
  
  local distance = v1[len_t]
  local similarity = (1 - distance/math.max(len_s, len_t))
  
  return distance, similarity
end -- function LevenshteinDistanceArray

local function LevenshteinDistancePath(s, t)
  -- Check for degenerate cases
  local len_s, len_t = #s, #t
  if (len_s <= 0) then return end
  if (len_t <= 0) then return end
  -- Prepare distance matrix
  local D = torch.ShortTensor(len_s, len_t):zero()
  local function getD(i, j)
    if (i > 0) and (j > 0) then
      return D[i][j]
    elseif (j > 0) then
      return j
    elseif (i > 0) then
      return i
    end
    return 0
  end -- function getD
  -- Build distance matrix
  for i = 1, len_s do
    local ss = s[i]
    for j = 1, len_t do
      local tt = t[j]
      local deletion_cost = getD(i-1, j) + 1
      local insertion_cost = getD(i, j-1) + 1
      local substitution_cost = getD(i-1, j-1) + ((ss == tt) and 0 or 1)
      D[i][j] = math.min(deletion_cost, insertion_cost, substitution_cost)
    end -- for t
  end -- for s
  -- Prepare path matrix
  local P = torch.ByteTensor(len_s, len_t):zero()
  local function setP(i, j)
    if (i > 0) and (j > 0) then
      P[i][j] = 1
    end
  end -- function setP
  setP(len_s, len_t)
  -- Build path matrix
  for i = len_s, 1, -1 do
    for j = len_t, 1, -1 do
      if (P[i][j] > 0) then
        local a, b, c = getD(i-1, j), getD(i-1, j-1), getD(i, j-1)
        local min = math.min(a, b, c)
        if (a == min) then setP(i-1, j) end
        if (b == min) then setP(i-1, j-1) end
        if (c == min) then setP(i, j-1) end
      end -- if P[i][j]
    end -- for t
  end -- for s
  return D, P
end -- function LevenshteinDistancePath

function Syntax:entity(obj)
  local result
  if type(obj) == 'string' then
    local sequence = stringToSequence(obj)
    local code = table.concat(sequence, ' ')
    return { mishmash=sequence, sequence=sequence, code=code }
  elseif type(obj) == 'table' then
    if type(obj.sequence) == 'table' then
      obj.mishmash = obj.sequence
      result = obj
    elseif type(obj.mishmash) == 'table' then
      obj.sequence = obj.mishmash
      result = obj
    elseif type(obj.code or obj.exec) == 'string' then
      obj.mishmash = stringToSequence(obj.code or obj.exec)
      obj.sequence = obj.mishmash
      result = obj
    else
      result = { mishmash=obj, sequence=obj }
    end
    if (not result) or (not result.sequence) then return end
    if not result.code then
      result.code = table.concat(result.sequence, ' ')
    end
    if not result.hash then
      result.hash = hash(result.code)
    end
    return result
  end
end -- function Syntax:entity

function Syntax:decode(mishmash)
  local sequence = mishmash
  return sequence
end -- function Syntax:decode

function Syntax:encode(sequence)
  if type(sequence) == 'string' then
    sequence = stringToSequence(sequence)
  end
  assert(type(sequence) == 'table' and (#sequence > 0), 'Syntax:encode: Invalid sequence!')
  local mishmash = sequence
  return mishmash
end -- function Syntax:encode

function Syntax:getLength(mishmash)
  return #mishmash
end -- function Syntax:getLength

function Syntax:clone(mishmash)
  local result = {}
  for _, v in ipairs(mishmash) do table.insert(result, v) end
  return result
end -- function Syntax:clone

function Syntax:randomCommand()
  local t = math.random(Probabilities_Sum)
  local sum = 0
  for _, cmd in ipairs(Commands) do
    local p = Command_Probabilities[cmd]
    if (t <= sum + p) then
      if (cmd == '#') then
        cmd = self.random_numbers_min + math.random()*(self.random_numbers_max - self.random_numbers_min)
      end
      return cmd
    end
    sum = sum + p
  end
end -- function Syntax:randomCommand

function Syntax:randomLibrarySequence()
  assert(type(self.library) == 'table' and #self.library > 0,
    'Syntax:randomLibrarySequence: Library is not initialized!')
  local entity = assert(self.library[ math.random(#self.library) ],
    'Syntax:randomLibrarySequence: Failed to get random sequence from library!')
  if not entity.sequence then
    entity.sequence = stringToSequence(entity.code or entity.exec)
  end
  return entity.sequence
end -- function Syntax:randomLibrarySequence

function Syntax:randomMishmash(m, n)
  if not n then n = m; m = 1 end
  m = m or 1
  n = n or 150
  local len = math.random(m, n)
  local result = {}
  for i = 1, len do
    table.insert(result, self:randomCommand())
  end
  return result
end -- function Syntax:randomMishmash

function Syntax:crossOverSimple(mishmashA, mishmashB)
  local result = {}
  
  if (#mishmashA < 2) then
    for _, v in ipairs(mishmashB) do table.insert(result, v) end
    return result
  end
  if (#mishmashB < 2) then
    for _, v in ipairs(mishmashA) do table.insert(result, v) end
    return result
  end
  -- Search for possible places of split
  --local xa, xb = {}, {}
  --for i, cmd in ipairs(mishmashA) do
  --  if (cmd == 'XXX') or (cmd == 'Nop') then table.insert(xa, i) end
  --end
  --for i, cmd in ipairs(mishmashB) do
  --  if (cmd == 'XXX') or (cmd == 'Nop') then table.insert(xb, i) end
  --end
  --local ia = ((#xa > 1) and xa[ math.random(#xa) ]) or ((#xa == 1) and xa[1]) or math.random(#mishmashA)
  --local ib = ((#xb > 1) and xb[ math.random(#xb) ]) or ((#xb == 1) and xb[1]) or math.random(#mishmashA)
  local ia = math.random(2, #mishmashA)
  local ib = math.floor(#mishmashB * ia / #mishmashA)
  -- Specify start and end indexes
--  local as, ae, bs, be
--  if ia then
--    as, ae = 1, ia-1
--  else
--    as, ae = 1, #mishmashA
--  end
--  if ib then
--    bs, be = ib+1, #mishmashB
--  else
--    bs, be = 1, #mishmashB
--  end
  local as, ae = 1, ia-1
  local bs, be = ib, #mishmashB
  -- Combine sequences
  for i = as, ae do table.insert(result, mishmashA[i]) end
  --table.insert(result, 'XXX')
  for i = bs, be do table.insert(result, mishmashB[i]) end
  return result
end -- function Syntax:crossOverSimple

function Syntax:crossOver(mishmashA, mishmashB)
  local result = {}
  if (#mishmashA < 2) then
    for _, v in ipairs(mishmashB) do table.insert(result, v) end
    return result
  end
  if (#mishmashB < 2) then
    for _, v in ipairs(mishmashA) do table.insert(result, v) end
    return result
  end
  -- Choose random index in A
  local ia = math.random(
    math.max(2, math.floor(0.5 + #mishmashA/2 - #mishmashA/5)),
    math.min(#mishmashA, math.floor(0.5 + #mishmashA/2 + #mishmashA/5)))
  -- Calculate Levenstein distance and path matrixes
  local D, P = LevenshteinDistancePath(mishmashA, mishmashB)
  assert(P, 'Syntax:crossOver: Failed to calculate Levenshtein path')
  D = nil
  -- Select one of applicable B indexes
  local ibs = {}
  for j = 1, #mishmashB do
    if (P[ia][j] > 0) then table.insert(ibs, j) end
  end
  assert(#ibs > 0, 'Syntax:crossOver: Invalid Levenshtein path')
  local ib = ibs[ math.random(#ibs) ]
  -- Specify start and end indexes
  local as, ae = 1, ia-1
  local bs, be = ib, #mishmashB
  -- Combine sequences
  for i = as, ae do table.insert(result, mishmashA[i]) end
  for i = bs, be do table.insert(result, mishmashB[i]) end
  return result
end -- function Syntax:crossOver

function Syntax:mutateErase(mishmash, n)
  n = n and (n > 1) and math.random(n) or 1
  for i = 1, n do
    table.remove( mishmash, math.random(#mishmash) )
  end
  return mishmash
end -- function Syntax:mutateErase

function Syntax:mutateInsert(mishmash, n)
  n = n and (n > 1) and math.random(n) or 1
  for i = 1, n do
    local index = math.random(#mishmash + 1)
    if (not self.library) or (math.random() <= self.random_to_library_ratio) then
      table.insert( mishmash, index, self:randomCommand() )
    else
      local index = math.random(#mishmash)
      local sequence = self:randomLibrarySequence()
      for j = #sequence, 1, -1 do
        table.insert( mishmash, index, sequence[j] )
      end
    end
  end
  return mishmash
end -- function Syntax:mutateInsert

function Syntax:mutateSubstitute(mishmash, n)
  n = n and (n > 1) and math.random(n) or 1
  for i = 1, n do
    local index = math.random(#mishmash)
    local old = mishmash[index]
    if (type(old) == 'number') then
      local new
      if (old ~= 0) then
        new = old * (1 + (math.random() - 0.5)*self.substitute_numbers_ratio)
      else
        new = (math.random() - 0.5)
      end
      --print('#'..tostring(old)..'->#'..tostring(new))
      mishmash[index] = new
    elseif (not self.library) or (math.random() <= self.random_to_library_ratio) then
      local new = self:randomCommand()
      mishmash[index] = new
    else
      local sequence = self:randomLibrarySequence()
      table.remove( mishmash, index )
      for j = #sequence, 1, -1 do
        table.insert( mishmash, index, sequence[j] )
      end
    end
  end
  return mishmash
end -- function Syntax:mutateSubstitute

function Syntax:equals(mishmashA, mishmashB)
  if #mishmashA ~= #mishmashB then return false end
  for i = 1, #mishmashA do
    if mishmashA[i] ~= mishmashB[i] then
      return false
    end
  end
  return true
end -- function Syntax:equals

function Syntax:similarity(mishmashA, mishmashB)
  local distance, similarity = LevenshteinDistanceArray(mishmashA, mishmashB)
  return similarity
end -- function Syntax:similarity

---------------------------------------------------------------------
---------------------------------------------------------------------

-- Return if not running from console.
-- Continue to unit testing otherwise.
local info = debug.getinfo(2)
if info and (info.name or (info.what ~= 'C')) then
  return Syntax
end

---------------------------------------------------------------------
------- UNIT TESTS
---------------------------------------------------------------------

local function test_similarity_array(s, t)
  local distance, similarity = LevenshteinDistanceArray(stringToSequence(s), stringToSequence(t))
  print(s..'\n'..t)
  print('distance='..tostring(distance)..' similarity='..tostring(similarity)..'\n')
end
test_similarity_array('I I I I I Hours pc Delta Neg Nop 0 time Val Nop 0.79322 Gt Nop time Val Nop 0.86424 Lt Mul If Sum nume Max Sub I nume vol Val Nop ol nume ph Gt Nop Max',
  'I I I I I Hours pc Delta Neg Nop 0 time Val Nop 0.81029 Gt Nop time Val Nop 0.8821 Lt Nop Mul If Prod Val nume Max Max Prod oh vol Max Gt I Max vwap')

require 'torch'
math.randomseed( os.time() )

local function cross(a, b, index_a)
  local s, t = {}, {}
  for i = 1, a:len() do table.insert(s, a:sub(i, i)) end
  for j = 1, b:len() do table.insert(t, b:sub(j, j)) end
  local r = Syntax:crossOver(s, t)
  assert(type(r) == 'table', 'Failed Syntax:crossOver')
  r = table.concat(r, ' ')
  print(a .. ' + ' .. b ..'\n='.. r)
end -- function cross

cross('Saturday', 'Sunday')
cross('Sunday', 'Saturday')
cross('Levenshtein', 'Distance')
