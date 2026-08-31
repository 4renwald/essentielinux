-- Overrides for the Caelestia Hyprland defaults.
-- Managed by workstation; reapply with ./install.sh 50.
--
-- Caelestia's upstream defaults point at codium, thunar and pwvucontrol.
-- The package manifest installs Code - OSS, Thunar, and pavucontrol, so these
-- overrides use their available commands instead.
--
-- hl.exec_cmd failures are silent, so Code - OSS is included in the required
-- package manifest and SUPER + C always has a concrete editor target.
--
-- sleepGestureCmd overrides Caelestia's suspend-then-hibernate default. This
-- system swaps only to zram, which cannot be a hibernation target, so the
-- hibernate half of that command could never succeed.
--
-- kbShowPanels moves off SUPER + K so the keybind cheatsheet can take it.
-- B is free (C D E F K L M N P Q R S T U V W X Z are taken) and reads as
-- "bars", which is what caelestia:showall reveals.
--
-- automaticNightLight controls the GeoClue + Gammastep startup in execs.lua.
-- SUPER + SHIFT + N temporarily toggles that running adjustment. Set this to
-- false only to disable automatic night light at future session startups.
return {
    kbShowPanels        = "SUPER + B",
    automaticNightLight = true,

    terminal             = "ghostty",
    browser              = "zen-browser",
    editor               = "code",
    fileExplorer         = "thunar",
    audioSettings        = "pavucontrol",
    sleepGestureCmd      = "systemctl suspend",
    cursorTheme          = "Bibata-Modern-Classic",
    cursorSize           = 24,
}
