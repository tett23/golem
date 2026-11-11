#include <sys/file.h>

int golem_lock_directory(int fd) {
    return flock(fd, LOCK_EX);
}
