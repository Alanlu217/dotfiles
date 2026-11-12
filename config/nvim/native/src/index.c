#define _DEFAULT_SOURCE
#include "internal.h"

#include <stdlib.h>
#include <string.h>

#define MAX_TERMS 8

NV_API int nv_abi_version(void) { return NV_ABI_VERSION; }
NV_API const char *nv_version(void) { return "0.3.0"; }

static struct nv_index *index_new(void) {
    return calloc(1, sizeof(struct nv_index));
}

int nv_index_push(struct nv_index *idx, const char *s, size_t n) {
    if (idx->len == idx->cap) {
        size_t cap = idx->cap ? idx->cap * 2 : 256;
        char **items = realloc(idx->items, cap * sizeof *items);
        if (!items) return -1;
        idx->items = items;
        idx->cap = cap;
    }
    char *copy = malloc(n + 1);
    if (!copy) return -1;
    memcpy(copy, s, n);
    copy[n] = '\0';
    idx->items[idx->len++] = copy;
    return 0;
}

static int cmp_str(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

void nv_index_sort(struct nv_index *idx) {
    if (idx->len > 1) qsort(idx->items, idx->len, sizeof *idx->items, cmp_str);
}

NV_API nv_index *nv_index_from_text(const char *text, size_t len) {
    struct nv_index *idx = index_new();
    if (!idx) return NULL;
    size_t i = 0;
    while (i < len) {
        size_t j = i;
        while (j < len && text[j] != '\n') j++;
        size_t n = j - i;
        if (n > 0 && text[i + n - 1] == '\r') n--;
        if (n > 0 && nv_index_push(idx, text + i, n) != 0) {
            idx->truncated = 1;
            break;
        }
        i = j + 1;
    }
    return idx;
}

NV_API void nv_index_free(nv_index *idx) {
    if (!idx) return;
    for (size_t i = 0; i < idx->len; i++) free(idx->items[i]);
    free(idx->items);
    free(idx);
}

NV_API size_t nv_index_count(const nv_index *idx) { return idx ? idx->len : 0; }
NV_API int nv_index_truncated(const nv_index *idx) { return idx ? idx->truncated : 0; }

NV_API const char *nv_index_get(const nv_index *idx, size_t i) {
    return (idx && i < idx->len) ? idx->items[i] : NULL;
}

typedef struct {
    int score;
    uint32_t len;
    uint32_t idx;
} scored;

static int cmp_scored(const void *a, const void *b) {
    const scored *x = a, *y = b;
    if (x->score != y->score) return x->score > y->score ? -1 : 1;
    if (x->len != y->len) return x->len < y->len ? -1 : 1;
    return x->idx < y->idx ? -1 : (x->idx > y->idx);
}

NV_API size_t nv_index_filter(const nv_index *idx, const char *query,
                              uint32_t *out, size_t limit) {
    if (!idx || !out || limit == 0) return 0;

    char *buf = strdup(query ? query : "");
    if (!buf) return 0;
    const char *terms[MAX_TERMS];
    size_t nterms = 0;
    for (char *p = buf; *p && nterms < MAX_TERMS;) {
        while (*p == ' ' || *p == '\t') p++;
        if (!*p) break;
        terms[nterms++] = p;
        while (*p && *p != ' ' && *p != '\t') p++;
        if (*p) *p++ = '\0';
    }

    size_t n = 0;
    if (nterms == 0) {
        for (; n < limit && n < idx->len; n++) out[n] = (uint32_t)n;
        free(buf);
        return n;
    }

    scored *hits = malloc((idx->len ? idx->len : 1) * sizeof *hits);
    if (!hits) {
        free(buf);
        return 0;
    }
    size_t nhits = 0;
    for (size_t i = 0; i < idx->len; i++) {
        int total = 0;
        size_t t;
        for (t = 0; t < nterms; t++) {
            int s = nv_fuzzy_score(terms[t], idx->items[i]);
            if (s < 0) break;
            total += s;
        }
        if (t < nterms) continue;
        hits[nhits].score = total;
        hits[nhits].len = (uint32_t)strlen(idx->items[i]);
        hits[nhits].idx = (uint32_t)i;
        nhits++;
    }
    qsort(hits, nhits, sizeof *hits, cmp_scored);
    for (; n < limit && n < nhits; n++) out[n] = hits[n].idx;

    free(hits);
    free(buf);
    return n;
}
