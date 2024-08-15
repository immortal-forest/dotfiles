#!/usr/bin/python3

import subprocess
import json
import sys
# import re


# CLEAN = re.compile("<.*?>|&([a-z0-9]+|#[0-9]{1,6}|#x[0-9a-f]{1,6});")


def get_dunst_history():
    result = subprocess.run(["dunstctl", "history"], stdout=subprocess.PIPE)
    history = json.loads(result.stdout.decode("utf-8"))
    return history


def format_history(history):
    count = len(history["data"][0])
    tooltip_click = []
    tooltip_click.append("󰎟 Notifications")
    tooltip_click.append("󰳽 scroll-down:  history pop")
    tooltip_click.append("󰳽 click-left:  Enable & Disable DND")
    tooltip_click.append("󰳽 click-middle: 󰛌 clear history")
    tooltip_click.append("󰳽 click-right: 󱄊 close all")

    tooltip = []

    if count == 0:
        notif_text = "󰂚 0"
        tooltip_text = "\n".join(tooltip_click)
    else:
        notif_text = f"󱅫 {count}"
        # show only 10 notifications in tooltip
        for notification in history["data"][0][:10]:
            body = notification.get("body", {}).get("data", "")
            app = notification.get("appname", {}).get("data", "")
            if app == "t2":
                app = ""
            if body != "":
                tooltip.append(f" {body}  {app}".strip())

        tooltip_text = "\n".join(tooltip_click) + "\n\n" + "\n".join(tooltip)

    if count == 20:
        notif_text += "+"

    # check if dnd
    isDND = subprocess.run(["dunstctl", "get-pause-level"], stdout=subprocess.PIPE)
    isDND = isDND.stdout.decode("utf-8").strip()
    if isDND != "0":
        notif_text = "󰂛" + notif_text[1:]

    history = {
        "text": notif_text,
        "tooltip": tooltip_text,
    }
    return history


def main():
    history = get_dunst_history()
    formatted_history = format_history(history)
    sys.stdout.write(json.dumps(formatted_history) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
