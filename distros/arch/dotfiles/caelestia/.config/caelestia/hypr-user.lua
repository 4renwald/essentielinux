-- User-level additions to Caelestia's Hyprland configuration.
-- VRR mode 3 enables adaptive sync only for fullscreen surfaces that declare
-- `video` or `game` content type, which keeps the OLED off VRR on the desktop
-- and during fullscreen non-media windows where it causes brightness flicker.
-- If a game ever fails to advertise a content type it will run without VRR;
-- test with `hyprctl keyword misc:vrr 2` before changing this permanently.
hl.config({
    misc = {
        vrr = 3,
    },
})

-- SUPER + K shows a searchable list of the active keybinds, the way Omarchy
-- does. Caelestia had SUPER + K on kbShowPanels; that moves to SUPER + B in
-- hypr-vars.lua. This file is required after hyprland.keybinds, so the bind is
-- added on top of Caelestia's set.
-- The absolute path avoids depending on ~/.local/bin being in the PATH that
-- Hyprland hands to exec.
hl.bind("SUPER + K", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/hypr-keybinds"))

-- Gammastep has no way to query a running daemon, so the toggle derives the
-- state from the process itself: when the daemon is running the night light is
-- on, and toggling off stops it entirely. An inhibit-style toggle (SIGUSR1)
-- cannot report the resulting state, and a state file would drift from reality
-- after a session restart or a manual daemon kill. The low-urgency transient
-- notification names the resulting state instead of just confirming the
-- keypress.
hl.bind(
    "SUPER + SHIFT + N",
    hl.dsp.exec_cmd(
        "/bin/sh -c 'if /usr/bin/pgrep -x gammastep >/dev/null 2>&1; then " ..
        "/usr/bin/pkill -x gammastep && " ..
        "/usr/bin/notify-send --urgency=low --transient --expire-time=1500 " ..
        "--app-name=Gammastep --icon=night-light-symbolic \"Night light off\"; else " ..
        "/usr/bin/setsid --fork /usr/bin/gammastep >/dev/null 2>&1; " ..
        "/usr/bin/notify-send --urgency=low --transient --expire-time=1500 " ..
        "--app-name=Gammastep --icon=night-light-symbolic \"Night light on\"; fi'"
    ),
    { description = "Toggle night light" }
)

-- Hardware video decoding for the browsers. These belong in the Hyprland
-- environment rather than ~/.config/environment.d: greetd starts the session
-- through start-hyprland, not through a systemd user unit, so environment.d is
-- not read by anything Hyprland spawns. Every browser here is a descendant of
-- Hyprland, so setting them at config-parse time reaches all of them.
--
-- libva 2.20 and later refuse to guess a driver, so libva-nvidia-driver has to
-- be named. Its direct backend talks to the NVIDIA kernel driver instead of
-- sharing buffers through EGL, which is the only backend that works on driver
-- series 525 and later.
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")

-- Firefox runs the decoder inside its RDD process, whose sandbox blocks the
-- device access libva-nvidia-driver needs. This is a real reduction in Zen's
-- sandboxing, and it is the documented requirement for VA-API on NVIDIA: the
-- media decoder process loses its sandbox, the content processes keep theirs.
-- Drop this line and hardware decoding in Zen stops working.
hl.env("MOZ_DISABLE_RDD_SANDBOX", "1")
