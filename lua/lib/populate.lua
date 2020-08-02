local config = require'lib.config'
local git = require'lib.git'
local icon_config = config.get_icon_state()

local api = vim.api
local luv = vim.loop

local M = {
  show_ignored = false
}

local path_to_matching_str = require'lib.utils'.path_to_matching_str

local function dir_new(cwd, name)
  local absolute_path = cwd..'/'..name
  local stat = luv.fs_stat(absolute_path)
  return {
    name = name,
    absolute_path = absolute_path,
    -- TODO: last modified could also involve atime and ctime
    last_modified = stat.mtime.sec,
    match_name = path_to_matching_str(name),
    match_path = path_to_matching_str(absolute_path),
    open = false,
    entries = {}
  }
end

local function file_new(cwd, name)
  local absolute_path = cwd..'/'..name
  local is_exec = luv.fs_access(absolute_path, 'X')
  return {
    name = name,
    absolute_path = absolute_path,
    executable = is_exec,
    extension = vim.fn.fnamemodify(name, ':e') or "",
    match_name = path_to_matching_str(name),
    match_path = path_to_matching_str(absolute_path),
  }
end

-- TODO-INFO: sometimes fs_realpath returns nil
-- I expect this be a bug in glibc, because it fails to retrieve the path for some
-- links (for instance libr2.so in /usr/lib) and thus even with a C program realpath fails
-- when it has no real reason to. Maybe there is a reason, but errno is definitely wrong.
-- So we need to check for link_to ~= nil when adding new links to the main tree
local function link_new(cwd, name)
  local absolute_path = cwd..'/'..name
  local link_to = luv.fs_realpath(absolute_path)
  return {
    name = name,
    absolute_path = absolute_path,
    link_to = link_to,
    match_name = path_to_matching_str(name),
    match_path = path_to_matching_str(absolute_path),
  }
end

local function gen_ignore_check()
  local ignore_list = {}
  if vim.g.lua_tree_ignore and #vim.g.lua_tree_ignore > 0 then
    for _, entry in pairs(vim.g.lua_tree_ignore) do
      ignore_list[entry] = true
    end
  end

  return function(path)
    return not M.show_ignored and ignore_list[path] == true
  end
end

local should_ignore = gen_ignore_check()

function M.refresh_entries(entries, cwd)
  local handle = luv.fs_scandir(cwd)
  if type(handle) == 'string' then
    api.nvim_err_writeln(handle)
    return
  end

  local named_entries = {}
  local cached_entries = {}
  local entries_idx = {}
  for i, node in ipairs(entries) do
    cached_entries[i] = node.name
    entries_idx[node.name] = i
    named_entries[node.name] = node
  end

  local dirs = {}
  local links = {}
  local files = {}
  local new_entries = {}

  while true do
    local name, t = luv.fs_scandir_next(handle)
    if not name then break end

    if not should_ignore(name) then
      if t == 'directory' then
        table.insert(dirs, name)
        new_entries[name] = true
      elseif t == 'file' then
        table.insert(files, name)
        new_entries[name] = true
      elseif t == 'link' then
        table.insert(links, name)
        new_entries[name] = true
      end
    end
  end

  local idx = 1
  for _, name in ipairs(cached_entries) do
    if not new_entries[name] then
      table.remove(entries, idx, idx + 1)
    else
      idx = idx + 1
    end
  end

  local all = {
    { entries = dirs, fn = dir_new, check = function(_, abs) return luv.fs_access(abs, 'R') end },
    { entries = links, fn = link_new, check = function(name) return name ~= nil end },
    { entries = files, fn = file_new, check = function() return true end }
  }

  local prev = nil
  local change_prev
  for _, e in ipairs(all) do
    for _, name in ipairs(e.entries) do
      change_prev = true
      if not named_entries[name] then
        local n = e.fn(cwd, name)
        if e.check(n.link_to, n.absolute_path) then
          idx = 1
          if prev then
            idx = entries_idx[prev] + 1
          end
          table.insert(entries, idx, n)
          entries_idx[name] = idx
          cached_entries[idx] = name
        else
          change_prev = false
        end
      end
      if change_prev then prev = name end
    end
  end
end

function M.populate(entries, cwd)
  local handle = luv.fs_scandir(cwd)
  if type(handle) == 'string' then
    api.nvim_err_writeln(handle)
    return
  end

  local dirs = {}
  local links = {}
  local files = {}

  while true do
    local name, t = luv.fs_scandir_next(handle)
    if not name then break end

    if not should_ignore(name) then
      if t == 'directory' then
        table.insert(dirs, name)
      elseif t == 'file' then
        table.insert(files, name)
      elseif t == 'link' then
        table.insert(links, name)
      end
    end
  end

  -- Create Nodes --

  for _, dirname in ipairs(dirs) do
    local dir = dir_new(cwd, dirname)
    if luv.fs_access(dir.absolute_path, 'R') then
      table.insert(entries, dir)
    end
  end

  for _, linkname in ipairs(links) do
    local link = link_new(cwd, linkname)
    if link.link_to ~= nil then
      table.insert(entries, link)
    end
  end

  for _, filename in ipairs(files) do
    local file = file_new(cwd, filename)
    table.insert(entries, file)
  end

  if not icon_config.show_git_icon and vim.g.lua_tree_git_hl ~= 1 then
    return
  end

  git.update_status(entries, cwd)
end

return M
