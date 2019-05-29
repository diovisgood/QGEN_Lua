local lfs = require 'lfs'
local zlib = require 'zlib'

local filelock = require 'ipc.filelock'

local File_Name_Pattern = '^(%a+)%.specie%.gz$'

local function specieFileNameToName(file_name)
  return string.match(file_name, File_Name_Pattern)
end

local function specieNameToFileName(name)
  return tostring(name)..'.specie.gz'
end

local ENOENT = 2

local ffi = require 'ffi'
ffi.cdef[[
int kill(unsigned int pid, int sig);

typedef struct {
  char *fpos;
  void *base;
  unsigned short handle;
  short flags;
  short unget;
  unsigned long alloc;
  unsigned short buffincrement;
} FILE;
int fileno(FILE* stream);
int ftruncate(int fd, unsigned int length);
int truncate(const char* path, unsigned int length);
unsigned int sleep(unsigned int seconds);
char* strerror(int errnum);
]]

local function ftruncate(file, size)
  local fd = ffi.C.fileno(file)
  if (not fd) or (fd == -1) then
    local errno = ffi.errno
    return nil, ffi.string( ffi.C.strerror(errno) ), errno
  end
  if not size then
    local reason, errno
    size, reason, errno = file:seek()
    if not size then return nil, reason, errno end
  end
  local result = ffi.C.ftruncate(fd, size)
  if (not result) or (result ~= 0) then
    local errno = ffi.errno
    return nil, ffi.string( ffi.C.strerror(errno) ), errno
  end
  return size
end -- function ftruncate

local Species = {}

function Species.findSpeciesFiles(dir_path, limit)
  dir_path = dir_path or '.'
  -- Search filenames for given security name
  local files = {}
  for file_name in lfs.dir(dir_path) do
    local name = specieFileNameToName(file_name)
    if name then
      if (dir_path ~= '.') then
        file_name = dir_path .. '/' .. file_name
      end
      table.insert(files, file_name)
      if limit and (#files >= limit) then break end
    end
  end
  if #files <= 0 then return nil, 'Species files not found!' end
  table.sort(files)
  return files
end -- function Species.findSpeciesFiles

local Entity_Fields = {
  'code', 'exec', 'text', 'rate', 'annual_rate', 'annual_rate_std', 'max_drawdown_percent',
  'profit_factor', 'best_duration', 'max_proto_corr', 'signal_pos', 'signal_neg', 'serial'
}
local Specie_Fields = {
  'name', 'dataset_last_time', 'last_iteration_time', 'iterations_count',
  'epochs_count', 'update_count', 'last_serial',
}
local Info_Fields = { 'name', 'best_score',
  'best_code', 'best_exec', 'best_text', 'best_rate', 'annual_rate', 'annual_rate_std',
  'max_drawdown_percent', 'profit_factor', 'best_duration', 'max_proto_corr', 'signal_pos', 'signal_neg',
  'best_serial', 'last_serial', 'dataset_last_time', 'last_iteration_time', 'iterations_count',
  'epochs_count', 'update_count',
}

local function writeField(file, tab, field, indent)
  local result, reason, errno
  indent = indent or ''
  local v = tab[field]
  local t = type(v)
  if (t == 'string') then
    result, reason, errno = file:write(indent, field, '=\'', v, '\',\r\n')
    if not result then return nil, reason, errno end
  elseif (t == 'number') and (field:sub(-5) == '_time') then
    result, reason, errno = file:write(indent, field, '=', tostring(v), ', -- ',
      os.date('%Y-%m-%d %H:%M:%S', v), '\r\n')
    if not result then return nil, reason, errno end
  elseif (t ~= 'nil') then
    result, reason, errno = file:write(indent, field, '=', tostring(v), ',\r\n')
    if not result then return nil, reason, errno end
  end
  return true
end

local function specieExport(self, file_name)
  file_name = file_name or (self.name..'.export.dat')
  local file = assert( io.open(file_name, 'w') )
  assert( file:write('return {\r\n') )
  
  for _, entity in ipairs(self) do
    assert((type(entity) == 'table') and (type(entity.code) == 'string'),
      'speciesExport: code not found in entity!')
    assert( file:write('  {\r\n') )
    for _, field in ipairs(Entity_Fields) do
      assert( writeField(file, entity, field, '    ') )
    end
    file:write('  },\r\n')
  end -- for population
  
  for _, field in ipairs(Specie_Fields) do
    assert( writeField(file, self, field, '  ') )
  end
  
  assert( file:write('}\r\n') )
  file:close()
  return true
end -- function specieExport

local function specieSave(self, file, format)
  format = format or 'binary'
  local result, reason, errno
  -- Seek to the beginning of file
  result, reason, errno = file:seek('set', 0)
  if not result then return nil, reason, errno end
  -- Serialize specie (i.e. self)
  local inflated
  result, inflated = pcall( torch.serialize, self, format )
  if not result then return nil, inflated end
  -- Get zlib stream to create .gz compatible file
  local stream
  result, stream = pcall( zlib.deflate, 6, 15+16 )
  if not result then return nil, stream end
  -- Compress data
  local deflated
  result, deflated = pcall( stream, inflated, 'finish' )
  if not result then return nil, deflated end
  inflated = nil
  -- Write compressed data to file
  result, reason, errno = file:write(deflated)
  if not result then return nil, reason, errno end
  return ftruncate(file)
end -- function specieSave

function Species.importSpecieFromFile(file_name)
  local status, specie = pcall(dofile, file_name)
  if not status then return nil, result end
  if (type(specie) ~= 'table') then return nil, 'Invalid content in specie file' end
  if (type(specie.name) ~= 'string') then
    local name = file_name:match('specie%-(%a+)%.dat$')
    specie.name = name
  end
  -- Update metatable
  local mt = getmetatable(specie) or {}
  local __index = mt.__index
  if type(__index) ~= 'table' then __index = {}; mt.__index = __index end
  __index.close = function() end
  __index.save = function(self)
    local file_name = specieNameToFileName(specie.name)
    local file, reason, errno = io.open(file_name, 'r+b')
    if not file then return nil, reason, errno end
    local result
    result, reason, errno = specieSave(self, file, 'binary')
    file:close()
    return result, reason, errno
  end
  __index.export = specieExport
  return setmetatable(specie, mt)
end -- function Species.importSpecieFromFile

function Species.findAndLoadSpecies()
  local files, reason = Species.findSpeciesFiles()
  if not files then return nil, reason end
  local result = {}
  for _, file_name in ipairs(files) do
    local specie
    print('Loading specie from '..tostring(file_name)..'...')
    specie, reason = Species.importSpecieFromFile(file_name)
    if specie then
      table.insert(result, specie)
    else
      print(' - '..tostring(reason))
    end
  end -- for files
  if #result <= 0 then return nil, 'Failed to load any file!' end
  return result
end -- function Species.findAndLoadSpecies

local function indexSort(self)
  table.sort(self, function(a, b)
      local ar, br = (a.annual_rate or -math.huge), (b.annual_rate or -math.huge)
      if (ar*br < 0) and (ar > br) then
        return true
      elseif (ar*br < 0) and (ar < br) then
        return false
      elseif (a.best_score or -math.huge ) > (b.best_score or -math.huge) then
        return true
      elseif (a.best_score or -math.huge ) < (b.best_score or -math.huge) then
        return false
      else
        return (a.epochs_count or 0) > (b.epochs_count or 0)
      end
    end)
end

local function indexSave(self, file)
  local result, reason, errno
  -- Seek to the beginning of file
  result, reason, errno = file:seek('set', 0)
  if not result then return nil, reason, errno end
  -- Write index
  result, reason, errno = file:write('return {\r\n')
  if not result then return nil, reason, errno end
  -- Sort species info
  indexSort(self)
  -- Cycle through species info blocks
  for _, info in ipairs(self) do
    if (type(info) == 'table')
    and (type(info.name) == 'string') then
    --and (type(info.best_code) == 'string') then
      result, reason, errno = file:write('  {\r\n')
      if not result then return nil, reason, errno end
      for _, field in ipairs(Info_Fields) do
        result, reason, errno = writeField(file, info, field, '    ')
        if not result then return nil, reason, errno end
      end
      result, reason, errno = file:write('  },\r\n')
      if not result then return nil, reason, errno end
    end
  end
  result, reason, errno = file:write('}\r\n')
  if not result then return nil, reason, errno end
  return ftruncate(file)
end -- indexSave

local function indexUpdate(self, name, new_info)
  for i, info in ipairs(self) do
    if (info.name == name) then
      self[i] = new_info
      return
    end
  end
  table.insert(self, new_info)
end -- function indexUpdate

function Species.getSpecieInfo(specie)
  if (type(specie) ~= 'table')
  or (type(specie.name) ~= 'string')
  or (type(specie.iterations_count) ~= 'number')
  then return nil end
  local info = {}
  info.name = specie.name
  info.last_serial = specie.last_serial
  info.dataset_last_time = specie.dataset_last_time
  info.last_iteration_time = specie.last_iteration_time
  info.iterations_count = specie.iterations_count
  info.epochs_count = specie.epochs_count
  info.update_count = specie.update_count
  local entity = specie[1]
  if (type(entity) == 'table') then
    info.best_code = entity.code
    info.best_exec = entity.exec
    info.best_text = entity.text
    info.best_score = entity.score
    info.best_rate = entity.rate
    info.annual_rate = entity.annual_rate
    info.annual_rate_std = entity.annual_rate_std
    info.max_drawdown_percent = entity.max_drawdown_percent
    info.profit_factor = entity.profit_factor
    info.best_duration = entity.best_duration
    info.max_proto_corr = entity.max_proto_corr
    info.signal_pos = entity.signal_pos
    info.signal_neg = entity.signal_neg
    info.best_serial = entity.serial
  end
  return info
end -- function Species.getSpecieInfo

function Species.getIndex(dir_path)
  dir_path = dir_path or '.'
  local index_file_name = dir_path..'/index.dat'
  -- Open index file for read and update
  local result, reason, errno
  local file
  file, reason, errno = io.open(index_file_name, 'r+')
  if not file then
    if (errno ~= ENOENT) then return nil, reason, errno end
    -- Create new file if it doesn't exist
    file, reason, errno = io.open(index_file_name, 'w')
    if not file then return nil, reason, errno end
  end
  -- Lock file
  result, reason, errno = filelock.lock(file, 'w')
  if not result then return nil, reason, errno end
  -- Prepare close function
  local function indexClose()
    filelock.unlock(file)
    file:close()
    file = nil
  end
  -- Read index file
  local index
  local text
  text, reason, errno = file:read('*a')
  if text then
    local f
    f, reason = loadstring(text)
    if f then
      -- Safely load index with pcall
      result, index = pcall( f )
    end
  end
  -- Check if index was loaded or construct empty table otherwise
  if (type(index) ~= 'table') then index = {} end
  -- Get names from loaded index
  local names_from_index = {}
  for i = #index, 1, -1 do
    local info = index[i]
    if info.name then
      names_from_index[info.name] = i
    end
  end
  -- Find all species files
  local file_names
  file_names, reason = Species.findSpeciesFiles(dir_path)
  if (not file_names) then indexClose(); return nil, reason end
  -- Get names from file_names
  local names_from_files = {}
  for _, file_name in ipairs(file_names) do
    local name = specieFileNameToName(file_name)
    if name then names_from_files[name] = file_name end
  end
  local f_save_index
  -- Check invalid (non-existing) records in index
  for i = #index, 1, -1 do
    local info = index[i]
    if not names_from_files[info.name] then
      table.remove(i)
      f_save_index = true
    end
  end
  -- Remove non-numeric indexes from index
  for k, info in pairs(index) do
    if type(k) ~= 'number' then
      index[k] = nil
      f_save_index = true
    end
  end
  -- Check missing records in index
  for name, file_name in pairs(names_from_files) do
    if not names_from_index[name] then
      local specie = Species.openSpecie(name)
      if specie then
        local info = Species.getSpecieInfo(specie)
        if info then
          info.name = name
          table.insert(index, info)
          f_save_index = true
        end
        specie:close()
      end
    end
  end
  -- Save file if modified index
  if f_save_index then
    indexSave(index, file)
  end
  -- Update metatable
  local mt = getmetatable(index) or {}
  local __index = mt.__index
  if type(__index) ~= 'table' then __index = {}; mt.__index = __index end
  __index.update = indexUpdate
  __index.sort = indexSort
  __index.close = indexClose
  __index.save = function(self) return indexSave(self, file) end
  return setmetatable(index, mt)
end -- function Species.getIndex

function Species.createSpecie(name, format)
  format = format or 'binary'
  local result, reason, errno
  -- Create new file
  local file
  local file_name = specieNameToFileName(name)
  file, reason, errno = io.open(file_name, 'w+b')
  if not file then return nil, reason, errno end
  -- Lock file
  result, reason, errno = lfs.lock(file, 'w')
  if not result then file:close(); return nil, reason, errno end
  -- Prepare close function
  local function specieClose()
    lfs.unlock(file)
    file:close()
    file = nil
  end
  local specie = { name = name }
  -- Update metatable
  local mt = getmetatable(specie) or {}
  local __index = mt.__index
  if type(__index) ~= 'table' then __index = {}; mt.__index = __index end
  __index.close = specieClose
  __index.save = function(self) return specieSave(self, file, format) end
  __index.export = specieExport
  return setmetatable(specie, mt)
end -- function Species.createSpecie

function Species.saveSpecie(specie, format)
  format = format or 'binary'
  assert(type(specie) == 'table' and type(specie.name) == 'string',
    'Species.saveSpecie: Invalid specie')
  local result, reason, errno
  -- Create new file
  local file
  local file_name = specieNameToFileName(specie.name)
  file, reason, errno = io.open(file_name, 'w+b')
  if not file then return nil, reason, errno end
  -- Lock file
  result, reason, errno = lfs.lock(file, 'r')
  if not result then file:close(); return nil, reason, errno end
  -- Write specie to file
  result, reason, errno = specieSave(specie, file, format)
  lfs.unlock(file)
  file:close()
  return result, reason, errno
end -- function Species.saveSpecie

function Species.openSpecie(name, format)
  format = format or 'binary'
  local result, reason, errno
  -- Open existing file for read and update
  local file
  local file_name = specieNameToFileName(name)
  file, reason, errno = io.open(file_name, 'r+b')
  if not file then return nil, reason, errno end
  -- Lock file
  result, reason, errno = lfs.lock(file, 'w')
  if not result then file:close(); return nil, reason, errno end
  -- Prepare close function
  local function specieClose()
    lfs.unlock(file)
    file:close()
    file = nil
  end
  -- Read specie file
  local deflated
  deflated, reason, errno = file:read('*a')
  if not deflated then specieClose(); return nil, reason, errno end
  -- Get zlib stream to decompress .gz file
  local stream
  result, stream = pcall( zlib.inflate )
  if not result then return nil, stream end
  -- Decompress data
  local inflated
  result, inflated = pcall( stream, deflated, 'finish' )
  if not result then return nil, inflated end
  deflated = nil
  -- Deserialize specie
  local specie
  result, specie = pcall( torch.deserialize, inflated, format )
  if (not result) or (type(specie) ~= 'table') then specieClose(); return nil, specie end
  -- Update metatable
  local mt = getmetatable(specie) or {}
  local __index = mt.__index
  if type(__index) ~= 'table' then __index = {}; mt.__index = __index end
  __index.close = specieClose
  __index.save = function(self) return specieSave(self, file, format) end
  __index.export = specieExport
  return setmetatable(specie, mt)
end -- function Species.openSpecie

--function Species.appendEntityToFile(entity, file_name)
--  assert(type(entity) == 'table' and type(entity.code) == 'string',
--    'exportPrototype: Incomplete entity specified!')
--  local file, pos, str, idx, res
--  file = io.open(file_name, 'r+')
--  if file then
--    pos = file:seek('end', 0)
--    if pos then
--      pos = file:seek('cur', -10)
--      if pos then
--        str = file:read('*a')
--        assert(str, 'Failed to read last 10 characters of '..tostring(file_name))
--        idx = str:find('}%s*}%s*$')
--        if idx then
--          pos = file:seek('cur', -10 + idx)
--          if pos then
--            res = file:write(',\r\n')
--          end
--        end -- if found two '}'
--      end -- if seeked to the (end-10)
--    end -- if seeked to the end
--  end -- if opened existing file
--  if not file then
--    file = assert( io.open(file_name, 'w') )
--  end
--  if not res then
--    file:seek('set', 0)
--    file:write('return {\r\n')
--  end
  
--  writeEntityInfo(entity, file)
  
--  file:write('\r\n}\r\n')
--  file:close()
--end -- function function Species.appendEntityToFile

return Species
