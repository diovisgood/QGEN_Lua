local lfs = require 'lfs'
local torch = require 'torch'

package.path = './?.lua;' .. package.path

local Env = dofile 'env.lua'
local Score = dofile 'score.lua'
local Syntax = dofile 'syntax.lua'
local Genetic = dofile 'genetic.lua'
local Species = dofile 'species.lua'
local Data = dofile 'data.lua'

local Dataset

local function loadDataset()
  print('Loading Dataset...')
  Dataset = Env.universalLoad(Dataset_File, 'binary')
  assert(Dataset, 'main: Failed to load Dataset from '..tostring(Dataset_File))
  print('Loaded Dataset from '..tostring(Dataset_File))
  Env.printInfo('Dataset', Dataset)
  Data.addExpand(Dataset)
  Score.dataset = Dataset
  -- Get dataset last time
  local last_series = Dataset[#Dataset]
  assert((type(last_series) == 'table')
    and (type(last_series.candles) == 'table')
    and last_series.candles.tc,
    'loadDataset: Invalid dataset!')
  Dataset.last_time = last_series.candles.tc[-1]
end -- function loadDataset

-- Load and initialize library for insertion and substitution operations
local Library = dofile('library.dat')
local Library_Record_Average_Length = 0
for i, entity in ipairs(Library) do
  Library[i] = Syntax:entity(entity)
  entity.mishmash = Syntax:encode(entity.code or entity.exec)
  entity.sequence = Syntax:decode(entity.mishmash)
  Library_Record_Average_Length = Library_Record_Average_Length + #entity.sequence
end
if (#Library > 0) then
  Library_Record_Average_Length = Library_Record_Average_Length / #Library
end
print('Loaded library of '..tostring(#Library)..' elements from library.dat')

local Names = dofile('names.dat')
for i, v in ipairs(Names) do Names[i] = v:lower() end
print('Loaded '..tostring(#Names)..' names from names.dat')

local Index

local function generateNewName()
  local name, is_unique
  repeat
    name = Names[ math.random(#Names) ]
    is_unique = true
    for _, specie in ipairs(Index) do
      if specie.name == name then
        is_unique = false
        break
      end
    end
  until is_unique
  return name
end -- function generateNewName

local function getRandomIndex(N, kind)
  if (not kind) or (kind == 'uniform') then
    return math.random(N)
  end
  local p = (1 / 5)
  local sn = math.pow(N, (p+1)) / (p+1)
  return math.ceil( math.exp( math.log(sn*math.random()*(p+1)) / (p+1)) )
end -- function getRandomIndex

local function main()
  local reason
  
  local work_dir = arg[1]
  if work_dir then
    assert( lfs.chdir(work_dir) )
    print('Changed dir to '..work_dir)
  end
  dofile 'config.lua'
  assert(Dataset_File and Iterations_In_Epoch and Autosave_Interval and Species_Count_Limit
    and Population_Size and Negative_Rate_Epochs_Limit and Negative_Rate_Profit_Factor_Limit,
    'Invalid config file!')
  
  -- Initialize Torch
  math.randomseed( os.time() )
  --torch.manualSeed(1)
  torch.setdefaulttensortype('torch.FloatTensor')
  torch.setnumthreads(2)
  
  -- Initialize insert and substitute library in Syntax
  Syntax.library = Library
  
  local specie
  local f_save_index
  
  while true do
    
    -- Load Dataset or reload it if it has changed
    local attr = lfs.attributes(Dataset_File)
    if (not Dataset) or (not Dataset.file_attributes)
    or (attr.size ~= Dataset.file_attributes.size)
    or (attr.modification ~= Dataset.file_attributes.modification) then
      loadDataset()
      assert(type(Dataset) == 'table', 'main: Failed to load dataset!')
      Dataset.file_attributes = attr
    end
    
    -- Aquire and lock index
    print('Aquiring index...')
    Index = assert( Species.getIndex() )
    print('Index has '..tostring(#Index)..' records')
    f_save_index = false
    
    -- Update previous specie's info
    if specie then
      print('Updating index for specie '..tostring(specie.name))
      -- Generate new specie's info
      local info = assert( Species.getSpecieInfo(specie) )
      Index:update(specie.name, info)
      f_save_index = true
      -- Check if specie has negative annual_rate
      -- and reached max allowed limit
      if ((not info.best_rate) or (info.best_rate < 0))
      and ((info.epochs_count or 0) >= Negative_Rate_Epochs_Limit)
      and ((info.profit_factor or 0) < Negative_Rate_Profit_Factor_Limit) then
        -- Reset specie and start from the scratch
        print('Specie has negative best_rate and reached max allowed limit. Resetting...')
        specie:reset()
        specie.update_count = 0
        specie:preparePopulation()
        -- New info
        info = assert( Species.getSpecieInfo(specie) )
        Index:update(specie.name, info)
      end
      -- Save specie
      print('Saving specie '..tostring(specie.name))
      assert( specie:save() )
      specie:export()
      -- Unlock specie file
      print('Unlocking '..tostring(specie.name))
      specie:close()
      specie = nil
    end
    
    -- Check if all species are profitable
    io.write('Checking if all species are profitable... ')
    local all_species_are_profitable = true
    for _, info in ipairs(Index) do
      if (not info.annual_rate) or (info.annual_rate <= 0) then
        all_species_are_profitable = false
        break
      end
    end
    
    -- Create new specie if all existing are profitable
    if all_species_are_profitable and (#Index < (Species_Count_Limit or 70)) then
      print('True')
      local name = generateNewName()
      print('Creating new specie '..tostring(name))
      local specie = assert( Species.createSpecie(name) )
      specie = Genetic.initialize(specie, Syntax, Score)
      specie:save()
      specie:close()
      -- Add new specie info into index
      print('Updating index for specie '..tostring(name))
      local info = assert( Species.getSpecieInfo(specie) )
      specie:preparePopulation()
      Index:update(name, info)
      f_save_index = true
      specie = nil
    else
      print('False')
    end
    
    -- Randomly select next specie to process
    -- Some special non-linear randomness is used
    --  so that species with low score are selected more often
    Index:sort()
    local i = #Index -- Try the last specie first
    repeat
      i = getRandomIndex(#Index)
      local info = Index[i]
      io.write('Opening '..tostring(info.name)..' ... ')
      io.flush()
      specie, reason = Species.openSpecie(info.name)
      if specie then
        print('Ok')
        info = assert( Species.getSpecieInfo(specie) )
        Env.printInfo('specie info', info)
        Index:update(info.name, info)
        break
      end
      print('Failed: '..tostring(reason))
      --i = getRandomIndex(#Index)
    until specie
    
    -- Unlock index file but keep it's contents loaded in 'Index'
    if f_save_index then
      print('Saving index')
      Index:save()
    end
    print('Unlocking index')
    Index:close()
    
    -- Initialize specie
    if specie.name then
      local splitter = string.rep('-', 4 + specie.name:len())
      io.write(splitter,'\n  ', string.upper(tostring(specie.name)), '  \n', splitter, '\n')
    end
    specie = Genetic.initialize(specie, Syntax, Score)
    print('Initializing specie '..tostring(specie.name))
    io.flush()
    specie.population_size = (Population_Size or 100)
    specie:preparePopulation()
    specie.max_score = nil
    for _, entity in ipairs(specie) do
      entity.score = nil
      entity.vectors = nil
      entity.annual_rate = nil
    end
    
    -- Check dataset last time and epoch counters
    if (not specie.dataset_last_time) or (specie.dataset_last_time ~= Dataset.last_time) then
      print('Database has changed since last epoch. Purging cache...')
      specie.dataset_last_time = Dataset.last_time
      specie:purgeHistory(Population_Size)
      specie.update_count = 0
    end
    specie.epochs_count = specie.epochs_count or 0
    specie.update_count = specie.update_count or 0
    
    -- Initialize list of other concurrent species
    print('Initializing competitors:')
    Score.prototypes = {}
    local competitors = {}
    for i, info in ipairs(Index) do
      io.write('\rProcessing specie '..tostring(i)..'/'..tostring(#Index))
      io.flush()
      if (info.name ~= specie.name) and info.annual_rate and (info.annual_rate > 0) then
        local competitor_entity = assert( Syntax:entity(info.best_code), 'main: Invalid concurrent entity')
        Score:calculate(competitor_entity)
        if competitor_entity.annual_rate and (competitor_entity.annual_rate > 0)
        and competitor_entity.vectors then
        --assert(concurrent_entity.annual_rate and concurrent_entity.annual_rate > 0,
        --  'main: Invalid concurrent entity annual_rate')
        --assert(competitor_entity.vectors,
        --  'main: Invalid competitor entity vectors')
          table.insert(competitors, competitor_entity)
        end
      end
    end -- for species infos
    io.write('\n')
    Score.prototypes = competitors
    print('Initialized '..tostring(#competitors)..' competitors')
    
    -- Update Score parameters
    print('Calculating mean entity length:')
    local mean, std = specie:calculateLengthMeanStd()
    if (not mean) or (mean <= 0) then mean = 30 end
    if (not std) or (std <= 0) then std = 0.05*mean end
    Score.sequence_max = math.floor(0.5 + mean + math.max(2*std, Library_Record_Average_Length))
    print('Entities sequence length mean='..tostring(mean)..' std='..tostring(std))
    
    print('Starting epoch of evolution (Autosave_Interval='..tostring(Autosave_Interval)
      ..' Iterations_In_Epoch='..tostring(Iterations_In_Epoch)..')')
    
    -- Perform one epoch of evalution
    while true do
      local entity = specie[1]
      specie.allow_random = (not entity.annual_rate) or (entity.annual_rate <= 0)
      
      -- Do one iteration of genetic algorithm
      local best_score = specie:iterate(true)
      
      -- Set winner counter for all entities
      entity = specie[1]
      entity.winner = (entity.winner or 0) + 1
      for p = 2, #specie do
        specie[p].winner = nil
      end
      
      if (entity.winner < 2) then
        Env.printInfo(' Best entity:', entity)
      end
      
      print((work_dir and tostring(work_dir) or '')..' '
        ..tostring(specie.name)
        ..' Iter: '..tostring(specie.iterations_count)
        ..' Epochs: '..tostring(specie.epochs_count)
        ..' Update: '..tostring(specie.update_count)
        ..' Score: '..tostring(best_score)
        ..' Winner: '..tostring(entity.winner))
      
      specie.last_iteration_time = os.time()
      if (specie.iterations_count % Iterations_In_Epoch == 0) then
        break
      end
      
      if Autosave_Interval and (specie.iterations_count % Autosave_Interval == 0) then
        print('Autosaving specie '..tostring(specie.name))
        assert( specie:save() )
      end
    end -- while iterations
    
    specie.epochs_count = specie.epochs_count + 1
    specie.update_count = specie.update_count + 1
    
  end -- while true
  
end -- function main

main()
