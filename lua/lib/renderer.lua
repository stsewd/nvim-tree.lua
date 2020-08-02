local colors = require'lib.colors'
local config = require'lib.config'

local api = vim.api

local lines = {}
local hl = {}
local index = 0
local namespace_id = api.nvim_create_namespace('LuaTreeHighlights')

local icon_state = config.get_icon_state()

local get_folder_icon = function() return "" end
local set_folder_hl = function(line, depth, git_icon_len, hl_group)
  table.insert(hl, {hl_group, line, depth+git_icon_len, -1})
end

if icon_state.show_folder_icon then
  get_folder_icon = function(open)
    if open then
      return icon_state.icons.folder_icons.open .. " "
    else
      return icon_state.icons.folder_icons.default .. " "
    end
  end
  set_folder_hl = function(line, depth, icon_len, name_len, hl_group)
    table.insert(hl, {hl_group, line, depth+icon_len, depth+icon_len+name_len})
    table.insert(hl, {'LuaTreeFolderIcon', line, depth, depth+icon_len})
  end
end

local get_file_icon = function() return "" end
if icon_state.show_file_icon then
  local web_devicons = require'nvim-web-devicons'

  get_file_icon = function(fname, extension, line, depth)
    local icon, hl_group = web_devicons.get_icon(fname, extension)
    local hl_override = colors.hl_groups[fname] or colors.hl_groups[extension]
    hl_group = hl_override or hl_group

    if icon then
      table.insert(hl, { 'LuaTree'..hl_group, line, depth, depth + #icon })
      return icon.." "
    else
      return icon_state.icons.default and icon_state.icons.default.." " or ""
    end
  end

end

local get_git_icons = function() return "" end
local get_git_hl = function() return end

if vim.g.lua_tree_git_hl == 1 then
  local git_hl = {
    ["M "] = { { hl = "LuaTreeFileStaged" } },
    [" M"] = { { hl = "LuaTreeFileDirty" } },
    ["MM"] = {
      { hl = "LuaTreeFileStaged" },
      { hl = "LuaTreeFileDirty" }
    },
    ["A "] = {
      { hl = "LuaTreeFileStaged" },
      { hl = "LuaTreeFileNew" }
    },
    ["AM"] = {
      { hl = "LuaTreeFileStaged" },
      { hl = "LuaTreeFileNew" },
      { hl = "LuaTreeFileDirty" }
    },
    ["??"] = { { hl = "LuaTreeFileNew" } },
    ["R "] = { { hl = "LuaTreeFileRenamed" } },
    ["UU"] = { { hl = "LuaTreeFileMerge" } },
    dirty = { { hl = "LuaTreeFileDirty" } },
  }
  get_git_hl = function(node)
    local git_status = node.git_status
    if not git_status then return end

    local icons = git_hl[git_status]
    -- TODO: how would we determine hl color when multiple git status are active ?
    return icons[1].hl
    -- return icons[#icons].hl
  end
end

if icon_state.show_git_icon then
  local git_icon_state = {
    ["M "] = { { icon = icon_state.icons.git_icons.staged, hl = "LuaTreeGitStaged" } },
    [" M"] = { { icon = icon_state.icons.git_icons.unstaged, hl = "LuaTreeGitDirty" } },
    ["MM"] = {
      { icon = icon_state.icons.git_icons.staged, hl = "LuaTreeGitStaged" },
      { icon = icon_state.icons.git_icons.unstaged, hl = "LuaTreeGitDirty" }
    },
    ["A "] = {
      { icon = icon_state.icons.git_icons.staged, hl = "LuaTreeGitStaged" },
      { icon = icon_state.icons.git_icons.untracked, hl = "LuaTreeGitNew" }
    },
    ["AM"] = {
      { icon = icon_state.icons.git_icons.staged, hl = "LuaTreeGitStaged" },
      { icon = icon_state.icons.git_icons.untracked, hl = "LuaTreeGitNew" },
      { icon = icon_state.icons.git_icons.unstaged, hl = "LuaTreeGitDirty" }
    },
    ["??"] = { { icon = icon_state.icons.git_icons.untracked, hl = "LuaTreeGitNew" } },
    ["R "] = { { icon = icon_state.icons.git_icons.renamed, hl = "LuaTreeGitRenamed" } },
    ["UU"] = { { icon = icon_state.icons.git_icons.unmerged, hl = "LuaTreeGitMerge" } },
    dirty = { { icon = icon_state.icons.git_icons.unstaged, hl = "LuaTreeGitDirty" } },
  }

  get_git_icons = function(node, line, depth, icon_len)
    local git_status = node.git_status
    if not git_status then return "" end

    local icon = ""
    local icons = git_icon_state[git_status]
    for _, v in ipairs(icons) do
      table.insert(hl, { v.hl, line, depth+icon_len+#icon, depth+icon_len+#icon+#v.icon })
      icon = icon..v.icon.." "
    end

    return icon
  end
end

local get_padding = function(depth)
  return string.rep(' ', depth)
end

if vim.g.lua_tree_indent_markers == 1 then
  get_padding = function(depth, idx, tree, _, markers)
    local padding = ""
    if depth ~= 0 then
      local rdepth = depth/2
      markers[rdepth] = idx ~= #tree.entries
      for i=1,rdepth do
        if idx == #tree.entries and i == rdepth then
          padding = padding..'└ '
        elseif markers[i] then
          padding = padding..'│ '
        else
          padding = padding..'  '
        end
      end
    end
    return padding
  end
end

local picture = {
  jpg = true,
  jpeg = true,
  png = true,
  gif = true,
}

local special = {
  ["Cargo.toml"] = true,
  Makefile = true,
  ["README.md"] = true,
  ["readme.md"] = true,
}

local function update_draw_data(tree, depth, markers)
  if tree.cwd and tree.cwd ~= '/' then
    table.insert(lines, "..")
    table.insert(hl, {'LuaTreeFolderName', index, 0, 2})
    index = 1
  end

  for idx, node in ipairs(tree.entries) do
    local padding = get_padding(depth, idx, tree, node, markers)
    local offset = string.len(padding)
    if depth > 0 then
      table.insert(hl, { 'LuaTreeIndentMarker', index, 0, offset })
    end

    local git_hl = get_git_hl(node)

    if node.entries then
      local icon = get_folder_icon(node.open)
      local git_icon = get_git_icons(node, index, offset, #icon+1) or ""
      -- INFO: this is mandatory in order to keep gui attributes (bold/italics)
      set_folder_hl(index, offset, #icon, #node.name+#git_icon, 'LuaTreeFolderName')
      if git_hl then
        set_folder_hl(index, offset, #icon, #node.name+#git_icon, git_hl)
      end
      index = index + 1
      if node.open then
        table.insert(lines, padding..icon..git_icon..node.name)
        update_draw_data(node, depth + 2, markers)
      else
        table.insert(lines, padding..icon..git_icon..node.name)
      end
    elseif node.link_to then
      local link_hl = git_hl or 'LuaTreeSymlink'
      table.insert(hl, { link_hl, index, offset, -1 })
      table.insert(lines, padding..node.name.." ➛ "..node.link_to)
      index = index + 1

    else
      local icon
      local git_icons
      if special[node.name] then
        icon = ""
        git_icons = get_git_icons(node, index, offset, 0)
        table.insert(hl, {'LuaTreeSpecialFile', index, offset+#git_icons, -1})
      else
        icon = get_file_icon(node.name, node.extension, index, offset)
        git_icons = get_git_icons(node, index, offset, #icon)
      end
      table.insert(lines, padding..icon..git_icons..node.name)

      if node.executable then
        table.insert(hl, {'LuaTreeExecFile', index, offset+#icon+#git_icons, -1 })
      elseif picture[node.extension] then
        table.insert(hl, {'LuaTreeImageFile', index, offset+#icon+#git_icons, -1 })
      end

      if git_hl then
        table.insert(hl, {git_hl, index, offset+#icon+#git_icons, -1 })
      end
      index = index + 1
    end
  end
end

local M = {}

function M.draw(tree, reload)
  if not tree.bufnr then return end
  api.nvim_buf_set_option(tree.bufnr, 'modifiable', true)
  local cursor = api.nvim_win_get_cursor(tree.winnr)
  if reload then
    index = 0
    lines = {}
    hl = {}
    update_draw_data(tree, 0, {})
  end

  api.nvim_buf_set_lines(tree.bufnr, 0, -1, false, lines)
  M.render_hl(tree.bufnr)
  if #lines > cursor[1] then
    api.nvim_win_set_cursor(tree.winnr, cursor)
  end
  api.nvim_buf_set_option(tree.bufnr, 'modifiable', false)
end

function M.render_hl(bufnr)
  if not bufnr then return end
  api.nvim_buf_clear_namespace(bufnr, namespace_id, 0, -1)
  for _, data in ipairs(hl) do
    api.nvim_buf_add_highlight(bufnr, namespace_id, data[1], data[2], data[3], data[4])
  end
end

return M
