local env = {
    "XDG_CURRENT_DESKTOP,Hyprland",
    "XDG_SESSION_DESKTOP,Hyprland",
    "XDG_SESSION_TYPE,wayland",
    "QT_QPA_PLATFORMTHEME,qt6ct",
    "QT_AUTO_SCREEN_SCALE_FACTOR,1",
    "QT_WAYLAND_DISABLE_WINDOWDECORATION,1",
    "GDK_BACKEND,wayland,x11",
    "QT_QPA_PLATFORM,wayland;xcb",
    "SDL_VIDEODRIVER,wayland,x11,windows",
    "CLUTTER_BACKEND,wayland",
    "ELECTRON_OZONE_PLATFORM_HINT,wayland",
    "_JAVA_AWT_WM_NONREPARENTING,1",
    "WLR_NO_HARDWARE_CURSORS,1",
    "TERMINAL,ghostty",
    "BROWSER,helium",
    "EDITOR,codium",
}

-- The NVIDIA variables poison the GL/EGL stack on AMD, Intel, and VM sessions
-- (GTK4 apps such as Ghostty abort at startup). Only use them when the primary
-- DRM card is NVIDIA. This also keeps hybrid laptops on their Intel or AMD
-- display GPU unless the firmware exposes NVIDIA as the primary card.
local function read_trimmed(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local value = (file:read("*l") or ""):gsub("^%s+", ""):gsub("%s+$", "")
    file:close()
    return value
end

local primary_nvidia = false
local primary_detected = false
for card = 0, 15 do
    local base = "/sys/class/drm/card" .. card .. "/device/"
    if read_trimmed(base .. "boot_vga") == "1" then
        primary_detected = true
        primary_nvidia = read_trimmed(base .. "vendor") == "0x10de"
        break
    end
end
if not primary_detected then
    primary_nvidia = read_trimmed("/sys/class/drm/card0/device/vendor") == "0x10de"
end

if primary_nvidia then
    table.insert(env, "LIBVA_DRIVER_NAME,nvidia")
    table.insert(env, "GBM_BACKEND,nvidia-drm")
    table.insert(env, "__GLX_VENDOR_LIBRARY_NAME,nvidia")
    table.insert(env, "NVD_BACKEND,direct")
end

for _, item in ipairs(env) do
    local key, value = item:match("^([^,]+),(.+)$")
    if key and value then hl.env(key, value) end
end

-- The greetd session does not carry ~/.local/bin on PATH, which hides every
-- CLI and wrapper the installer places there (codex, opencode, starship,
-- zen-browser, ...).
local home = os.getenv("HOME") or ""
local local_bin = home .. "/.local/bin"
local session_path = os.getenv("PATH") or ""
if not (":" .. session_path .. ":"):find(local_bin, 1, true) then
    hl.env("PATH", local_bin .. ":" .. session_path)
end

hl.on("hyprland.start", function()
    local commands = {
        "systemctl --user start hyprpolkitagent.service",
        "gnome-keyring-daemon --start --components=secrets",
        "systemctl --user start --ignore-dependencies xdg-desktop-portal-hyprland.service xdg-desktop-portal.service",
        "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
        "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
        "trash-empty 30",
        "hyprctl setcursor Bibata-Modern-Classic 24",
        "gsettings set org.gnome.desktop.interface cursor-theme Bibata-Modern-Classic",
        "gsettings set org.gnome.desktop.interface cursor-size 24",
        "noctalia",
    }
    for _, command in ipairs(commands) do hl.exec_cmd(command) end
end)

return true
