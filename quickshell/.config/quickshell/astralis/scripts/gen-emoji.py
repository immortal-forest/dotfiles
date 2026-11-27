#!/usr/bin/env python3
# astralis — regenerate pill/lib/emoji.js (the launcher's ":" emoji search).
# Names, tags and shortcodes come from emojibase-data (MIT); the SLANG block
# below adds what people actually type ("dead" → 💀, "no cap" → 🧢).
# Usage: scripts/gen-emoji.py   (downloads emojibase into /tmp on first run)
import json, os, re, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "pill", "lib", "emoji.js")
CACHE = "/tmp/astralis-emojibase"
BASE = "https://cdn.jsdelivr.net/npm/emojibase-data@latest/en/"

# One emoji per line, then comma-separated words / phrases.
SLANG = """
😂 lol, laugh, laughing, lmao, lmfao, haha, hahaha, crying laughing, dying, kekw
🤣 rofl, lmao, lmfao, dying, hilarious, haha, kekw
😭 crying, sobbing, bawling, i cant, im crying, lol, lmao, help, so real, emotional, pls, begging, fr
💀 dead, im dead, deceased, ded, dying, lmao, lol, i cant, bruh, deadass, unalive, cooked, l
☠️ dead, deceased, rip, danger, toxic, pirate
🥀 sad, heartbroken, broken, wilted, emo, pain, its over
🔥 lit, fire, hot, slaps, banger, heat, goes hard, gas, hype, bussin, ate, w
🧢 cap, no cap, lying, liar, fake, capping
🐐 goat, legend, the goat, goated, greatest of all time
💅 slay, slayed, sassy, unbothered, iconic, period, periodt, queen, mother, ate, its giving, main character, idc
👑 king, queen, slay, royalty, mother, boss, winner, w, ate
🗿 bruh, moai, deadpan, chad, sigma, based, aura, unfazed, gigachad, stoic
🤡 clown, clowning, fool, joke, circus, goofy, delulu, l
🫠 melting, overwhelmed, dying inside, its fine, exhausted, brainrot
🥺 pleading, puppy eyes, pls, please, uwu, begging, aww, soft, simp
👀 eyes, looking, watching, drama, sus, side eye, interesting, lowkey, pov, chat is this real
🍵 tea, spill the tea, gossip, sipping tea, none of my business
🤨 sus, suspicious, sussy, raised eyebrow, the rock, doubt, skeptical, hmm, huh, chat is this real
📮 sus, amogus, among us, impostor, imposter, crewmate
😳 flushed, embarrassed, shocked, blushing, oh no, awkward, caught, omg, shy, gyatt, sheesh
🙏 please, thanks, thank you, pray, praying, bless, blessed, begging, hope, namaste, ty, ong, on god, hopium
💯 100, facts, keep it 100, real, perfect, agreed, legit, true, fr, for real, ong, on god, tbh, deadass, based, w
✨ sparkles, aesthetic, vibe, vibes, magic, glitter, shiny, aura, main character, its giving, delulu
🫡 salute, respect, o7, yes sir, on it, understood, roger, f in chat
🤝 deal, handshake, respect, agreement, bet, we good, gg
🫶 heart hands, ily, love you, support, appreciate, simp
🤌 chefs kiss, italian, perfection, what do you mean, mamma mia
👌 ok, okay, perfect, chefs kiss, nice, good, fine
🤯 mind blown, mindblown, shocked, omg, wow, no way
🙃 upside down, sarcasm, sarcastic, irony, its fine, whatever, passive aggressive
😬 yikes, big yikes, awkward, cringe, eek, oops, nervous, uh oh, oof
🤓 nerd, um actually, akshually, actually, geek, smart
🤪 crazy, goofy, silly, zany, unhinged, derp, goofy ahh
😏 smirk, smug, flirty, flirt, sly, rizz, ayo, wink wink
🥵 hot, sweating, thirsty, spicy, horny, heatwave
🥶 cold, freezing, ice cold, cold blooded, frozen, sheesh, brrr
🧠 big brain, galaxy brain, smart, genius, 200 iq, brainrot
🤑 money, rich, bag, cash, paid, greedy
💸 money, broke, spending, cash, expensive, bills
📈 stonks, gains, up, growth, trending, to the moon
📉 not stonks, losses, down, crash, ratio, l
🚩 red flag, warning, toxic, ick
✅ done, check, yes, correct, approved, complete, green flag
🤷 shrug, idk, whatever, dunno, i dont know, meh, oh well, idc, situationship, mid
🤦 facepalm, smh, bruh, ugh, seriously, why
😩 weary, ugh, tired, exhausted, frustrated, fml
😮‍💨 exhale, sigh, relief, phew, finally, vape
❤️‍🔥 heart on fire, passion, burning love, obsessed
❤️ love, heart, ily, love you, romance
💔 heartbroken, heartbreak, sad, breakup, its over, situationship
🫂 hug, hugs, support, comfort, sending love
🤗 hug, hugging, warm, welcome, aww, jazz hands
🙄 eye roll, whatever, ugh, annoyed, sure jan, ok boomer
😒 unamused, meh, not impressed, side eye, annoyed, shade
😑 deadpan, unimpressed, done, speechless, seriously
😐 meh, neutral, blank, no reaction, npc, mid
🫥 invisible, ignored, ghosted, introvert
🤐 secret, zip it, shut up, no comment
🤫 shh, shush, quiet, secret, hush, lowkey
😇 innocent, angel, wasnt me, saint
🙈 oops, embarrassed, cant look, shy, cringe, hiding
🫣 peeking, scared, cant watch, embarrassed, shy
😈 devil, evil, mischievous, naughty, horny, up to no good
👻 ghost, ghosting, ghosted, boo, spooky
😵‍💫 dizzy, confused, hypnotized, overwhelmed, dazed, delulu
😶‍🌫️ brain fog, spaced out, in the clouds, confused, daydreaming
🥴 woozy, drunk, tipsy, dizzy, high, goofy
😴 sleeping, sleepy, zzz, bored, tired, nap, gn, goodnight
🥱 yawn, boring, bored, tired, ez
😌 relieved, content, peaceful, calm, chill, mood, vibing, unbothered
😎 cool, deal with it, swag, chill, boss, confident, based, rizz, ez
🤠 cowboy, yeehaw, howdy
🥳 party, celebrate, birthday, yay, woohoo, congrats, hbd
🎉 party, congrats, congratulations, tada, celebrate, yay, hooray, hbd
🧐 hmm, inspecting, monocle, fancy, investigating
🤔 thinking, hmm, wonder, pondering, hmmm
😤 huffing, determined, mad, frustrated, proud, lets go, copium
😡 angry, mad, rage, furious, pissed, livid, triggered
🤬 swearing, cursing, angry, rage, wtf, swear, pissed
🖕 middle finger, fuck you, screw you, flip off
💩 poop, shit, crap, trash
🤮 vomit, puke, gross, disgusting, ew, eww, barf, cringe, ick
🤢 nauseated, gross, ew, eww, disgusting, cringe, yuck, ick
🍿 popcorn, drama, watching, grab popcorn
🥹 holding back tears, touched, aww, emotional, grateful, proud, soft
🥲 its fine, bittersweet, pain, smiling through pain, coping, copium
😅 nervous laugh, oops, sweat, phew, awkward, haha, close one
😆 xd, haha, funny, hehe
😁 grin, cheesy, happy, excited, hehe
😊 happy, blush, smile, cute, content, glad, uwu
🙂 smile, fine, polite, passive aggressive, nice
😀 happy, smile, grin, glad
😄 happy, haha, smile, glad
😍 heart eyes, in love, obsessed, crush, gorgeous, simp, stan
🤩 star struck, excited, amazing, wow, fan, omg, pog
🥰 in love, adore, cute, aww, crush, wholesome
😘 kiss, mwah, xoxo, muah, flirt
💋 kiss, mwah, lips, xoxo
🫦 biting lip, flirty, rizz, seductive, nervous, thirsty
😜 wink, silly, joking, kidding, jk, playful, cheeky
😉 wink, flirt, joking, jk, wink wink, kidding
😋 yum, delicious, tasty, yummy, hungry, bussin
🤤 drooling, yum, want, hungry, thirsty, bussin
😢 sad, cry, tear, upset, hurt, sadge
😔 sad, pensive, down, disappointed, sorry, regret, sadge
😰 anxious, nervous, worried, scared, stressed, monkas
😱 scream, shocked, scared, omg, horror, terrified, no way, wtf
😮 wow, shocked, surprised, gasp, omg, pog
😲 shocked, astonished, wow, omg, gasp, pog
🫢 gasp, oops, shocked, omg, no way
🤭 giggle, oops, tee hee, hehe
🫨 shaking, shook, shocked, anxious
🙂‍↕️ nod, nodding, yes, agree, yep
🙂‍↔️ shake head, no, nope, disagree, nah
😺 cat, uwu
😹 lol, lmao, cat laughing, haha
💪 strong, flex, gains, gym, muscle, workout, you got this, lets go
🏆 win, winner, champion, w, victory, goat, gg
🥇 first, winner, number one, w
🎯 on point, bullseye, spot on, focus, nailed it
⚡ zap, fast, energy, power, speed, quick
🌚 creepy, smug, shady, shade, side eye, sus
🐍 snake, traitor, sneaky, fake, python
🐀 rat, snitch, traitor
🐸 frog, pepe, kermit, sipping tea, none of my business
🦀 crab, rust, crab rave, rustacean
🐧 penguin, linux, tux, arch
🦊 fox, firefox, sly
🐛 bug, debug, issue
🚀 rocket, ship it, launch, to the moon, deploy, blast off, lfg, lets go, yeet
🗣️ yapping, yap, talking, loud, screaming, shouting, preach, say it louder, highkey
🔒 locked in, lock in, focused, private
🙌 hands up, praise, yay, hallelujah, finally, lets go, diamond hands
👏 clap, applause, bravo, well done, congrats, preach
🤘 rock on, metal, rock, horns
✌️ peace, peace out, bye, two
👋 wave, hi, hello, bye, goodbye, hey, yo, bye felicia
🤙 call me, shaka, hang loose, chill
🫵 you, pointing at you, your turn
👍 ok, okay, yes, like, good, agree, nice, bet, sure, k, boomer
👎 no, dislike, bad, disagree, nope, boo
👊 fist bump, bro, respect, pound
🤞 fingers crossed, hopefully, good luck, hope, hopium
🫰 finger heart, korean heart, money
🥂 cheers, toast, celebrate, champagne
🍻 cheers, beers, drinks
☕ coffee, caffeine, morning, gm
💤 sleep, zzz, tired, bored, nap, gn
🍆 eggplant, aubergine
🍑 peach, booty, butt, ass, thicc, gyatt
💦 sweat, splash, water, wet, thirsty
🌈 rainbow, pride, gay, lgbt, lgbtq, queer, delulu
🏳️‍🌈 pride, gay, lgbt, lgbtq, queer
🏳️‍⚧️ trans, transgender, trans pride
🖤 emo, goth, dark, edgy
💜 bts, army
💕 hearts, cute, xoxo
💎 diamond hands, gem, rare, precious, hodl
🙅 no, nope, stop, nah
🧘 chill, zen, calm, meditate, inner peace
🎶 music, song, vibe, vibing, tunes, bop, slaps
🎧 music, listening, vibing
🎮 gaming, gamer, games, gg
💻 laptop, coding, work, wfh, programming
🤖 robot, bot, ai, beep boop, npc
🧍 standing, awkward, npc
👽 alien, weird
🌙 night, goodnight, gn
🌞 good morning, gm, sunny
🧂 salty, bitter, jealous
🌶️ spicy, hot, saucy
🧊 ice cold, chill, cool
🌱 touch grass, growth, plant
🪦 rip, dead, grave, rest in peace, its over
⚰️ dead, rip, funeral, unalive
🍳 cooking, cook, let him cook, cooked
🧑‍🍳 chef, cooking, let him cook, cooked
🥜 nuts, deez nuts
🦍 monke, apes together strong
🐒 monke
🙊 oops, said too much
🦆 rubber duck, quack, debugging
🐢 slow, lag, laggy
⏳ waiting, loading, patience, soon
📌 pin, pinned, important
📝 notes, todo, homework
📢 announcement, psa, attention, loud, highkey
💬 chat, message, dm, text
⚠️ warning, caution, careful, danger, tw, cw
❌ no, wrong, cancel, nope, delete, fail, l
🚫 no, banned, forbidden, not allowed
❓ question, what, huh
⁉️ what, wtf
😕 confused, unsure, meh, hmm
🫤 meh, unsure, skeptical, hmm, mid
😫 tired, exhausted, ugh, fed up
🤒 sick, ill, fever
🤧 sick, sneeze, flu, allergies
🥸 disguise, incognito, undercover
🤥 liar, lying
😶 speechless, no words, silent
🙁 sad, frown, unhappy
😠 angry, mad, annoyed, grumpy
💢 anger, mad, annoyed
🧌 troll, trolling
💁 sassy, hair flip, here you go, whatever
🙇 sorry, bow, apology, grateful
🏃 run, running, gotta go, brb, escape
💨 fast, dash, gone, zoom, poof, yeet
🗑️ trash, garbage, delete
🌹 rose, romantic, for you
💐 flowers, bouquet, for you, sorry
🍀 luck, lucky, good luck
⭐ star, favourite, favorite, gold star
🔄 repeat, again, refresh, retry
📸 photo, pic, selfie, snap
🎤 mic drop, sing, karaoke
🎨 art, creative, design, draw
📚 books, study, studying, homework
🧑‍💻 coder, developer, programmer, hacker, coding
🦋 butterflies, nervous, pretty
🎀 bow, cute, coquette, girly
🛐 worship, stan
🚽 toilet, skibidi
"""


def fetch(name):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, name.replace("/", "_"))
    if not os.path.exists(path):
        urllib.request.urlretrieve(BASE + name, path)
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def words(s):
    """Lowercase, apostrophes dropped, everything else not a-z0-9 becomes a space."""
    return " ".join(re.sub(r"[^a-z0-9+]+", " ", s.lower().replace("’", "").replace("'", "")).split())


def bare(g):
    return g.replace("️", "")


slang = {}
for line in SLANG.strip().splitlines():
    glyph, _, rest = line.strip().partition(" ")
    slang[bare(glyph)] = [words(p) for p in rest.split(",") if p.strip()]

data = fetch("data.json")
codes = {}
for src in ("shortcodes/github.json", "shortcodes/iamcal.json", "shortcodes/emojibase.json"):
    for hexcode, c in fetch(src).items():
        for one in ([c] if isinstance(c, str) else c):
            codes.setdefault(hexcode, []).append(words(one.replace("_", " ")))

out, used = [], set()
for e in sorted(data, key=lambda e: e.get("order", 1 << 30)):
    if e.get("group") in (None, 2):   # regional-indicator letters, skin/hair components
        continue
    label = e["label"].lower()
    s = slang.get(bare(e["emoji"]), [])
    used.add(bare(e["emoji"]))
    tags = [words(t) for t in e.get("tags", [])] + codes.get(e["hexcode"], [])
    tags = [t for t in dict.fromkeys(tags) if t and t not in s and t != words(label)]
    out.append([e["emoji"], label, ",".join(s), ",".join(tags)])

missing = set(slang) - used
if missing:
    raise SystemExit("SLANG has emoji emojibase doesn't: " + " ".join(sorted(missing)))

with open(OUT, "w", encoding="utf-8") as f:
    f.write(""".pragma library

// GENERATED by scripts/gen-emoji.py — edit the SLANG block there, not this file.
// Every emoji (Emoji 17, flags and ZWJ sequences included; no skin tones) as
// [glyph, name, slang phrases, tags + shortcodes], phrases comma-separated.
// Names/tags/shortcodes: emojibase-data (MIT). Used by the launcher's ":" mode.
var list = """)
    f.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    f.write(""";

for (var i = 0; i < list.length; i++) {
    list[i][2] = list[i][2] ? list[i][2].split(",") : [];
    list[i][3] = list[i][3] ? list[i][3].split(",") : [];
}

/** How well query word `w` matches phrase list `ps`: 3 whole word, 2 word prefix, 1 stem (smile → smiling), 0 none. */
function hit(w, ps) {
    var best = 0, stem = w.length > 3 ? w.replace(/(ing|es|e|s)$/, "") : "";
    for (var i = 0; i < ps.length && best < 3; i++) {
        var p = " " + ps[i] + " ";
        if (p.indexOf(" " + w + " ") >= 0) best = 3;
        else if (best < 2 && p.indexOf(" " + w) >= 0) best = 2;
        else if (best < 1 && stem.length > 2 && p.indexOf(" " + stem) >= 0) best = 1;
    }
    return best;
}

/**
 * Up to `limit` [glyph, name] pairs for `q`. Every word must hit the name, a
 * slang phrase or a tag; slang counts most, tags least, and a query that IS a
 * whole phrase ("no cap", "spill the tea") jumps ahead. Ties go to the emoji
 * you copy most (`usage`: {"emoji:<glyph>": count}), then the standard order.
 * An empty query lists your most-used emoji.
 */
function search(q, limit, usage) {
    usage = usage || {};
    var key = String(q).toLowerCase().replace(/['’]/g, "").replace(/[^a-z0-9+]+/g, " ").trim();
    var ws = key.length ? key.split(" ") : [];
    var hits = [];
    for (var i = 0; i < list.length; i++) {
        var e = list[i], score = 0, uses = usage["emoji:" + e[0]] || 0;
        if (ws.length === 0) {
            if (uses > 0) hits.push([uses, i, e]);
            continue;
        }
        var name = [e[1].replace(/['’]/g, "").replace(/[^a-z0-9+]+/g, " ")];
        for (var j = 0; j < ws.length && score >= 0; j++) {
            var h = Math.max(hit(ws[j], name), hit(ws[j], e[2]) * 1.2, hit(ws[j], e[3]) * 0.8);
            score = h > 0 ? score + h : -1;
        }
        if (score < 0) continue;
        if (e[2].indexOf(key) >= 0 || name[0] === key) score += 10;
        hits.push([score + Math.min(2, uses * 0.25), i, e]);
    }
    hits.sort(function (a, b) { return b[0] - a[0] || a[1] - b[1]; });
    var res = [];
    for (var k = 0; k < hits.length && k < limit; k++)
        res.push([hits[k][2][0], hits[k][2][1]]);
    return res;
}
""")
print(f"wrote {len(out)} emoji, {len(slang)} with slang → {os.path.normpath(OUT)}")
