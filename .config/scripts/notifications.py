#!/usr/bin/python3

import subprocess
import json
import sys
import re


CLEAN = re.compile("<.*?>|&([a-z0-9]+|#[0-9]{1,6}|#x[0-9a-f]{1,6});")


def get_dunst_history():
    result = subprocess.run(["dunstctl", "history"], stdout=subprocess.PIPE)
    history = json.loads(result.stdout.decode("utf-8"))
    return history


def format_history(history):
    count = len(history["data"][0])
    tooltip_click = []
    tooltip_click.append("󰎟 Notifications")
    tooltip_click.append("󰳽 click-left:  history pop")
    tooltip_click.append("󰳽 click-middle: 󰛌 clear history")
    tooltip_click.append("󰳽 click-right: 󱄊 close all")

    tooltip = []

    if count == 0:
        text = f"󰂚 {count}"
        tooltip_text = "\n".join(tooltip_click)
    else:
        text = f"󱅫 {count}"
        for notification in history["data"][0]:
            body = notification.get("message", {}).get("data", "")
            if body != "":
                body = re.sub(CLEAN, "", body.strip().replace("\n", " "))
                tooltip.append(body)
                break
        tooltip_text = "\n".join(tooltip_click) + "\n\n " + "\n".join(tooltip)

    if count == 20:
        text += "+"

    history = {
        "text": f"{text}",
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
