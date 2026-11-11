#include <sys/file.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <string.h>
#include <unistd.h>

int golem_lock_directory(int fd) {
    return flock(fd, LOCK_EX);
}

/* Walk only real directories beneath the project and remove the Finder file
   relative to the opened directory. A concurrent symlink replacement of an
   ancestor cannot redirect unlinkat outside the directory we opened. */
int golem_clean_finder_info(const char *root, const char *relative) {
    int dir = open(root, O_RDONLY | O_DIRECTORY);
    if (dir < 0) return -1;

    const char *part = relative;
    if (*part == '/' || *part == '\0') {
        close(dir);
        return 0;
    }
    while (strcmp(part, ".") != 0) {
        const char *slash = strchr(part, '/');
        size_t length = slash ? (size_t)(slash - part) : strlen(part);
        if (length == 0 || length > NAME_MAX || part[0] == '.') {
            close(dir);
            return 0;
        }
        char name[NAME_MAX + 1];
        memcpy(name, part, length);
        name[length] = '\0';
        int next = openat(dir, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
        if (next < 0) {
            int error = errno;
            close(dir);
            if (error == ENOENT || error == ENOTDIR || error == ELOOP) return 0;
            errno = error;
            return -1;
        }
        close(dir);
        dir = next;
        if (!slash) break;
        part = slash + 1;
    }

    struct stat info;
    if (fstatat(dir, ".DS_Store", &info, AT_SYMLINK_NOFOLLOW) < 0) {
        int error = errno;
        close(dir);
        if (error == ENOENT) return 0;
        errno = error;
        return -1;
    }
    if (!S_ISREG(info.st_mode)) {
        close(dir);
        return 0;
    }
    if (unlinkat(dir, ".DS_Store", 0) < 0) {
        int error = errno;
        close(dir);
        if (error == ENOENT || error == EISDIR) return 0;
        errno = error;
        return -1;
    }
    close(dir);
    return 1;
}
