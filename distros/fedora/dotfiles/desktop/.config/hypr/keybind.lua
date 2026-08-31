local home = os.getenv("HOME") or ""
local bin = home .. "/.local/bin/"
local ipc = "noctalia msg "
local input = require("inputs")

local function bind(keys, command, description, options)
    options = options or {}
    options.description = description
    hl.bind(keys, hl.dsp.exec_cmd(command), options)
end

local function dispatch(command)
    return "hyprctl dispatch " .. command
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
bind("SUPER + ALT + S", dispatch("movetoworkspacesilent special"), "Move window to special workspace")
bind("SUPER + CTRL + SHIFT + Up", dispatch("movetoworkspacesilent special"), "Move window to special workspace")
bind("SUPER + CTRL + SHIFT + Down", dispatch("movetoworkspace e+0"), "Move window out of special workspace")

for _, keys in ipairs({ "SUPER + ALT + mouse_down", "SUPER + ALT + Page_Down", "SUPER + CTRL + SHIFT + Right" }) do
    bind(keys, dispatch("movetoworkspacesilent r+1"), "Move window to next workspace")
end
for _, keys in ipairs({ "SUPER + ALT + mouse_up", "SUPER + ALT + Page_Up", "SUPER + CTRL + SHIFT + Left" }) do
    bind(keys, dispatch("movetoworkspacesilent r-1"), "Move window to previous workspace")
end
for _, keys in ipairs({ "SUPER + mouse_down", "SUPER + Page_Down", "SUPER + CTRL + Right" }) do
    bind(keys, dispatch("workspace r+1"), "Go to next workspace")
end
for _, keys in ipairs({ "SUPER + mouse_up", "SUPER + Page_Up", "SUPER + CTRL + Left" }) do
    bind(keys, dispatch("workspace r-1"), "Go to previous workspace")
end
bind("SUPER + CTRL + mouse_down", bin .. "hypr-workspace-group next-group", "Go to next workspace group")
bind("SUPER + CTRL + mouse_up", bin .. "hypr-workspace-group previous-group", "Go to previous workspace group")

for workspace = 1, 10 do
    local key = tostring(workspace % 10)
    bind("SUPER + " .. key, dispatch("workspace " .. workspace), "Go to workspace " .. workspace)
    bind("SUPER + ALT + " .. key, dispatch("movetoworkspacesilent " .. workspace), "Move window to workspace " .. workspace)
    bind("SUPER + CTRL + " .. key, bin .. "hypr-workspace-group focus-slot " .. workspace, "Go to workspace group " .. workspace)
    bind("SUPER + CTRL + ALT + " .. key, bin .. "hypr-workspace-group move-slot " .. workspace, "Move window to workspace group " .. workspace)
end

-- Window focus, movement, sizing, groups, and floating modes.
for _, item in ipairs({
    {"Left", "l"}, {"Right", "r"}, {"Up", "u"}, {"Down", "d"},
}) do
    bind("SUPER + " .. item[1], dispatch("movefocus " .. item[2]), "Focus window " .. item[1]:lower())
    bind("SUPER + SHIFT + " .. item[1], dispatch("movewindow " .. item[2]), "Move window " .. item[1]:lower())
end

bind("SUPER + Minus", dispatch("resizeactive -10 0"), "Decrease window width", { repeating = true })
bind("SUPER + ALT + Left", dispatch("resizeactive -10 0"), "Decrease window width", { repeating = true })
bind("SUPER + Equal", dispatch("resizeactive 10 0"), "Increase window width", { repeating = true })
bind("SUPER + ALT + Right", dispatch("resizeactive 10 0"), "Increase window width", { repeating = true })
bind("SUPER + SHIFT + Minus", dispatch("resizeactive 0 -10"), "Decrease window height", { repeating = true })
bind("SUPER + ALT + Up", dispatch("resizeactive 0 -10"), "Decrease window height", { repeating = true })
bind("SUPER + SHIFT + Equal", dispatch("resizeactive 0 10"), "Increase window height", { repeating = true })
bind("SUPER + ALT + Down", dispatch("resizeactive 0 10"), "Increase window height", { repeating = true })

hl.bind("SUPER + Z", hl.dsp.window.drag(), { description = "Move window (drag)" })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window (drag)" })
hl.bind("SUPER + X", hl.dsp.window.resize(), { description = "Resize window (drag)" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window (drag)" })
bind("SUPER + CTRL + Backslash", dispatch("centerwindow"), "Center window")
bind("SUPER + CTRL + ALT + Backslash", dispatch("resizeactive exact 55% 70%; hyprctl dispatch centerwindow"), "Resize window to 55x70% and center")
bind("SUPER + ALT + Backslash", bin .. "hypr-pip", "Picture-in-picture mode")
bind("SUPER + P", dispatch("pin"), "Pin window")
bind("SUPER + F", dispatch("fullscreen 0"), "Fullscreen window")
bind("SUPER + ALT + F", dispatch("fullscreen 1"), "Fullscreen window (bordered)")
bind("SUPER + ALT + Space", dispatch("togglefloating"), "Toggle floating for window")
bind("SUPER + Q", dispatch("killactive"), "Close window")
bind("ALT + Tab", dispatch("cyclenext"), "Next window")
bind("ALT + SHIFT + Tab", dispatch("cyclenext prev"), "Previous window")
bind("CTRL + ALT + Tab", dispatch("changegroupactive f"), "Next window in group")
bind("CTRL + ALT + SHIFT + Tab", dispatch("changegroupactive b"), "Previous window in group")
bind("SUPER + U", dispatch("moveoutofgroup"), "Move window out of group")
bind("SUPER + Comma", dispatch("togglegroup"), "Toggle group")
bind("SUPER + SHIFT + Comma", dispatch("lockactivegroup toggle"), "Lock active group")

-- Special workspaces.
hl.bind("SUPER + S", input.toggle_active_special, { description = "Toggle special workspace" })
bind("SUPER + M", dispatch("togglespecialworkspace music"), "Toggle music workspace")
bind("SUPER + D", dispatch("togglespecialworkspace communication"), "Toggle communication workspace")
bind("SUPER + R", dispatch("togglespecialworkspace todo"), "Toggle todo workspace")
bind("CTRL + SHIFT + Escape", dispatch("exec [workspace special:sysmon silent] ghostty -e btop; hyprctl dispatch togglespecialworkspace sysmon"), "Toggle system monitor workspace")

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
