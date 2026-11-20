#ifndef NV_INTERNAL_H
#define NV_INTERNAL_H

#include "nvcore.h"

struct nv_index {
    char **items;
    size_t len;
    size_t cap;
    int truncated;
};

/* Copies n bytes of s. Returns 0 on success, -1 on allocation failure. */
int nv_index_push(struct nv_index *idx, const char *s, size_t n);
void nv_index_sort(struct nv_index *idx);


/* Regex engine entry point for tests (grep.c). Searches `text` for the first
 * match of `pattern` with smartcase. Returns 1 and sets [*start, *end) on a
 * match, 0 when there is none, -1 when the pattern is invalid or unsupported. */
int nv_re_search(const char *pattern, const char *text, size_t len, size_t *start,
                 size_t *end);

#endif
