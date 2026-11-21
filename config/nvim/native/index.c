#include "internal.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define MAX_TERMS 8

NV_API int nv_abi_version(void) { return NV_ABI_VERSION; }
NV_API const char *nv_version(void) { return "0.4.0"; }

static struct nv_index *index_new(void) {
  return calloc(1, sizeof(struct nv_index));
}

int nv_index_push(struct nv_index *idx, const char *s, size_t n) {
  if (idx->len == idx->cap) {
    if (idx->cap > SIZE_MAX / 2 / sizeof(char *))
      return -1;
    size_t cap = idx->cap ? idx->cap * 2 : 256;
    char **items = realloc(idx->items, cap * sizeof *items);
    if (!items)
      return -1;
    idx->items = items;
    idx->cap = cap;
  }
  char *copy = malloc(n + 1);
  if (!copy)
    return -1;
  memcpy(copy, s, n);
  copy[n] = '\0';
  idx->items[idx->len++] = copy;
  return 0;
}

static int cmp_str(const void *a, const void *b) {
  return strcmp(*(char *const *)a, *(char *const *)b);
}

uint64_t nv_char_mask(const char *s) {
  uint64_t m = 0;
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    unsigned c = *p;
    if (c >= 'A' && c <= 'Z')
      c += 'a' - 'A';
    unsigned bit;
    if (c >= 'a' && c <= 'z')
      bit = c - 'a';
    else if (c >= '0' && c <= '9')
      bit = 26 + (c - '0');
    else
      bit = 36 + (c % 28); /* punctuation and non-ASCII share bits: only false positives */
    m |= (uint64_t)1 << bit;
  }
  return m;
}

void nv_index_seal(struct nv_index *idx) {
  free(idx->masks);
  free(idx->lens);
  idx->masks = NULL;
  idx->lens = NULL;
  if (idx->len == 0 || idx->len > SIZE_MAX / sizeof(uint64_t))
    return;
  uint64_t *masks = malloc(idx->len * sizeof *masks);
  uint32_t *lens = malloc(idx->len * sizeof *lens);
  if (!masks || !lens) {
    free(masks);
    free(lens);
    return;
  }
  for (size_t i = 0; i < idx->len; i++) {
    masks[i] = nv_char_mask(idx->items[i]);
    lens[i] = (uint32_t)strlen(idx->items[i]);
  }
  idx->masks = masks;
  idx->lens = lens;
}

void nv_index_sort(struct nv_index *idx) {
  if (idx->len > 1)
    qsort(idx->items, idx->len, sizeof *idx->items, cmp_str);
  nv_index_seal(idx);
}

NV_API nv_index *nv_index_from_text(const char *text, size_t len) {
  struct nv_index *idx = index_new();
  if (!idx)
    return NULL;
  size_t i = 0;
  while (i < len) {
    size_t j = i;
    while (j < len && text[j] != '\n')
      j++;
    size_t n = j - i;
    if (n > 0 && text[i + n - 1] == '\r')
      n--;
    if (n > 0 && nv_index_push(idx, text + i, n) != 0) {
      idx->truncated = 1;
      break;
    }
    i = j + 1;
  }
  nv_index_seal(idx);
  return idx;
}

NV_API void nv_index_free(nv_index *idx) {
  if (!idx)
    return;
  for (size_t i = 0; i < idx->len; i++)
    free(idx->items[i]);
  free(idx->items);
  free(idx->masks);
  free(idx->lens);
  free(idx);
}

NV_API size_t nv_index_count(const nv_index *idx) { return idx ? idx->len : 0; }
NV_API int nv_index_truncated(const nv_index *idx) {
  return idx ? idx->truncated : 0;
}

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
  if (x->score != y->score)
    return x->score > y->score ? -1 : 1;
  if (x->len != y->len)
    return x->len < y->len ? -1 : 1;
  return x->idx < y->idx ? -1 : (x->idx > y->idx);
}

typedef struct {
  const nv_index *idx;
  const char *const *terms;
  const uint64_t *tmask;
  size_t nterms;
  size_t lo, hi, limit;
  scored *hits; /* capacity `limit` */
  size_t nhits;
} range_job;

/* Best `limit` hits among items [lo, hi): a bounded max-heap whose root is the
 * worst hit kept, so a new hit only has to beat the root. */
static void filter_range(range_job *j) {
  const nv_index *idx = j->idx;
  scored *hits = j->hits;
  size_t nhits = 0, limit = j->limit, nterms = j->nterms;
  const char *const *terms = j->terms;
  const uint64_t *tmask = j->tmask;
#define WORSE(a, b) (cmp_scored(&(a), &(b)) > 0)
  for (size_t i = j->lo; i < j->hi; i++) {
    int total = 0; size_t t;
    if (idx->masks) {
      uint64_t have = idx->masks[i];
      for (t = 0; t < nterms; t++)
        if (tmask[t] & ~have)
          break;
      if (t < nterms)
        continue; /* a term has a character this item lacks */
    }
    for (t = 0; t < nterms; t++) {
      int s = nv_fuzzy_score(terms[t], idx->items[i]);
      if (s < 0) break;
      total += s;
    }
    if (t < nterms) continue;
    scored c = {total, idx->lens ? idx->lens[i] : (uint32_t)strlen(idx->items[i]), (uint32_t)i};
    if (nhits < limit) { /* sift up */
      size_t k = nhits++;
      hits[k] = c;
      while (k > 0) {
        size_t parent = (k - 1) / 2;
        if (!WORSE(hits[k], hits[parent]))
          break;
        scored swap = hits[k];
        hits[k] = hits[parent];
        hits[parent] = swap;
        k = parent;
      }
    } else if (cmp_scored(&c, &hits[0]) < 0) { /* replace the root, sift down */
      hits[0] = c;
      size_t k = 0;
      for (;;) {
        size_t l = 2 * k + 1, r = l + 1, worst = k;
        if (l < nhits && WORSE(hits[l], hits[worst]))
          worst = l;
        if (r < nhits && WORSE(hits[r], hits[worst]))
          worst = r;
        if (worst == k)
          break;
        scored swap = hits[k];
        hits[k] = hits[worst];
        hits[worst] = swap;
        k = worst;
      }
    }
  }
  j->nhits = nhits;
}

static void *range_worker(void *arg) {
  filter_range(arg);
  return NULL;
}

#define FILTER_PAR_MIN 50000 /* items; below this threads cost more than they save */
#define FILTER_MAX_THREADS 8

/* NV_FILTER_THREADS overrides the default (online CPUs); 1 = sequential. */
static size_t filter_threads(size_t len) {
  long n = 1;
#ifdef _SC_NPROCESSORS_ONLN
  n = sysconf(_SC_NPROCESSORS_ONLN);
#endif
  const char *env = getenv("NV_FILTER_THREADS");
  if (env && *env) {
    long v = strtol(env, NULL, 10);
    if (v >= 1)
      n = v;
  }
  if (n < 1)
    n = 1;
  if (n > FILTER_MAX_THREADS)
    n = FILTER_MAX_THREADS;
  if (len < FILTER_PAR_MIN)
    n = 1;
  return (size_t)n;
}

NV_API size_t nv_index_filter(const nv_index *idx, const char *query,
                              uint32_t *out, size_t limit) {
  if (!idx || !out || limit == 0)
    return 0;

  char *buf = strdup(query ? query : "");
  if (!buf)
    return 0;
  const char *terms[MAX_TERMS];
  size_t nterms = 0;
  for (char *p = buf; *p && nterms < MAX_TERMS;) {
    while (*p == ' ' || *p == '\t')
      p++;
    if (!*p)
      break;
    terms[nterms++] = p;
    while (*p && *p != ' ' && *p != '\t')
      p++;
    if (*p)
      *p++ = '\0';
  }

  size_t n = 0;
  if (nterms == 0) {
    for (; n < limit && n < idx->len; n++)
      out[n] = (uint32_t)n;
    free(buf);
    return n;
  }

  if (idx->len > SIZE_MAX / sizeof(scored) || idx->len > UINT32_MAX) {
    free(buf);
    return 0;
  }
  if (limit > idx->len)
    limit = idx->len; /* never keep more than exist */
  uint64_t tmask[MAX_TERMS];
  for (size_t t = 0; t < nterms; t++)
    tmask[t] = nv_char_mask(terms[t]);

  size_t nthreads = filter_threads(idx->len);
  if (nthreads < 1 || limit > SIZE_MAX / FILTER_MAX_THREADS / sizeof(scored))
    nthreads = 1;
  range_job jobs[FILTER_MAX_THREADS];
  pthread_t tid[FILTER_MAX_THREADS];
  int started[FILTER_MAX_THREADS] = {0};
  scored *all = malloc(nthreads * limit * sizeof *all);
  if (!all) {
    free(buf);
    return 0;
  }
  size_t per = (idx->len + nthreads - 1) / nthreads;
  for (size_t t = 0; t < nthreads; t++) {
    jobs[t] = (range_job){idx, terms, tmask, nterms,
                          t * per < idx->len ? t * per : idx->len,
                          (t + 1) * per < idx->len ? (t + 1) * per : idx->len,
                          limit, all + t * limit, 0};
  }
  for (size_t t = 1; t < nthreads; t++)
    started[t] = pthread_create(&tid[t], NULL, range_worker, &jobs[t]) == 0;
  filter_range(&jobs[0]);
  for (size_t t = 1; t < nthreads; t++) {
    if (started[t])
      pthread_join(tid[t], NULL);
    else
      filter_range(&jobs[t]); /* could not start a thread: do it here */
  }
  /* Merge: compact every part's hits, then one sort. The order is total (score,
   * length, index), so the result does not depend on the thread count. */
  size_t nhits = jobs[0].nhits;
  for (size_t t = 1; t < nthreads; t++) {
    memmove(all + nhits, jobs[t].hits, jobs[t].nhits * sizeof *all);
    nhits += jobs[t].nhits;
  }
  qsort(all, nhits, sizeof *all, cmp_scored); /* at most threads * limit entries */
  for (; n < limit && n < nhits; n++)
    out[n] = all[n].idx;

  free(all);
  free(buf);
  return n;
}
