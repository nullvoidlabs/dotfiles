-- Docs: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- To check class name, open the app and run:
-- hyprctl clients

hl.layer_rule({
    match = { namespace = "rofi" },
    blur = true,
    ignore_alpha = 0.15,
})

-- Opacity rules for all windows except fullscreen.
-- Default 0.7. Super + O saves your pick to ~/.local/state/43pr/opacity
-- (outside the repo), so changing it doesn't leave this file modified.
local window_opacity = "0.7"
do
    local state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/43pr/opacity"
    local fh = io.open(state, "r")
    if fh then
        local v = tonumber(fh:read("*l") or "")
        fh:close()
        if v and v >= 0.1 and v <= 1.0 then window_opacity = string.format("%.2f", v) end
    end
end

hl.window_rule({
    match = { class = ".*" },
    opacity = window_opacity .. " override",
})

hl.window_rule({
    match = { class = ".*", fullscreen = true },
    opacity = "1.0 override",
})

--hl.window_rule({
--    name = "brave",
--    match = { class = "^brave-browser$" },
--    opacity = "1.0 override",
--})

hl.window_rule({
    match = { class = "kitty" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "file-picker-float",
    match = { class = "^(xdg-desktop-portal-gtk)$" },
    float = true,
    center = true,
    size = "900 600",
})

hl.window_rule({
    name = "float-pavucontrol",
    match = { class = "^(pavucontrol)$" },
    float = true,
})

hl.window_rule({
    name = "float-nm-connection-editor",
    match = { class = "^(nm-connection-editor)$" },
    float = true,
})

hl.window_rule({
    name = "float-blueman-manager",
    match = { class = "^(blueman-manager)$" },
    float = true,
})

hl.window_rule({
    name = "float-open-file",
    match = { title = "^(Open File)$" },
    float = true,
})

hl.window_rule({
    name = "float-save-file",
    match = { title = "^(Save File)$" },
    float = true,
})
