/* appnap-mem — page a napped app's memory out to swap, and read it back in on wake.
 *
 *   appnap-mem out PID...   MADV_PAGEOUT over each process's anonymous and shared-memory
 *                           mappings: their pages are written to swap and leave RAM.
 *   appnap-mem in  PID...   MADV_WILLNEED over the same, plus code (executable file
 *                           mappings): every swapped page is read back at once, in
 *                           parallel, so a woken app doesn't fault them in one at a time.
 *
 * Used by ~/.local/bin/appnap. Advising another process needs CAP_SYS_NICE
 * (process_madvise), so the helper is installed once with that capability:
 *
 *   gcc -O2 -Wall -o /tmp/appnap-mem appnap-mem.c
 *   sudo install -m755 /tmp/appnap-mem /usr/local/bin/appnap-mem
 *   sudo setcap cap_sys_nice=ep /usr/local/bin/appnap-mem
 *
 * Reinstalling drops the capability: run the setcap again. The kernel still only lets it
 * touch processes of the same user. Exit: 0 done, 1 usage, 2 not permitted, 3 no pid worked.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#ifndef MADV_PAGEOUT
#define MADV_PAGEOUT 21
#endif

#define STEP (128UL << 20)

static unsigned long since_pause;

/* One range, in 128 MB steps. Paging out pauses 20 ms per 128 MB so the swap writes don't
 * stall the desktop. -1: not permitted (stop), 0 otherwise (a special mapping refusing the
 * advice, or the process exiting, just skips it). */
static int advise(int pidfd, unsigned long s, unsigned long e, int advice) {
    for (unsigned long a = s; a < e; a += STEP) {
        unsigned long n = e - a < STEP ? e - a : STEP;
        struct iovec iov = {(void *)a, n};
        if (syscall(SYS_process_madvise, pidfd, &iov, 1, advice, 0) < 0)
            return errno == EPERM ? -1 : 0;
        if (advice == MADV_PAGEOUT && (since_pause += n) >= STEP) {
            since_pause = 0;
            nanosleep(&(struct timespec){0, 20 * 1000 * 1000}, NULL);
        }
    }
    return 0;
}

/* Which mappings hold the app's own memory. Device mappings (GPU buffers) and the kernel's
 * [vdso]-style pages never; regular files only their code, and only when reading back. */
static int wanted(const char *perms, unsigned long ino, const char *path, int in) {
    if (!strncmp(perms, "---", 3) || !strncmp(path, "[v", 2))
        return 0;
    if (!strncmp(path, "/memfd:", 7) || !strncmp(path, "/dev/shm/", 9) || !strncmp(path, "/SYSV", 5))
        return 1;
    if (!strncmp(path, "/dev/", 5))
        return 0;
    if (ino == 0)
        return 1;
    return in && perms[2] == 'x';
}

int main(int argc, char **argv) {
    if (argc < 3 || (strcmp(argv[1], "out") && strcmp(argv[1], "in"))) {
        fprintf(stderr, "usage: appnap-mem out|in PID...\n");
        return 1;
    }
    int in = !strcmp(argv[1], "in");
    int advice = in ? MADV_WILLNEED : MADV_PAGEOUT;
    int done = 0;
    char *line = NULL;
    size_t cap = 0;

    for (int i = 2; i < argc; i++) {
        int pid = atoi(argv[i]);
        if (pid <= 1)
            continue;
        int pidfd = syscall(SYS_pidfd_open, pid, 0);
        if (pidfd < 0)
            continue;
        char maps[64];
        snprintf(maps, sizeof maps, "/proc/%d/maps", pid);
        FILE *f = fopen(maps, "r");
        if (!f) {
            close(pidfd);
            continue;
        }
        while (getline(&line, &cap, f) > 0) {
            unsigned long s, e, ino;
            char perms[5];
            int path_at = 0;
            if (sscanf(line, "%lx-%lx %4s %*x %*x:%*x %lu %n", &s, &e, perms, &ino, &path_at) < 4)
                continue;
            char *path = line + path_at;
            path[strcspn(path, "\n")] = 0;
            if (!wanted(perms, ino, path, in))
                continue;
            if (advise(pidfd, s, e, advice) < 0) {
                fprintf(stderr, "appnap-mem: not permitted (needs cap_sys_nice: see the header of appnap-mem.c)\n");
                return 2;
            }
        }
        fclose(f);
        close(pidfd);
        done++;
    }
    return done ? 0 : 3;
}
