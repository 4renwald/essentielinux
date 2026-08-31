local config_dir = (os.getenv("HOME") or "") .. "/.config/hypr"
package.path = table.concat({
    config_dir .. "/?.lua",
    config_dir .. "/?/init.lua",
    package.path,
}, ";")

for _, mod in ipairs({
    "monitors", "startup", "inputs", "keybind", "windowrules",
    "animations", "themes.theme",
}) do
    package.loaded[mod] = nil
end

require("monitors")
require("startup")
require("inputs")
require("keybind")
require("windowrules")
require("animations")
require("themes.theme")

-- The generated palette is optional during installation and available after
-- Noctalia has rendered its built-in Hyprland template.
local palette = io.open(config_dir .. "/noctalia.lua", "r")
if palette then
    palette:close()
    require("noctalia").apply_theme()
end

hl.config({
    dwindle = { preserve_split = true },
    master = { new_status = "master" },
    misc = {
        vrr = 3,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        anr_missed_pings = 5,
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        middle_click_paste = false,
        focus_on_activate = true,
        session_lock_xray = true,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
    xwayland = { force_zero_scaling = true },
    general = {
        snap = { enabled = true },
    },
    debug = {
        error_position = 1,
    },
})
