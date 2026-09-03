-- Workspace rules

hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR, default = true })

-- Main monitor: HDMI-A-1
hl.workspace_rule({ workspace = "1", monitor = MONITOR1, default = true, persistent = true })
hl.workspace_rule({ workspace = "2", monitor = MONITOR1, default = true, persistent = true })
hl.workspace_rule({ workspace = "3", monitor = MONITOR1, default = true, persistent = true })

-- Second monitor: DP-1
hl.workspace_rule({ workspace = "4", monitor = MONITOR2, default = true, persistent = true })
hl.workspace_rule({ workspace = "5", monitor = MONITOR2, default = true, persistent = true })
hl.workspace_rule({ workspace = "6", monitor = MONITOR2, default = true, persistent = true })
