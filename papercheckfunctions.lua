-- Papercheck (functions)
-- Version 0.4 (2022/08/05)
-- By Simon Winter
-- https://github.com/ems-press/papercheck

local M = {}

local pl_file = require 'pl.file'

M.sep = package.config:sub(1, 1)
-- TRUE if Windows, otherwise FALSE
-- local win = (M.sep == '\\')

--- Create (OS-dependent) path.
-- Concatenates all given parts with the path separator.
-- Input: variable number of strings ...
-- Output: string
function M.path(...)
  local t = {}
  for i = 1, select('#', ...) do
    t[i] = tostring((select(i, ...)))
  end
  return table.concat(t, M.sep)
end

function M.read_file(file)
  local str = pl_file.read(file)
  return str
end

function M.tablelength(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

-- Escape all magic characters in a string.
-- https://github.com/lua-nucleo/lua-nucleo/blob/v0.1.0/lua-nucleo/string.lua#L245-L267
do
  local match = {
    ['^'] = '%^';
    ['$'] = '%$';
    ['('] = '%(';
    [')'] = '%)';
    ['%'] = '%%';
    ['.'] = '%.';
    ['['] = '%[';
    [']'] = '%]';
    ['*'] = '%*';
    ['+'] = '%+';
    ['-'] = '%-';
    ['?'] = '%?';
    ['\0'] = '%z';
  }
  M.escape_lua = function(str)
    return (str:gsub('.', match))
  end
end

local function capitalize(str)
  return (str:gsub("^%l", string.upper))
end

function M.add_blankline()
  if blankline then
    blankline = false
    print('')
  end
end

-- If 'pattern' is found in 'text', then return 'note'
function M.patternsearch(text,pattern,note)
  if text:match(pattern) then
    blankline = true
    print(note)
  end
end

-- If 'pattern' is found in 'text', then return 'note' and 'pattern'.
function M.recursivepatternsearch(text,pattern,note)
  local finding = text:match(pattern)
  if finding then
    blankline = true
    print(note..": "..finding)
    -- Recursive:
    M.recursivepatternsearch(text:gsub(M.escape_lua(finding),''),pattern,note)
  end
end

-- If repeated words of at least two letters are found in 'text', then return them.
function M.repeatedword(text)
  local finding = text:match('[^%a](%a%a+)[%s\n~]+%1[^%a]')
  if finding then
    blankline = true
    print('Double word: '..finding)
    -- Recursive:
    M.repeatedword(text:gsub(M.escape_lua(finding),''))
  end
end

-- If two out of 'pattern' are found in 'text', then return them.
function M.inconsistencysearch(text,pattern)
  local finds = {}
  local counts = {}
  for i = 1, #pattern do
    if text:match(pattern[i]) then
      finds[#finds + 1] = text:match(pattern[i])
      local _
      _, counts[#counts + 1] = text:gsub(pattern[i],'')
    end
  end
  if #finds > 1 then
    for i = 1, #finds do
      finds[i] = finds[i]..' ('..counts[i]..')'
    end
    blankline = true
    print('Inconsistency? '..table.concat(finds, ', '))
  end
end

-- If two out of 'ab', 'a-b', 'a b' are found in 'text', then return them.
function M.hyphenatedsearch(text,a,b)
  M.inconsistencysearch(text,{a..b, a..'%-'..b, a..'[%s\n~]+'..b})
  M.inconsistencysearch(text,{capitalize(a)..b, capitalize(a)..'%-'..b, capitalize(a)..'[%s\n~]+'..b})
end

local function prefixsuffixsearch(text,prefixsuffix,patterns)
  local finds = {}
  for i = 1, #patterns do
    while text:match('[^%a]'..patterns[i]..'[^%a]') do
      local w = text:match('[^%a]('..patterns[i]..')[^%a]')
      finds[#finds + 1] = w
      text = text:gsub(M.escape_lua(w), '')
     end
  end
  if #finds > 0 then
    blankline = true
    table.sort(finds)
    print('The following "'..prefixsuffix..'" spellings were found:')
    for i = 1, #finds do
      print(finds[i])
    end
  end
end

-- If "prefix + space/hyphen + at least one letter" is found in 'text',
-- then return all words containing this prefix.
-- N.B.: single "non" will not be reported.
function M.prefixsearch(text,prefix)
  local patterns = {
    prefix..'[%s]+%a%a-',             -- e.g. "non trivial"
    capitalize(prefix)..'[%s]+%a%a-', -- e.g. "Non trivial"
    prefix..'[%-–]+%a-',              -- e.g. "non-trivial"
    capitalize(prefix)..'[%-–]+%a-',  -- e.g. "Non-trivial"
    prefix..'%a%a-',                  -- e.g. "nontrivial"
    capitalize(prefix)..'%a%a-',      -- e.g. "Nontrivial"
  }
  prefixsuffixsearch(text,prefix,patterns)
end

-- If "at least one letter + space/hyphen + suffix" is found in 'text',
-- then return all words containing this suffix.
-- N.B.: single "dimensional" will not be reported.
function M.suffixsearch(text,suffix)
  local patterns = {
    '[%w%$]-[%w%$][\n%s]-'..suffix, -- e.g. "$1$ dimensional"
    '[%w%$]-[%-–]+'..suffix,        -- e.g. "$1$-dimensional"
    '[%w%$]-[%w%$]'..suffix,        -- e.g. "onedimensional"
  }
  prefixsuffixsearch(text,suffix,patterns)
end

local function spellcount(text,t)
  local finds = {}
  for i = 1, #t do
    local _, count = text:gsub(t[i][1],'')
    finds[#finds + 1] = t[i][2]..' ('..count..')'
  end
  return table.concat(finds, ', ')
end

-- Collect indicators for American English and British English.
function M.americanbritish(text)
  local AE = {
    {"[cC]enter", "center"},
    {"[cC]olor", "color"},
    {"[nN]eighbor", "neighbor"},
    --{"%a%aense[sd]?%A", ".ense"},
    {"%a%aeled%A", ".eled"},
    {"%a%aelings?%A", ".eling"},
    {"%a%ayze[sd]?%A", ".yze"},
    {"%a%aize[sd]?%A", ".ize"},
  }
  local BE = {
    {"[cC]entre", "centre"},
    {"[cC]olour", "colour"},
    {"[nN]eighbour", "neighbour"},
    --{"%a%aence[sd]?%A", ".ence"},
    {"%a%aelled%A", ".elled"},
    {"%a%aellings?%A", ".elling"},
    {"%a%ayse[sd]?%A", ".yse"},
    {"%a%aise[sd]?%A", ".ise"},
  }
  -- TODO https://de.wikipedia.org/wiki/Oxford_spelling
  print("Text written in AE or BE?"
    .." (.ize can be both AE and BE; .ise could be exercise, otherwise, etc.)")
  print("AE: "..spellcount(text,AE))
  print("BE: "..spellcount(text,BE))
  blankline = true
end

return M

-- End of file.
