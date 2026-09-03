source /usr/share/cachyos-fish-config/cachyos-config.fish

# Custom Fastfetch greeting
function fish_greeting
    fastfetch --config ~/.config/fastfetch/config.jsonc
end
