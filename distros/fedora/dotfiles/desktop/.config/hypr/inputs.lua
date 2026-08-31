hl.config({
    input = {
        kb_layout = "us",
        numlock_by_default = false,
        repeat_delay = 250,
        repeat_rate = 35,
        focus_on_close = 1,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            scroll_factor = 0.3,
        },
    },
    binds = {
        scroll_event_delay = 0,
    },
    cursor = {
        hotspot_padding = 1,
    },
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.15,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
    },
})

local function toggle_active_special()
    local active = hl.get_active_special_workspace()
    local target = active and active.name:gsub("^special:", "") or "special"
    hl.dispatch(hl.dsp.workspace.toggle_special(target))
end

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = "special", workspace_name = "special" })
hl.gesture({ fingers = 3, direction = "down", action = toggle_active_special })
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.exec_cmd("noctalia msg session lock-and-suspend")
    end,
})

return {
    toggle_active_special = toggle_active_special,
}
