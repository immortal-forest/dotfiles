#!/bin/sh
# Matugen renders the colours directly into this helper. Foot does not reload
# foot.ini at runtime, but it supports xterm dynamic-colour OSC sequences.
# Send them only to terminals whose foreground process inherited TERM=foot.

emit_palette() {
    target=$1
    [ -w "$target" ] || return 0

    printf '\033]10;{{colors.on_background.default.hex}}\033\\' >"$target"
    printf '\033]11;{{colors.surface.default.hex}}\033\\' >"$target"
    printf '\033]12;{{colors.primary.default.hex}}\033\\' >"$target"
    printf '\033]17;{{colors.primary.default.hex}}\033\\' >"$target"
    printf '\033]19;{{colors.on_primary.default.hex}}\033\\' >"$target"

    printf '\033]4;0;{{colors.surface.default.hex}}\033\\' >"$target"
    printf '\033]4;1;{{colors.ansi_red.default.hex}}\033\\' >"$target"
    printf '\033]4;2;{{colors.ansi_green.default.hex}}\033\\' >"$target"
    printf '\033]4;3;{{colors.ansi_yellow.default.hex}}\033\\' >"$target"
    printf '\033]4;4;{{colors.ansi_blue.default.hex}}\033\\' >"$target"
    printf '\033]4;5;{{colors.ansi_magenta.default.hex}}\033\\' >"$target"
    printf '\033]4;6;{{colors.ansi_cyan.default.hex}}\033\\' >"$target"
    printf '\033]4;7;{{colors.on_surface.default.hex}}\033\\' >"$target"
    printf '\033]4;8;{{colors.outline.default.hex}}\033\\' >"$target"
    printf '\033]4;9;{{colors.ansi_red_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;10;{{colors.ansi_green_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;11;{{colors.ansi_yellow_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;12;{{colors.ansi_blue_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;13;{{colors.ansi_magenta_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;14;{{colors.ansi_cyan_bright.default.hex}}\033\\' >"$target"
    printf '\033]4;15;{{colors.on_background.default.hex}}\033\\' >"$target"
}

seen=' '
for process in /proc/[0-9]*; do
    [ -r "$process/environ" ] || continue
    tr '\000' '\n' <"$process/environ" 2>/dev/null | grep -qx 'TERM=foot' || continue
    target=$(readlink "$process/fd/1" 2>/dev/null || true)
    case "$target" in
        /dev/pts/*)
            case "$seen" in
                *" $target "*) ;;
                *)
                    emit_palette "$target"
                    seen="$seen$target "
                    ;;
            esac
            ;;
    esac
done
