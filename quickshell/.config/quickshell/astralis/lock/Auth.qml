import QtQuick
import Quickshell.Services.Pam

/**
 * astralis — the lockscreen's PAM gate (ported from Ricelin lock/Auth.qml).
 * One in-flight authentication at a time: submit(password) stashes the
 * password, starts the "login" PAM stack, and answers its single response
 * request with it. `lastError` carries any PAM error message (bad password,
 * faillock lockout text like "account locked due to failed logins", or a
 * backend failure) so the capsule can surface it verbatim.
 *
 * Fail-closed by design: only PamResult.Success emits `succeeded`; a PAM
 * error (missing config, dead pam module, anything) lands in `failed` with
 * "auth unavailable" — it never silently accepts.
 */
Item {
    id: auth

    property string user: ""
    readonly property bool authenticating: pam.active

    signal failed
    signal succeeded

    property string pendingPassword: ""
    property string lastError: ""

    // Set while we are tearing down a stuck attempt so PamContext's own
    // onCompleted/onError (fired by abort()) does not emit a second `failed`.
    property bool aborting: false

    function submit(password) {
        if (pam.active)
            return;
        auth.lastError = "";
        auth.pendingPassword = password;
        auth.aborting = false;
        pam.start();
    }

    // Watchdog: a blocking/hung PAM module would otherwise leave the field
    // disabled forever (only a TTY or reboot recovers). If an attempt has not
    // completed in ~10s, abort it, wipe the password, and surface an error so
    // the capsule re-enables. Fail-closed: abort never grants access.
    Timer {
        id: watchdog
        interval: 10000
        repeat: false
        running: pam.active
        onTriggered: {
            auth.aborting = true;
            auth.pendingPassword = "";
            auth.lastError = "auth timed out";
            pam.abort();
            auth.failed();
        }
    }

    PamContext {
        id: pam
        config: "login"
        user: auth.user

        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(auth.pendingPassword);
                // Do not auto-replay on a subsequent prompt (e.g. 2FA / retry);
                // a fresh submit() must supply the next answer.
                auth.pendingPassword = "";
            }
        }

        onPamMessage: {
            if (messageIsError && message.length > 0)
                auth.lastError = message;
        }

        onCompleted: result => {
            auth.pendingPassword = "";
            if (auth.aborting) {
                auth.aborting = false;
                return;
            }
            if (result === PamResult.Success)
                auth.succeeded();
            else
                auth.failed();
        }

        onError: {
            auth.pendingPassword = "";
            if (auth.aborting) {
                auth.aborting = false;
                return;
            }
            if (auth.lastError.length === 0)
                auth.lastError = "auth unavailable";
            auth.failed();
        }
    }
}
