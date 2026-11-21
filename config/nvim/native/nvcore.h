/*
 * nvcore public API.
 *
 * This header is parsed directly by LuaJIT's ffi.cdef (see lua/core/native.lua),
 * so keep it FFI-safe: plain declarations only, no function-like macros, and no
 * includes beyond <stddef.h>/<stdint.h>. Comments and #-lines are stripped
 * before parsing; NV_ABI_VERSION is read by the loader and compared against
 * nv_abi_version() to detect a stale library.
 */
#ifndef NVCORE_H
#define NVCORE_H

#include <stddef.h>
#include <stdint.h>

#define NV_ABI_VERSION 3
#if defined(__GNUC__) || defined(__clang__)
#define NV_API __attribute__((visibility("default")))
#else
#define NV_API
#endif

typedef struct nv_index nv_index;
typedef struct nv_words nv_words;

NV_API int nv_abi_version(void);
NV_API const char *nv_version(void);

/* Fuzzy score of `pattern` against `text`: -1 = no match, otherwise >= 0
 * (higher is better). Smartcase: an uppercase letter makes the pattern
 * case-sensitive. */
NV_API int nv_fuzzy_score(const char *pattern, const char *text);

/* Build an index by walking `root`. `ignore_dirs` is a comma-separated list of
 * names skipped at any depth. Symlinked directories are never followed.
 * Stops after `max_files` entries (see nv_index_truncated). Paths are relative
 * to `root` and sorted. Returns NULL on allocation failure. */
NV_API nv_index *nv_index_scan(const char *root, const char *ignore_dirs,
                               int include_hidden, size_t max_files);

/* Build an index from newline-separated text (empty lines dropped, input order
 * kept). */
NV_API nv_index *nv_index_from_text(const char *text, size_t len);

NV_API void nv_index_free(nv_index *idx);
NV_API size_t nv_index_count(const nv_index *idx);
NV_API int nv_index_truncated(const nv_index *idx);

/* Item i (0-based) or NULL when out of range. Owned by the index. */
NV_API const char *nv_index_get(const nv_index *idx, size_t i);

/* Rank items against a whitespace-separated query (every term must match).
 * Writes up to `limit` item indices, best first, into `out`; returns the count.
 * An empty query returns the first `limit` items in index order. */
NV_API size_t nv_index_filter(const nv_index *idx, const char *query,
                              uint32_t *out, size_t limit);

/* ---- Words (buffer completion) ------------------------------------------ */

/* Distinct words of `text` in first-seen order, with occurrence counts. A word
 * is a run of ASCII letters/digits, '_' and bytes >= 128; runs starting with a
 * digit or shorter than `min_len` are skipped. Stops once `max_words` distinct
 * words are held (0 = no limit). Returns NULL on allocation failure. */
NV_API nv_words *nv_words_collect(const char *text, size_t len, size_t min_len,
                                  size_t max_words);
NV_API size_t nv_words_count(const nv_words *w);
/* Word i (NUL-terminated, owned by `w`) or NULL when out of range. */
NV_API const char *nv_words_get(const nv_words *w, size_t i);
NV_API uint32_t nv_words_occurrences(const nv_words *w, size_t i);
NV_API void nv_words_free(nv_words *w);

/* ---- Live grep ---------------------------------------------------------- */

/* Cancellation token: another thread may call nv_cancel_set while a search
 * using the token runs; the search then stops at its next check and reports
 * NV_GREP_CANCELLED. The token must outlive the search. */
typedef struct nv_cancel nv_cancel;

NV_API nv_cancel *nv_cancel_new(void);
NV_API void nv_cancel_set(nv_cancel *c);
NV_API void nv_cancel_free(nv_cancel *c);

typedef struct nv_grep nv_grep;

/* nv_grep_run flags */
#define NV_GREP_FIXED 1 /* the pattern is plain text, never a regex */

/* nv_grep_status bits */
#define NV_GREP_MORE 1      /* more matches exist than `limit` */
#define NV_GREP_CANCELLED 2 /* stopped by the cancel token; results are partial */
#define NV_GREP_LITERAL 4   /* pattern is not valid regex syntax: searched as text */

/* Search the files of `files` (paths relative to `root`, as built by
 * nv_index_scan) for `pattern` and collect up to `limit` matching lines, in
 * index order, at most one per line.
 *
 * The pattern is a regex unless NV_GREP_FIXED is set or it has no regex
 * syntax; the syntax is a small RE2-like subset (see grep.c), matched in
 * linear time. An invalid pattern is searched as literal text. Smartcase:
 * case-insensitive unless the pattern contains an uppercase ASCII letter.
 *
 * Files with a NUL byte, empty files and files larger than `max_file_bytes`
 * (0 = 1 MiB) are skipped. Each hit's text is the line with surrounding
 * blanks trimmed, cut to about `max_text` bytes (0 = 200). `cancel` may be
 * NULL. Thread-safe: `files` is only read, so several searches may share one
 * index. Large file lists are searched on several threads (online CPUs, at most 8;
 * the NV_GREP_THREADS environment variable overrides, 1 = one thread); the hits are
 * the same, and in the same order, whatever the thread count. Returns NULL only on
 * allocation failure; an empty or unusable
 * pattern gives an empty result. Free with nv_grep_free. */
NV_API nv_grep *nv_grep_run(const nv_index *files, const char *root, const char *pattern,
                            int flags, size_t limit, size_t max_file_bytes,
                            size_t max_text, const nv_cancel *cancel);

NV_API void nv_grep_free(nv_grep *g);
NV_API size_t nv_grep_count(const nv_grep *g);
NV_API int nv_grep_status(const nv_grep *g);

/* Hit i (0-based); NULL / 0 when out of range. Strings are owned by `g`.
 * `line` and `col` are 1-based; `col` is the byte column of the match start
 * in the original line (not in the trimmed text). */
NV_API const char *nv_grep_path(const nv_grep *g, size_t i);
NV_API const char *nv_grep_text(const nv_grep *g, size_t i);
NV_API uint32_t nv_grep_line(const nv_grep *g, size_t i);
NV_API uint32_t nv_grep_col(const nv_grep *g, size_t i);

#endif
