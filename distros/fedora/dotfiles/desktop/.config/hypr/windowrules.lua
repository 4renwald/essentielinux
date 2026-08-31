-- Center normal Wayland dialogs and utility windows.
hl.window_rule({ match = { float = true, xwayland = false }, center = true })

for _, class in ipairs({
    "^blueman-manager$",
    "^dev\\.noctalia\\.Noctalia$",
}) do
    hl.window_rule({ match = { class = class }, float = true })
end

hl.window_rule({
    match = { class = "^dev\\.noctalia\\.Noctalia$" },
    size = { 1080, 920 },
})
hl.window_rule({
    match = { class = "^org\\.pulseaudio\\.pavucontrol$" },
    float = true,
    size = "60% 70%",
})
hl.window_rule({
    match = { class = "^system-config-printer$" },
    float = true,
    size = "50% 60%",
})

for _, title in ipairs({
    "^(Select|Open)( a)? (File|Folder)(s)?$",
    "^Save As$",
    "^File (Operation|Upload)( Progress)?$",
    "^.* Properties$",
    "^Rename .*$",
}) do
    hl.window_rule({ match = { title = title }, float = true })
end

-- Picture-in-picture windows remain visible in the bottom-right corner.
hl.window_rule({ match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture).*$" }, tag = "picture-in-picture" })
hl.window_rule({
    match = { tag = "picture-in-picture" },
    float = true,
    pin = true,
    keep_aspect_ratio = true,
    move = "73% 72%",
    size = "25% 25%",
})

-- Games are opaque, latency-sensitive, and inhibit idle while running.
hl.window_rule({
    match = { class = "^(steam_app_[0-9]+|steam_app_default|gamescope)$" },
    opaque = true,
    immediate = true,
    idle_inhibit = "always",
})
hl.window_rule({ match = { class = "^steam$", title = "^Friends List$" }, float = true })
hl.window_rule({ match = { class = "^steam$", title = "^$" }, no_shadow = true })

for _, class in ipairs({
    "^(.*mpv.*|.*vlc.*|.*Spotify.*|steam_app_.*)$",
    "^(.*brave-browser.*|.*zen.*)$",
}) do
    hl.window_rule({ match = { class = class }, idle_inhibit = "fullscreen" })
end

-- Keep the dedicated special workspaces populated by their matching apps.
hl.window_rule({
    match = { class = "^[Ss]potify$" },
    workspace = "special:music",
})
hl.window_rule({
    match = { initial_title = "^(Spotify|Spotify Free)$" },
    workspace = "special:music",
})
hl.window_rule({
    match = { class = "^(discord|equibop|vesktop|Signal|org\\.telegram\\.desktop)$" },
    workspace = "special:communication",
})

-- XWayland's empty helper popups should not receive normal decoration.
hl.window_rule({
    match = { xwayland = true, title = "^win[0-9]+$" },
    no_dim = true,
    no_shadow = true,
    no_blur = true,
    opaque = true,
})
hl.window_rule({
    match = { xwayland = true, title = "^$", class = "^$", initial_title = "^$", initial_class = "^$" },
    no_dim = true,
    no_shadow = true,
    no_blur = true,
    opaque = true,
})

for _, class in ipairs({
    "^VSCodium$", "^[Cc]odium$", "^codium-url-handler$", "^com\\.mitchellh\\.ghostty$",
    "^thunar$", "^[Ss]team$", "^steamwebhelper$", "^[Ss]potify$",
    "^discord$", "^Signal$", "^brave-browser$", "^zen.*$",
}) do
    hl.window_rule({ match = { class = class }, opacity = 1.0 })
end

hl.layer_rule({ match = { namespace = "^hyprpicker$" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "^selection$" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "^launcher$" }, animation = "popin 80%", blur = true })
hl.layer_rule({
    name = "noctalia",
    match = { namespace = "^noctalia-(bar-.+|notification|dock|panel|attached-panel|osd|window-switcher)$" },
    no_anim = true,
    ignore_alpha = 0.5,
    blur = true,
    blur_popups = true,
})

return true
