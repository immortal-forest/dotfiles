# Arch Dotfiles

Repo for my dotfiles for Arch Linux with [Hyprland](https://hyprland.org)

Inspired by [Hyde](https://github.com/prasanthrangan/hyprdots)

# How it looks?

![screen](/assets/new-screen.png)
![screen-ii](/assets/new-screen-ii.png)
![rofi](/assets/rofi-new.png)
![lockscreen](/assets/hyprlock.png) 

See [assets](/assets) for more


# Wallpapers
Check this [repo](../../../wallpapers)


# Stuffs used

 - [hyprlock](https://github.com/hyprwm/hyprlock) - lock screen
 - [hypridle](https://github.com/hyprwm/hypridle) - idle management
 - [swww](https://github.com/LGFae/swww) - wallpaper
 - [dunst](https://dunst-project.org) - notification
 - [pywal](https://github.com/dylanaraps/pywal) - color generation
 - [waybar](https://github.com/Alexays/Waybar) - status bar
 - [rofi](https://github.com/lbonn/rofi) (for wayland) - app launcher
 - [wlogout](https://github.com/ArtsyMacaw/wlogout) - logout menu
 - [cliphist](https://github.com/sentriz/cliphist) - clipboard
 - and more....

# Installation

### Cloning the repo

Clone this repo to your home directory and cd into it

```bash
git clone https://github.com/immortal-forest/dotfiles.git ~/dotfiles && cd ~/dotfiles
```

### Dependencies

> [!WARNING]
> Make sure you have an AUR helper installed on your system before proceeding to the next step. Next step uses `yay` but you can use any.

> [!TIP]
> Add '#' at the beginning of the package in [install.lst](/install.lst) will ignore it

```bash
cat install.lst | grep -v "^#" | sed '/^$/d' | yay -S --removemake -
```
This will install all the required packages. 

> [!TIP]
> Installing all the packages will take time. You will be prompted for password and confirmation multiple times during this process. Adding `--noconfirm --sudoloop` after `-S` will skip confirmation and further need to type in the password.


```bash
cat install.lst | grep -v "^#" | sed '/^$/d' | yay -S --removemake --noconfirm --sudoloop -
```

### Stow

> [!WARNING]
> Make sure to backup your existing files

Run this special command:

```bash
stow .
```

This will create symlinks in your home directory pointing to the files in the `~/dotfiles` directory.

### Icons and themes

Extract the archives in `.icons` and `.themes` directory

Create `.icons` and `.themes` directory in your home directory

```bash
mkdir ~/.icons ~/.themes
```

For each archive in `.icons`, run

```bash
tar xvf .icons/<archive name> -C ~/.icons
```

For `.themes`,

```bash
tar xvf .themes/catppuccin-mocha-lavender.tar.gz -C ~/.themes
```

### Wallpapers

Clone the wallpapers repo into `~/wallpapers`

```bash
git clone https://github.com/immortal-forest/wallpapers.git ~/wallpapers
```

> [!NOTE]
> This part is optional

Then delete `.git` directory inside wallpapers

```bash
rm -rf ~/wallpapers/.git
```

Next, create a file named `wall.conf` inside wallpapers

```bash
touch ~/wallpapers/wall.conf
```

And put this:
```
Theme=Wal
wallpaper=shorekeeper_illus_2.jpeg
```

### Updating dotfiles

```bash
git pull
```
Just run this inside the dotfiles directory, and you're done.

