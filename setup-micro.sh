#!/usr/bin/env bash
# micro IDE setup: emacs keys, 2-space indent, neovim-style dashboard,
# line selection, file/symbol search, project find/replace, formatters,
# LSP completion, and automatic installation of the required tools.
#
# Usage:
#   bash setup-micro.sh              # install everything
#   bash setup-micro.sh --no-install # write config only
#   bash setup-micro.sh --no-manager # skip the optional manager plugin
set -e

DO_INSTALL=1
DO_MANAGER=1
for arg in "$@"; do
  case "$arg" in
    --no-install) DO_INSTALL=0 ;;
    --no-manager) DO_MANAGER=0 ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown arg: $arg"; exit 2 ;;
  esac
done

CFG="$HOME/.config/micro"
mkdir -p "$CFG"
[ -d "$CFG/plug" ] && cp -r "$CFG" "$CFG.bak.$(date +%s)"
rm -rf "$CFG/plug/projsearch"
mkdir -p "$CFG/plug/ide"

############################ package installation ############################
install_tools() {
  local os=""
  if   command -v apt-get >/dev/null 2>&1; then os="debian"
  elif command -v dnf     >/dev/null 2>&1; then os="fedora"
  elif command -v pacman  >/dev/null 2>&1; then os="arch"
  elif command -v brew    >/dev/null 2>&1; then os="macos"
  else os="unknown"
  fi

  echo "==> Detected package manager: $os"

  case "$os" in
    fedora)
      # Lean install: skip weak deps, prefer clang-tools-extra over full clang.
      sudo dnf install -y --setopt=install_weak_deps=False \
        micro ripgrep fzf ctags git clang-tools-extra shfmt \
        python3-yapf bat perl nodejs npm python3-pip curl
      # Fedora ships 'yapf-3.x' as /usr/bin/yapf3 (or /usr/bin/yapf); make sure 'yapf' resolves.
      if ! command -v yapf >/dev/null 2>&1 && command -v yapf3 >/dev/null 2>&1; then
        sudo ln -sf "$(command -v yapf3)" /usr/local/bin/yapf
      fi
      # clangd comes from clang-tools-extra; verify.
      command -v clangd >/dev/null 2>&1 || echo "!! clangd not found; install 'clang-tools-extra'"
      # stylua is not packaged on Fedora — installed via cargo below if available.
      ;;
    debian)
      sudo apt-get update
      sudo apt-get install -y \
        micro ripgrep fzf universal-ctags git clang-format shfmt yapf3 \
        bat perl python3-pip npm curl
      command -v yapf >/dev/null 2>&1 || sudo ln -sf "$(command -v yapf3)" /usr/local/bin/yapf
      ;;
    arch)
      sudo pacman -S --needed --noconfirm \
        micro ripgrep fzf ctags git clang shfmt yapf bat perl nodejs npm
      ;;
    macos)
      brew install micro ripgrep fzf universal-ctags git clang-format shfmt yapf bat perl node
      ;;
    *)
      echo "!! Unknown OS. Install manually: micro ripgrep fzf universal-ctags git"
      echo "   clang-format shfmt yapf bat perl nodejs npm"
      ;;
  esac

  if command -v npm >/dev/null 2>&1; then
    echo "==> npm: prettier + LSP servers"
    npm i -g prettier \
      vscode-langservers-extracted \
      bash-language-server \
      python-lsp-server 2>/dev/null \
      || echo "!! npm global install failed; install prettier / LSP servers manually"
  fi

  if command -v cargo >/dev/null 2>&1; then
    echo "==> cargo: stylua"
    cargo install stylua --locked 2>/dev/null || echo "!! stylua install failed"
  else
    echo "!! cargo not found; install Rust (https://rustup.rs) for stylua, or skip"
    [ "$os" = "fedora" ] && echo "   on Fedora: sudo dnf install rust cargo"
  fi

  if command -v pip3 >/dev/null 2>&1; then
    echo "==> pip: python-lsp-server"
    pip3 install --user python-lsp-server 2>/dev/null || true
  fi
  echo "==> Note: clangd, lua-language-server, marksman are not installed automatically."
  echo "    clangd:        sudo dnf install clang-tools-extra"
  echo "    lua-ls:        https://github.com/LuaLS/lua-language-server/releases"
  echo "    marksman:      https://github.com/artempyanykh/marksman/releases"
}

if [ "$DO_INSTALL" -eq 1 ]; then
  install_tools
else
  echo "==> Skipping tool installation (--no-install)"
fi

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

  "pluginrepos": [
    "https://codeberg.org/micro-plugins/manager/raw/branch/main/repo.json"
  ],

  "lsp.server": "python=pylsp,c=clangd,c++=clangd,lua=lua-language-server,shell=bash-language-server start,json=vscode-json-language-server --stdio,html=vscode-html-language-server --stdio,css=vscode-css-language-server --stdio,markdown=marksman server"
}
EOF_SETTINGS

############################ bindings.json (Emacs core + selection) ############################
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
  "CtrlX": "lua:ide.cx",

  "ShiftUp": "SelectUp",
  "ShiftDown": "SelectDown",
  "ShiftLeft": "SelectLeft",
  "ShiftRight": "SelectRight",
  "Alt-Up": "MoveLinesUp",
  "Alt-Down": "MoveLinesDown",
  "CtrlShiftK": "SelectLine,SelectDown",
  "CtrlShiftL": "lua:ide.sellines",
  "CtrlShiftC": "CopyLine",
  "CtrlShiftX": "CutLine",
  "CtrlShiftD": "DuplicateLine",

  "Alt-Ctrl-o": "lua:ide.dashboard"
}
EOF_BIND

############################ plugin: ide ############################
cat > "$CFG/plug/ide/repo.json" <<'EOF_REPO'
[{"Name":"ide","Description":"Personal IDE layer for micro (emacs nav + neovim-style dashboard + line selection)","Website":"","Tags":["ide"],"Versions":[{"Version":"1.3.0","Url":"","Require":{"micro":">=2.0.0"}}]}]
EOF_REPO

cat > "$CFG/plug/ide/ide.lua" <<'EOF_LUA'
VERSION = "1.3.0"

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

local function pick(cmd, opts)
  local full = "(" .. cmd .. ") | fzf " .. (opts or "")
  local out, err = shell.RunInteractiveShell("sh -c " .. q(full), false, true)
  if err ~= nil or out == nil then return nil end
  out = trim(out)
  if out == "" then return nil end
  return out
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

---------------------------------------------------------------- selection
-- Select N lines starting at the cursor. N defaults to 1 via prompt.
-- Called by: C-x S, CtrlShiftL, dashboard 'l' key, :sellines N
function sellines(bp, args)
  if bp.Buf:GetName() == "dashboard" then
    micro.InfoBar():Message("Open a file first, then select lines.")
    return
  end
  local n
  if args ~= nil and #args > 0 then n = tonumber(args[1]) end
  if n == nil then
    micro.InfoBar():Prompt("select N lines: ", "1", "Ide", nil, function(v, canceled)
      if canceled then return end
      local k = tonumber(v)
      if k and k > 0 then sellines(bp, { tostring(k) }) end
    end)
    return
  end
  if n < 1 then return end
  local sy = bp.Cursor.Y
  local ey = math.min(sy + n - 1, bp.Buf:Lines() - 1)
  bp.Cursor:SetSelectionStart(buffer.Loc(sy, 0))
  bp.Cursor:SetSelectionEnd(buffer.Loc(ey, #bp.Buf:Line(ey)))
  bp:Relocate()
  micro.InfoBar():Message(string.format("selected %d line(s)", ey - sy + 1))
end

---------------------------------------------------------------- neovim-style dashboard
local BANNER = [==[
    ╭─────────────────────────────────────╮
    │   m i c r o   ·   i d e             │
    │   a small editor with a big ego     │
    ╰─────────────────────────────────────╯
]==]

local dashmap = {}
local dashkeys = {}

local function dashText()
  dashmap = {}
  dashkeys = {}
  local L = {}
  local function add(s, e)
    L[#L + 1] = s
    if e then
      dashmap[#L - 1] = e
      if e.key then dashkeys[e.key] = e end
    end
  end

  for l in BANNER:gmatch("[^\n]+") do add("  " .. l) end
  add("")
  add("  cwd: " .. tidy(trim(sh("pwd"))))
  add("")

  add("  ▸ Quick actions")
  local function act(key, label, cmd)
    add(string.format("    %-2s  %s", key, label), { k = "cmd", c = cmd, key = key })
  end
  act("e", "New file",             "newfile")
  act("f", "Find file (fzf)",      "findfile")
  act("g", "Grep (rg --vimgrep)",  "rg")
  act("r", "Replace in project",   "rgreplace")
  act("s", "Symbols (ctags)",      "symbols")
  act("i", "Symbols in this file", "symbolshere")
  act("l", "Select lines",         "sellines")
  act("d", "Refresh dashboard",    "dashboard")
  act("q", "Quit",                 "quit")
  add("")

  add("  ▸ Recent")
  local r = readLines(RECENT)
  if #r == 0 then add("    (none yet)") end
  for i, p in ipairs(r) do
    add(string.format("    %2d  %s", i, tidy(p)), { k = "file", p = p, key = tostring(i) })
  end
  add("")

  add("  ▸ Projects")
  local pr = readLines(PROJECTS)
  if #pr == 0 then add("    (none yet)") end
  for i, p in ipairs(pr) do
    add(string.format("    %2d  %s", i, tidy(p)), { k = "proj", p = p })
  end
  add("")

  add("  ▸ Git")
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
  add("  ↑/↓ or C-p/C-n move · Enter run · e f g r s i d l q quick keys · C-x h toggle")
  return table.concat(L, "\n") .. "\n"
end

local function runAction(bp, e)
  if e == nil then return end
  if e.k == "file" then
    bp:HandleCommand("open " .. q(e.p))
  elseif e.k == "proj" then
    bp:HandleCommand("cd " .. q(e.p))
    showDashboard(bp)
  elseif e.k == "cmd" then
    if e.c == "quit" then
      bp:Quit()
    elseif e.c == "newfile" then
      bp:HandleCommand("newfile")
    else
      bp:HandleCommand(e.c)
    end
  end
end

function showDashboard(bp, args)
  local b = buffer.NewBuffer(dashText(), "dashboard")
  b:SetOption("readonly", "true")
  bp:OpenBuffer(b)
end

function preInsertNewline(bp)
  if bp.Buf:GetName() ~= "dashboard" then return true end
  runAction(bp, dashmap[bp.Cursor.Y])
  return false
end

local function dashkey(bp, ch)
  if bp.Buf:GetName() ~= "dashboard" then return end
  local e = dashkeys[ch]
  if e then runAction(bp, e) end
end

local KEYCHARS = { "e","f","g","r","s","i","d","l","q","1","2","3","4","5","6","7","8","9","0" }

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
local CTAGS = "ctags -x -R --exclude=.git --exclude=node_modules --exclude='*.min.*' --exclude=dist --exclude=build "

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

local function perlLiteral(s) return (s:gsub("([\\$@/])", "\\%1")) end

local function doReplace(old, new)
  local files = trim(sh("rg -l --fixed-strings -- " .. q(old)))
  if files == "" then micro.InfoBar():Message("No matches"); return end
  local list = {}
  for f in files:gmatch("[^\n]+") do list[#list + 1] = q(f) end
  micro.InfoBar():YNPrompt("Replace in " .. #list .. " file(s)? (y/n)", function(yes, canceled)
    if not yes or canceled then return end
    sh("perl -pi -e 'BEGIN{$a=shift;$b=shift} s/\\Q$a\\E/$b/g' " ..
      q(old) .. " " .. q(perlLiteral(new)) .. " " .. table.concat(list, " "))
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
  if bp.Buf:FileType() == "markdown" then return end
  doFormat(bp)
end

---------------------------------------------------------------- C-x prefix (Emacs)
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
  ["S"] = function(bp) sellines(bp) end,
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

local function makeDashKey(ch)
  local cmd = "dashkey-" .. ch
  config.MakeCommand(cmd, function(bp, args) dashkey(bp, ch) end, config.NoComplete)
  config.TryBindKey(ch, "command:" .. cmd, false)
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
  config.MakeCommand("sellines", sellines, config.NoComplete)

  for _, ch in ipairs(KEYCHARS) do makeDashKey(ch) end
end
EOF_LUA

############################ micro plugins ############################
if command -v micro >/dev/null 2>&1; then
  micro -plugin remove filemanager 2>/dev/null || true
  micro -plugin install lsp || echo "!! 'micro -plugin install lsp' failed (offline?). Retry later."

  if [ "$DO_MANAGER" -eq 1 ]; then
    # pluginrepos must already be in settings.json (written above), so this resolves.
    if micro -plugin install manager 2>/dev/null; then
      echo "==> manager installed. Alt-Ctrl-o now opens the nvim-style dashboard."
    else
      echo "!! Optional manager plugin failed (offline or repo unreachable?). Skipping."
      echo "   Retry with: micro -plugin install manager"
    fi
  fi
else
  echo "!! micro not found in PATH after install; check your distro package."
fi

cat <<'EOF_DONE'

──────────────────────────────────────────────
 micro IDE ready  (v1.3.0 · Fedora-aware)
──────────────────────────────────────────────
Config:  ~/.config/micro   (backups: micro.bak.*)

Fedora quick install:
  sudo dnf install -y --setopt=install_weak_deps=False \
      micro ripgrep fzf ctags git clang-tools-extra shfmt \
      python3-yapf bat perl nodejs npm python3-pip
  npm i -g prettier vscode-langservers-extracted bash-language-server python-lsp-server
  sudo dnf install rust cargo        # for stylua
  cargo install stylua --locked
  # clangd: already in clang-tools-extra
  # lua-ls / marksman: download release tarballs

Emacs navigation:
  C-f/C-b/C-n/C-p   char / line        M-f / M-b     word
  C-a/C-e           line start/end     M-< / M->     buffer start/end
  C-v / M-v         page down / up     C-k / C-w     kill / cut
  M-w / C-y         copy / paste       C-x prefix    see C-x h help

Line selection:
  Shift+↑/↓/←/→     extend selection   Alt+↑/↓       move lines up/down
  C-S-k             select line+next   C-S-l         select N lines
  C-S-c / C-S-x     copy / cut line    C-S-d         duplicate line
  C-x S             select N lines (prompt)

Neovim-style dashboard:
  Alt-Ctrl-o        open dashboard      C-x h        open dashboard
  Dashboard keys:   e f g r s i d l q   1-9 recent    Enter runs selection

Search / navigate:
  C-x f  find file (fzf)               C-x /  ripgrep
  C-x j  symbols (project)             C-x i  symbols (file)
  C-x r  replace in project            C-x =  format buffer

Plugins:  ide (this), lsp, manager (optional, telescope-style)
Manager repo: https://codeberg.org/micro-plugins/manager
EOF_DONE
