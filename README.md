# CachyOS Dotfiles

## 🚀 Установка dotfiles

Клонировать repository:

    git clone https://github.com/AkAkiW/AkAki-CachyOS-dotfiles.git

Перейти в repository:

    cd ~/AkAki-CachyOS-dotfiles

Проверить installer:

    bash -n install.sh

Запустить восстановление:

    ./install.sh

После запуска installer покажет план изменений и запросит подтверждение.

### Проверка после установки

Проверить статус repository:

    git status

Проверить основные конфиги:

    ls -la ~/.config/hypr
    ls -la ~/.config/noctalia
    ls -la ~/.config/kitty
    ls -la ~/.config/fish

Проверить backup:

    ls -lah ~/.config-backups/

### Wallpaper

Wallpaper находится в repository:

    ~/AkAki-CachyOS-dotfiles/assets/wallpapers/lunar-tides-5120x4266-26444.jpg

Он не устанавливается автоматически.

При необходимости назначить его вручную через Noctalia.

### Быстрая установка

Если repository уже клонирован:

    cd ~/AkAki-CachyOS-dotfiles
    bash -n install.sh
    ./install.sh

> ⚠️ Не запускай installer через `sudo`.
>
> Installer сам создаёт backup существующих managed-конфигураций
> перед их заменой.
