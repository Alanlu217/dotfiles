#define _DEFAULT_SOURCE
#include "common.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>

typedef struct {
    char *path;
    int score;
} MatchItem;

typedef struct {
    MatchItem *items;
    size_t len;
    size_t cap;
} MatchList;

static void match_list_init(MatchList *ml) {
    ml->cap = 256;
    ml->len = 0;
    ml->items = malloc(ml->cap * sizeof(MatchItem));
}

static void match_list_add(MatchList *ml, const char *path, int score) {
    if (ml->len >= ml->cap) {
        ml->cap *= 2;
        ml->items = realloc(ml->items, ml->cap * sizeof(MatchItem));
    }
    ml->items[ml->len].path = strdup(path);
    ml->items[ml->len].score = score;
    ml->len++;
}

static int compare_matches(const void *a, const void *b) {
    const MatchItem *item1 = (const MatchItem *)a;
    const MatchItem *item2 = (const MatchItem *)b;
    return item2->score - item1->score;
}

static void walk(const char *dir_path, const char *base_path, const char *query, MatchList *ml) {
    DIR *dir = opendir(dir_path);
    if (!dir) return;

    struct dirent *entry;
    size_t base_len = strlen(base_path);

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if (entry->d_name[0] == '.' || strcmp(entry->d_name, "node_modules") == 0)
            continue;

        // Dynamically allocate exact path size: len(dir_path) + len(entry) + 2 ('/' + '\0')
        size_t path_len = strlen(dir_path) + strlen(entry->d_name) + 2;
        char *path = malloc(path_len);
        if (!path) continue;

        snprintf(path, path_len, "%s/%s", dir_path, entry->d_name);

        struct stat st;
        if (lstat(path, &st) == 0) {
            if (S_ISLNK(st.st_mode)) {
                free(path);
                continue;
            }
            if (S_ISDIR(st.st_mode)) {
                walk(path, base_path, query, ml);
            } else if (S_ISREG(st.st_mode)) {
                const char *rel = path + base_len;
                if (*rel == '/') rel++;

                int score = fuzzy_match(query, rel);
                if (score > 0) {
                    match_list_add(ml, rel, score);
                }
            }
        }
        free(path);
    }
    closedir(dir);
}

__attribute__((visibility("default")))
void free_string(char *ptr) {
    if (ptr) {
        free(ptr);
    }
}

__attribute__((visibility("default")))
const char* native_core_version(void) {
    return "0.2.1-alpha";
}

__attribute__((visibility("default")))
char* search_directory(const char *root_path, const char *query) {
    MatchList ml;
    match_list_init(&ml);
    if (!ml.items) return NULL;

    walk(root_path, root_path, (query && query[0] != '\0') ? query : "", &ml);

    if (ml.len > 1) {
        qsort(ml.items, ml.len, sizeof(MatchItem), compare_matches);
    }

    size_t total_len = 0;
    for (size_t i = 0; i < ml.len; i++) {
        total_len += strlen(ml.items[i].path) + 1;
    }

    char *result = malloc(total_len + 1);
    if (!result) {
        for (size_t i = 0; i < ml.len; i++) free(ml.items[i].path);
        free(ml.items);
        return NULL;
    }
    result[0] = '\0';

    size_t offset = 0;
    for (size_t i = 0; i < ml.len; i++) {
        size_t plen = strlen(ml.items[i].path);
        memcpy(result + offset, ml.items[i].path, plen);
        result[offset + plen] = '\n';
        offset += plen + 1;
        free(ml.items[i].path);
    }
    result[offset] = '\0';

    free(ml.items);
    return result;
}
