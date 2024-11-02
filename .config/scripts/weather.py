#!/usr/bin/env python

import json

import requests

WEATHER_CODES = {
    "113": "☀️ ",
    "116": "⛅ ",
    "119": "☁️ ",
    "122": "☁️ ",
    "143": "☁️ ",
    "176": "🌧️",
    "179": "🌧️",
    "182": "🌧️",
    "185": "🌧️",
    "200": "⛈️ ",
    "227": "🌨️",
    "230": "🌨️",
    "248": "☁️ ",
    "260": "☁️ ",
    "263": "🌧️",
    "266": "🌧️",
    "281": "🌧️",
    "284": "🌧️",
    "293": "🌧️",
    "296": "🌧️",
    "299": "🌧️",
    "302": "🌧️",
    "305": "🌧️",
    "308": "🌧️",
    "311": "🌧️",
    "314": "🌧️",
    "317": "🌧️",
    "320": "🌨️",
    "323": "🌨️",
    "326": "🌨️",
    "329": "❄️ ",
    "332": "❄️ ",
    "335": "❄️ ",
    "338": "❄️ ",
    "350": "🌧️",
    "353": "🌧️",
    "356": "🌧️",
    "359": "🌧️",
    "362": "🌧️",
    "365": "🌧️",
    "368": "🌧️",
    "371": "❄️",
    "374": "🌨️",
    "377": "🌨️",
    "386": "🌨️",
    "389": "🌨️",
    "392": "🌧️",
    "395": "❄️ ",
}

data = {}


def degToSym(num):
    val = int((float(num) / 22.5) + 0.5)
    arr = [
        "N",
        "NNE",
        "NE",
        "ENE",
        "E",
        "ESE",
        "SE",
        "SSE",
        "S",
        "SSW",
        "SW",
        "WSW",
        "W",
        "WNW",
        "NW",
        "NNW",
    ]
    return arr[(val % 16)]


weather = requests.get("https://wttr.in/?format=j1").json()

tempint = int(weather["current_condition"][0]["FeelsLikeC"])

data["text"] = (
    " "
    + WEATHER_CODES[weather["current_condition"][0]["weatherCode"]]
    + " "
    + weather["current_condition"][0]["FeelsLikeC"]
    + "°"
    + " | "
    + weather["nearest_area"][0]["areaName"][0]["value"]
    + " "
)

data["tooltip"] = (
    f"<b>{weather['current_condition'][0]['weatherDesc'][0]['value']}   {weather['current_condition'][0]['temp_C']}°C</b>\n"
)
data["tooltip"] += f"Feels like: {weather['current_condition'][0]['FeelsLikeC']}°C\n"
data["tooltip"] += f"Location: {weather['nearest_area'][0]['areaName'][0]['value']}\n"
data["tooltip"] += (
    f"Wind: {weather['current_condition'][0]['windspeedKmph']}Km/h {degToSym(weather['current_condition'][0]['winddirDegree'])}\n"
)
data["tooltip"] += f"Humidity: {weather['current_condition'][0]['humidity']}%\n"
data["tooltip"] += f"Visibility: {weather['current_condition'][0]['visibility']}Km"


print(json.dumps(data))
