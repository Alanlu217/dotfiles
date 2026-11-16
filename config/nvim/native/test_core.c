#include "nvcore.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
#define CHECK(cond)                                                            \
  do {                                                                         \
    if (!(cond)) {                                                             \
      fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
      failures++;                                                              \
    }                                                                          \
  } while (0)

static void touch(const char *dir, const char *rel) {
  char p[1024];
  snprintf(p, sizeof p, "%s/%s", dir, rel);
  FILE *f = fopen(p, "w");
  if (f)
    fclose(f);
}

static void test_fuzzy(void) {
  /* Classification is ASCII-only: UTF-8 bytes are ordinary non-word bytes and
   * must not change with the process locale or libc. */
  CHECK(nv_fuzzy_score("caf\xc3\xa9", "src/caf\xc3\xa9.lua") >= 0);
  CHECK(nv_fuzzy_score("FOO", "foo") == -1); /* smartcase: uppercase is exact */
  CHECK(nv_fuzzy_score("foo", "FOO") >= 0);
  CHECK(nv_fuzzy_score("", "anything") == 0);
  CHECK(nv_fuzzy_score("abc", "ab") == -1);
  CHECK(nv_fuzzy_score("xyz", "lua/core/ffi.lua") == -1);
  CHECK(nv_fuzzy_score("ffi", "lua/core/ffi.lua") >= 0);
  CHECK(nv_fuzzy_score("ffi", "README.md") == -1);
  /* smartcase */
  CHECK(nv_fuzzy_score("readme", "README.md") >= 0);
  CHECK(nv_fuzzy_score("Readme", "README.md") == -1);
  /* tight basename match beats scattered match */
  CHECK(nv_fuzzy_score("picker", "lua/core/picker.lua") >
        nv_fuzzy_score("picker", "p/i/c/k/e/r/x.lua"));
}

static void test_filter(void) {
  const char *text =
      "src/main.c\nsrc/fuzzy.c\nREADME.md\n\nlua/core/picker.lua\n";
  nv_index *idx = nv_index_from_text(text, strlen(text));
  CHECK(idx && nv_index_count(idx) == 4);
  uint32_t out[8];
  CHECK(nv_index_filter(idx, "", out, 8) == 4);
  CHECK(nv_index_filter(idx, "", out, 2) == 2);
  CHECK(nv_index_filter(idx, "zzz", out, 8) == 0);
  size_t n = nv_index_filter(idx, "pick", out, 8);
  CHECK(n == 1 &&
        strcmp(nv_index_get(idx, out[0]), "lua/core/picker.lua") == 0);
  n = nv_index_filter(idx, "src c", out, 8); /* AND of terms */
  CHECK(n == 2);
  CHECK(nv_index_get(idx, 99) == NULL);
  nv_index_free(idx);
}

/* Fixture paths, relative to the temp root; removed by cleanup (children first). */
static const char *const FILES[] = {"a.txt", ".hidden", "sub/b.txt", ".git/config", "target/junk.o", "loop"};
static const char *const DIRS[] = {"sub", ".git", "target"};

/* Create a fresh temp dir under $TMPDIR (Termux has no /tmp), else /tmp. */
static int make_root(char *out, size_t cap) {
  const char *base = getenv("TMPDIR");
  if (!base || !*base)
    base = "/tmp";
  int n = snprintf(out, cap, "%s/nvcore-test-XXXXXX", base);
  return n > 0 && (size_t)n < cap && mkdtemp(out) != NULL;
}

static void cleanup(const char *root) {
  char p[1024];
  for (size_t i = 0; i < sizeof FILES / sizeof *FILES; i++) {
    snprintf(p, sizeof p, "%s/%s", root, FILES[i]);
    unlink(p);
  }
  for (size_t i = 0; i < sizeof DIRS / sizeof *DIRS; i++) {
    snprintf(p, sizeof p, "%s/%s", root, DIRS[i]);
    rmdir(p);
  }
  rmdir(root);
}

static void test_scan(void) {
  char root[512];
  if (!make_root(root, sizeof root)) {
    CHECK(!"cannot create temp dir (set TMPDIR to a writable directory)");
    return;
  }
  char p[1024];
  snprintf(p, sizeof p, "%s/sub", root);
  mkdir(p, 0755);
  snprintf(p, sizeof p, "%s/.git", root);
  mkdir(p, 0755);
  snprintf(p, sizeof p, "%s/target", root);
  mkdir(p, 0755);
  touch(root, "a.txt");
  touch(root, ".hidden");
  touch(root, "sub/b.txt");
  touch(root, ".git/config");
  touch(root, "target/junk.o");
  snprintf(p, sizeof p, "%s/loop", root);
  CHECK(symlink(".", p) == 0); /* directory symlink loop must not recurse */

  nv_index *idx = nv_index_scan(root, ".git,target", 1, 0);
  CHECK(idx && nv_index_count(idx) == 3); /* .hidden a.txt sub/b.txt */
  CHECK(idx && strcmp(nv_index_get(idx, 0), ".hidden") == 0);
  nv_index_free(idx);

  idx = nv_index_scan(root, ".git,target", 0, 0);
  CHECK(idx && nv_index_count(idx) == 2);
  nv_index_free(idx);

  idx = nv_index_scan(root, ".git,target", 1, 1);
  CHECK(idx && nv_index_truncated(idx) && nv_index_count(idx) == 1);
  nv_index_free(idx);

  cleanup(root);
}

int main(void) {
  CHECK(nv_abi_version() == NV_ABI_VERSION);
  test_fuzzy();
  test_filter();
  test_scan();
  if (failures) {
    fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  printf("nvcore %s: all tests passed\n", nv_version());
  return 0;
}
