-- Look and feel configuration

hl.config({
    general = {
        gaps_in = 3,
        gaps_out = 8,
        border_size = 2,
        extend_border_grab_area = 10,
        resize_on_border = true,

        col = {
            active_border = WINDOW_ACTIVE,
            inactive_border = WINDOW_INACTIVE,
        },
    },

    group = {
        col = {
            border_active = WINDOW_ACTIVE,
            border_inactive = WINDOW_INACTIVE,
            border_locked_active = WINDOW_ACTIVE,
            border_locked_inactive = WINDOW_INACTIVE,
        },

        groupbar = {
            col = {
                active = WINDOW_ACTIVE,
                inactive = WINDOW_INACTIVE,
                locked_active = WINDOW_ACTIVE,
                locked_inactive = WINDOW_INACTIVE,
            },
        },
    },

    decoration = {
        dim_special = 0.3,
        rounding = 10,

        active_opacity = 0.95,
        inactive_opacity = 0.85,
        fullscreen_opacity = 1,

        blur = {
            size = 5,
            passes = 4,
            special = true,
        },
    },
})
