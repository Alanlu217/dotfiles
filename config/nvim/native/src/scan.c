#define _DEFAULT_SOURCE
#include "internal.h"

#include <dirent.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define MAX_DEPTH 64
#define MAX_IGNORES 64

typedef struct {
    struct nv_index *idx;
    char *ignore_buf;
    const char *ignore[MAX_IGNORES];
    size_t n_ignore;
    int hidden;
    size_t max_files;
    size_t root_len;
    char path[PATH_MAX];
} scan_ctx;

static int ignored(const scan_ctx *c, const char *name) {
    for (size_t i = 0; i < c->n_ignore; i++)
        if (strcmp(c->ignore[i], name) == 0) return 1;
    return 0;
}

enum { KIND_NONE, KIND_FILE, KIND_DIR };

static int kind_of(const struct dirent *e, const char *path) {
    struct stat st;
    switch (e->d_type) {
    case DT_REG: return KIND_FILE;
    case DT_DIR: return KIND_DIR;
    case DT_LNK: break;
    default:
        if (lstat(path, &st) != 0) return KIND_NONE;
        if (!S_ISLNK(st.st_mode)) return S_ISREG(st.st_mode) ? KIND_FILE : S_ISDIR(st.st_mode) ? KIND_DIR : KIND_NONE;
    }
    /* Symlink: keep it only when it points at a regular file (never recurse). */
    return (stat(path, &st) == 0 && S_ISREG(st.st_mode)) ? KIND_FILE : KIND_NONE;
}

static void walk(scan_ctx *c, size_t dir_len, int depth) {
    if (depth > MAX_DEPTH || c->idx->truncated) return;
    DIR *d = opendir(dir_len ? c->path : "/");
    if (!d) return;

    struct dirent *e;
    while (!c->idx->truncated && (e = readdir(d)) != NULL) {
        const char *name = e->d_name;
        if (name[0] == '.' && (name[1] == '\0' || (name[1] == '.' && name[2] == '\0'))) continue;
        if (name[0] == '.' && !c->hidden) continue;
        if (ignored(c, name)) continue;

        size_t nlen = strlen(name);
        if (dir_len + 1 + nlen + 1 > sizeof c->path) continue;
        c->path[dir_len] = '/';
        memcpy(c->path + dir_len + 1, name, nlen + 1);

        switch (kind_of(e, c->path)) {
        case KIND_DIR:
            walk(c, dir_len + 1 + nlen, depth + 1);
            break;
        case KIND_FILE:
            if (c->idx->len >= c->max_files ||
                nv_index_push(c->idx, c->path + c->root_len + 1, strlen(c->path + c->root_len + 1)) != 0)
                c->idx->truncated = 1;
            break;
        default:
            break;
        }
    }
    closedir(d);
    c->path[dir_len] = '\0';
}

NV_API nv_index *nv_index_scan(const char *root, const char *ignore_dirs,
                               int include_hidden, size_t max_files) {
    if (!root || !*root) root = ".";
    size_t rlen = strlen(root);
    if (rlen >= PATH_MAX - 2) return NULL;

    scan_ctx *c = calloc(1, sizeof *c);
    if (!c) return NULL;
    c->idx = calloc(1, sizeof *c->idx);
    if (!c->idx) {
        free(c);
        return NULL;
    }
    c->hidden = include_hidden;
    c->max_files = max_files ? max_files : (size_t)-1;

    memcpy(c->path, root, rlen + 1);
    while (rlen > 0 && c->path[rlen - 1] == '/') c->path[--rlen] = '\0';
    c->root_len = rlen; /* "/" collapses to length 0 */

    if (ignore_dirs && *ignore_dirs) {
        c->ignore_buf = strdup(ignore_dirs);
        if (c->ignore_buf) {
            char *save = NULL;
            for (char *tok = strtok_r(c->ignore_buf, ",", &save); tok && c->n_ignore < MAX_IGNORES;
                 tok = strtok_r(NULL, ",", &save))
                c->ignore[c->n_ignore++] = tok;
        }
    }

    walk(c, rlen, 0);
    nv_index_sort(c->idx);

    struct nv_index *idx = c->idx;
    free(c->ignore_buf);
    free(c);
    return idx;
}
