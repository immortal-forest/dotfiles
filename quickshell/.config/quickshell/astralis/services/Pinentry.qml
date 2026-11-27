pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * astralis — GnuPG's pinentry, in the pill.
 *
 * gpg-agent runs `pinentry-program` (~/.local/bin/pinentry-astralis, from
 * scripts/.local/bin). That script speaks Assuan to gpg-agent and, for each
 * GETPIN / CONFIRM / MESSAGE, calls `ipc call pinentry ask <json>` here with
 * the request and the path of a unix socket it is listening on (inside a
 * 0700 dir in $XDG_RUNTIME_DIR). The pill opens the 認/鍵 auth surface
 * (pill/surfaces/Auth.qml); the answer goes back down that socket as one
 * line — `PIN <assuan-escaped>`, `OK`, `NOTOK` or `CANCEL` — and the socket
 * closes. The passphrase is never put on a command line, in a file, or in
 * the log.
 *
 * The socket is connected for the whole request, so if gpg-agent kills the
 * pinentry (its own timeout, the user hit Ctrl-C on gpg) the disconnect
 * clears the prompt here too.
 *
 * Force-loaded from shell.qml (singletons are lazy, and an unloaded
 * IpcHandler is no target at all). If the shell is locked or already asking
 * something, `ask` says so and the script falls back to pinentry-qt.
 */
Singleton {
    id: root

    /** A request is waiting for the user. */
    property bool active: false
    /** "pin" (a passphrase), "confirm" (OK / Cancel [/ Not OK]) or "message" (OK). */
    property string mode: "pin"
    property string title: ""
    property string desc: ""
    property string prompt: ""
    property string error: ""
    property string okLabel: ""
    property string cancelLabel: ""
    property string notOkLabel: ""
    /** SETREPEAT: ask twice; the prompt for the second entry and the mismatch text. */
    property bool repeat: false
    property string repeatPrompt: ""
    property string repeatError: ""
    /** Bumped per request, so the surface can reset itself. */
    property int serial: 0

    /** Set by shell.qml: the pill is hidden under the lock, so a prompt there would stall. */
    property bool locked: false

    /**
     * True for a moment after a passphrase is sent. gpg-agent checks it after
     * the pinentry has exited and, if it was wrong, starts a NEW pinentry
     * with SETERROR — so the surface holds open (showing "checking") instead
     * of collapsing and re-growing between the two.
     */
    property bool lingering: false
    Timer {
        id: linger
        interval: 1100
        onTriggered: {
            root.lingering = false;
            if (!root.active) {
                root.desc = "";
                root.error = "";
            }
        }
    }

    function clear() {
        root.active = false;
        root.desc = "";
        root.error = "";
        if (sock.connected)
            sock.connected = false;
    }

    function reply(line) {
        if (!root.active)
            return;
        sock.write(line + "\n");
        sock.flush();
        root.active = false;
        // Let the write leave before hanging up; the script treats EOF without a line as cancel.
        hangup.restart();
    }

    /** Assuan data escaping: %, CR and LF are the only bytes that must be quoted. */
    function submit(pin) {
        const esc = String(pin).replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A");
        root.reply("PIN " + esc);
        root.lingering = true;
        linger.restart();
    }
    function confirm() { root.reply("OK"); }
    function notOk() { root.reply("NOTOK"); }
    function cancel() { root.reply("CANCEL"); }

    Timer {
        id: hangup
        interval: 150
        // Only hang up: the request's text stays on screen while gpg-agent
        // checks the answer (`lingering`) and is replaced by the next ask.
        onTriggered: if (!root.active)
            sock.connected = false;
    }

    Socket {
        id: sock
        // The script owns the socket; if it goes away mid-request, so does the prompt.
        onConnectedChanged: if (!connected && root.active) {
            root.active = false;
            root.desc = "";
            root.error = "";
        }
        // The script hanging up after its answer is the normal end (PeerClosed);
        // only an error mid-request means the prompt has nobody to answer.
        onError: err => {
            if (root.active) {
                console.warn("Pinentry: socket error mid-request", err);
                root.active = false;
                root.desc = "";
            }
        }
    }

    /** One request from pinentry-astralis. Returns "ok", or why it can't be shown here. */
    function ask(json) {
        if (root.locked)
            return "locked";
        if (root.active)
            return "busy";
        // (a retry after a wrong passphrase lands here while `lingering`)
        let r;
        try {
            r = JSON.parse(json);
        } catch (e) {
            return "bad-request";
        }
        if (!r.sock || String(r.sock).length === 0)
            return "bad-request";
        if (sock.connected)
            sock.connected = false;
        root.mode = r.mode === "confirm" || r.mode === "message" ? r.mode : "pin";
        root.title = String(r.title || "");
        root.desc = String(r.desc || "");
        root.prompt = String(r.prompt || "");
        root.error = String(r.error || "");
        root.okLabel = String(r.ok || "");
        root.cancelLabel = String(r.cancel || "");
        root.notOkLabel = String(r.notok || "");
        root.repeat = !!r.repeat;
        root.repeatPrompt = String(r.repeatPrompt || "");
        root.repeatError = String(r.repeatError || "");
        sock.path = String(r.sock);
        sock.connected = true;
        root.serial++;
        linger.stop();
        root.lingering = false;
        root.active = true;
        return "ok";
    }

    /** For the script's startup probe: is a shell here that can take a prompt. */
    function ready() {
        return root.locked ? "locked" : (root.active ? "busy" : "ok");
    }

    IpcHandler {
        target: "pinentry"
        function ask(json: string): string { return root.ask(json); }
        function ready(): string { return root.ready(); }
    }
}
