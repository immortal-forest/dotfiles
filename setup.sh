#!/usr/bin/env bash
# setup.sh: set these dotfiles up on an Arch machine.
#
# Installs the packages they use (only what's missing, it never upgrades
# anything) and our own builds from the GitHub release (the patched skwd-wall,
# Obel Mono Lig), compiles appnap's memory helper on this machine, fetches
# the Outfit font, links every package into $HOME with GNU stow and clones the
# tmux plugin manager. Anything already in the way is
# moved to ~/.dotfiles-backup/<time>/ first, so nothing is lost.
# Safe to run again after a `git pull`.
#
#   ./setup.sh                  everything below
#   ./setup.sh --no-packages    skip pacman, the AUR and our builds
#   ./setup.sh --no-fonts       skip the Outfit download
#   ./setup.sh --skip git,kitty don't link these packages
#   ./setup.sh --extras         also install the platform-profile udev rule (sudo)
#   ./setup.sh --dry-run        print what would happen, change nothing
#   ./setup.sh --yes            don't ask before installing packages
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
stamp=$(date +%Y%m%d-%H%M%S)
backup_dir="$HOME/.dotfiles-backup/$stamp"
fonts_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts"

do_packages=1 do_fonts=1 extras=0 dry=0 yes=0
skip=()

# --- output ----------------------------------------------------------------

if [ -t 1 ]; then b=$'\e[1m' dim=$'\e[2m' yel=$'\e[33m' red=$'\e[31m' off=$'\e[0m'
else b="" dim="" yel="" red="" off=""; fi
step() { printf '\n%s==> %s%s\n' "$b" "$*" "$off"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    %swarning:%s %s\n' "$yel" "$off" "$*"; warnings+=("$*"); }
die()  { printf '%serror:%s %s\n' "$red" "$off" "$*" >&2; exit 1; }
warnings=()

# run CMD...: do it, or just print it under --dry-run
run() {
    if [ $dry -eq 1 ]; then printf '    %swould run:%s %s\n' "$dim" "$off" "$*"; else "$@"; fi
}

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
    --no-packages) do_packages=0 ;;
    --no-fonts) do_fonts=0 ;;
    --skip) [ $# -ge 2 ] || die "--skip needs a list, e.g. --skip git,kitty"
            IFS=, read -ra more <<<"$2"; skip+=("${more[@]}"); shift ;;
    --skip=*) IFS=, read -ra more <<<"${1#--skip=}"; skip+=("${more[@]}") ;;
    --extras) extras=1 ;;
    -n | --dry-run) dry=1 ;;
    -y | --yes) yes=1 ;;
    -h | --help) usage; exit 0 ;;
    *) usage; die "unknown option: $1" ;;
    esac
    shift
done

[ "$(id -u)" -ne 0 ] || die "run this as your user, not root (it asks for sudo when it needs it)"
command -v pacman >/dev/null || die "this setup is for Arch Linux (no pacman found)"
[ $dry -eq 1 ] && printf '%sDry run: nothing will be changed.%s\n' "$b" "$off"

confirm() { # question: yes unless the answer starts with n
    [ $yes -eq 1 ] || [ $dry -eq 1 ] && return 0
    local a
    read -rp "    $1 [Y/n] " a
    [[ ! "$a" =~ ^[Nn] ]]
}

# --- packages --------------------------------------------------------------

repo_pkgs=(
    # compositor and shell
    base-devel hyprland quickshell hypridle xdg-desktop-portal-hyprland
    # colours from the wallpaper, and the Qt apps that follow them
    matugen qt5ct qt6ct
    # what astralis runs: clipboard, screenshots, recording, audio, network, media
    wl-clipboard cliphist grim slurp hyprshot hyprpicker gpu-screen-recorder ffmpeg
    pipewire pipewire-pulse wireplumber libpulse playerctl cava
    networkmanager bluez bluez-utils upower brightnessctl libnotify
    curl jq uv python imagemagick psmisc kakasi xdg-utils libarchive fontconfig
    # terminal side
    ghostty kitty zsh tmux neovim ripgrep starship eza zoxide fzf fastfetch git stow
    # fonts
    ttf-material-symbols-variable ttf-jetbrains-mono-nerd ttf-nerd-fonts-symbols-mono
    noto-fonts noto-fonts-cjk noto-fonts-emoji
)
# "a|b": install a unless a or b is already there
aur_pkgs=(
    "skwd-deck-bin|skwd-deck" "skwd-paper-bin|skwd-paper" # wallpaper daemon (the picker is ours, below)
    spicetify-bin                             # Spotify theming (not spicetify-cli-git, it blanks Spotify)
    python-pywalfox                           # Firefox / Zen theming
    zen-browser-bin                           # the browser Super+F opens
)
# Our own builds (PKGBUILDs in system/), built by .github/workflows/packages.yml
# and attached to the "packages" release with a SHA256SUMS. An installed
# skwd-wall-v2 or skwd-wall-v2-bin is left alone.
release=https://github.com/immortal-forest/dotfiles/releases/download/packages
built_pkgs=(skwd-wall-v2 ttf-obel-mono-lig)
has_nvidia() { grep -qs 0x10de /sys/bus/pci/devices/*/vendor; }
has_nvidia && repo_pkgs+=(nvidia-prime) # prime-run, for the launcher's "open on NVIDIA"

# Print the entries that aren't installed (or provided by something installed).
missing() {
    local e a found plain=()
    for e in "$@"; do
        if [[ "$e" != *"|"* ]]; then plain+=("$e"); continue; fi
        found=0
        IFS='|' read -ra alts <<<"$e"
        for a in "${alts[@]}"; do pacman -T "$a" >/dev/null && found=1 && break; done
        [ $found -eq 1 ] || echo "${alts[0]}"
    done
    [ ${#plain[@]} -eq 0 ] || pacman -T "${plain[@]}" || true
}

aur_helper() {
    local h
    for h in paru yay; do command -v "$h" >/dev/null && { echo "$h"; return 0; }; done
    return 0
}

bootstrap_yay() {
    local tmp
    info "no AUR helper found, building yay-bin"
    [ $dry -eq 1 ] && { info "would build yay-bin from https://aur.archlinux.org/yay-bin.git"; return 0; }
    tmp=$(mktemp -d)
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin" &&
        (cd "$tmp/yay-bin" && run makepkg -si --noconfirm)
    local rc=$?
    rm -rf "$tmp"
    return $rc
}

install_packages() {
    local -a need_repo need_aur flags=(--needed)
    [ $yes -eq 1 ] && flags+=(--noconfirm)
    mapfile -t need_repo < <(missing "${repo_pkgs[@]}")
    mapfile -t need_aur < <(missing "${aur_pkgs[@]}")

    if [ ${#need_repo[@]} -eq 0 ] && [ ${#need_aur[@]} -eq 0 ]; then
        info "everything is already installed"
        return
    fi
    if [ ${#need_repo[@]} -gt 0 ]; then
        info "from the Arch repos: ${need_repo[*]}"
        if confirm "Install these?"; then
            run sudo pacman -S "${flags[@]}" "${need_repo[@]}" || warn "pacman failed, some packages are missing"
        else
            warn "skipped: ${need_repo[*]}"
        fi
    fi
    if [ ${#need_aur[@]} -gt 0 ]; then
        info "from the AUR: ${need_aur[*]}"
        if confirm "Install these?"; then
            local helper
            helper=$(aur_helper)
            if [ -z "$helper" ]; then
                bootstrap_yay || { warn "couldn't build yay; install ${need_aur[*]} yourself"; return; }
                helper=yay
            fi
            run "$helper" -S "${flags[@]}" "${need_aur[@]}" || warn "$helper failed, some AUR packages are missing"
        else
            warn "skipped: ${need_aur[*]}"
        fi
    fi
}

# (no grep -q: under pipefail its early exit would fail the pipe)
have_font() { fc-list : family | tr ',' '\n' | grep -xF "$1" >/dev/null; }

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

# Download our builds, check each against the release's SHA256SUMS and install
# them with pacman -U. Runs after the AUR: skwd-wall-v2 needs skwd-deck and skwd-paper.
install_built() {
    local name line file tmp
    local -a want=() files=() flags=(--needed)
    [ $yes -eq 1 ] && flags+=(--noconfirm)
    for name in "${built_pkgs[@]}"; do
        pacman -T "$name" >/dev/null && continue                                 # installed, or provided
        [ "$name" = ttf-obel-mono-lig ] && have_font "Obel Mono Lig" && continue # e.g. in ~/.local/share/fonts
        want+=("$name")
    done
    if [ ${#want[@]} -eq 0 ]; then info "our builds: installed"; return 0; fi
    if [ $dry -eq 1 ]; then info "would download from the packages release: ${want[*]}"; return 0; fi

    tmp=$(mktemp -d)
    if ! fetch "$release/SHA256SUMS" "$tmp/SHA256SUMS"; then
        warn "couldn't reach the packages release, skipped ${want[*]}"
        rm -rf "$tmp"
        return 0
    fi
    for name in "${want[@]}"; do
        # each line: <sha256>  <name>-<version>-<rel>-<arch>.pkg.tar.zst
        line=$(grep -E "  ${name}-[0-9][^ ]*\.pkg\.tar\.zst\$" "$tmp/SHA256SUMS" | head -1 || true)
        file=${line##* }
        if [ -n "$file" ] && fetch "$release/$file" "$tmp/$file" &&
            (cd "$tmp" && echo "$line" | sha256sum -c --status); then
            files+=("$tmp/$file")
        else
            warn "couldn't get $name from the release, or its checksum didn't match"
        fi
    done
    if [ ${#files[@]} -gt 0 ]; then
        info "our builds: ${files[*]##*/}"
        run sudo pacman -U "${flags[@]}" "${files[@]}" || warn "pacman couldn't install our builds"
    fi
    rm -rf "$tmp"
}

# appnap-mem (system/appnap-mem): the small C helper appnap uses to write a
# napped app's memory to disk and read it back in one go on wake. Compiled here
# on this machine and installed to /usr/local/bin with CAP_SYS_NICE, which it
# needs to advise another process (reinstalling drops the capability, so it's
# set on every install). appnap still works without it, it just wakes slower.
install_appnap_mem() {
    local src="$repo/system/appnap-mem/appnap-mem.c" dst=/usr/local/bin/appnap-mem tmp
    command -v gcc >/dev/null || { warn "gcc isn't installed (base-devel), skipping appnap-mem"; return; }
    tmp=$(mktemp -d)
    if ! gcc -O2 -Wall -o "$tmp/appnap-mem" "$src"; then
        warn "appnap-mem didn't compile"
    elif cmp -s "$tmp/appnap-mem" "$dst" && getcap "$dst" 2>/dev/null | grep cap_sys_nice >/dev/null; then
        info "appnap-mem: up to date"
    else
        run sudo install -m755 "$tmp/appnap-mem" "$dst" &&
            run sudo setcap cap_sys_nice=ep "$dst" &&
            { [ $dry -eq 1 ] || info "appnap-mem compiled and installed"; } ||
            warn "couldn't install appnap-mem"
    fi
    rm -rf "$tmp"
}

# --- fonts that aren't packaged --------------------------------------------

# Outfit: the shell's UI font (OFL), straight from the Google Fonts repo.
install_outfit() {
    local gf=https://raw.githubusercontent.com/google/fonts/main/ofl/outfit
    run mkdir -p "$fonts_dir/Outfit"
    [ $dry -eq 1 ] && { info "would download Outfit[wght].ttf to $fonts_dir/Outfit"; return; }
    fetch "$gf/Outfit%5Bwght%5D.ttf" "$fonts_dir/Outfit/Outfit[wght].ttf" &&
        fetch "$gf/OFL.txt" "$fonts_dir/Outfit/OFL.txt"
}

install_fonts() {
    local changed=0
    if have_font Outfit; then info "Outfit: installed"
    elif install_outfit; then [ $dry -eq 1 ] || info "Outfit: done"; changed=1
    else warn "couldn't download Outfit (https://fonts.google.com/specimen/Outfit)"; fi

    [ $changed -eq 1 ] && [ $dry -eq 0 ] && fc-cache -f "$fonts_dir" >/dev/null
    return 0
}

# --- links -----------------------------------------------------------------

# Every top-level folder is a stow package, except system/ (build files and
# a udev rule, installed by --extras).
packages=()
for d in "$repo"/*/; do
    p=$(basename "$d")
    [ "$p" = system ] && continue
    packages+=("$p")
done

declare -A owned=() # paths already known to link into the repo

ours() { case "$(readlink -f "$1" 2>/dev/null)" in "$repo"/*) return 0 ;; esac; return 1; }

backup() { # path relative to $HOME
    if [ $dry -eq 1 ]; then info "would move ~/$1 to $backup_dir/"; return; fi
    mkdir -p "$backup_dir/$(dirname "$1")"
    mv "$HOME/$1" "$backup_dir/$1"
    info "moved ~/$1 to $backup_dir/"
}

# Make room for one file of a package: walk down its path in $HOME and move
# away whatever stow can't link over (a real file, a file where a folder
# belongs, or a link that points somewhere else).
clear_path() {
    local rel=$1 part="" seg t
    local -a segs
    IFS=/ read -ra segs <<<"$rel"
    for seg in "${segs[@]}"; do
        part=${part:+$part/}$seg
        [ -n "${owned[$part]:-}" ] && return 0
        t="$HOME/$part"
        if [ -L "$t" ]; then
            if ours "$t"; then owned[$part]=1; else backup "$part"; fi
            return 0
        fi
        [ -e "$t" ] || return 0
        if [ "$part" = "$rel" ] || [ ! -d "$t" ]; then
            backup "$part"
            return 0
        fi
    done
    return 0
}

link_package() {
    local pkg=$1 rel
    while IFS= read -r -d '' rel; do
        rel=${rel#./}
        case "$rel" in README* | LICENSE* | COPYING) continue ;; esac # stow ignores these
        clear_path "$rel"
    done < <(cd "$repo/$pkg" && find . \( -type f -o -type l \) -print0)

    if [ $dry -eq 1 ]; then
        info "would link $pkg"
    elif stow --dir="$repo" --target="$HOME" "$pkg" 2>"$tmp_err"; then
        info "$pkg"
    else
        warn "stow couldn't link $pkg: $(head -3 "$tmp_err" | tr '\n' ' ')"
    fi
}

link_all() {
    local pkg s skipped
    # These folders are shared with other programs: make them real folders,
    # or stow would link the whole folder into the repo and everything else
    # that writes there (uv, pipx, other icon themes...) would land in it.
    run mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/share/icons" "$HOME/.local/state"
    tmp_err=$(mktemp)
    for pkg in "${packages[@]}"; do
        skipped=0
        for s in "${skip[@]}"; do [ "$s" = "$pkg" ] && skipped=1; done
        if [ $skipped -eq 1 ]; then info "$pkg (skipped)"; continue; fi
        # git carries my name and signing key: never replace someone's own ~/.gitconfig with it
        if [ "$pkg" = git ] && [ -e "$HOME/.gitconfig" ] && ! ours "$HOME/.gitconfig"; then
            info "git (kept your own ~/.gitconfig)"
            continue
        fi
        link_package "$pkg"
    done
    rm -f "$tmp_err"
}

# --- after linking ---------------------------------------------------------

post_link() {
    # starship reads ~/.config/starship.toml; the repo has four prompt layouts
    if [ ! -e "$HOME/.config/starship.toml" ] && [ ! -L "$HOME/.config/starship.toml" ]; then
        run ln -s "$HOME/.config/starship/format-1.toml" "$HOME/.config/starship.toml"
        info "starship prompt: format-1"
    fi
    # tmux plugins (tmux.conf runs ~/.tmux/plugins/tpm/tpm); then prefix + I in tmux
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
        if run git clone -q --depth 1 https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"; then
            [ $dry -eq 1 ] || info "tmux plugin manager cloned (press prefix + I in tmux to install the plugins)"
        else
            warn "couldn't clone tpm"
        fi
    fi
}

# --- extras (--extras) -----------------------------------------------------

# Lets the wheel group switch the ACPI platform profile, so the overview's
# power-profile control works without root.
install_udev() {
    local rule=90-platform-profile.rules
    if [ ! -d /sys/class/platform-profile ] && [ ! -e /sys/firmware/acpi/platform_profile ]; then
        info "no ACPI platform profile on this machine, skipping the udev rule"
        return
    fi
    if cmp -s "$repo/system/udev/$rule" "/etc/udev/rules.d/$rule"; then info "udev rule: installed"; return; fi
    run sudo install -m644 "$repo/system/udev/$rule" /etc/udev/rules.d/ &&
        run sudo udevadm control --reload &&
        run sudo udevadm trigger -s platform-profile &&
        { [ $dry -eq 1 ] || info "udev rule installed"; } ||
        warn "couldn't install the udev rule"
}

# --- checks for this machine -----------------------------------------------

check_machine() {
    local gfx="$repo/hypr/.config/hypr/hypr.d/graphics.lua" devs d bad=""
    devs=$(sed -n 's/^hl.env("AQ_DRM_DEVICES", "\(.*\)")/\1/p' "$gfx")
    if [ -n "$devs" ]; then
        IFS=: read -ra list <<<"$devs"
        for d in "${list[@]}"; do [ -e "$d" ] || bad="$bad $d"; done
        [ -n "$bad" ] && warn "Hyprland is set to render on${bad}, which this machine doesn't have. Fix AQ_DRM_DEVICES in hypr/.config/hypr/hypr.d/graphics.lua (or delete the line) before logging in."
    fi
    has_nvidia || warn "no NVIDIA GPU here: remove __GLX_VENDOR_LIBRARY_NAME and NVD_BACKEND from hypr/.config/hypr/hypr.d/graphics.lua"
    grep -qs 0x1002 /sys/bus/pci/devices/*/vendor ||
        warn "no AMD GPU here: LIBVA_DRIVER_NAME=radeonsi in hypr/.config/hypr/hypr.d/graphics.lua is wrong for this machine (use iHD for Intel, nvidia for NVIDIA, or delete it)"
    [ "$(basename "${SHELL:-}")" = zsh ] || info "your login shell is ${SHELL:-unknown}; switch with: chsh -s /usr/bin/zsh"
    [ -e "$HOME/wallpapers" ] || info "no ~/wallpapers yet: the wallpaper picker (Super+C) reads its folders"
    return 0
}

# --- go --------------------------------------------------------------------

if [ $do_packages -eq 1 ]; then
    step "Packages"
    install_packages
    install_built
    install_appnap_mem
fi
if [ $do_fonts -eq 1 ]; then
    step "Fonts"
    if command -v fc-list >/dev/null; then install_fonts; else warn "fontconfig isn't installed, skipping fonts"; fi
fi

command -v stow >/dev/null || die "stow isn't installed (sudo pacman -S stow), can't link anything"
step "Linking into $HOME"
link_all
post_link

if [ $extras -eq 1 ]; then
    step "Extras"
    install_udev
fi

step "This machine"
check_machine

step "Done"
[ -d "$backup_dir" ] && info "files that were in the way: $backup_dir"
if [ ${#warnings[@]} -gt 0 ]; then
    info "${yel}${#warnings[@]} warning(s) above, worth a look.${off}"
fi
info "Log into Hyprland and astralis starts with it. Super+C picks a wallpaper and recolours everything."
