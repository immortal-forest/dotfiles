#!/usr/bin/python3

import os
import sys


with open(f"{os.environ['HOME']}/.cache/wal/colors") as file:
    colors = file.read().split("\n")


args = sys.argv[1:][0]

svg = f"""
<svg viewBox="-25 -25 250 250" version="1.1" xmlns="http://www.w3.org/2000/svg"><circle r="90" cx="100" cy="100" stroke="{colors[0]}" stroke-width="16px" stroke-linecap="round" stroke-dashoffset="0px" fill="{colors[0]}" stroke-dasharray="565.48px"></circle><circle r="90" cx="100" cy="100" fill="transparent" stroke="{colors[1]}" stroke-width="30px" stroke-linecap="round" stroke-dasharray="565.48px" stroke-dashoffset="{args}px"></circle></svg>
"""

with open(f"{os.environ['HOME']}/.config/waybar/progress.svg", "w") as file:
    file.write(svg.format(value=args))
