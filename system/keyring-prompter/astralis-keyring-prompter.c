/*
 * astralis-keyring-prompter: gnome-keyring's password prompts, drawn by the
 * astralis shell instead of gcr-prompter's GTK dialog.
 *
 * gnome-keyring asks for passwords over D-Bus, from whoever owns
 * org.gnome.keyring.SystemPrompter. This program owns that name and lets
 * libgcr's GcrSystemPrompter do the D-Bus side, including the encrypted
 * password handoff, so the protocol is exactly gcr's own. Each prompt it gets
 * is passed to ~/.local/bin/pinentry-astralis over Assuan, the same way
 * gpg-agent does, so it opens the pill's auth surface. When the shell can't
 * take it (not running, locked, already asking), pinentry-astralis hands it
 * to pinentry-qt.
 *
 * setup.sh compiles it to ~/.local/bin and adds a D-Bus service file in
 * ~/.local/share/dbus-1/services that points org.gnome.keyring.SystemPrompter
 * here, so the bus starts it on the first prompt. It quits after 30 s idle,
 * like gcr-prompter. If pinentry-astralis is missing it runs gcr-prompter.
 *
 *   gcc -O2 -Wall -o astralis-keyring-prompter astralis-keyring-prompter.c \
 *       $(pkg-config --cflags --libs gcr-base-3)
 */

#define GCR_API_SUBJECT_TO_CHANGE
#include <gcr/gcr-base.h>
#include <glib-unix.h>

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define QUIT_TIMEOUT 30
#define GCR_PROMPTER "/usr/lib/gcr-prompter"

static gchar *pinentry_path;

/* ── the prompt ──────────────────────────────────────────────────────── */

#define ASTRALIS_TYPE_PROMPT (astralis_prompt_get_type ())
G_DECLARE_FINAL_TYPE (AstralisPrompt, astralis_prompt, ASTRALIS, PROMPT, GObject)

struct _AstralisPrompt {
	GObject parent;
	gchar *title, *message, *description, *warning;
	gchar *choice_label, *caller_window, *continue_label, *cancel_label;
	gboolean password_new, choice_chosen;
	gint password_strength;
	gchar *password;  /* the last answer; wiped when replaced */
	GMutex lock;      /* guards child */
	GPid child;       /* the pinentry asking right now, 0 when none */
};

enum {
	PROP_0,
	PROP_TITLE,
	PROP_MESSAGE,
	PROP_DESCRIPTION,
	PROP_WARNING,
	PROP_PASSWORD_NEW,
	PROP_PASSWORD_STRENGTH,
	PROP_CHOICE_LABEL,
	PROP_CHOICE_CHOSEN,
	PROP_CALLER_WINDOW,
	PROP_CONTINUE_LABEL,
	PROP_CANCEL_LABEL,
};

static void astralis_prompt_iface_init (GcrPromptIface *iface);

G_DEFINE_TYPE_WITH_CODE (AstralisPrompt, astralis_prompt, G_TYPE_OBJECT,
                         G_IMPLEMENT_INTERFACE (GCR_TYPE_PROMPT, astralis_prompt_iface_init))

static void
wipe_free (gpointer p)
{
	if (p) {
		explicit_bzero (p, strlen (p));
		g_free (p);
	}
}

static void
astralis_prompt_init (AstralisPrompt *self)
{
	g_mutex_init (&self->lock);
}

static void
astralis_prompt_set_property (GObject *obj, guint id, const GValue *v, GParamSpec *pspec)
{
	AstralisPrompt *self = ASTRALIS_PROMPT (obj);
	gchar **str = NULL;

	switch (id) {
	case PROP_TITLE: str = &self->title; break;
	case PROP_MESSAGE: str = &self->message; break;
	case PROP_DESCRIPTION: str = &self->description; break;
	case PROP_WARNING: str = &self->warning; break;
	case PROP_CHOICE_LABEL: str = &self->choice_label; break;
	case PROP_CALLER_WINDOW: str = &self->caller_window; break;
	case PROP_CONTINUE_LABEL: str = &self->continue_label; break;
	case PROP_CANCEL_LABEL: str = &self->cancel_label; break;
	case PROP_PASSWORD_NEW: self->password_new = g_value_get_boolean (v); return;
	case PROP_CHOICE_CHOSEN: self->choice_chosen = g_value_get_boolean (v); return;
	default: G_OBJECT_WARN_INVALID_PROPERTY_ID (obj, id, pspec); return;
	}
	g_free (*str);
	*str = g_value_dup_string (v);
}

static void
astralis_prompt_get_property (GObject *obj, guint id, GValue *v, GParamSpec *pspec)
{
	AstralisPrompt *self = ASTRALIS_PROMPT (obj);

	switch (id) {
	case PROP_TITLE: g_value_set_string (v, self->title); break;
	case PROP_MESSAGE: g_value_set_string (v, self->message); break;
	case PROP_DESCRIPTION: g_value_set_string (v, self->description); break;
	case PROP_WARNING: g_value_set_string (v, self->warning); break;
	case PROP_CHOICE_LABEL: g_value_set_string (v, self->choice_label); break;
	case PROP_CALLER_WINDOW: g_value_set_string (v, self->caller_window); break;
	case PROP_CONTINUE_LABEL: g_value_set_string (v, self->continue_label); break;
	case PROP_CANCEL_LABEL: g_value_set_string (v, self->cancel_label); break;
	case PROP_PASSWORD_NEW: g_value_set_boolean (v, self->password_new); break;
	case PROP_CHOICE_CHOSEN: g_value_set_boolean (v, self->choice_chosen); break;
	case PROP_PASSWORD_STRENGTH: g_value_set_int (v, self->password_strength); break;
	default: G_OBJECT_WARN_INVALID_PROPERTY_ID (obj, id, pspec); break;
	}
}

static void
kill_child (AstralisPrompt *self)
{
	g_mutex_lock (&self->lock);
	if (self->child > 0)
		kill (self->child, SIGTERM);  /* pinentry-astralis clears the pill on SIGTERM */
	g_mutex_unlock (&self->lock);
}

static void
astralis_prompt_finalize (GObject *obj)
{
	AstralisPrompt *self = ASTRALIS_PROMPT (obj);

	kill_child (self);
	g_free (self->title);
	g_free (self->message);
	g_free (self->description);
	g_free (self->warning);
	g_free (self->choice_label);
	g_free (self->caller_window);
	g_free (self->continue_label);
	g_free (self->cancel_label);
	wipe_free (self->password);
	g_mutex_clear (&self->lock);
	G_OBJECT_CLASS (astralis_prompt_parent_class)->finalize (obj);
}

static void
astralis_prompt_class_init (AstralisPromptClass *klass)
{
	GObjectClass *oc = G_OBJECT_CLASS (klass);

	oc->set_property = astralis_prompt_set_property;
	oc->get_property = astralis_prompt_get_property;
	oc->finalize = astralis_prompt_finalize;

	g_object_class_override_property (oc, PROP_TITLE, "title");
	g_object_class_override_property (oc, PROP_MESSAGE, "message");
	g_object_class_override_property (oc, PROP_DESCRIPTION, "description");
	g_object_class_override_property (oc, PROP_WARNING, "warning");
	g_object_class_override_property (oc, PROP_PASSWORD_NEW, "password-new");
	g_object_class_override_property (oc, PROP_PASSWORD_STRENGTH, "password-strength");
	g_object_class_override_property (oc, PROP_CHOICE_LABEL, "choice-label");
	g_object_class_override_property (oc, PROP_CHOICE_CHOSEN, "choice-chosen");
	g_object_class_override_property (oc, PROP_CALLER_WINDOW, "caller-window");
	g_object_class_override_property (oc, PROP_CONTINUE_LABEL, "continue-label");
	g_object_class_override_property (oc, PROP_CANCEL_LABEL, "cancel-label");
}

/* ── Assuan, to pinentry-astralis ────────────────────────────────────── */

/* One request, copied out of the prompt so the worker thread owns it. */
typedef struct {
	gboolean confirm;
	gchar *title, *desc, *warning, *ok, *cancel;
	gboolean password_new;
} Request;

static void
request_free (gpointer data)
{
	Request *r = data;
	g_free (r->title);
	g_free (r->desc);
	g_free (r->warning);
	g_free (r->ok);
	g_free (r->cancel);
	g_free (r);
}

/*
 * %, CR, LF and other control bytes are percent-escaped in Assuan arguments.
 * A line may be at most 1000 bytes (pinentry-qt refuses longer ones), so long
 * text is cut, at the start of a character: the check leaves room for a
 * 4-byte UTF-8 character or a 3-byte escape plus the newline.
 */
#define ASSUAN_LINE_MAX 1000

static void
append_escaped (GString *s, const gchar *text)
{
	for (const guchar *p = (const guchar *) text; *p; p++) {
		if ((*p & 0xC0) != 0x80 && s->len + 5 > ASSUAN_LINE_MAX)
			break;
		if (*p == '%' || *p < 0x20)
			g_string_append_printf (s, "%%%02X", *p);
		else
			g_string_append_c (s, *p);
	}
}

static gint
hexval (gchar c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

/*
 * Read up to the response's OK or ERR. D lines are unescaped into `data` when
 * given. Returns 1 for OK, 0 for ERR, -1 if the pinentry went away.
 */
static gint
assuan_read (FILE *from, GString *data)
{
	/* Big enough for any Assuan line, so getline never moves a half-read
	 * password to a new buffer and leaves the old one unwiped. */
	gsize cap = 2048;
	gchar *line = malloc (cap);
	gssize n;
	gint result = -1;

	while ((n = getline (&line, &cap, from)) >= 0) {
		while (n > 0 && (line[n - 1] == '\n' || line[n - 1] == '\r'))
			line[--n] = '\0';
		if (g_str_has_prefix (line, "OK")) {
			result = 1;
			break;
		}
		if (g_str_has_prefix (line, "ERR")) {
			result = 0;
			break;
		}
		if (data && g_str_has_prefix (line, "D ")) {
			for (const gchar *p = line + 2; *p; p++) {
				gint hi, lo;
				if (*p == '%' && (hi = hexval (p[1])) >= 0 && (lo = hexval (p[2])) >= 0) {
					g_string_append_c (data, (gchar) (hi * 16 + lo));
					p += 2;
				} else {
					g_string_append_c (data, *p);
				}
			}
		}
		/* S (status) and # (comment) lines carry nothing we need */
	}
	if (line) {
		explicit_bzero (line, cap);
		free (line);
	}
	return result;
}

static gint
assuan_command (FILE *to, FILE *from, const gchar *cmd, const gchar *arg, GString *data)
{
	GString *s = g_string_new (cmd);

	if (arg) {
		g_string_append_c (s, ' ');
		append_escaped (s, arg);
	}
	g_string_append_c (s, '\n');
	gboolean sent = fwrite (s->str, 1, s->len, to) == s->len && fflush (to) == 0;
	g_string_free (s, TRUE);
	return sent ? assuan_read (from, data) : -1;
}

/* Text for the prompt is best-effort: an ERR only loses that line. FALSE only if the pinentry is gone. */
static gboolean
set_text (FILE *to, FILE *from, const gchar *cmd, const gchar *text)
{
	return !text || !*text || assuan_command (to, from, cmd, text, NULL) >= 0;
}

static void
on_cancelled (GCancellable *cancellable, gpointer self)
{
	kill_child (self);
}

/*
 * Worker thread: run one pinentry-astralis for one request. Returns the
 * password (GETPIN) or a GcrPromptReply (CONFIRM) through the task.
 */
static void
ask_thread (GTask *task, gpointer source, gpointer data, GCancellable *cancellable)
{
	AstralisPrompt *self = source;
	Request *r = data;
	gchar *argv[] = { pinentry_path, NULL };
	gchar **envp = g_environ_setenv (g_get_environ (), "PINENTRY_ASTRALIS_SOURCE", "keyring", TRUE);
	GError *error = NULL;
	GPid pid = 0;
	gint to_fd = -1, from_fd = -1;
	gint answer = -1;
	GString *pin = r->confirm ? NULL : g_string_sized_new (1024);  /* no regrowth: see assuan_read */

	/* gnome-keyring already gave up (StopPrompting before the thread ran): don't flash a prompt */
	if (g_cancellable_is_cancelled (cancellable)) {
		g_strfreev (envp);
		goto done;
	}
	if (!g_spawn_async_with_pipes (NULL, argv, envp, G_SPAWN_DO_NOT_REAP_CHILD,
	                               NULL, NULL, &pid, &to_fd, &from_fd, NULL, &error)) {
		g_warning ("couldn't run %s: %s", pinentry_path, error->message);
		g_clear_error (&error);
		g_strfreev (envp);
		goto done;
	}
	g_strfreev (envp);

	g_mutex_lock (&self->lock);
	self->child = pid;
	g_mutex_unlock (&self->lock);
	gulong cancel_id = cancellable ? g_cancellable_connect (cancellable, G_CALLBACK (on_cancelled), self, NULL) : 0;

	FILE *to = fdopen (to_fd, "w");
	FILE *from = fdopen (from_fd, "r");
	if (to && from) {
		setvbuf (from, NULL, _IONBF, 0);  /* the answer shouldn't linger in a stdio buffer */
		if (assuan_read (from, NULL) == 1) {  /* greeting */
			gboolean ok = set_text (to, from, "SETTITLE", r->title)
				&& set_text (to, from, "SETDESC", r->desc)
				&& set_text (to, from, "SETPROMPT", r->confirm ? NULL : "Password:")
				&& set_text (to, from, "SETERROR", r->warning)
				&& set_text (to, from, "SETOK", r->ok)
				&& set_text (to, from, "SETCANCEL", r->cancel)
				&& set_text (to, from, "SETREPEAT", !r->confirm && r->password_new ? "Confirm:" : NULL);
			if (ok)
				answer = assuan_command (to, from, r->confirm ? "CONFIRM" : "GETPIN", NULL, pin);
			if (answer >= 0)
				assuan_command (to, from, "BYE", NULL, NULL);
		}
	} else {
		g_warning ("couldn't talk to %s", pinentry_path);
		kill_child (self);
	}

	if (to) fclose (to); else close (to_fd);
	if (from) fclose (from); else close (from_fd);
	if (cancel_id)
		g_cancellable_disconnect (cancellable, cancel_id);
	g_mutex_lock (&self->lock);
	self->child = 0;
	g_mutex_unlock (&self->lock);
	while (waitpid (pid, NULL, 0) < 0 && errno == EINTR)
		;
	g_spawn_close_pid (pid);

done:
	if (r->confirm) {
		g_task_return_int (task, answer == 1 ? GCR_PROMPT_REPLY_CONTINUE : GCR_PROMPT_REPLY_CANCEL);
	} else if (answer == 1) {
		gchar *pw = g_strndup (pin->str, pin->len);
		explicit_bzero (pin->str, pin->allocated_len);
		g_string_free (pin, TRUE);
		g_task_return_pointer (task, pw, wipe_free);
	} else {
		explicit_bzero (pin->str, pin->allocated_len);
		g_string_free (pin, TRUE);
		g_task_return_pointer (task, NULL, NULL);  /* cancelled: gcr replies "no" */
	}
}

static void
start_request (AstralisPrompt *self, gboolean confirm, GCancellable *cancellable,
               GAsyncReadyCallback callback, gpointer user_data)
{
	Request *r = g_new0 (Request, 1);
	GTask *task = g_task_new (self, cancellable, callback, user_data);

	r->confirm = confirm;
	r->title = g_strdup (self->title);
	/* message (the headline) and description on separate lines; the shell lays them out */
	r->desc = g_strdup_printf ("%s\n%s", self->message ? self->message : "",
	                           self->description ? self->description : "");
	r->warning = g_strdup (self->warning);
	r->ok = g_strdup (self->continue_label);
	r->cancel = g_strdup (self->cancel_label);
	r->password_new = self->password_new;
	g_task_set_task_data (task, r, request_free);
	g_task_run_in_thread (task, ask_thread);
	g_object_unref (task);
}

static void
astralis_prompt_password_async (GcrPrompt *prompt, GCancellable *cancellable,
                                GAsyncReadyCallback callback, gpointer user_data)
{
	start_request (ASTRALIS_PROMPT (prompt), FALSE, cancellable, callback, user_data);
}

static const gchar *
astralis_prompt_password_finish (GcrPrompt *prompt, GAsyncResult *result, GError **error)
{
	AstralisPrompt *self = ASTRALIS_PROMPT (prompt);
	gchar *pw = g_task_propagate_pointer (G_TASK (result), error);

	wipe_free (self->password);
	self->password = pw;
	/* gnome-keyring only tells empty (0) from not (1): an empty new password gets a "store unencrypted?" check */
	self->password_strength = (pw && *pw) ? 1 : 0;
	g_object_notify (G_OBJECT (self), "password-strength");
	return pw;
}

static void
astralis_prompt_confirm_async (GcrPrompt *prompt, GCancellable *cancellable,
                               GAsyncReadyCallback callback, gpointer user_data)
{
	start_request (ASTRALIS_PROMPT (prompt), TRUE, cancellable, callback, user_data);
}

static GcrPromptReply
astralis_prompt_confirm_finish (GcrPrompt *prompt, GAsyncResult *result, GError **error)
{
	gssize reply = g_task_propagate_int (G_TASK (result), error);
	return reply == GCR_PROMPT_REPLY_CONTINUE ? GCR_PROMPT_REPLY_CONTINUE : GCR_PROMPT_REPLY_CANCEL;
}

/* The app gave up or gnome-keyring is done: take the prompt off screen. */
static void
astralis_prompt_close (GcrPrompt *prompt)
{
	kill_child (ASTRALIS_PROMPT (prompt));
}

static void
astralis_prompt_iface_init (GcrPromptIface *iface)
{
	iface->prompt_password_async = astralis_prompt_password_async;
	iface->prompt_password_finish = astralis_prompt_password_finish;
	iface->prompt_confirm_async = astralis_prompt_confirm_async;
	iface->prompt_confirm_finish = astralis_prompt_confirm_finish;
	iface->prompt_close = astralis_prompt_close;
}

/* ── the service ─────────────────────────────────────────────────────── */

static GMainLoop *loop;
static GcrSystemPrompter *prompter;
static gboolean registered;
static guint quit_id;

static gboolean
on_quit_timeout (gpointer unused)
{
	quit_id = 0;
	g_main_loop_quit (loop);
	return G_SOURCE_REMOVE;
}

static void
on_prompting (GObject *obj, GParamSpec *pspec, gpointer unused)
{
	if (gcr_system_prompter_get_prompting (prompter)) {
		if (quit_id)
			g_source_remove (quit_id);
		quit_id = 0;
	} else if (!quit_id) {
		quit_id = g_timeout_add_seconds (QUIT_TIMEOUT, on_quit_timeout, NULL);
	}
}

static void
on_bus_acquired (GDBusConnection *connection, const gchar *name, gpointer unused)
{
	gcr_system_prompter_register (prompter, connection);
	registered = TRUE;
}

static void
on_name_lost (GDBusConnection *connection, const gchar *name, gpointer unused)
{
	g_message ("not the keyring prompter (any more), quitting");
	g_main_loop_quit (loop);
}

static gboolean
on_signal (gpointer unused)
{
	g_main_loop_quit (loop);
	return G_SOURCE_CONTINUE;
}

static gchar *
find_pinentry (void)
{
	const gchar *env = g_getenv ("ASTRALIS_PINENTRY");
	if (env && g_file_test (env, G_FILE_TEST_IS_EXECUTABLE))
		return g_strdup (env);
	gchar *home = g_build_filename (g_get_home_dir (), ".local", "bin", "pinentry-astralis", NULL);
	if (g_file_test (home, G_FILE_TEST_IS_EXECUTABLE))
		return home;
	g_free (home);
	return g_find_program_in_path ("pinentry-astralis");
}

int
main (int argc, char **argv)
{
	signal (SIGPIPE, SIG_IGN);  /* a pinentry that dies mid-write must not take us with it */

	pinentry_path = find_pinentry ();
	if (!pinentry_path) {
		/* Still answer gnome-keyring, with its usual dialog. */
		g_message ("pinentry-astralis not found, handing over to %s", GCR_PROMPTER);
		execl (GCR_PROMPTER, GCR_PROMPTER, NULL);
		g_critical ("couldn't run %s either", GCR_PROMPTER);
		return 1;
	}

	loop = g_main_loop_new (NULL, FALSE);
	prompter = gcr_system_prompter_new (GCR_SYSTEM_PROMPTER_SINGLE, ASTRALIS_TYPE_PROMPT);
	g_signal_connect (prompter, "notify::prompting", G_CALLBACK (on_prompting), NULL);

	/* REPLACE takes over from a gcr-prompter that's already up; no ALLOW_REPLACEMENT,
	 * so a later gcr-prompter can't take the name back. */
	guint owner = g_bus_own_name (G_BUS_TYPE_SESSION, "org.gnome.keyring.SystemPrompter",
	                              G_BUS_NAME_OWNER_FLAGS_REPLACE,
	                              on_bus_acquired, NULL, on_name_lost, NULL, NULL);
	g_unix_signal_add (SIGTERM, on_signal, NULL);
	g_unix_signal_add (SIGINT, on_signal, NULL);
	on_prompting (NULL, NULL, NULL);  /* start the idle clock */

	g_main_loop_run (loop);

	g_bus_unown_name (owner);
	if (registered)  /* never got the bus: unregistering would be a critical */
		gcr_system_prompter_unregister (prompter, TRUE);
	g_object_unref (prompter);
	g_main_loop_unref (loop);
	g_free (pinentry_path);
	return 0;
}
