#!/usr/bin/env bash
# micro IDE setup: emacs keys, 2-space indent, dashboard, file/symbol search,
# project find/replace, formatters, LSP completion.
set -e

CFG="$HOME/.config/micro"
mkdir -p "$CFG"
[ -d "$CFG/plug" ] && cp -r "$CFG" "$CFG.bak.$(date +%s)"
rm -rf "$CFG/plug/projsearch"
mkdir -p "$CFG/plug/ide"

############################ settings.json ############################
cat > "$CFG/settings.json" <<'EOF_SETTINGS'
{
  "basename": true,
  "colorscheme": "rouge",
  "colorcolumn": 80,
  "diffgutter": true,
  "divchars": "|=",
  "eofnewline": true,
  "hlsearch": true,
  "hltaberrors": true,
  "hltrailingws": true,
  "matchbracestyle": "highlight",
  "mkparents": true,
  "savecursor": true,
  "saveundo": true,
  "scrollbar": true,
  "smartcase": true,
  "softwrap": true,
  "wordwrap": true,
  "splitright": true,
  "statusformatl": " ● $(filename) $(modified) «$(line),$(col)» [$(opt:filetype)-$(opt:fileformat)-$(opt:encoding)]",
  "statusformatr": "$(bind:ToggleKeyMenu):Bind, $(bind:ToggleHelp):Help",
  "tabmovement": true,

  "tabsize": 2,
  "tabstospaces": true,
  "autoindent": true,
  "mouse": true,

  "ft:makefile": { "tabstospaces": false },

  "ide.fmtonsave": true,
  "lsp.server": "python=pylsp,c=clangd,c++=clangd,lua=lua-language-server,shell=bash-language-server start,json=vscode-json-language-server --stdio,html=vscode-html-language-server --stdio,css=vscode-css-language-server --stdio,markdown=marksman server"
}
EOF_SETTINGS

############################ bindings.json ############################
cat > "$CFG/bindings.json" <<'EOF_BIND'
{
  "CtrlF": "CursorRight",
  "CtrlB": "CursorLeft",
  "CtrlN": "CursorDown",
  "CtrlP": "CursorUp",
  "CtrlA": "StartOfTextToggle",
  "CtrlE": "EndOfLine",
  "Alt-f": "WordRight",
  "Alt-b": "WordLeft",
  "Alt-<": "CursorStart",
  "Alt->": "CursorEnd",
  "CtrlV": "CursorPageDown",
  "Alt-v": "CursorPageUp",
  "CtrlD": "Delete",
  "Alt-d": "DeleteWordRight",
  "Alt-Backspace": "DeleteWordLeft",
  "CtrlK": "SelectToEndOfLine,Cut",
  "CtrlW": "Cut",
  "Alt-w": "Copy",
  "CtrlY": "Paste",
  "CtrlO": "InsertNewline,CursorLeft",
  "CtrlL": "Center",
  "CtrlG": "Escape",
  "CtrlUnderscore": "Undo",
  "CtrlS": "Find",
  "CtrlR": "FindPrevious",
  "Alt-%": "command-edit:replace ",
  "Alt-x": "CommandMode",
  "Alt-/": "Autocomplete",
  "Alt-;": "lua:comment.comment",
  "Alt-n": "SpawnMultiCursor",
  "Alt-s": "SkipMultiCursor",
  "Alt-m": "SpawnMultiCursorSelect",
  "Alt-q": "RemoveAllMultiCursors",
  "CtrlX": "lua:ide.cx"
}
EOF_BIND

############################ plugin: ide ############################
cat > "$CFG/plug/ide/repo.json" <<'EOF_REPO'
[{"Name":"ide","Description":"Personal IDE layer for micro","Website":"","Tags":["ide"],"Versions":[{"Version":"1.0.0","Url":"","Require":{"micro":">=2.0.0"}}]}]
EOF_REPO

cat > "$CFG/plug/ide/ide.lua" <<'EOF_LUA'
VERSION = "1.0.0"

local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")

---------------------------------------------------------------- helpers
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function q(s) return "'" .. (s:gsub("'", "'\\''")) .. "'" end

local function sh(cmd)
  local out = shell.ExecCommand("sh", "-c", cmd)
  return out or ""
end

local HOME = trim(sh("echo $HOME"))
local DATA = HOME .. "/.config/micro/ide-data"
local RECENT = DATA .. "/recent.txt"
local PROJECTS = DATA .. "/projects.txt"

local function tidy(p)
  if HOME ~= "" and p:sub(1, #HOME) == HOME then return "~" .. p:sub(#HOME + 1) end
  return p
end

local function readLines(path)
  local t = {}
  for l in sh("cat " .. q(path) .. " 2>/dev/null"):gmatch("[^\n]+") do t[#t + 1] = l end
  return t
end

local function writeLines(path, t)
  local parts = {}
  for _, l in ipairs(t) do parts[#parts + 1] = q(l) end
  sh("mkdir -p " .. q(DATA) .. " && printf '%s\\n' " .. table.concat(parts, " ") .. " > " .. q(path))
end

local function pushMRU(path, entry, max)
  local out = { entry }
  for _, l in ipairs(readLines(path)) do
    if l ~= entry and #out < max then out[#out + 1] = l end
  end
  writeLines(path, out)
end

-- fzf picker: runs cmd, pipes to fzf, returns chosen line or nil
local function pick(cmd, opts)
  local full = "(" .. cmd .. ") | fzf " .. (opts or "")
  local out, err = shell.RunInteractiveShell("sh -c " .. q(full), false, true)
  if err ~= nil or out == nil then return nil end
  out = trim(out)
  if out == "" then return nil end
  return out
end

local function pager(cmd)
  shell.RunInteractiveShell("sh -c " .. q(cmd), false, false)
end

local function openAt(file, line)
  local bp = micro.CurPane()
  bp:HandleCommand("open " .. q(file))
  if line then micro.CurPane():HandleCommand("goto " .. line) end
end

local function wordAtCursor(bp)
  local line = bp.Buf:Line(bp.Cursor.Y)
  local x = bp.Cursor.X + 1
  local s, e = x, x
  while s > 1 and line:sub(s - 1, s - 1):match("[%w_]") do s = s - 1 end
  while e <= #line and line:sub(e, e):match("[%w_]") do e = e + 1 end
  return line:sub(s, e - 1)
end

---------------------------------------------------------------- dashboard
local BANNER = [==[
 __  __ ___ ____ ____   ___
|  \/  |_ _/ ___|  _ \ / _ \
| |\/| || | |   | |_) | | | |
| |  | || | |___|  _ <| |_| |
|_|  |_|___\____|_| \_\\___/
]==]

local dashmap = {}

local function dashText()
  dashmap = {}
  local L = {}
  local function add(s, e)
    L[#L + 1] = s
    if e then dashmap[#L - 1] = e end
  end

  for l in BANNER:gmatch("[^\n]+") do add("  " .. l) end
  add("")
  add("  cwd: " .. tidy(trim(sh("pwd"))))
  add("")

  add("  Recent files")
  local r = readLines(RECENT)
  if #r == 0 then add("    (none yet)") end
  for i, p in ipairs(r) do add(string.format("   %2d  %s", i, tidy(p)), { k = "file", p = p }) end
  add("")

  add("  Projects")
  local pr = readLines(PROJECTS)
  if #pr == 0 then add("    (none yet)") end
  for i, p in ipairs(pr) do add(string.format("   %2d  %s", i, tidy(p)), { k = "proj", p = p }) end
  add("")

  add("  Git status")
  local g = sh("git status -sb 2>/dev/null")
  if g == "" then
    add("    not a git repository")
  else
    local n = 0
    for l in g:gmatch("[^\n]+") do
      n = n + 1
      if n > 12 then add("    ..."); break end
      add("    " .. l)
    end
  end
  add("")
  add("  Enter: open   C-x f: find file   C-x j: symbols   M-x: commands")
  return table.concat(L, "\n") .. "\n"
end

function showDashboard(bp, args)
  local b = buffer.NewBuffer(dashText(), "dashboard")
  b:SetOption("readonly", "true")
  bp:OpenBuffer(b)
end

function preInsertNewline(bp)
  if bp.Buf:GetName() ~= "dashboard" then return true end
  local e = dashmap[bp.Cursor.Y]
  if e then
    if e.k == "file" then
      bp:HandleCommand("open " .. q(e.p))
    elseif e.k == "proj" then
      bp:HandleCommand("cd " .. q(e.p))
      showDashboard(bp)
    end
  end
  return false
end

function postinit()
  local bp = micro.CurPane()
  if bp ~= nil and bp.Buf.Path == "" and bp.Buf:Size() == 0 then
    showDashboard(bp)
  end
end

function onBufPaneOpen(bp)
  if bp.Buf:GetName() == "dashboard" then return end
  local p = bp.Buf.AbsPath
  if p == nil or p == "" then return end
  pushMRU(RECENT, p, 10)
  local dir = p:match("^(.*)/[^/]*$") or "."
  local root = trim(sh("git -C " .. q(dir) .. " rev-parse --show-toplevel 2>/dev/null"))
  if root ~= "" then pushMRU(PROJECTS, root, 8) end
end

---------------------------------------------------------------- search / navigation
local PREVIEW = [[--preview '(bat --color=always --line-range :80 {} 2>/dev/null || head -n 80 {})']]
local CTAGS = "ctags -x -R --exclude=.git --exclude=node_modules --exclude='*.min.*' "

function findFile(bp, args)
  local f = pick("rg --files --hidden -g '!.git' 2>/dev/null || find . -type f -not -path './.git/*'",
    "--prompt='file> ' " .. PREVIEW)
  if f then openAt(f) end
end

local function openTag(line)
  local name, kind, lnum, file = line:match("^(%S+)%s+(%S+)%s+(%d+)%s+(%S+)")
  if file then openAt(file, lnum) end
end

function symbols(bp, args)
  local l = pick(CTAGS .. ". 2>/dev/null | sort -u", "--prompt='symbol> '")
  if l then openTag(l) end
end

function symbolsHere(bp, args)
  if bp.Buf.Path == "" then return end
  local l = pick("ctags -x " .. q(bp.Buf.Path) .. " 2>/dev/null", "--prompt='here> '")
  if l then openTag(l) end
end

local function openVimgrep(l)
  local file, lnum = l:match("^(.-):(%d+):%d+:")
  if file then openAt(file, lnum) end
end

local function runSearch(pattern)
  local l = pick("rg --vimgrep --smart-case -- " .. q(pattern), "--prompt='rg> '")
  if l then openVimgrep(l) else micro.InfoBar():Message("No matches for " .. pattern) end
end

function search(bp, args)
  if args ~= nil and #args > 0 then
    runSearch(table.concat(args, " "))
  else
    micro.InfoBar():Prompt("rg: ", "", "Ide", nil, function(p, canceled)
      if not canceled and p ~= "" then runSearch(p) end
    end)
  end
end

local function doReplace(old, new)
  local files = trim(sh("rg -l --fixed-strings -- " .. q(old)))
  if files == "" then micro.InfoBar():Message("No matches"); return end
  local list = {}
  for f in files:gmatch("[^\n]+") do list[#list + 1] = q(f) end
  micro.InfoBar():YNPrompt("Replace in " .. #list .. " file(s)? (y/n)", function(yes, canceled)
    if not yes or canceled then return end
    sh("perl -pi -e 'BEGIN{$a=shift;$b=shift} s/\\Q$a\\E/$b/g' " ..
      q(old) .. " " .. q(new) .. " " .. table.concat(list, " "))
    micro.InfoBar():Message("Replaced in " .. #list .. " file(s). Run 'reopen' on open buffers.")
  end)
end

function replaceAll(bp, args)
  if args ~= nil and #args == 2 then doReplace(args[1], args[2]); return end
  micro.InfoBar():Prompt("replace: ", "", "Ide", nil, function(old, c1)
    if c1 or old == "" then return end
    micro.InfoBar():Prompt("with: ", "", "Ide", nil, function(new, c2)
      if not c2 then doReplace(old, new) end
    end)
  end)
end

---------------------------------------------------------------- formatting
local FMT = {
  ["c"] = "clang-format -i --style='{BasedOnStyle: LLVM, IndentWidth: 2}' %s",
  ["c++"] = "clang-format -i --style='{BasedOnStyle: LLVM, IndentWidth: 2}' %s",
  ["python"] = "yapf -i --style='{based_on_style: pep8, indent_width: 2}' %s",
  ["lua"] = "stylua --indent-type Spaces --indent-width 2 %s",
  ["shell"] = "shfmt -i 2 -w %s",
  ["json"] = "prettier --tab-width 2 --write %s",
  ["html"] = "prettier --tab-width 2 --write %s",
  ["css"] = "prettier --tab-width 2 --write %s",
  ["markdown"] = "prettier --tab-width 2 --write %s",
}

local formatting = false

local function doFormat(bp)
  local ft = bp.Buf:FileType()
  local tpl = FMT[ft]
  if not tpl then micro.InfoBar():Message("No formatter for filetype: " .. ft); return end
  if bp.Buf.Path == "" then return end
  formatting = true
  if bp.Buf:Modified() then bp:Save() end
  local out, err = shell.ExecCommand("sh", "-c", string.format(tpl, q(bp.Buf.Path)))
  formatting = false
  if err ~= nil then
    micro.InfoBar():Error("format failed: " .. ((out or ""):match("[^\n]+") or tostring(err)))
  else
    bp.Buf:ReOpen()
    micro.InfoBar():Message("Formatted (" .. ft .. ")")
  end
end

function fmt(bp, args) doFormat(bp) end

function onSave(bp)
  if formatting then return end
  if config.GetGlobalOption("ide.fmtonsave") ~= true then return end
  if bp.Buf:FileType() == "markdown" then return end -- markdown: manual only
  doFormat(bp)
end

---------------------------------------------------------------- C-x prefix
local CX = {
  ["s"] = function(bp) bp:Save() end,
  ["f"] = function(bp) findFile(bp) end,
  ["q"] = function(bp) bp:QuitAll() end,
  ["k"] = function(bp) bp:Quit() end,
  ["b"] = function(bp) bp:NextTab() end,
  ["o"] = function(bp) bp:NextSplit() end,
  ["2"] = function(bp) bp:HSplitBuf(bp.Buf) end,
  ["3"] = function(bp) bp:VSplitBuf(bp.Buf) end,
  ["0"] = function(bp) bp:Unsplit() end,
  ["h"] = function(bp) showDashboard(bp) end,
  ["i"] = function(bp) symbolsHere(bp) end,
  ["j"] = function(bp) symbols(bp) end,
  ["/"] = function(bp) search(bp) end,
  ["r"] = function(bp) replaceAll(bp) end,
  ["="] = function(bp) doFormat(bp) end,
}

function cx(bp, args)
  local done = false
  local function run(k)
    if done then return end
    done = true
    local fn = CX[k]
    if fn then
      local ok, e = pcall(fn, bp)
      if not ok then micro.InfoBar():Error("C-x " .. k .. ": " .. tostring(e)) end
    else
      micro.InfoBar():Error("C-x " .. k .. " is undefined")
    end
  end
  micro.InfoBar():Prompt("C-x ", "", "Ide",
    function(text)
      if text ~= "" and not done then
        micro.InfoBar():DonePrompt(true)
        run(text:sub(1, 1))
      end
    end,
    function(text, canceled)
      if not canceled and text ~= "" then run(text:sub(1, 1)) end
    end)
end

---------------------------------------------------------------- init
function init()
  config.RegisterCommonOption("ide", "fmtonsave", true)
  config.MakeCommand("dashboard", showDashboard, config.NoComplete)
  config.MakeCommand("findfile", findFile, config.NoComplete)
  config.MakeCommand("symbols", symbols, config.NoComplete)
  config.MakeCommand("symbolshere", symbolsHere, config.NoComplete)
  config.MakeCommand("rg", search, config.NoComplete)
  config.MakeCommand("rgreplace", replaceAll, config.NoComplete)
  config.MakeCommand("fmt", fmt, config.NoComplete)
end
EOF_LUA

############################ plugins ############################
if command -v micro >/dev/null 2>&1; then
  micro -plugin remove filemanager 2>/dev/null || true
  micro -plugin install lsp || echo "Plugin install failed (offline?). Run: micro -plugin install lsp"
else
  echo "micro not found in PATH; install it first."
fi

cat <<'EOF_DONE'

Config written to ~/.config/micro (old config backed up as micro.bak.*).

Install tools (Debian/Ubuntu example):
  sudo apt install micro ripgrep fzf universal-ctags git clang-format shfmt yapf3 bat
  npm i -g prettier
  cargo install stylua        # Lua formatter
Optional LSP servers: clangd, python-lsp-server, lua-language-server,
  bash-language-server, vscode-langservers-extracted, marksman

macOS: brew install micro ripgrep fzf universal-ctags git clang-format shfmt yapf stylua prettier bat

Start with:  micro        (dashboard)   or   micro file.c
EOF_DONE
