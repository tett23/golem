/* The watchdog of Golem.TestSupport.Watchdog (docs/adr ADR 0117).

   A POSIX thread of its own, outside the Haskell runtime: it reads the
   table of the running tests once a second and, when a test has run for
   longer than its limit, or when no test has run for longer than the
   limit since the last one ended, writes what it knows to the standard
   error and aborts the process. It never calls into Haskell and takes no
   capability, so it fires even when every Haskell thread is stuck,
   including a runtime that waits for a garbage collection that never
   starts (scripts/ci/rts-capabilities.sh, the roadmap's unsafe FFI
   calls).

   The Haskell side calls the functions below as unsafe foreign calls;
   each of them only takes the table's lock for a copy or a store. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define SLOTS 1024
#define NAME_MAX_BYTES 1024

struct slot {
  int used;
  double started;
  char name[NAME_MAX_BYTES];
};

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static struct slot slots[SLOTS];
static int started = 0;
static long limit_seconds = 0;
static double last_beat = 0;
static double last_change = 0;

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

/* Writes the whole text to the standard error, unbuffered. */
static void say(const char *text) {
  size_t left = strlen(text);
  while (left > 0) {
    ssize_t n = write(2, text, left);
    if (n <= 0) return;
    text += n;
    left -= (size_t)n;
  }
}

/* The report, then abort. Called with the lock held. */
static void fire(double t) {
  char line[NAME_MAX_BYTES + 256];
  int running = 0;
  say("\n");
  for (int i = 0; i < SLOTS; i++) {
    if (!slots[i].used) continue;
    running++;
    if (t - slots[i].started > (double)limit_seconds) {
      snprintf(line, sizeof line, "watchdog: \"%s\" has run for more than %ld seconds of wall-clock time\n",
               slots[i].name, limit_seconds);
      say(line);
    }
  }
  for (int i = 0; i < SLOTS; i++) {
    if (!slots[i].used || t - slots[i].started > (double)limit_seconds) continue;
    snprintf(line, sizeof line, "watchdog: \"%s\" is also running, for %.0f seconds\n", slots[i].name,
             t - slots[i].started);
    say(line);
  }
  if (running == 0) {
    snprintf(line, sizeof line,
             "watchdog: no test is running, and the last one ended %.0f seconds ago (more than %ld): the process has not exited\n",
             t - last_change, limit_seconds);
    say(line);
  }
  snprintf(line, sizeof line, "watchdog: the Haskell runtime last ran a thread %.1f seconds ago%s\n", t - last_beat,
           t - last_beat > 2.0 ? " (it is stuck, not only the tests)" : "");
  say(line);
  say("watchdog: aborting the process\n");
  abort();
}

static void *watch(void *unused) {
  (void)unused;
  for (;;) {
    sleep(1);
    pthread_mutex_lock(&lock);
    double t = now();
    int running = 0, over = 0;
    for (int i = 0; i < SLOTS; i++) {
      if (!slots[i].used) continue;
      running++;
      if (t - slots[i].started > (double)limit_seconds) over = 1;
    }
    if (over || (running == 0 && t - last_change > (double)limit_seconds)) fire(t);
    pthread_mutex_unlock(&lock);
  }
  return NULL;
}

/* Starts the watchdog with a limit in seconds, once: 1 when this call
   started it, 0 when it had started already (the first limit stays),
   -1 when the thread could not be made. */
int golem_watchdog_start(long limit) {
  int r = 0;
  pthread_mutex_lock(&lock);
  if (!started) {
    pthread_t th;
    limit_seconds = limit;
    last_beat = last_change = now();
    if (pthread_create(&th, NULL, watch, NULL) == 0) {
      pthread_detach(th);
      started = 1;
      r = 1;
    } else {
      r = -1;
    }
  }
  pthread_mutex_unlock(&lock);
  return r;
}

/* Records a test that starts: the slot to give back to
   golem_watchdog_leave, or -1 when every slot is taken. */
int golem_watchdog_enter(const char *name) {
  int r = -1;
  pthread_mutex_lock(&lock);
  for (int i = 0; i < SLOTS; i++) {
    if (slots[i].used) continue;
    slots[i].used = 1;
    slots[i].started = last_change = now();
    snprintf(slots[i].name, NAME_MAX_BYTES, "%s", name);
    r = i;
    break;
  }
  pthread_mutex_unlock(&lock);
  return r;
}

/* Records that the test of the slot has ended. */
void golem_watchdog_leave(int slot) {
  if (slot < 0 || slot >= SLOTS) return;
  pthread_mutex_lock(&lock);
  slots[slot].used = 0;
  last_change = now();
  pthread_mutex_unlock(&lock);
}

/* Records that a Haskell thread has just run. */
void golem_watchdog_beat(void) {
  pthread_mutex_lock(&lock);
  last_beat = now();
  pthread_mutex_unlock(&lock);
}
