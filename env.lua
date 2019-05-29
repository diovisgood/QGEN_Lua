require 'lfs'
require 'zlib'

local Env = {}

local function orderedPairs(collection, reverse)
  local index = 0
  local orderedIndex = {}
  for key in pairs(collection) do
    table.insert(orderedIndex, key)
  end
  if not reverse then
    table.sort(orderedIndex, function(a,b) return (type(a)==type(b)) and (type(a)=='number' or type(a)=='string') and (a < b) end)
  else
    table.sort(orderedIndex, function(a,b) return (type(a)==type(b)) and (type(a)=='number' or type(a)=='string') and (a > b) end)
  end
  -- The closure function is returned
  return function ()
    index = index + 1
    local key = orderedIndex[index]
    if key then return key, collection[key] end
  end -- function
end -- function orderedPairs

function Env.universalSave(obj, file_path, format)
  format = format or 'ascii'
  if string.sub(file_path, -3) == '.gz' then
    local inflated = torch.serialize(obj, format)
    local deflated = zlib.deflate(6, 15+16)(inflated, 'finish')
    assert(io.open(file_path, 'wb')):write(deflated)
  else
    torch.save(file_path, obj, format)
  end
end -- function Env.universalSave

function Env.universalLoad(file_path, format)
  format = format or 'ascii'
  local attr = lfs.attributes(file_path, 'mode')
  if (not attr) or (attr ~= 'file') then return end
  if string.sub(file_path, -3) == '.gz' then
    local deflated = assert(io.open(file_path, 'rb')):read('*a')
    local inflated = zlib.inflate()(deflated)
    return torch.deserialize(inflated, format)
  else
    return torch.load(file_path, format)
  end
end -- function Env.universalLoad

--- Saves environment to the file specified in Env_File.
-- File will be located in current directory.
function Env.saveEnvironment(env, file_name)
  assert(env)
  file_name = file_name or Env_File
  if (not env) or (not file_name) then return end
  print('Saving current environment...')
  -- Clear gradients
  for name, v in pairs(env) do
    if (type(v) == 'table') then
      if (type(v.zeroGradParameters) == 'function') then
        v:zeroGradParameters()
      end
      if (type(v.apply) == 'function') then
        v:apply(function(self)
            if self.gradInput then self.gradInput = torch.Tensor() end
            if self.output then self.output = torch.Tensor() end
          end)
      end
    end
  end
  -- Save environment
  Env.universalSave(env, file_name, 'binary')
end -- function Env.saveEnvironment

--- Saves environment to the file specified in Env_File.
-- File will be located in current directory.
function Env.loadEnvironment(file_name)
  file_name = file_name or Env_File
  if (not file_name) then return end
  print('Loading environment...')
  -- Try to load previously saved environment
  local env = Env.universalLoad(file_name, 'binary')
  if not env then
    print('Failed to load environment!')
  else
    print('Loaded environment from file '..tostring(file_name))
    printInfo('env', env)
  end
  return env
end -- function Env.saveEnvironment

function Env.printInfo(k, v, indent)
  indent = indent or ''
  local t = torch.type(v)
  if t:match('torch.') then
    io.write(indent, tostring(k), ': ', tostring(t), ' ')
    for i = 1, v:nDimension() do
      io.write((i > 1 and ' x ' or ''), tostring(v:size(i)))
    end
    io.write('\n')
  elseif (t == 'number') or (t == 'boolean') then
    io.write(indent, tostring(k), ' = ', tostring(v), '\n')
  elseif t == 'string' then
    io.write(indent, tostring(k), ' = "', tostring(v), '"', '\n')
  elseif t == 'table' then
    local f_print = (#v <= 2)
    io.write(indent, tostring(k), ' table: ', (f_print and '' or tostring(#v)..' array elements'), '\n')
    if f_print then
      for i, vv in ipairs(v) do Env.printInfo(i, vv, indent..'  ') end
    end
    for k, vv in orderedPairs(v) do
      if (#v <= 0) or ((type(k) == 'number') and (k < 1 or k > #v or math.floor(k)~=k)) then
        Env.printInfo(k, vv, indent..'  ')
      end
    end
  elseif t == 'function' then
    io.write(indent, tostring(k), ' = function\n')
  else
    io.write(indent, tostring(k), '\t', t, '\n')
  end
end -- function Env.printInfo

return Env
