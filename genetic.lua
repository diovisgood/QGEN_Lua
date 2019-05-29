
local Genetic = {}

function Genetic.initialize(self, syntax, score)
  self = self or {}
  
  -- Save link to syntax
  assert(type(syntax) == 'table'
    and type(syntax.clone) == 'function'
    and type(syntax.decode) == 'function'
    and type(syntax.encode) == 'function'
    and type(syntax.getLength) == 'function'
    and type(syntax.randomMishmash) == 'function'
    and type(syntax.crossOver) == 'function'
    and type(syntax.mutateErase) == 'function'
    and type(syntax.mutateInsert) == 'function'
    and type(syntax.mutateSubstitute) == 'function',
    'Genetic:initialize: Invalid syntax specified!')
  --self.syntax = syntax
  
  -- Save link to score
  assert(type(score) == 'table' and type(score.calculate) == 'function',
    'Genetic:initialize: Invalid score specified!')
  --self.score = score
  
  -- Number of 'organisms' on each iteration. 10 is Minimum!
  self.population_size = math.max(10, self.population_size or 100)
  
  -- Double value in [0,1), excluding 1.<br/>
  -- Specifies what percent of population should be copied to new population without mutation.<br/>
  -- It is useful to preserve some of the best 'organisms' unchanged.
  self.preserve_rate = self.preserve_rate or 0.6
  
  self.allow_erase = self.allow_erase or true
  self.allow_insert = self.allow_insert or true
  self.allow_substitute = self.allow_substitute or true
  self.allow_cross_breeding = self.allow_cross_breeding or true
  self.allow_random = self.allow_random or false
  
  -- Double value in (0,1), excluding 0 and 1.<br/>
  -- Specifies what percent of genes should be altered by mutation.
  self.mutation_factor_min = self.mutation_factor_min or 0.01
  self.mutation_factor_max = self.mutation_factor_min or 0.15
  self.mutation_factor_score = self.mutation_factor_score or 2000
  
  self.history = self.history or {}
  self.epochs_count = self.epochs_count or 0
  self.iterations_count = self.iterations_count or 0
  self.last_serial = self.last_serial or 0
  self.max_score = self.max_score or 0
  
  -- Update metatable
  local mt = getmetatable(self) or {}
  local __index = mt.__index
  if type(__index) ~= 'table' then __index = {}; mt.__index = __index end
  __index.syntax = syntax
  __index.score = score
  for k, v in pairs(Genetic) do
    if type(v) == 'function' then
      __index[k] = v
    end
  end
  return setmetatable(self, mt)
end -- function Genetic.initialize

function Genetic:reset()
  for i = #self, 1, -1 do
    table.remove(self, i)
  end
  self.history = {}
  self.iterations_count = 0
  self.epochs_count = 0
  self.last_serial = 0
end -- function Genetic:reset

--- <summary>
--- Creates initial population from one textual initial entities.<br/>
--- After calling this method population will contain population_size organisms.<br/>
--- This method also sets iteration_count to zero.
--- </summary>
--- <param name="initial">array or entities or string of mishmash</param>
function Genetic:preparePopulation(initial)
  local syntax = self.syntax
  -- Create entities based on initial entities
  if type(initial) == 'table' then
    for _, entity in ipairs(initial) do
      assert(type(entity) == 'table' and entity.mishmash,
        'Genetic:preparePopulation: Invalid initial entity!')
      local mishmash = syntax:clone(entity.mishmash)
      if mishmash then
        local entity = syntax:entity(mishmash)
        self.last_serial = (self.last_serial or 0) + 1
        entity.serial = self.last_serial
        table.insert(self, entity)
      end
    end
  end
  -- Check and correct existing entities
  for p = #self, 1, -1 do
    local entity = syntax:entity( self[p] )
    if entity and (not entity.sequence) then
      entity = syntax:entity(entity)
    end
    if (not entity) or (not entity.sequence) then
      table.remove(self, p)
    else
      if not entity.serial then
        self.last_serial = (self.last_serial or 0) + 1
        entity.serial = self.last_serial
      end
      self[p] = entity
    end
  end
  local nbase = #self
  if nbase > 0 then
    -- Create all other entities as mutated copies of initial
    for p = nbase+1, self.population_size do
      local entity = self[ math.random(nbase) ]
      local mishmash = self:mutate(entity.mishmash)
      if mishmash then
        mishmash = self:mutate( mishmash )
        entity = syntax:entity(mishmash)
        self.last_serial = (self.last_serial or 0) + 1
        entity.serial = self.last_serial
        table.insert(self, entity)
      end
    end
  else
    -- Create random entities
    for p = 1, self.population_size do
      local mishmash = self.syntax:randomMishmash(10, 50)
      if mishmash then
        local entity = syntax:entity(mishmash)
        self.last_serial = (self.last_serial or 0) + 1
        entity.serial = self.last_serial
        table.insert(self, syntax:entity(mishmash))
      end
    end
  end
end -- function Genetic:preparePopulation

function Genetic:calculateLengthMeanStd()
  -- Calculate mean length
  local count, mean = 0, 0
  for _, entity in ipairs(self) do
    if entity.mishmash then
      mean = (mean or 0) + self.syntax:getLength(entity.mishmash)
      count = count + 1
    end
  end
  if (count <= 0) then return end
  mean = mean / count
  
  -- Calculate dispersion
  local std = 0
  for _, entity in ipairs(self) do
    if entity.mishmash then
      std = std + (self.syntax:getLength(entity.mishmash) - mean)^2
    end
  end
  std = math.sqrt(std / count)
  
  return mean, std
end -- function Genetic:calculateLengthMeanStd
  
function Genetic:mutate(mishmash, mutation_factor)
  mutation_factor = mutation_factor or self.mutation_factor or (self.mutation_factor_min + self.mutation_factor_max)/2
  local factors = (self.allow_erase and 1 or 0) + (self.allow_insert and 1 or 0)
    + (self.allow_substitute and 1 or 0)
  
  local syntax = self.syntax
  local result = syntax:clone(mishmash)
  local n = syntax:getLength(mishmash) * mutation_factor
  if n > 1 then
    n = math.floor(n)
  else
    if math.random() > n then return result end
    n = 1
  end
  
  for i = 1, n do
    local kind = math.random(factors)
    if self.allow_erase then
      if (kind == 1) then
        syntax:mutateErase(result)
      end
      kind = kind - 1
    end
    if self.allow_insert then
      if (kind == 1) then
        syntax:mutateInsert(result)
      end
      kind = kind - 1
    end
    if self.allow_substitute then
      if (kind == 1) then
        syntax:mutateSubstitute(result)
      end
      kind = kind - 1
    end
  end -- for

  return result
end -- function Genetic:mutate

local function soft_decline_func(x, half)
  half = half or 1.678348
  if x > 0 then
    return (x*1.678348/half + 1) * math.exp(-x*1.678348/half)
  end
  return 1
end -- function soft_decline_func

function Genetic:contains(entity)
  assert(entity.hash and entity.mishmash, 'Genetic:contains: Entity has no hash or mishmash!')
  for _, _entity in ipairs(self) do
    if not _entity.hash then
      _entity.hash = hash(_entity.code)
    end
    if _entity.hash then
      if (entity.hash == _entity.hash) then return true end
    elseif _entity.mishmash then
      if self.syntax:equals(entity.mishmash, _entity.mishmash) then return true end
    end
  end
end -- function Genetic:contains

function Genetic:iterate(verbose)
  -- Assign scores to entities in population
  for p, entity in ipairs(self) do
    if verbose then
      io.write('\rProcessing '..tostring(p)..'/'..tostring(#self))
      io.flush()
    end
    
    -- Process unprocessed entities
    if not entity.score then
      local score, reason = self.score:calculate(entity)
      entity.score = score
      entity.reason = reason
      if entity.hash then
        self.history[entity.hash] = entity.serial or true
      end
    end
  end -- for entities
  if verbose then
    io.write('\rSelecting best entities...')
    io.flush()
  end
  
  -- Sort population based on scores
  table.sort(self, function(a,b) return (a.score > b.score) end)
  self.iterations_count = (self.iterations_count or 0) + 1
  
  -- Update average score based on best score
  local max_score = self[1].score or 0
  if self.max_score and (self.max_score > max_score) then
    error('Genetic:iterate: Error: Max score in population must not decrease!')
  end
  self.max_score = max_score
  
  -- Prepare next population
  -- Remove entities that did not pass the selection
  local reserv = math.floor(self.preserve_rate*#self)
  for i = #self, reserv+1, -1 do
    table.remove(self, i)
  end
  
  -- Apply cross breedings
  if self.allow_cross_breeding then
    for p = 1, math.floor((self.population_size - reserv)/2) do
      if verbose then
        io.write('\rCreating new entities '..tostring(#self+1)..'/'..tostring(self.population_size)
          ..' by cross-breeding')
        io.flush()
      end
      self.last_serial = (self.last_serial or 0) + 1
      local ia = math.random(reserv)
      local mishmash, entity
      local counter = 0
      repeat
        local ib
        repeat ib = math.random(reserv) until ib ~= ia
        local a, b = self[ia], self[ib]
        mishmash = self.syntax:crossOver(a.mishmash, b.mishmash)
        counter = counter + 1
        if (counter > 10) then
          mishmash = self:mutate(mishmash)
        end
        entity = self.syntax:entity(mishmash)
        entity.serial = self.last_serial
      until (not self.history[entity.hash]) and (not self:contains(entity))
      table.insert(self, entity)
    end
  end
  
  -- Apply mutations
  for p = #self+1, (self.population_size - (self.allow_random and 1 or 0)) do
    if verbose then
      io.write('\rCreating new entities '..tostring(#self+1)..'/'..tostring(self.population_size)
        ..' by mutations')
      io.flush()
    end
    local a = self[ math.random(reserv) ]
    local mutation_factor = soft_decline_func(a.score or 0, self.mutation_factor_score)
    mutation_factor = self.mutation_factor_min
      + mutation_factor*(self.mutation_factor_max - self.mutation_factor_min)
    self.last_serial = (self.last_serial or 0) + 1
    local mishmash, entity
    repeat
      mishmash = self:mutate(a.mishmash, mutation_factor)
      entity = self.syntax:entity(mishmash)
      entity.serial = self.last_serial
    until (not self.history[entity.hash]) and (not self:contains(entity))
    table.insert(self, entity)
  end
  
  -- Insert random string
  if self.allow_random then
    self.last_serial = (self.last_serial or 0) + 1
    local mishmash = self.syntax:randomMishmash(10, 50)
    local entity = self.syntax:entity(mishmash)
    entity.serial = self.last_serial
    table.insert(self, entity)
  end
  if verbose then io.write('\r') end
  
  local purge_length = 0
  if self.last_serial and self[1] and self[1].serial then
    purge_length = 1.5*(self.last_serial - self[1].serial)
  end
  self:purgeHistory(math.max(self.population_size * 1000, purge_length))
  
  return max_score
end -- function Genetic:iterate

function Genetic:purgeHistory(limit)
  limit = limit or self.population_size * 1000
  limit = self.last_serial - limit
  for hash, serial in pairs(self.history) do
    if (type(serial) ~= 'number') or (serial <= limit) then
      self.history[hash] = nil
    end
  end
end -- function Genetic:purgeHistory

return Genetic
