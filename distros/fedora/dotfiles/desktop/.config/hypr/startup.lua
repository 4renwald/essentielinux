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
    "LIBVA_DRIVER_NAME,nvidia",
    "GBM_BACKEND,nvidia-drm",
    "__GLX_VENDOR_LIBRARY_NAME,nvidia",
    "NVD_BACKEND,direct",
    "TERMINAL,ghostty",
    "BROWSER,zen-browser",
    "EDITOR,codium",
}

for _, item in ipairs(env) do
    local key, value = item:match("^([^,]+),(.+)$")
    if key and value then hl.env(key, value) end
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
        "sleep 3; easyeffects --gapplication-service",
    }
    for _, command in ipairs(commands) do hl.exec_cmd(command) end
end)

return true
