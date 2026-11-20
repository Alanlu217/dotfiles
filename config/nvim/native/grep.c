/*
 * Live grep: search the files of an nv_index for a pattern and collect the
 * first matching lines.
 *
 * Matching is self-contained (no libc regex, so results do not depend on the
 * libc or the process locale; the same rule as fuzzy.c):
 *
 *   - Literal patterns use a memchr-driven substring search over the whole
 *     file buffer; lines are only located around a hit.
 *   - Patterns with regex syntax are compiled to a small program and run on a
 *     Pike VM: time is O(line length x program size) with no backtracking, so
 *     no pattern can blow up. Supported: literals, . [] [^] ^ $ \b \B \d \w \s
 *     (and \D \W \S), * + ? {m} {m,} {m,n} (each with a lazy ? form), |, and
 *     (...) / (?:...) groups (never capturing). `.` and negated classes match
 *     whole UTF-8 code points; class members are ASCII only. A pattern that
 *     does not compile (e.g. one still being typed, like "foo(") is searched
 *     as a literal instead and flagged with NV_GREP_LITERAL.
 *   - Smartcase, ASCII only: an uppercase letter in the pattern makes the
 *     search case-sensitive; otherwise it is case-insensitive.
 *
 * Files with a NUL byte, empty files and files over the size cap are skipped.
 * At most one hit per line is reported.
 */
#include "internal.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __STDC_NO_ATOMICS__
#define NV_NO_ATOMICS 1
#else
#include <stdatomic.h>
#endif

/* ---- cancellation -------------------------------------------------------- */

struct nv_cancel {
#ifdef NV_NO_ATOMICS
  volatile int flag;
#else
  atomic_int flag;
#endif
};

NV_API nv_cancel *nv_cancel_new(void) {
  struct nv_cancel *c = malloc(sizeof *c);
  if (!c)
    return NULL;
#ifdef NV_NO_ATOMICS
  c->flag = 0;
#else
  atomic_init(&c->flag, 0);
#endif
  return c;
}

NV_API void nv_cancel_set(nv_cancel *c) {
  if (!c)
    return;
#ifdef NV_NO_ATOMICS
  c->flag = 1;
#else
  atomic_store_explicit(&c->flag, 1, memory_order_relaxed);
#endif
}

NV_API void nv_cancel_free(nv_cancel *c) { free(c); }

static int is_cancelled(const nv_cancel *c) {
  if (!c)
    return 0;
#ifdef NV_NO_ATOMICS
  return c->flag != 0;
#else
  return atomic_load_explicit(&c->flag, memory_order_relaxed) != 0;
#endif
}

/* ---- ASCII helpers (locale independent) ---------------------------------- */

static unsigned char lower_of(unsigned char c) {
  return (c >= 'A' && c <= 'Z') ? (unsigned char)(c + 32) : c;
}
static unsigned char upper_of(unsigned char c) {
  return (c >= 'a' && c <= 'z') ? (unsigned char)(c - 32) : c;
}
static int is_word(unsigned char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '_';
}

static void set_add(uint8_t *set, unsigned c) {
  set[c >> 3] = (uint8_t)(set[c >> 3] | (1u << (c & 7)));
}
static int set_has(const uint8_t *set, unsigned c) {
  return (set[c >> 3] >> (c & 7)) & 1;
}
static void set_range(uint8_t *set, unsigned lo, unsigned hi) {
  for (unsigned c = lo; c <= hi; c++)
    set_add(set, c);
}

/* ---- regex: syntax tree -------------------------------------------------- */

enum { N_EMPTY, N_CHAR, N_CLASS, N_BOL, N_EOL, N_WB, N_NWB, N_CAT, N_ALT, N_REP };

enum {
  MAX_PROG = 12000,    /* instructions */
  MAX_REP = 1000,      /* largest {m,n} bound */
  MAX_DEPTH = 64,      /* group nesting */
  MAX_RE_PATTERN = 512 /* longer patterns are searched as literals */
};

typedef struct {
  int kind;
  int c;        /* N_CHAR: the byte */
  int a, b;     /* N_CAT: first item; N_ALT: left, right; N_REP: body */
  int next;     /* next item of a N_CAT list, or -1 */
  int min, max; /* N_REP; max == -1 is unbounded */
  int greedy;
  int neg;      /* N_CLASS: the member set is negated */
  int utf8;     /* N_CLASS: also matches every non-ASCII code point */
  uint8_t set[32]; /* N_CLASS: ASCII members, before case folding / negation */
} node;

typedef struct {
  const char *s;
  size_t n, i;
  node *nodes;
  int nn, cap;
  int err;
  int has_upper; /* an uppercase letter appears as a literal or class member */
} parser;

static int pnew(parser *P, int kind) {
  if (P->nn == P->cap) {
    int cap = P->cap * 2;
    node *grown = realloc(P->nodes, (size_t)cap * sizeof *grown);
    if (!grown) {
      P->err = 1;
      return 0; /* node 0 is a dummy, so callers may keep going until they check err */
    }
    P->nodes = grown;
    P->cap = cap;
  }
  int id = P->nn++;
  node *nd = &P->nodes[id];
  memset(nd, 0, sizeof *nd);
  nd->kind = kind;
  nd->a = nd->b = nd->next = -1;
  nd->greedy = 1;
  nd->max = 1;
  nd->min = 1;
  return id;
}

static int utf8_seq_len(const unsigned char *s, size_t avail) {
  unsigned char c = s[0];
  size_t need = (c >= 0xf0 && c <= 0xf4)   ? 4
                : (c >= 0xe0 && c <= 0xef) ? 3
                : (c >= 0xc2 && c <= 0xdf) ? 2
                                           : 1;
  if (need > avail)
    return 1;
  for (size_t k = 1; k < need; k++)
    if ((s[k] & 0xc0) != 0x80)
      return 1;
  return (int)need;
}

/* A literal character: one node, or for a multi-byte UTF-8 character a
 * concatenation of its bytes (so a following quantifier applies to all of it). */
static int parse_literal(parser *P) {
  const unsigned char *s = (const unsigned char *)P->s + P->i;
  int len = utf8_seq_len(s, P->n - P->i);
  if (s[0] >= 'A' && s[0] <= 'Z')
    P->has_upper = 1;
  int first = -1, last = -1;
  for (int k = 0; k < len; k++) {
    int ch = pnew(P, N_CHAR);
    P->nodes[ch].c = s[k];
    if (first < 0)
      first = ch;
    else
      P->nodes[last].next = ch;
    last = ch;
  }
  P->i += (size_t)len;
  if (len == 1)
    return first;
  int cat = pnew(P, N_CAT);
  P->nodes[cat].a = first;
  return cat;
}

/* Members of \d \w \s (ASCII). `upper` selects the negated forms. */
static int shorthand_set(unsigned char k, uint8_t set[32], int *negated) {
  unsigned char lo = lower_of(k);
  memset(set, 0, 32);
  *negated = (k >= 'A' && k <= 'Z');
  switch (lo) {
  case 'd':
    set_range(set, '0', '9');
    return 1;
  case 'w':
    set_range(set, 'a', 'z');
    set_range(set, 'A', 'Z');
    set_range(set, '0', '9');
    set_add(set, '_');
    return 1;
  case 's':
    set_add(set, ' ');
    set_range(set, '\t', '\r'); /* \t \n \v \f \r */
    return 1;
  default:
    return 0;
  }
}

/* The byte an escape like \t or \. stands for; -1 when it is not a plain
 * single-character escape. */
static int escape_byte(unsigned char k) {
  switch (k) {
  case 't':
    return '\t';
  case 'r':
    return '\r';
  case 'f':
    return '\f';
  case 'v':
    return '\v';
  default:
    break;
  }
  if (k < 0x80 && !((k >= 'a' && k <= 'z') || (k >= 'A' && k <= 'Z') ||
                    (k >= '0' && k <= '9')))
    return k; /* escaped punctuation */
  return -1;
}

static int parse_class(parser *P) {
  P->i++; /* '[' */
  int id = pnew(P, N_CLASS);
  if (P->err)
    return 0;
  uint8_t set[32];
  memset(set, 0, sizeof set);
  int neg = 0, nonascii = 0, first = 1;
  if (P->i < P->n && P->s[P->i] == '^') {
    neg = 1;
    P->i++;
  }
  for (;;) {
    if (P->i >= P->n) {
      P->err = 1; /* unterminated */
      return 0;
    }
    unsigned char c = (unsigned char)P->s[P->i];
    if (c == ']' && !first) {
      P->i++;
      break;
    }
    first = 0;
    if (c >= 0x80 || (c == '[' && P->i + 1 < P->n && P->s[P->i + 1] == ':')) {
      P->err = 1; /* non-ASCII members and [:posix:] classes are not supported */
      return 0;
    }

    int lo;
    if (c == '\\') {
      if (P->i + 1 >= P->n) {
        P->err = 1;
        return 0;
      }
      unsigned char k = (unsigned char)P->s[P->i + 1];
      uint8_t sh[32];
      int sneg;
      if (shorthand_set(k, sh, &sneg)) {
        P->i += 2;
        for (int b = 0; b < 32; b++) {
          if (sneg) {
            /* complement within ASCII; everything non-ASCII matches too */
            uint8_t comp = (b < 16) ? (uint8_t)~sh[b] : 0;
            set[b] = (uint8_t)(set[b] | comp);
          } else {
            set[b] = (uint8_t)(set[b] | sh[b]);
          }
        }
        if (sneg)
          nonascii = 1;
        continue;
      }
      lo = escape_byte(k);
      if (lo < 0) {
        P->err = 1;
        return 0;
      }
      P->i += 2;
    } else {
      lo = c;
      P->i++;
    }

    int hi = lo;
    if (P->i + 1 < P->n && P->s[P->i] == '-' && P->s[P->i + 1] != ']') {
      unsigned char h = (unsigned char)P->s[P->i + 1];
      if (h >= 0x80) {
        P->err = 1;
        return 0;
      }
      if (h == '\\') {
        if (P->i + 2 >= P->n) {
          P->err = 1;
          return 0;
        }
        hi = escape_byte((unsigned char)P->s[P->i + 2]);
        if (hi < 0) { /* a shorthand cannot end a range */
          P->err = 1;
          return 0;
        }
        P->i += 3;
      } else {
        hi = h;
        P->i += 2;
      }
      if (hi < lo) {
        P->err = 1;
        return 0;
      }
    }
    set_range(set, (unsigned)lo, (unsigned)hi);
    if (lo <= 'Z' && hi >= 'A')
      P->has_upper = 1;
  }
  node *nd = &P->nodes[id];
  memcpy(nd->set, set, sizeof set);
  nd->neg = neg;
  nd->utf8 = neg ? !nonascii : nonascii;
  return id;
}

static int parse_alt(parser *P, int depth);

static int parse_escape(parser *P) {
  if (P->i + 1 >= P->n) {
    P->err = 1;
    return 0;
  }
  unsigned char k = (unsigned char)P->s[P->i + 1];
  uint8_t set[32];
  int neg;
  if (shorthand_set(k, set, &neg)) {
    P->i += 2;
    int id = pnew(P, N_CLASS);
    memcpy(P->nodes[id].set, set, sizeof set);
    P->nodes[id].neg = neg;
    P->nodes[id].utf8 = neg;
    return id;
  }
  if (k == 'b' || k == 'B') {
    P->i += 2;
    return pnew(P, k == 'b' ? N_WB : N_NWB);
  }
  int b = escape_byte(k);
  if (b >= 0) {
    P->i += 2;
    int id = pnew(P, N_CHAR);
    P->nodes[id].c = b;
    return id;
  }
  if (k >= 0x80) { /* escaped non-ASCII character: just that character */
    P->i++;
    return parse_literal(P);
  }
  P->err = 1; /* unknown escape (\1, \x.., \A, ...) */
  return 0;
}

static int parse_atom(parser *P, int depth) {
  unsigned char c = (unsigned char)P->s[P->i];
  int id;
  switch (c) {
  case '(': {
    if (depth >= MAX_DEPTH) {
      P->err = 1;
      return 0;
    }
    P->i++;
    if (P->i < P->n && P->s[P->i] == '?') {
      if (P->i + 1 < P->n && P->s[P->i + 1] == ':') {
        P->i += 2;
      } else {
        P->err = 1; /* lookaround, flags, named groups: unsupported */
        return 0;
      }
    }
    id = parse_alt(P, depth + 1);
    if (P->err)
      return 0;
    if (P->i >= P->n || P->s[P->i] != ')') {
      P->err = 1;
      return 0;
    }
    P->i++;
    return id;
  }
  case ')':
  case '*':
  case '+':
  case '?':
    P->err = 1; /* unmatched ')' or nothing to repeat */
    return 0;
  case '[':
    return parse_class(P);
  case '.':
    P->i++;
    id = pnew(P, N_CLASS);
    P->nodes[id].neg = 1; /* not-nothing: every code point */
    P->nodes[id].utf8 = 1;
    return id;
  case '^':
    P->i++;
    return pnew(P, N_BOL);
  case '$':
    P->i++;
    return pnew(P, N_EOL);
  case '\\':
    return parse_escape(P);
  default:
    return parse_literal(P); /* includes a '{' that is not a quantifier */
  }
}

/* "{m}", "{m,}" or "{m,n}" at P->i. Returns 1 and consumes it when it is a
 * quantifier; 0 (nothing consumed) when the brace is a plain character. */
static int parse_braces(parser *P, int *mn, int *mx) {
  size_t i = P->i + 1;
  long lo = 0, hi = -1;
  size_t digits = 0;
  while (i < P->n && P->s[i] >= '0' && P->s[i] <= '9' && lo <= MAX_REP + 1) {
    lo = lo * 10 + (P->s[i] - '0');
    i++;
    digits++;
  }
  if (digits == 0)
    return 0;
  if (i < P->n && P->s[i] == ',') {
    i++;
    size_t hd = 0;
    hi = 0;
    while (i < P->n && P->s[i] >= '0' && P->s[i] <= '9' && hi <= MAX_REP + 1) {
      hi = hi * 10 + (P->s[i] - '0');
      i++;
      hd++;
    }
    if (hd == 0)
      hi = -1; /* {m,} */
  } else {
    hi = lo; /* {m} */
  }
  if (i >= P->n || P->s[i] != '}')
    return 0;
  P->i = i + 1;
  if (lo > MAX_REP || hi > MAX_REP || (hi >= 0 && hi < lo)) {
    P->err = 1;
    return 1;
  }
  *mn = (int)lo;
  *mx = (int)hi;
  return 1;
}

static int parse_rep(parser *P, int depth) {
  int atom = parse_atom(P, depth);
  if (P->err || P->i >= P->n)
    return atom;
  int mn, mx;
  unsigned char c = (unsigned char)P->s[P->i];
  if (c == '*') {
    mn = 0, mx = -1;
    P->i++;
  } else if (c == '+') {
    mn = 1, mx = -1;
    P->i++;
  } else if (c == '?') {
    mn = 0, mx = 1;
    P->i++;
  } else if (c == '{') {
    if (!parse_braces(P, &mn, &mx))
      return atom;
    if (P->err)
      return 0;
  } else {
    return atom;
  }
  int greedy = 1;
  if (P->i < P->n && P->s[P->i] == '?') {
    greedy = 0;
    P->i++;
  }
  if (P->i < P->n && (P->s[P->i] == '*' || P->s[P->i] == '+' || P->s[P->i] == '?')) {
    P->err = 1; /* a** and friends */
    return 0;
  }
  int rep = pnew(P, N_REP);
  if (P->err)
    return 0;
  node *nd = &P->nodes[rep];
  nd->a = atom;
  nd->min = mn;
  nd->max = mx;
  nd->greedy = greedy;
  return rep;
}

static int parse_cat(parser *P, int depth) {
  int first = -1, last = -1;
  while (!P->err && P->i < P->n && P->s[P->i] != '|' &&
         !(P->s[P->i] == ')' && depth > 0)) {
    int item = parse_rep(P, depth);
    if (P->err)
      return 0;
    if (first < 0)
      first = item;
    else
      P->nodes[last].next = item;
    last = item;
  }
  if (P->err)
    return 0;
  if (first < 0)
    return pnew(P, N_EMPTY);
  if (first == last)
    return first;
  int cat = pnew(P, N_CAT);
  P->nodes[cat].a = first;
  return cat;
}

static int parse_alt(parser *P, int depth) {
  int left = parse_cat(P, depth);
  if (P->err)
    return 0;
  if (P->i < P->n && P->s[P->i] == '|') {
    P->i++;
    int right = parse_alt(P, depth);
    if (P->err)
      return 0;
    int alt = pnew(P, N_ALT);
    P->nodes[alt].a = left;
    P->nodes[alt].b = right;
    return alt;
  }
  return left;
}

/* ---- regex: program ------------------------------------------------------ */

enum { OP_CHAR, OP_CLASS, OP_SPLIT, OP_JMP, OP_BOL, OP_EOL, OP_WB, OP_NWB, OP_MATCH };

typedef struct {
  uint8_t op;
  uint8_t c;
  int x, y; /* OP_CLASS: x = set; OP_JMP: x = target; OP_SPLIT: x preferred, y */
} inst;

typedef struct {
  inst *code;
  int n, cap;
  uint8_t (*sets)[32];
  int nsets, setcap;
  uint8_t first[256]; /* bytes a match can start with (when !nullable) */
  int nullable;       /* may match without consuming input, or ends in assertions */
  int icase;
  int err;
  inst dummy;   /* written instead of out-of-range code once err is set */
  int shared[4]; /* lazily created UTF-8 lead2/lead3/lead4/continuation sets */
} re_prog;

static inst *at(re_prog *C, int pc) { return C->err ? &C->dummy : &C->code[pc]; }

static int push(re_prog *C, int op, int c, int x, int y) {
  if (C->err)
    return 0;
  if (C->n >= MAX_PROG) {
    C->err = 1;
    return 0;
  }
  if (C->n == C->cap) {
    int cap = C->cap ? C->cap * 2 : 64;
    inst *grown = realloc(C->code, (size_t)cap * sizeof *grown);
    if (!grown) {
      C->err = 1;
      return 0;
    }
    C->code = grown;
    C->cap = cap;
  }
  inst *in = &C->code[C->n];
  in->op = (uint8_t)op;
  in->c = (uint8_t)c;
  in->x = x;
  in->y = y;
  return C->n++;
}

static int add_set(re_prog *C, const uint8_t set[32]) {
  if (C->err)
    return 0;
  if (C->nsets == C->setcap) {
    int cap = C->setcap ? C->setcap * 2 : 16;
    void *grown = realloc(C->sets, (size_t)cap * sizeof *C->sets);
    if (!grown) {
      C->err = 1;
      return 0;
    }
    C->sets = grown;
    C->setcap = cap;
  }
  memcpy(C->sets[C->nsets], set, 32);
  return C->nsets++;
}

/* which: 0 = lead of a 2-byte sequence, 1 = 3-byte, 2 = 4-byte, 3 = continuation */
static int shared_set(re_prog *C, int which) {
  if (C->shared[which] < 0) {
    uint8_t s[32];
    memset(s, 0, sizeof s);
    switch (which) {
    case 0:
      set_range(s, 0xc2, 0xdf);
      break;
    case 1:
      set_range(s, 0xe0, 0xef);
      break;
    case 2:
      set_range(s, 0xf0, 0xf4);
      break;
    default:
      set_range(s, 0x80, 0xbf);
      break;
    }
    C->shared[which] = add_set(C, s);
  }
  return C->shared[which];
}

/* Match one whole UTF-8 code point: the ASCII set `ascii`, or any valid
 * multi-byte sequence. */
static void emit_utf8_class(re_prog *C, int ascii) {
  int l2 = shared_set(C, 0), l3 = shared_set(C, 1), l4 = shared_set(C, 2);
  int cont = shared_set(C, 3);
  int jmps[4], nj = 0;

  int sp1 = push(C, OP_SPLIT, 0, 0, 0);
  at(C, sp1)->x = C->n;
  push(C, OP_CLASS, 0, ascii, 0);
  jmps[nj++] = push(C, OP_JMP, 0, 0, 0);

  at(C, sp1)->y = C->n;
  int sp2 = push(C, OP_SPLIT, 0, 0, 0);
  at(C, sp2)->x = C->n;
  push(C, OP_CLASS, 0, l2, 0);
  push(C, OP_CLASS, 0, cont, 0);
  jmps[nj++] = push(C, OP_JMP, 0, 0, 0);

  at(C, sp2)->y = C->n;
  int sp3 = push(C, OP_SPLIT, 0, 0, 0);
  at(C, sp3)->x = C->n;
  push(C, OP_CLASS, 0, l3, 0);
  push(C, OP_CLASS, 0, cont, 0);
  push(C, OP_CLASS, 0, cont, 0);
  jmps[nj++] = push(C, OP_JMP, 0, 0, 0);

  at(C, sp3)->y = C->n;
  push(C, OP_CLASS, 0, l4, 0);
  push(C, OP_CLASS, 0, cont, 0);
  push(C, OP_CLASS, 0, cont, 0);
  push(C, OP_CLASS, 0, cont, 0);

  for (int k = 0; k < nj; k++)
    at(C, jmps[k])->x = C->n;
}

static void emit(re_prog *C, const node *nodes, int id) {
  if (C->err)
    return;
  const node *nd = &nodes[id];
  switch (nd->kind) {
  case N_EMPTY:
    break;
  case N_CHAR:
    push(C, OP_CHAR, C->icase ? lower_of((unsigned char)nd->c) : nd->c, 0, 0);
    break;
  case N_CLASS: {
    uint8_t s[32];
    memcpy(s, nd->set, sizeof s);
    if (C->icase) {
      for (unsigned ch = 'a'; ch <= 'z'; ch++) {
        if (set_has(s, ch) || set_has(s, ch - 32)) {
          set_add(s, ch);
          set_add(s, ch - 32);
        }
      }
    }
    if (nd->neg)
      for (int b = 0; b < 16; b++)
        s[b] = (uint8_t)~s[b];
    for (int b = 16; b < 32; b++)
      s[b] = 0; /* sets only ever hold ASCII */
    int idx = add_set(C, s);
    if (nd->utf8)
      emit_utf8_class(C, idx);
    else
      push(C, OP_CLASS, 0, idx, 0);
    break;
  }
  case N_BOL:
    push(C, OP_BOL, 0, 0, 0);
    break;
  case N_EOL:
    push(C, OP_EOL, 0, 0, 0);
    break;
  case N_WB:
    push(C, OP_WB, 0, 0, 0);
    break;
  case N_NWB:
    push(C, OP_NWB, 0, 0, 0);
    break;
  case N_CAT:
    for (int k = nd->a; k >= 0 && !C->err; k = nodes[k].next)
      emit(C, nodes, k);
    break;
  case N_ALT: {
    int sp = push(C, OP_SPLIT, 0, 0, 0);
    at(C, sp)->x = C->n;
    emit(C, nodes, nd->a);
    int jmp = push(C, OP_JMP, 0, 0, 0);
    at(C, sp)->y = C->n;
    emit(C, nodes, nd->b);
    at(C, jmp)->x = C->n;
    break;
  }
  case N_REP: {
    int body = nd->a, mn = nd->min, mx = nd->max, greedy = nd->greedy;
    if (mx == -1 && mn >= 1) { /* x{m,}: m-1 copies, then a loop around the last */
      for (int k = 0; k < mn - 1 && !C->err; k++)
        emit(C, nodes, body);
      int l1 = C->n;
      emit(C, nodes, body);
      int sp = push(C, OP_SPLIT, 0, 0, 0);
      at(C, sp)->x = greedy ? l1 : C->n;
      at(C, sp)->y = greedy ? C->n : l1;
      break;
    }
    for (int k = 0; k < mn && !C->err; k++)
      emit(C, nodes, body);
    if (mx == -1) { /* x* */
      int sp = push(C, OP_SPLIT, 0, 0, 0);
      int start = C->n;
      emit(C, nodes, body);
      push(C, OP_JMP, 0, sp, 0);
      at(C, sp)->x = greedy ? start : C->n;
      at(C, sp)->y = greedy ? C->n : start;
    } else { /* x{m,n}: each optional copy may skip straight to the end */
      int *splits = malloc((size_t)(mx - mn + 1) * sizeof *splits);
      if (!splits) {
        C->err = 1;
        break;
      }
      int ns = 0;
      for (int k = mn; k < mx && !C->err; k++) {
        int sp = push(C, OP_SPLIT, 0, 0, 0);
        splits[ns++] = sp;
        if (greedy)
          at(C, sp)->x = C->n;
        else
          at(C, sp)->y = C->n;
        emit(C, nodes, body);
      }
      for (int k = 0; k < ns; k++) {
        if (greedy)
          at(C, splits[k])->y = C->n;
        else
          at(C, splits[k])->x = C->n;
      }
      free(splits);
    }
    break;
  }
  default:
    C->err = 1;
    break;
  }
}

/* Which bytes can start a match, found by following every path from pc 0
 * (assertions are treated as transparent, which only over-approximates). */
static void compute_first(re_prog *C) {
  memset(C->first, 0, sizeof C->first);
  C->nullable = 0;
  int n = C->n;
  char *seen = calloc((size_t)n, 1);
  int *stack = malloc((size_t)n * sizeof *stack);
  if (!seen || !stack) {
    C->nullable = 1; /* no skipping optimisation, still correct */
    free(seen);
    free(stack);
    return;
  }
  int sp = 0;
  stack[sp++] = 0;
  while (sp > 0) {
    int pc = stack[--sp];
    while (!seen[pc]) {
      seen[pc] = 1;
      const inst *in = &C->code[pc];
      if (in->op == OP_CHAR) {
        C->first[in->c] = 1;
        if (C->icase)
          C->first[upper_of(in->c)] = 1;
        break;
      } else if (in->op == OP_CLASS) {
        for (int b = 0; b < 256; b++)
          if (set_has(C->sets[in->x], (unsigned)b))
            C->first[b] = 1;
        break;
      } else if (in->op == OP_JMP) {
        pc = in->x;
      } else if (in->op == OP_SPLIT) {
        stack[sp++] = in->y;
        pc = in->x;
      } else if (in->op == OP_MATCH) {
        C->nullable = 1;
        break;
      } else { /* BOL EOL WB NWB */
        pc++;
      }
    }
  }
  free(seen);
  free(stack);
}

static void re_free(re_prog *C) {
  if (!C)
    return;
  free(C->code);
  free(C->sets);
  free(C);
}

/* Returns NULL when the pattern is invalid, unsupported or too big. */
static re_prog *re_compile(const char *pat, size_t n) {
  parser P;
  memset(&P, 0, sizeof P);
  P.s = pat;
  P.n = n;
  P.cap = 32;
  P.nodes = malloc((size_t)P.cap * sizeof *P.nodes);
  if (!P.nodes)
    return NULL;
  P.nn = 1;
  memset(&P.nodes[0], 0, sizeof P.nodes[0]); /* dummy node 0 */
  P.nodes[0].a = P.nodes[0].b = P.nodes[0].next = -1;

  int root = parse_alt(&P, 0);
  if (!P.err && P.i != P.n)
    P.err = 1;
  if (P.err) {
    free(P.nodes);
    return NULL;
  }

  re_prog *C = calloc(1, sizeof *C);
  if (!C) {
    free(P.nodes);
    return NULL;
  }
  for (int k = 0; k < 4; k++)
    C->shared[k] = -1;
  C->icase = !P.has_upper;
  emit(C, P.nodes, root);
  push(C, OP_MATCH, 0, 0, 0);
  free(P.nodes);
  if (C->err) {
    re_free(C);
    return NULL;
  }
  compute_first(C);
  return C;
}

/* ---- regex: Pike VM ------------------------------------------------------ */

typedef struct {
  int pc;
  int start;
} thread;

typedef struct {
  thread *dense;
  int *sparse;
  int n;
} tlist;

typedef struct {
  const re_prog *p;
  tlist a, b;
  int *stack;
} re_vm;

static void vm_free(re_vm *v) {
  if (!v)
    return;
  free(v->a.dense);
  free(v->a.sparse);
  free(v->b.dense);
  free(v->b.sparse);
  free(v->stack);
  free(v);
}

static re_vm *vm_new(const re_prog *p) {
  re_vm *v = calloc(1, sizeof *v);
  if (!v)
    return NULL;
  size_t n = (size_t)p->n;
  v->p = p;
  v->a.dense = malloc(n * sizeof *v->a.dense);
  v->a.sparse = calloc(n, sizeof *v->a.sparse);
  v->b.dense = malloc(n * sizeof *v->b.dense);
  v->b.sparse = calloc(n, sizeof *v->b.sparse);
  v->stack = malloc(n * sizeof *v->stack);
  if (!v->a.dense || !v->a.sparse || !v->b.dense || !v->b.sparse || !v->stack) {
    vm_free(v);
    return NULL;
  }
  return v;
}

static int word_at(const unsigned char *s, size_t len, size_t pos) {
  return pos < len && is_word(s[pos]);
}

/* Add pc and everything reachable from it without consuming input, in
 * priority order. Each pc is added at most once per list. */
static void vm_add(re_vm *v, tlist *l, int pc0, int start, const unsigned char *s,
                   size_t len, size_t pos) {
  const inst *code = v->p->code;
  int *stack = v->stack;
  int sp = 0;
  stack[sp++] = pc0;
  while (sp > 0) {
    int pc = stack[--sp];
    for (;;) {
      int slot = l->sparse[pc];
      if (slot < l->n && l->dense[slot].pc == pc)
        break; /* already queued */
      l->sparse[pc] = l->n;
      l->dense[l->n].pc = pc;
      l->dense[l->n].start = start;
      l->n++;
      const inst *in = &code[pc];
      if (in->op == OP_JMP) {
        pc = in->x;
      } else if (in->op == OP_SPLIT) {
        stack[sp++] = in->y;
        pc = in->x;
      } else if (in->op == OP_BOL) {
        if (pos != 0)
          break;
        pc++;
      } else if (in->op == OP_EOL) {
        if (pos != len)
          break;
        pc++;
      } else if (in->op == OP_WB || in->op == OP_NWB) {
        int boundary = (pos > 0 && word_at(s, len, pos - 1)) != word_at(s, len, pos);
        if (boundary != (in->op == OP_WB))
          break;
        pc++;
      } else {
        break; /* CHAR, CLASS, MATCH wait for the next step */
      }
    }
  }
}

/* Leftmost match in s[0..len). Returns 1 and sets [*ms, *me), or 0. */
static int vm_search(re_vm *v, const unsigned char *s, size_t len, size_t *ms, size_t *me) {
  const re_prog *p = v->p;
  tlist *cl = &v->a, *nl = &v->b;
  int matched = 0;
  size_t best_s = 0, best_e = 0;
  cl->n = 0;
  nl->n = 0;

  for (size_t pos = 0;; pos++) {
    if (cl->n == 0 && !matched && !p->nullable) {
      while (pos < len && !p->first[s[pos]])
        pos++;
      if (pos >= len)
        break; /* a non-nullable pattern needs at least one more byte */
    }
    /* A match may start here (lowest priority), but never inside a multi-byte
     * character: that would put an empty match, or the cursor, in its middle. */
    if (!matched && (pos >= len || pos == 0 || (s[pos] & 0xc0) != 0x80))
      vm_add(v, cl, 0, (int)pos, s, len, pos);

    nl->n = 0;
    for (int i = 0; i < cl->n; i++) {
      thread t = cl->dense[i];
      const inst *in = &p->code[t.pc];
      if (in->op == OP_MATCH) {
        matched = 1;
        best_s = (size_t)t.start;
        best_e = pos;
        break; /* lower-priority threads are dropped */
      }
      if (pos >= len)
        continue;
      if (in->op == OP_CHAR) {
        unsigned char b = p->icase ? lower_of(s[pos]) : s[pos];
        if (b == in->c)
          vm_add(v, nl, t.pc + 1, t.start, s, len, pos + 1);
      } else if (in->op == OP_CLASS) {
        if (set_has(p->sets[in->x], s[pos]))
          vm_add(v, nl, t.pc + 1, t.start, s, len, pos + 1);
      }
    }
    tlist *tmp = cl;
    cl = nl;
    nl = tmp;
    if (pos >= len || (matched && cl->n == 0))
      break;
  }
  if (matched) {
    *ms = best_s;
    *me = best_e;
  }
  return matched;
}

/* Test hook (internal.h): 1 = match, 0 = no match, -1 = pattern rejected. */
int nv_re_search(const char *pattern, const char *text, size_t len, size_t *start,
                 size_t *end) {
  re_prog *p = re_compile(pattern, strlen(pattern));
  if (!p)
    return -1;
  re_vm *v = vm_new(p);
  int r = -1;
  if (v) {
    size_t s = 0, e = 0;
    r = vm_search(v, (const unsigned char *)text, len, &s, &e);
    if (r > 0) {
      *start = s;
      *end = e;
    }
  }
  vm_free(v);
  re_free(p);
  return r;
}

/* ---- literal search ------------------------------------------------------ */

/* Boyer-Moore-Horspool: the skip table makes a mismatch on the window's last
 * byte jump by up to the needle length. With icase the needle is lower-case
 * and every haystack byte is folded before it is looked at. */
typedef struct {
  const unsigned char *needle;
  size_t m;
  int icase;
  size_t shift[256];
} litpat;

static void lit_init(litpat *L, const unsigned char *needle, size_t m, int icase) {
  L->needle = needle;
  L->m = m;
  L->icase = icase;
  for (int c = 0; c < 256; c++)
    L->shift[c] = m;
  for (size_t i = 0; i + 1 < m; i++)
    L->shift[needle[i]] = m - 1 - i;
}

/* First occurrence of the needle in h[0..n), or NULL. */
static const unsigned char *lit_find(const litpat *L, const unsigned char *h, size_t n) {
  size_t m = L->m;
  if (m == 0 || n < m)
    return NULL;
  if (m == 1 && !L->icase)
    return memchr(h, L->needle[0], n);
  const unsigned char *nd = L->needle;
  size_t last = n - m, i = 0;
  while (i <= last) {
    unsigned char tail = h[i + m - 1];
    if (L->icase)
      tail = lower_of(tail);
    if (tail == nd[m - 1]) {
      size_t k = 0;
      if (L->icase) {
        while (k + 1 < m && lower_of(h[i + k]) == nd[k])
          k++;
      } else {
        while (k + 1 < m && h[i + k] == nd[k])
          k++;
      }
      if (k + 1 == m)
        return h + i;
    }
    i += L->shift[tail];
  }
  return NULL;
}

/* ---- results ------------------------------------------------------------- */

typedef struct {
  char *path;
  char *text;
  uint32_t line, col;
} hit;

struct nv_grep {
  hit *hits;
  size_t len, cap;
  int status;
};

static int add_hit(nv_grep *g, const char *rel, uint32_t line, const unsigned char *buf,
                   size_t ls, size_t le, size_t at_off, size_t max_text) {
  /* Text shown for the line: leading/trailing blanks trimmed, control bytes
   * made blank, cut to max_text bytes. A match far into a long line gets a
   * window around it (marked with "..."). */
  size_t ts = ls, te = le;
  while (ts < te && (buf[ts] == ' ' || buf[ts] == '\t'))
    ts++;
  while (te > ts && (buf[te - 1] == ' ' || buf[te - 1] == '\t' || buf[te - 1] == '\r'))
    te--;
  size_t ws = ts;
  int ellipsis = 0;
  if (at_off > ts && at_off - ts > max_text * 3 / 4) {
    ws = at_off - max_text / 4;
    ellipsis = 1;
    while (ws < te && (buf[ws] & 0xc0) == 0x80)
      ws++;
  }
  size_t len = te > ws ? te - ws : 0;
  if (len > max_text)
    len = max_text;
  while (len > 0 && ws + len < te && (buf[ws + len] & 0xc0) == 0x80)
    len--;

  if (g->len == g->cap) {
    size_t cap = g->cap ? g->cap * 2 : 64;
    hit *grown = realloc(g->hits, cap * sizeof *grown);
    if (!grown)
      return -1;
    g->hits = grown;
    g->cap = cap;
  }
  char *text = malloc(len + 4);
  char *path = strdup(rel);
  if (!text || !path) {
    free(text);
    free(path);
    return -1;
  }
  char *o = text;
  if (ellipsis) {
    memcpy(o, "...", 3);
    o += 3;
  }
  for (size_t k = 0; k < len; k++) {
    unsigned char c = buf[ws + k];
    *o++ = (char)((c < 0x20 || c == 0x7f) ? ' ' : c);
  }
  *o = '\0';

  hit *h = &g->hits[g->len++];
  h->path = path;
  h->text = text;
  h->line = line;
  h->col = (uint32_t)(at_off - ls + 1);
  return 0;
}

NV_API void nv_grep_free(nv_grep *g) {
  if (!g)
    return;
  for (size_t i = 0; i < g->len; i++) {
    free(g->hits[i].path);
    free(g->hits[i].text);
  }
  free(g->hits);
  free(g);
}

NV_API size_t nv_grep_count(const nv_grep *g) { return g ? g->len : 0; }
NV_API int nv_grep_status(const nv_grep *g) { return g ? g->status : 0; }
NV_API const char *nv_grep_path(const nv_grep *g, size_t i) {
  return (g && i < g->len) ? g->hits[i].path : NULL;
}
NV_API const char *nv_grep_text(const nv_grep *g, size_t i) {
  return (g && i < g->len) ? g->hits[i].text : NULL;
}
NV_API uint32_t nv_grep_line(const nv_grep *g, size_t i) {
  return (g && i < g->len) ? g->hits[i].line : 0;
}
NV_API uint32_t nv_grep_col(const nv_grep *g, size_t i) {
  return (g && i < g->len) ? g->hits[i].col : 0;
}

/* ---- search -------------------------------------------------------------- */

enum {
  DEFAULT_MAX_FILE = 1 << 20,
  DEFAULT_MAX_TEXT = 200,
  MAX_LIMIT = 100000,
  MAX_PATTERN = 4096,
  CANCEL_LINES = 512 /* regex mode: check the cancel flag this often */
};

static int has_meta(const char *p, size_t n) {
  for (size_t i = 0; i < n; i++)
    if (strchr("\\.^$*+?()[]{}|", p[i]))
      return 1;
  return 0;
}

typedef struct {
  nv_grep *g;
  const char *rel;
  size_t limit; /* stop once g->len exceeds this */
  size_t max_text;
  const nv_cancel *cancel;
  /* literal mode */
  litpat lit;
  /* regex mode */
  re_vm *vm;
} searcher;

/* Search one file buffer. Returns 1 to stop the whole search (limit reached,
 * cancelled or out of memory). */
static int search_buffer(searcher *S, const unsigned char *buf, size_t n) {
  nv_grep *g = S->g;
  if (S->vm) {
    size_t p = 0;
    uint32_t line = 1;
    unsigned counter = 0;
    while (p < n) {
      const unsigned char *nl = memchr(buf + p, '\n', n - p);
      size_t le = nl ? (size_t)(nl - buf) : n;
      size_t mlen = le - p;
      if (mlen > 0 && buf[le - 1] == '\r')
        mlen--; /* "$" matches before a CRLF */
      size_t ms, me;
      if (vm_search(S->vm, buf + p, mlen, &ms, &me)) {
        if (add_hit(g, S->rel, line, buf, p, le, p + ms, S->max_text) != 0)
          return 1;
        if (g->len > S->limit)
          return 1;
      }
      p = le + 1;
      line++;
      if ((++counter % CANCEL_LINES) == 0 && is_cancelled(S->cancel)) {
        g->status |= NV_GREP_CANCELLED;
        return 1;
      }
    }
    return 0;
  }

  size_t pos = 0, counted = 0;
  uint32_t line = 1;
  while (pos < n) {
    const unsigned char *found = lit_find(&S->lit, buf + pos, n - pos);
    if (!found)
      break;
    size_t at_off = (size_t)(found - buf);
    size_t ls = at_off;
    while (ls > 0 && buf[ls - 1] != '\n')
      ls--;
    const unsigned char *nl = memchr(buf + at_off, '\n', n - at_off);
    size_t le = nl ? (size_t)(nl - buf) : n;
    while (counted < ls) { /* count the line breaks before this line */
      const unsigned char *brk = memchr(buf + counted, '\n', ls - counted);
      if (!brk)
        break;
      line++;
      counted = (size_t)(brk - buf) + 1;
    }
    if (add_hit(g, S->rel, line, buf, ls, le, at_off, S->max_text) != 0)
      return 1;
    if (g->len > S->limit)
      return 1;
    pos = le + 1;
  }
  return 0;
}

/* Read a whole regular file into *buf (grown as needed). Returns its length,
 * or 0 when it is empty, unreadable, not a regular file or over `max`. */
static size_t read_file(const char *path, size_t max, unsigned char **buf, size_t *cap) {
  int flags = O_RDONLY;
#ifdef O_CLOEXEC
  flags |= O_CLOEXEC;
#endif
#ifdef O_NONBLOCK
  flags |= O_NONBLOCK; /* never hang on a fifo that replaced a file */
#endif
  int fd = open(path, flags);
  if (fd < 0)
    return 0;
  struct stat st;
  if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 ||
      (unsigned long long)st.st_size > (unsigned long long)max) {
    close(fd);
    return 0;
  }
  size_t want = (size_t)st.st_size;
  if (*cap < want + 1) {
    unsigned char *grown = realloc(*buf, want + 1);
    if (!grown) {
      close(fd);
      return 0;
    }
    *buf = grown;
    *cap = want + 1;
  }
  size_t got = 0;
  while (got < want) {
    ssize_t r = read(fd, *buf + got, want - got);
    if (r < 0 && errno == EINTR)
      continue;
    if (r <= 0)
      break;
    got += (size_t)r;
  }
  close(fd);
  return got;
}

NV_API nv_grep *nv_grep_run(const nv_index *files, const char *root, const char *pattern,
                            int flags, size_t limit, size_t max_file_bytes, size_t max_text,
                            const nv_cancel *cancel) {
  nv_grep *g = calloc(1, sizeof *g);
  if (!g)
    return NULL;
  size_t plen = pattern ? strlen(pattern) : 0;
  if (!files || plen == 0 || plen > MAX_PATTERN || strchr(pattern, '\n') || limit == 0)
    return g;
  if (limit > MAX_LIMIT)
    limit = MAX_LIMIT;
  if (max_file_bytes == 0)
    max_file_bytes = DEFAULT_MAX_FILE;
  if (max_text == 0)
    max_text = DEFAULT_MAX_TEXT;
  if (max_text < 16)
    max_text = 16;
  if (max_text > 4096)
    max_text = 4096;

  searcher S;
  memset(&S, 0, sizeof S);
  S.g = g;
  S.limit = limit;
  S.max_text = max_text;
  S.cancel = cancel;

  re_prog *prog = NULL;
  unsigned char *lit = NULL;
  if (!(flags & NV_GREP_FIXED) && has_meta(pattern, plen)) {
    if (plen <= MAX_RE_PATTERN)
      prog = re_compile(pattern, plen);
    if (prog) {
      S.vm = vm_new(prog);
      if (!S.vm) {
        re_free(prog);
        return g;
      }
    } else {
      g->status |= NV_GREP_LITERAL; /* not a valid pattern (yet): search it as text */
    }
  }
  if (!S.vm) {
    int upper = 0;
    for (size_t i = 0; i < plen; i++)
      if (pattern[i] >= 'A' && pattern[i] <= 'Z')
        upper = 1;
    lit = malloc(plen);
    if (!lit)
      return g;
    for (size_t i = 0; i < plen; i++)
      lit[i] = upper ? (unsigned char)pattern[i] : lower_of((unsigned char)pattern[i]);
    lit_init(&S.lit, lit, plen, !upper);
  }

  if (!root || !*root)
    root = ".";
  size_t rlen = strlen(root);
  while (rlen > 0 && root[rlen - 1] == '/')
    rlen--; /* "/" collapses to length 0 */

  unsigned char *buf = NULL;
  size_t bufcap = 0;
  char *full = NULL;
  size_t fullcap = 0;
  size_t nfiles = nv_index_count(files);

  for (size_t f = 0; f < nfiles; f++) {
    if (is_cancelled(cancel)) {
      g->status |= NV_GREP_CANCELLED;
      break;
    }
    const char *rel = nv_index_get(files, f);
    size_t need = rlen + 1 + strlen(rel) + 1;
    if (need > fullcap) {
      char *grown = realloc(full, need + 256);
      if (!grown)
        break;
      full = grown;
      fullcap = need + 256;
    }
    memcpy(full, root, rlen);
    full[rlen] = '/';
    strcpy(full + rlen + 1, rel);

    size_t n = read_file(full, max_file_bytes, &buf, &bufcap);
    if (n == 0 || memchr(buf, 0, n))
      continue; /* empty, unreadable or binary */
    S.rel = rel;
    if (search_buffer(&S, buf, n))
      break;
  }

  if (g->len > limit) { /* one extra hit was collected only to learn there is more */
    free(g->hits[g->len - 1].path);
    free(g->hits[g->len - 1].text);
    g->len--;
    g->status |= NV_GREP_MORE;
  }

  free(buf);
  free(full);
  free(lit);
  vm_free(S.vm);
  re_free(prog);
  return g;
}
