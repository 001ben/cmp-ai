local job = require('plenary.job')
local requests = require('cmp_ai.requests')

local Gemini = requests:new(nil)

function Gemini:new(o, params)
  o = o or {}
  setmetatable(o, self)
  self.__index = self
  self.params = vim.tbl_deep_extend('keep', params or {}, {
    n = 1,
    model_name = 'gemini-1.5-pro',  -- Default model name
  })
  self.api_key = os.getenv('GEMINI_API_KEY')
  if not self.api_key then
    vim.schedule(function()
      vim.notify('GEMINI_API_KEY environment variable not set', vim.log.levels.ERROR)
    end)
    self.api_key = 'NO_KEY'
  end
  return o
end

function Gemini:complete(lines_before, lines_after, cb)
  if not self.api_key then
    vim.schedule(function()
      vim.notify('GEMINI_API_KEY environment variable not set', vim.log.levels.ERROR)
    end)
    return
  end

  local message = table.concat({
    'You are a coding companion.',
    ' You need to suggest code completions for the language ',
    vim.o.filetype,
    '. Given some code prefix and suffix for context, output code which should follow the prefix code.',
    ' You should only output valid code in ',
    vim.o.filetype,
    '. To clearly define a code block, including white space, we will wrap the code block with tags.',
    ' Make sure to respect the white space and indentation rules of the language.',
    ' Do not output anything in plain language, make sure you only use the relevant programming language verbatim.',
    ' OUTPUT ONLY CODE, DO NOT USE MARKUP! and follow the instructions appearing next.',
    ' For example, consider the following request:',
    ' <begin_code_prefix>def print_hello():<end_code_prefix><begin_code_suffix>\n    return<end_code_suffix><begin_code_middle>',
    ' Your answer should be:',
    [=[     print('Hello')<end_code_middle>]=],
    ' Now for the users request: ',
    '    <begin_code_prefix>',
    lines_before,
    '<end_code_prefix> <begin_code_suffix>',
    lines_after,
    '<end_code_suffix><begin_code_middle>',
  }, '\n')

  local command = table.concat({
    'import google.generativeai as genai',
    'import os',
    'import json',
    'genai.configure(api_key="' .. self.api_key .. '")',
    'model = genai.GenerativeModel(name="' .. self.params.model_name .. '")',
    'response = model.generate_content("""' .. message .. '""")',
    'print(json.dumps({"text": response.text}))',
  }, '\n')

  local tmpfname = os.tmpname()
  local f = io.open(tmpfname, 'w+')
  if f == nil then
    vim.notify('Cannot open temporary message file: ' .. tmpfname, vim.log.levels.ERROR)
    return
  end
  f:write(command)
  f:close()

  job
    :new({
      command = 'python3',
      args = { tmpfname },
      on_exit = vim.schedule_wrap(function(response, exit_code)
        os.remove(tmpfname)
        local result = table.concat(response:result(), '\n')
        if exit_code ~= 0 then
          vim.notify('An Error Occurred: ' .. result, vim.log.levels.ERROR)
          cb({})
        end
        local json = self:json_decode(result)
        local new_data = {}
        if json ~= nil and json.text ~= nil then
          local entry = json.text:gsub('<end_code_middle>', '')
          if entry:find('```') then
            -- extract the code inside ```
            entry = entry:match('```[^\n]*\n(.*)```')
          end
          table.insert(new_data, entry)
          cb(new_data)
        end
      end),
    })
    :start()
end

function Gemini:test()
  self:complete('def factorial(n)\n    if', '    return ans\n', function(data)
    dump(data)
  end)
end

function Gemini:debug_info(cb)
  local command = table.concat({
    'import sys, os, site, google.generativeai',
    'print(f"Python version: {sys.version}")',
    'print(f"Python executable: {sys.executable}")',
    'print(f"google-generativeai version: {google.generativeai.__version__}")',
    'print(f"Virtual env: {os.environ.get(\'VIRTUAL_ENV\', \'Not in a virtual environment\')}")',
    'print(f"Site packages: {site.getsitepackages()}")',
    'print(f"Gemini API key set: {\'Yes\' if os.environ.get(\'GEMINI_API_KEY\') else \'No\'}")',
  }, '\n')

  local tmpfname = os.tmpname()
  local f = io.open(tmpfname, 'w+')
  if f == nil then
    vim.notify('Cannot open temporary message file: ' .. tmpfname, vim.log.levels.ERROR)
    return
  end
  f:write(command)
  f:close()

  job
    :new({
      command = 'python3',
      args = { tmpfname },
      on_exit = vim.schedule_wrap(function(response, exit_code)
        os.remove(tmpfname)
        local result = table.concat(response:result(), '\n')
        if exit_code ~= 0 then
          vim.notify('An Error Occurred: ' .. result, vim.log.levels.ERROR)
          cb(result)
        else
          cb(result)
        end
      end),
    })
    :start()
end

return Gemini
