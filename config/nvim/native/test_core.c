#include "nvcore.h"
#include "internal.h"

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

/* The character-mask prefilter must never change results. */
static void test_filter_prefilter(void) {
  srand(7);
  char *text = malloc(64 * 1024);
  size_t len = 0;
  const char alpha[] = "abcdeABCDE/._-xyz09\xc3\xa9";
  for (int i = 0; i < 2000; i++) {
    int n = 1 + rand() % 24;
    for (int j = 0; j < n; j++)
      text[len++] = alpha[rand() % (int)(sizeof alpha - 1)];
    text[len++] = '\n';
  }
  nv_index *idx = nv_index_from_text(text, len);
  CHECK(idx && idx->masks && idx->lens);
  const char *queries[] = {"a", "ab", "AB", "a/b", "x y", "e\xc3\xa9", "zz9", "._", "dcba", "Abc d"};
  static uint32_t a[2000], b[2000];
  for (size_t q = 0; q < sizeof queries / sizeof *queries; q++) {
    size_t na = nv_index_filter(idx, queries[q], a, 2000);
    uint64_t *m = idx->masks;
    idx->masks = NULL; /* reference run without the prefilter */
    size_t nb = nv_index_filter(idx, queries[q], b, 2000);
    idx->masks = m;
    CHECK(na == nb && memcmp(a, b, na * sizeof *a) == 0);
  }
  nv_index_free(idx);
  free(text);
}

static void test_words(void) {
  const char *t = "foo bar_baz foo 12ab ab x_y foo caf\xc3\xa9 caf\xc3\xa9\n\tfoo+bar_baz";
  nv_words *w = nv_words_collect(t, strlen(t), 3, 0);
  CHECK(w && nv_words_count(w) == 4);
  CHECK(strcmp(nv_words_get(w, 0), "foo") == 0 && nv_words_occurrences(w, 0) == 4);
  CHECK(strcmp(nv_words_get(w, 1), "bar_baz") == 0 && nv_words_occurrences(w, 1) == 2);
  CHECK(strcmp(nv_words_get(w, 2), "x_y") == 0);
  CHECK(strcmp(nv_words_get(w, 3), "caf\xc3\xa9") == 0 && nv_words_occurrences(w, 3) == 2);
  CHECK(nv_words_get(w, 4) == NULL);
  nv_words_free(w);
  w = nv_words_collect(t, strlen(t), 3, 2); /* stops at two distinct words */
  CHECK(w && nv_words_count(w) == 2);
  nv_words_free(w);
  w = nv_words_collect("", 0, 3, 0);
  CHECK(w && nv_words_count(w) == 0);
  nv_words_free(w);
  /* many distinct words: table growth */
  char *big = malloc(400000);
  size_t len = 0;
  for (int i = 0; i < 30000; i++)
    len += (size_t)sprintf(big + len, "w%d_%d ", i, i % 7);
  w = nv_words_collect(big, len, 3, 0);
  CHECK(w && nv_words_count(w) == 30000);
  nv_words_free(w);
  free(big);
}

/* Threaded and sequential filtering must give the same answer. */
static void test_filter_threads(void) {
  srand(11);
  size_t cap = 4 << 20, len = 0;
  char *text = malloc(cap);
  const char alpha[] = "abcdefgABC/._-xyz019";
  for (int i = 0; i < 60000; i++) { /* above FILTER_PAR_MIN */
    int n = 3 + rand() % 30;
    for (int j = 0; j < n; j++)
      text[len++] = alpha[rand() % (int)(sizeof alpha - 1)];
    text[len++] = '\n';
  }
  nv_index *idx = nv_index_from_text(text, len);
  CHECK(idx && nv_index_count(idx) == 60000);
  const char *queries[] = {"a", "ab c", "zz", "AB", "x/y", "ge"};
  static uint32_t a[500], b[500];
  const size_t limits[] = {1, 50, 500};
  for (size_t q = 0; q < sizeof queries / sizeof *queries; q++) {
    for (size_t l = 0; l < 3; l++) {
      setenv("NV_FILTER_THREADS", "1", 1);
      size_t na = nv_index_filter(idx, queries[q], a, limits[l]);
      setenv("NV_FILTER_THREADS", "4", 1);
      size_t nb = nv_index_filter(idx, queries[q], b, limits[l]);
      CHECK(na == nb && memcmp(a, b, na * sizeof *a) == 0);
    }
  }
  unsetenv("NV_FILTER_THREADS");
  nv_index_free(idx);
  free(text);
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

/* ---- grep ---------------------------------------------------------------- */

#include "internal.h"

/* expect: start/end of the first match, -1/-1 = no match, -2/-2 = rejected */
static void check_re(const char *pat, const char *text, int es, int ee, int line) {
  size_t s = 0, e = 0;
  int r = nv_re_search(pat, text, strlen(text), &s, &e);
  int ok;
  if (es == -2)
    ok = (r == -1);
  else if (es == -1)
    ok = (r == 0);
  else
    ok = (r == 1 && (int)s == es && (int)e == ee);
  if (!ok) {
    fprintf(stderr, "FAIL %s:%d: /%s/ on \"%s\": got r=%d [%zu,%zu), want [%d,%d)\n", __FILE__,
            line, pat, text, r, s, e, es, ee);
    failures++;
  }
}
#define RE(pat, text, s, e) check_re(pat, text, s, e, __LINE__)

static void test_regex(void) {
  /* literals, classes, anchors */
  RE("abc", "xxabcxx", 2, 5);
  RE("a.c", "xabcx", 1, 4);
  RE("^abc", "abcabc", 0, 3);
  RE("abc$", "abcabc", 3, 6);
  RE("^$", "", 0, 0);
  RE("[a-c]+", "xxabcabx", 2, 7);
  RE("[^a-c]+", "abxyzc", 2, 5);
  RE("[]a]+", "x]a]", 1, 4);
  RE("[a\\]]+", "x]a]", 1, 4);
  RE("[\\d_]+", "ab_12c", 2, 5);
  RE("\\d+", "ab123c", 2, 5);
  RE("\\w+", "  foo_1 ", 2, 7);
  RE("\\W+", "ab, cd", 2, 4);
  RE("\\s+", "a \t b", 1, 4);
  /* repetition, leftmost-first and lazy */
  RE("a*", "baaa", 0, 0);
  RE("a+", "baaa", 1, 4);
  RE("a+?", "baaa", 1, 2);
  RE("a??b", "ab", 0, 2);
  RE("a{2}", "aaa", 0, 2);
  RE("a{2,}", "baaaa", 1, 5);
  RE("a{1,2}", "aaa", 0, 2);
  RE("a{1,2}?", "aaa", 0, 1);
  RE("(?:ab){2}", "ababab", 0, 4);
  RE("a|ab", "ab", 0, 1); /* leftmost-first, not longest */
  RE("ab|a", "ab", 0, 2);
  RE("(foo|bar)+", "xfoobarx", 1, 7);
  RE("(a*)*b", "aaac", -1, -1);
  RE("(a*)*b", "aaab", 0, 4);
  /* word boundaries */
  RE("\\bfoo\\b", "a foo b", 2, 5);
  RE("\\bfoo\\b", "afoob", -1, -1);
  RE("\\Boo", "foo", 1, 3);
  /* smartcase (ASCII) */
  RE("foo", "FOO", 0, 3);
  RE("Foo", "foo", -1, -1);
  RE("Foo", "xFoo", 1, 4);
  RE("[A-Z]+", "abcDEF", 3, 6);
  RE("\\D+", "ABC", 0, 3); /* an escape is not an uppercase letter */
  /* UTF-8: '.' and negated classes take whole code points */
  RE("caf.$", "caf\xc3\xa9", 0, 5);
  RE("^.{4}$", "caf\xc3\xa9", 0, 5);
  RE("^.{5}$", "caf\xc3\xa9", -1, -1);
  RE("[^a]", "\xc3\xa9", 0, 2);
  RE("\xc3\xa9+", "x\xc3\xa9\xc3\xa9", 1, 5);
  RE("\\B", "b\xc3\xa9", 2 + 1, 3); /* never inside a character: only at the end */
  /* '{' that is not a quantifier is a plain character */
  RE("{", "a{b", 1, 2);
  RE("a{,3}", "a{,3}", 0, 5);
  RE("a{2", "a{2", 0, 3);
  RE("}", "}", 0, 1);
  RE("]", "]", 0, 1);
  RE("\\(", "f(x", 1, 2);
  /* rejected: the caller searches these as plain text */
  RE("foo(", "foo(", -2, -2);
  RE("a)", "a", -2, -2);
  RE("*a", "a", -2, -2);
  RE("a**", "a", -2, -2);
  RE("[abc", "a", -2, -2);
  RE("(?i)a", "a", -2, -2);
  RE("(?=a)a", "a", -2, -2);
  RE("\\1", "a", -2, -2);
  RE("[[:alpha:]]", "a", -2, -2);
  RE("[\xc3\xa9]", "\xc3\xa9", -2, -2);
  RE("a{3,2}", "aaa", -2, -2);
  RE("x{1001}", "x", -2, -2);
  RE("(((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((((a)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))", "a", -2, -2); /* nesting limit */
  /* linear time: these never finish on a backtracking engine */
  {
    char text[5002];
    memset(text, 'a', 5000);
    text[5000] = 'c';
    text[5001] = '\0';
    RE("(a*)*b", text, -1, -1);
    RE("(a|aa)+$", text, -1, -1);
    char a200[201];
    memset(a200, 'a', 200);
    a200[200] = '\0';
    RE("(a?){200}a{200}", a200, 0, 200);
  }
}

static void write_file(const char *root, const char *rel, const char *data, size_t len) {
  char p[1024];
  snprintf(p, sizeof p, "%s/%s", root, rel);
  FILE *f = fopen(p, "wb");
  if (f) {
    fwrite(data, 1, len, f);
    fclose(f);
  }
}
#define WRITE(root, rel, str) write_file(root, rel, str, strlen(str))

static const char *const GREP_FILES[] = {"a.txt", "b.c", "crlf.txt", "empty.txt", "bin.dat",
                                         "big.txt", "long.txt", "sub/c.txt", "z.txt"};
static const char *const GREP_DIRS[] = {"sub"};

static void grep_cleanup(const char *root) {
  char p[1024];
  for (size_t i = 0; i < sizeof GREP_FILES / sizeof *GREP_FILES; i++) {
    snprintf(p, sizeof p, "%s/%s", root, GREP_FILES[i]);
    unlink(p);
  }
  for (size_t i = 0; i < sizeof GREP_DIRS / sizeof *GREP_DIRS; i++) {
    snprintf(p, sizeof p, "%s/%s", root, GREP_DIRS[i]);
    rmdir(p);
  }
  rmdir(root);
}

/* Hit i as "path:line:col:text". */
static const char *fmt_hit(const nv_grep *g, size_t i) {
  static char buf[8][512];
  static int k;
  char *b = buf[k++ & 7];
  snprintf(b, 512, "%s:%u:%u:%s", nv_grep_path(g, i), nv_grep_line(g, i), nv_grep_col(g, i),
           nv_grep_text(g, i));
  return b;
}

static void test_grep(void) {
  char root[512];
  if (!make_root(root, sizeof root)) {
    CHECK(!"cannot create temp dir (set TMPDIR to a writable directory)");
    return;
  }
  char p[1024];
  snprintf(p, sizeof p, "%s/sub", root);
  mkdir(p, 0755);

  WRITE(root, "a.txt", "hello world\n  foo bar\nHello again\nlast foo"); /* no final newline */
  WRITE(root, "b.c", "int main() {\n\treturn 0;\n}\n");
  WRITE(root, "crlf.txt", "alpha\r\nbeta\r\n");
  WRITE(root, "empty.txt", "");
  write_file(root, "bin.dat", "foo\0foo\n", 8); /* binary: skipped */
  {
    char big[3000];
    memset(big, 'x', sizeof big);
    memcpy(big, "foo", 3);
    big[2999] = '\n';
    write_file(root, "big.txt", big, sizeof big); /* over the size cap below */
  }
  {
    char line[400];
    memset(line, '.', sizeof line - 1);
    line[sizeof line - 1] = '\0';
    memcpy(line + 300, "NEEDLE", 6);
    WRITE(root, "long.txt", line);
  }
  WRITE(root, "sub/c.txt", "one\nfoo two\n\xc3\xa9 foo\n");
  WRITE(root, "z.txt", "foo\nfoo\nfoo\nfoo\n");

  nv_index *idx = nv_index_scan(root, "", 1, 0);
  CHECK(idx && nv_index_count(idx) == 9);
  nv_grep *g;

  /* literal, smartcase insensitive; order is index order, then line order */
  g = nv_grep_run(idx, root, "hello", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 2);
  CHECK(g && strcmp(fmt_hit(g, 0), "a.txt:1:1:hello world") == 0);
  CHECK(g && strcmp(fmt_hit(g, 1), "a.txt:3:1:Hello again") == 0);
  CHECK(g && nv_grep_status(g) == 0);
  nv_grep_free(g);

  /* an uppercase letter makes it case-sensitive */
  g = nv_grep_run(idx, root, "Hello", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 1 && nv_grep_line(g, 0) == 3);
  nv_grep_free(g);

  /* leading blanks are trimmed from the text but not from the column; a final
   * line without a newline is searched; the binary and the oversized file are not */
  g = nv_grep_run(idx, root, "foo", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 8);
  CHECK(g && strcmp(fmt_hit(g, 0), "a.txt:2:3:foo bar") == 0);
  CHECK(g && strcmp(fmt_hit(g, 1), "a.txt:4:6:last foo") == 0);
  CHECK(g && strcmp(fmt_hit(g, 2), "sub/c.txt:2:1:foo two") == 0);
  CHECK(g && strcmp(fmt_hit(g, 3), "sub/c.txt:3:4:\xc3\xa9 foo") == 0); /* byte column */
  CHECK(g && strcmp(nv_grep_path(g, 4), "z.txt") == 0 && nv_grep_line(g, 7) == 4);
  nv_grep_free(g);

  /* limit: exactly `limit` hits plus the MORE flag */
  g = nv_grep_run(idx, root, "foo", 0, 5, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 5 && (nv_grep_status(g) & NV_GREP_MORE));
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "foo", 0, 8, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 8 && !(nv_grep_status(g) & NV_GREP_MORE));
  nv_grep_free(g);

  /* regex */
  g = nv_grep_run(idx, root, "^\\s*return \\d+;", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 1 && strcmp(fmt_hit(g, 0), "b.c:2:1:return 0;") == 0);
  nv_grep_free(g);
  /* the longest plain run ("retu", "n 0;") pre-filters lines; results must not change */
  g = nv_grep_run(idx, root, "retu.n 0;", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 1 && nv_grep_line(g, 0) == 2);
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "RETU.n 0;", 0, 50, 2000, 0, NULL); /* uppercase: case-sensitive */
  CHECK(g && nv_grep_count(g) == 0);
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "a$", 0, 50, 2000, 0, NULL); /* CRLF: "$" sits before the CR */
  CHECK(g && nv_grep_count(g) == 2); /* alpha, beta */
  CHECK(g && strcmp(nv_grep_path(g, 0), "crlf.txt") == 0 && strcmp(nv_grep_text(g, 0), "alpha") == 0);
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "fo+ (bar|two)", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 2);
  nv_grep_free(g);

  /* invalid regex: searched as text and flagged; FIXED never compiles */
  g = nv_grep_run(idx, root, "main(", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 1 && (nv_grep_status(g) & NV_GREP_LITERAL));
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "main() {", 0, 50, 2000, 0, NULL); /* valid regex: "()" is an empty group */
  CHECK(g && nv_grep_count(g) == 0 && !(nv_grep_status(g) & NV_GREP_LITERAL));
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "main() {", NV_GREP_FIXED, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 1 && strcmp(fmt_hit(g, 0), "b.c:1:5:int main() {") == 0);
  nv_grep_free(g);

  /* a match far into a long line is shown in a window, column stays exact */
  g = nv_grep_run(idx, root, "NEEDLE", 0, 50, 2000, 100, NULL);
  CHECK(g && nv_grep_count(g) == 1 && nv_grep_col(g, 0) == 301);
  CHECK(g && strncmp(nv_grep_text(g, 0), "...", 3) == 0 && strstr(nv_grep_text(g, 0), "NEEDLE"));
  CHECK(g && strlen(nv_grep_text(g, 0)) <= 103);
  nv_grep_free(g);

  /* nothing to search for, or nothing that can match */
  g = nv_grep_run(idx, root, "", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 0);
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "a\nb", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 0);
  nv_grep_free(g);
  g = nv_grep_run(idx, root, "no such text", 0, 50, 2000, 0, NULL);
  CHECK(g && nv_grep_count(g) == 0 && nv_grep_status(g) == 0);
  nv_grep_free(g);
  CHECK(nv_grep_path(NULL, 0) == NULL && nv_grep_count(NULL) == 0);

  /* cancellation */
  nv_cancel *c = nv_cancel_new();
  CHECK(c != NULL);
  nv_cancel_set(c);
  g = nv_grep_run(idx, root, "foo", 0, 50, 2000, 0, c);
  CHECK(g && nv_grep_count(g) == 0 && (nv_grep_status(g) & NV_GREP_CANCELLED));
  nv_grep_free(g);
  nv_cancel_free(c);

  nv_index_free(idx);
  grep_cleanup(root);
}

/* The same search on 1 and on several threads must give the same hits, in the same order,
 * whatever the limit (the parallel search merges per-chunk results). */
static void test_grep_threads(void) {
  enum { NFILES = 300 };
  char root[512];
  if (!make_root(root, sizeof root)) {
    CHECK(!"cannot create temp dir (set TMPDIR to a writable directory)");
    return;
  }
  static char names[NFILES][32];
  char text[256], list[NFILES * 32], p[1024];
  size_t lp = 0;
  for (int i = 0; i < NFILES; i++) {
    snprintf(names[i], sizeof names[i], "f%03d.txt", i);
    snprintf(text, sizeof text, "alpha %d\nneedle %d here\n%s\nneedle again\n", i,
             i, i % 7 == 0 ? "no match" : "needle tail");
    write_file(root, names[i], text, strlen(text));
    lp += (size_t)snprintf(list + lp, sizeof list - lp, "%s\n", names[i]);
  }
  nv_index *idx = nv_index_from_text(list, lp);
  CHECK(idx != NULL);
  static const size_t limits[] = {1, 7, 100, 5000};
  static const char *const pats[] = {"needle", "need.e \\d+", "zzz"};
  for (size_t pi = 0; pi < sizeof pats / sizeof *pats; pi++) {
    for (size_t li = 0; li < sizeof limits / sizeof *limits; li++) {
      char one[1 << 16] = "", many[1 << 16] = "";
      for (int pass = 0; pass < 2; pass++) {
        setenv("NV_GREP_THREADS", pass ? "4" : "1", 1);
        nv_grep *g = nv_grep_run(idx, root, pats[pi], 0, limits[li], 0, 0, NULL);
        CHECK(g != NULL);
        char *out = pass ? many : one;
        size_t o = (size_t)snprintf(out, 1 << 16, "n=%zu st=%d\n", g ? nv_grep_count(g) : 0,
                                    g ? nv_grep_status(g) : -1);
        for (size_t k = 0; g && k < nv_grep_count(g) && o < (1 << 16) - 128; k++)
          o += (size_t)snprintf(out + o, (1 << 16) - o, "%s:%u:%u\n", nv_grep_path(g, k),
                                nv_grep_line(g, k), nv_grep_col(g, k));
        nv_grep_free(g);
      }
      CHECK(strcmp(one, many) == 0);
    }
  }
  unsetenv("NV_GREP_THREADS");
  nv_index_free(idx);
  for (int i = 0; i < NFILES; i++) {
    snprintf(p, sizeof p, "%s/%s", root, names[i]);
    unlink(p);
  }
  rmdir(root);
}

int main(void) {
  CHECK(nv_abi_version() == NV_ABI_VERSION);
  test_fuzzy();
  test_filter();
  test_filter_prefilter();
  test_words();
  test_filter_threads();
  test_scan();
  test_regex();
  test_grep();
  test_grep_threads();
  if (failures) {
    fprintf(stderr, "%d check(s) failed\n", failures);
    return 1;
  }
  printf("nvcore %s: all tests passed\n", nv_version());
  return 0;
}
