/* The watchdog of Golem.TestSupport.Watchdog (docs/adr ADR 0117). */
#ifndef GOLEM_WATCHDOG_H
#define GOLEM_WATCHDOG_H

int golem_watchdog_start(long limit);
int golem_watchdog_enter(const char *name);
void golem_watchdog_leave(int slot);
void golem_watchdog_beat(void);

#endif
