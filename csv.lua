function CSVFile (file_path, delimiter)
  delimiter = delimiter or '[;,]'
  -- Open file
  local file, reason = io.open(file_path, 'r')
  if (not file) then return nil, 'CSVFile: Failed to open file: '..tostring(reason) end
  
  local function parse(line)
    local i, pos, result = 0, 0, {}
    -- for each divider found
    for st,sp in function() return string.find(line, delimiter, pos) end do
      result[i + 1] = string.sub(line, pos, st - 1)
      pos = sp + 1
      i = i + 1
    end
    result[i + 1] = string.sub(line, pos)
    return result
  end
  
  -- Read header
  local str_line = file:read('*l')
  if (not str_line) then return nil, 'CSVFile: Failed to read header!' end
  local header = parse(str_line)
  
  local result = {}
  result.header = header
  
  -- Parse the rest of the file in cycle
  while true do
    -- Read next line
    str_line = file:read('*l')
    if (not str_line) then break end
    -- Parse line
    local v = parse(str_line)
    if not v then break end
    -- Add line to result table
    table.insert(result, v)
  end -- while reading lines
  
  return result
end -- CSVFile

return {CSVFile=CSVFile}