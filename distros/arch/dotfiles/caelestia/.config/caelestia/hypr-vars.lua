-- Overrides for the Caelestia Hyprland defaults.
-- Managed by workstation; reapply with ./install.sh 50.
--
-- Caelestia's upstream defaults point at codium, thunar and pwvucontrol.
-- thunar and pavucontrol are installed here; codium and pwvucontrol exist
-- solely in the AUR, so the mixer keybinding uses the official equivalent.
--
-- No editor is installed by this repository: install whichever VS Code build
-- you want yourself. SUPER + C stays pointed at `code` because every such
-- build provides that binary, and the upstream default it would otherwise
-- fall back to (codium) is not installed either. hl.exec_cmd failures are
-- silent, so check.sh warns when nothing provides the editor.
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
