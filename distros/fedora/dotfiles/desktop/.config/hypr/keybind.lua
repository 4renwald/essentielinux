local home = os.getenv("HOME") or ""
local bin = home .. "/.local/bin/"
local ipc = "noctalia msg "
local input = require("inputs")

local function bind(keys, command, description, options)
    options = options or {}
    options.description = description
    hl.bind(keys, hl.dsp.exec_cmd(command), options)
end

local function native_bind(keys, dispatcher, description, options)
    options = options or {}
    options.description = description
    hl.bind(keys, dispatcher, options)
end

-- Shell and session actions use Noctalia v5 IPC while retaining the established
-- key combinations.
bind("SUPER + SUPER_L", ipc .. "panel-toggle launcher", "Open launcher", { release = true })
bind("SUPER + N", ipc .. "panel-toggle control-center", "Toggle shell sidebar")
bind("SUPER + B", ipc .. "bar-toggle", "Show or hide shell panels")
bind("SUPER + K", bin .. "hypr-keybinds", "Show this keybind cheatsheet")
bind("CTRL + ALT + Delete", ipc .. "panel-toggle session", "Open shell session menu")
bind("CTRL + ALT + C", ipc .. "notification-clear-active && " .. ipc .. "notification-clear-history", "Clear shell notifications")
bind("SUPER + L", ipc .. "session lock", "Lock screen")
bind("SUPER + ALT + L", ipc .. "session lock", "Restore shell lockscreen")
bind("SUPER + SHIFT + L", ipc .. "session lock-and-suspend", "Sleep")
bind("SUPER + CTRL + SHIFT + R", "pkill noctalia", "Kill shell", { release = true })
bind("SUPER + CTRL + ALT + R", "pkill noctalia; noctalia", "Restart shell", { release = true })
bind("SUPER + SHIFT + N", ipc .. "nightlight-force-toggle", "Toggle night-light adjustment")

-- Regular and grouped workspaces.
native_bind("SUPER + ALT + S", hl.dsp.window.move({ workspace = "special:special", follow = false }), "Move window to special workspace")
native_bind("SUPER + CTRL + SHIFT + Up", hl.dsp.window.move({ workspace = "special:special", follow = false }), "Move window to special workspace")
native_bind("SUPER + CTRL + SHIFT + Down", hl.dsp.window.move({ workspace = "e+0" }), "Move window out of special workspace")

for _, keys in ipairs({ "SUPER + ALT + mouse_down", "SUPER + ALT + Page_Down", "SUPER + CTRL + SHIFT + Right" }) do
    native_bind(keys, hl.dsp.window.move({ workspace = "r+1", follow = false }), "Move window to next workspace")
end
for _, keys in ipairs({ "SUPER + ALT + mouse_up", "SUPER + ALT + Page_Up", "SUPER + CTRL + SHIFT + Left" }) do
    native_bind(keys, hl.dsp.window.move({ workspace = "r-1", follow = false }), "Move window to previous workspace")
end
for _, keys in ipairs({ "SUPER + mouse_down", "SUPER + Page_Down", "SUPER + CTRL + Right" }) do
    native_bind(keys, hl.dsp.focus({ workspace = "r+1" }), "Go to next workspace")
end
for _, keys in ipairs({ "SUPER + mouse_up", "SUPER + Page_Up", "SUPER + CTRL + Left" }) do
    native_bind(keys, hl.dsp.focus({ workspace = "r-1" }), "Go to previous workspace")
end
bind("SUPER + CTRL + mouse_down", bin .. "hypr-workspace-group next-group", "Go to next workspace group")
bind("SUPER + CTRL + mouse_up", bin .. "hypr-workspace-group previous-group", "Go to previous workspace group")

for workspace = 1, 10 do
    local key = tostring(workspace % 10)
    native_bind("SUPER + " .. key, hl.dsp.focus({ workspace = workspace }), "Go to workspace " .. workspace)
    native_bind("SUPER + ALT + " .. key, hl.dsp.window.move({ workspace = workspace, follow = false }), "Move window to workspace " .. workspace)
    bind("SUPER + CTRL + " .. key, bin .. "hypr-workspace-group focus-slot " .. workspace, "Go to workspace group " .. workspace)
    bind("SUPER + CTRL + ALT + " .. key, bin .. "hypr-workspace-group move-slot " .. workspace, "Move window to workspace group " .. workspace)
end

-- Window focus, movement, sizing, groups, and floating modes.
for _, item in ipairs({
    {"Left", "l"}, {"Right", "r"}, {"Up", "u"}, {"Down", "d"},
}) do
    native_bind("SUPER + " .. item[1], hl.dsp.focus({ direction = item[1]:lower() }), "Focus window " .. item[1]:lower())
    native_bind("SUPER + SHIFT + " .. item[1], hl.dsp.window.move({ direction = item[1]:lower() }), "Move window " .. item[1]:lower())
end

native_bind("SUPER + Minus", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), "Decrease window width", { repeating = true })
native_bind("SUPER + ALT + Left", hl.dsp.window.resize({ x = -10, y = 0, relative = true }), "Decrease window width", { repeating = true })
native_bind("SUPER + Equal", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), "Increase window width", { repeating = true })
native_bind("SUPER + ALT + Right", hl.dsp.window.resize({ x = 10, y = 0, relative = true }), "Increase window width", { repeating = true })
native_bind("SUPER + SHIFT + Minus", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), "Decrease window height", { repeating = true })
native_bind("SUPER + ALT + Up", hl.dsp.window.resize({ x = 0, y = -10, relative = true }), "Decrease window height", { repeating = true })
native_bind("SUPER + SHIFT + Equal", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), "Increase window height", { repeating = true })
native_bind("SUPER + ALT + Down", hl.dsp.window.resize({ x = 0, y = 10, relative = true }), "Increase window height", { repeating = true })

hl.bind("SUPER + Z", hl.dsp.window.drag(), { description = "Move window (drag)" })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window (drag)" })
hl.bind("SUPER + X", hl.dsp.window.resize(), { description = "Resize window (drag)" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window (drag)" })
native_bind("SUPER + CTRL + Backslash", hl.dsp.window.center(), "Center window")
bind("SUPER + CTRL + ALT + Backslash", "hyprctl dispatch resizeactive exact 55% 70%; hyprctl dispatch centerwindow", "Resize window to 55x70% and center")
bind("SUPER + ALT + Backslash", bin .. "hypr-pip", "Picture-in-picture mode")
native_bind("SUPER + P", hl.dsp.window.pin(), "Pin window")
native_bind("SUPER + F", hl.dsp.window.fullscreen(), "Fullscreen window")
native_bind("SUPER + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), "Fullscreen window (bordered)")
native_bind("SUPER + ALT + Space", hl.dsp.window.float(), "Toggle floating for window")
native_bind("SUPER + Q", hl.dsp.window.close(), "Close window")
native_bind("ALT + Tab", hl.dsp.window.cycle_next(), "Next window")
native_bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }), "Previous window")
native_bind("CTRL + ALT + Tab", hl.dsp.group.next(), "Next window in group")
native_bind("CTRL + ALT + SHIFT + Tab", hl.dsp.group.prev(), "Previous window in group")
native_bind("SUPER + U", hl.dsp.window.move({ out_of_group = true }), "Move window out of group")
native_bind("SUPER + Comma", hl.dsp.group.toggle(), "Toggle group")
native_bind("SUPER + SHIFT + Comma", hl.dsp.group.lock_active(), "Lock active group")

-- Special workspaces.
hl.bind("SUPER + S", input.toggle_active_special, { description = "Toggle special workspace" })
native_bind("SUPER + M", hl.dsp.workspace.toggle_special("music"), "Toggle music workspace")
native_bind("SUPER + D", hl.dsp.workspace.toggle_special("communication"), "Toggle communication workspace")
native_bind("SUPER + R", hl.dsp.workspace.toggle_special("todo"), "Toggle todo workspace")
bind("CTRL + SHIFT + Escape", "hyprctl dispatch exec '[workspace special:sysmon silent] ghostty -e btop'; hyprctl dispatch togglespecialworkspace sysmon", "Toggle system monitor workspace")

-- Applications.
bind("SUPER + T", "ghostty", "Terminal (ghostty)")
bind("SUPER + W", "zen-browser", "Browser (Zen Browser)")
bind("SUPER + C", "codium", "Editor (VSCodium)")
bind("SUPER + E", "thunar", "File explorer (Thunar)")
bind("CTRL + ALT + V", "pavucontrol", "Audio settings (pavucontrol)")

-- Screenshots and recordings.
bind("Print", ipc .. "screenshot-fullscreen", "Screenshot")
bind("SUPER + SHIFT + S", "HYPRSHOT_DIR=~/Pictures/Screenshots hyprshot -m region --freeze", "Screenshot (freeze)")
bind("SUPER + ALT + SHIFT + S", "HYPRSHOT_DIR=~/Pictures/Screenshots hyprshot -m region", "Screenshot (region)")
bind("CTRL + ALT + R", bin .. "hypr-record screen none", "Record fullscreen")
bind("SUPER + ALT + R", bin .. "hypr-record screen output", "Record with sound")
bind("SUPER + ALT + SHIFT + R", bin .. "hypr-record region output", "Record region")
bind("SUPER + SHIFT + C", "hyprpicker -a", "Colour picker")

-- Media and hardware keys.
bind("SUPER + CTRL + Space", ipc .. "media toggle", "Play/pause", { locked = true })
bind("XF86AudioPlay", ipc .. "media toggle", "Play/pause", { locked = true })
bind("XF86AudioPause", ipc .. "media toggle", "Play/pause", { locked = true })
bind("SUPER + CTRL + Equal", ipc .. "media next", "Next track", { locked = true })
bind("XF86AudioNext", ipc .. "media next", "Next track", { locked = true })
bind("SUPER + CTRL + Minus", ipc .. "media previous", "Previous track", { locked = true })
bind("XF86AudioPrev", ipc .. "media previous", "Previous track", { locked = true })
bind("SUPER + CTRL + Backspace", ipc .. "media stop", "Stop playback", { locked = true })
bind("XF86AudioStop", ipc .. "media stop", "Stop playback", { locked = true })
bind("SUPER + SHIFT + M", ipc .. "volume-mute", "Mute volume", { locked = true })
bind("XF86AudioMute", ipc .. "volume-mute", "Mute volume", { locked = true })
bind("XF86AudioMicMute", ipc .. "mic-mute", "Mute microphone", { locked = true })
bind("XF86AudioRaiseVolume", ipc .. "volume-up 10", "Volume up", { locked = true, repeating = true })
bind("XF86AudioLowerVolume", ipc .. "volume-down 10", "Volume down", { locked = true, repeating = true })
bind("XF86MonBrightnessUp", ipc .. "brightness-up", "Brightness up", { locked = true, repeating = true })
bind("XF86MonBrightnessDown", ipc .. "brightness-down", "Brightness down", { locked = true, repeating = true })

-- Clipboard, emoji, and diagnostics.
bind("SUPER + V", ipc .. "panel-toggle clipboard", "Clipboard history")
bind("SUPER + ALT + V", ipc .. "panel-toggle clipboard", "Clipboard history (delete mode)")
bind("CTRL + ALT + SHIFT + V", bin .. "hypr-paste-latest", "Paste latest clipboard entry")
bind("SUPER + Period", ipc .. "panel-toggle launcher \"/emo \"", "Emoji picker")
bind("SUPER + ALT + F12", "notify-send 'Test notification' 'Hyprland and Noctalia are working.'", "Test notification")

return true
