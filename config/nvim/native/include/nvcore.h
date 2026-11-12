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

#define NV_ABI_VERSION 1
#define NV_API __attribute__((visibility("default")))

typedef struct nv_index nv_index;

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

#endif
