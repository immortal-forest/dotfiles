#! /usr/bin/python3

import os
import sys
from itertools import batched


WALL_DIR = f"{os.environ['HOME']}/wallpapers"


def print_help(x):
    h = """\nUse cases
    \tswww.py w n/p (next/previous wallpaper)
    \tswww.py t n/p (next/previous theme)
    \tswww.py t <theme name> (select a specific theme)\n"""
    print(h.strip())
    exit(x)


def themes():
    t = [th for th in os.listdir(WALL_DIR) if os.path.isdir(f"{WALL_DIR}/{th}")]
    t.sort()
    return t


def wallpapers(theme: str):
    w = [wal for wal in os.listdir(f"{WALL_DIR}/{theme}")]
    w.sort()
    return w


def load_conf():
    with open(f"{WALL_DIR}/wall.conf", "r") as file:
        data = [i.strip().split("=") for i in file.readlines()]
    return {k: v for k, v in data}


def write_conf(conf: dict):
    with open(f"{WALL_DIR}/wall.conf", "w") as file:
        config = "\n".join([f"{k}={v}" for k, v in conf.items()])
        file.write(config)


def main(args: list[str]):
    if args[0] == "-th" or args[0] == "--themes":
        for theme in batched(themes(), 3):
            try:
                print("{:<25}{:<25}{:<25}".format(*theme))
            except Exception as _:
                pass
        return
    config = load_conf()
    _wallpapers = wallpapers(config["Theme"])
    _themes = themes()

    wall_index = None
    theme_index = None
    direction = "n"

    if len(args) == 2:
        opt = args[0]
        ac = args[1]
        if opt == "w":
            if ac == "n":
                wall_index = _wallpapers.index(config["wallpaper"]) + 1
            elif ac == "p":
                wall_index = _wallpapers.index(config["wallpaper"]) - 1
                direction = "p"
            elif os.path.isfile(f"{WALL_DIR}/{config['Theme']}/{ac}"):
                wall_index = _wallpapers.index(ac)
            else:
                print_help(1)

        elif opt == "t":
            if ac == "n":
                theme_index = _themes.index(config["Theme"]) + 1
            elif ac == "p":
                theme_index = _themes.index(config["Theme"]) - 1
                direction = "p"
            else:
                print_help(1)
        else:
            print_help(1)
    elif len(args) > 2:
        opt = args[0]
        ac = " ".join(args[1:])
        if opt == "t":
            if ac in _themes:
                theme_index = _themes.index(ac)
                wall_index = 0
        else:
            print_help(1)
    else:
        print_help(1)

    if theme_index is not None:
        if theme_index >= len(_themes):
            theme_index = 0

        theme_name = _themes[theme_index]
        wall_name = wallpapers(theme_name)[0]

    elif wall_index is not None:
        if wall_index >= len(_wallpapers):
            wall_index = 0
        theme_name = config["Theme"]
        wall_name = _wallpapers[wall_index]
    else:
        print_help(1)

    wall_set = f"{WALL_DIR}/{theme_name}/{wall_name}"
    os.system(f'swwwchange.sh "{wall_set}" {direction} r')
    write_conf(dict(Theme=theme_name, wallpaper=wall_name))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception as e:
        pass
