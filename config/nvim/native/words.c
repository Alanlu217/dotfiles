/*
 * Word extraction for buffer completion: the distinct identifiers of a text
 * with how often each occurs, in first-seen order.
 *
 * A word is a run of ASCII letters/digits, '_' and bytes >= 128 (so UTF-8 is
 * kept whole); runs that start with a digit or are shorter than `min_len` are
 * ignored. Scanning stops as soon as `max_words` distinct words are held.
 */
#include "internal.h"

#include <stdlib.h>
#include <string.h>

struct nv_words {
  char **words;
  uint32_t *counts;
  size_t len, cap;
  size_t *slots; /* open-addressing table of word index + 1 (0 = empty) */
  size_t nslots;
};

static int is_word_byte(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '_' || c >= 128;
}

static uint64_t hash_bytes(const char *s, size_t n) {
  uint64_t h = 1469598103934665603ULL;
  for (size_t i = 0; i < n; i++) {
    h ^= (unsigned char)s[i];
    h *= 1099511628211ULL;
  }
  return h;
}

static int grow_table(struct nv_words *w) {
  size_t nslots = w->nslots ? w->nslots * 2 : 1024;
  size_t *slots = calloc(nslots, sizeof *slots);
  if (!slots)
    return -1;
  for (size_t i = 0; i < w->len; i++) {
    size_t h = hash_bytes(w->words[i], strlen(w->words[i])) & (nslots - 1);
    while (slots[h])
      h = (h + 1) & (nslots - 1);
    slots[h] = i + 1;
  }
  free(w->slots);
  w->slots = slots;
  w->nslots = nslots;
  return 0;
}

/* Count one occurrence. Returns 1 when the word was new, 0 when seen, -1 on
 * allocation failure. */
static int add_word(struct nv_words *w, const char *s, size_t n) {
  if ((w->len + 1) * 2 > w->nslots && grow_table(w) != 0)
    return -1;
  size_t mask = w->nslots - 1, h = hash_bytes(s, n) & mask;
  while (w->slots[h]) {
    size_t i = w->slots[h] - 1;
    if (strncmp(w->words[i], s, n) == 0 && w->words[i][n] == '\0') {
      w->counts[i]++;
      return 0;
    }
    h = (h + 1) & mask;
  }
  if (w->len == w->cap) {
    size_t cap = w->cap ? w->cap * 2 : 256;
    char **words = realloc(w->words, cap * sizeof *words);
    if (!words)
      return -1;
    w->words = words;
    uint32_t *counts = realloc(w->counts, cap * sizeof *counts);
    if (!counts)
      return -1;
    w->counts = counts;
    w->cap = cap;
  }
  char *copy = malloc(n + 1);
  if (!copy)
    return -1;
  memcpy(copy, s, n);
  copy[n] = '\0';
  w->words[w->len] = copy;
  w->counts[w->len] = 1;
  w->slots[h] = ++w->len;
  return 1;
}

NV_API nv_words *nv_words_collect(const char *text, size_t len,
                                  size_t min_len, size_t max_words) {
  struct nv_words *w = calloc(1, sizeof *w);
  if (!w)
    return NULL;
  size_t i = 0;
  while (i < len) {
    if (!is_word_byte((unsigned char)text[i])) {
      i++;
      continue;
    }
    size_t j = i;
    while (j < len && is_word_byte((unsigned char)text[j]))
      j++;
    if (j - i >= min_len && !(text[i] >= '0' && text[i] <= '9')) {
      int r = add_word(w, text + i, j - i);
      if (r < 0 || (r > 0 && max_words && w->len >= max_words))
        break; /* out of memory: keep what we have */
    }
    i = j;
  }
  return w;
}

NV_API size_t nv_words_count(const nv_words *w) { return w ? w->len : 0; }

NV_API const char *nv_words_get(const nv_words *w, size_t i) {
  return (w && i < w->len) ? w->words[i] : NULL;
}

NV_API uint32_t nv_words_occurrences(const nv_words *w, size_t i) {
  return (w && i < w->len) ? w->counts[i] : 0;
}

NV_API void nv_words_free(nv_words *w) {
  if (!w)
    return;
  for (size_t i = 0; i < w->len; i++)
    free(w->words[i]);
  free(w->words);
  free(w->counts);
  free(w->slots);
  free(w);
}
