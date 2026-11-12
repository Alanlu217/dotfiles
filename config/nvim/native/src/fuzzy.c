/*
 * Fuzzy scoring in the style of Helix's matcher (nucleo, itself an fzf-v2
 * descendant): an optimal-alignment DP with
 *   - a flat score per matched character,
 *   - bonuses for matching after a boundary (whitespace, '/', symbols,
 *     camelCase, digits), doubled for the first pattern character,
 *   - a bonus for consecutive matches that inherits the chunk's boundary bonus,
 *   - affine gap penalties (cheap to extend, costly to start).
 */
#include "internal.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

enum {
    SCORE_MATCH = 16,
    PENALTY_GAP_START = 3,
    PENALTY_GAP_EXT = 1,
    BONUS_BOUNDARY = 8,
    BONUS_WHITE = 10,
    BONUS_DELIM = 9,
    BONUS_NONWORD = 8,
    BONUS_CAMEL = 7,
    BONUS_CONSECUTIVE = 4,
    FIRST_MULT = 2,
    MAX_PATTERN = 64,
    MAX_WINDOW = 1024
};

enum { C_WHITE, C_DELIM, C_NONWORD, C_LOWER, C_UPPER, C_DIGIT };

static int class_of(char ch) {
    unsigned char c = (unsigned char)ch;
    if (c == ' ' || c == '\t') return C_WHITE;
    if (c == '/') return C_DELIM;
    if (islower(c)) return C_LOWER;
    if (isupper(c)) return C_UPPER;
    if (isdigit(c)) return C_DIGIT;
    return C_NONWORD;
}

static int bonus_for(int prev, int cur) {
    if (cur >= C_LOWER) { /* word character */
        if (prev == C_WHITE) return BONUS_WHITE;
        if (prev == C_DELIM) return BONUS_DELIM;
        if (prev == C_NONWORD) return BONUS_BOUNDARY;
        if (prev == C_LOWER && cur == C_UPPER) return BONUS_CAMEL;
        if (prev != C_DIGIT && cur == C_DIGIT) return BONUS_CAMEL;
        return 0;
    }
    if (cur == C_WHITE) return BONUS_WHITE;
    if (cur == C_DELIM) return BONUS_DELIM;
    return BONUS_NONWORD;
}

static int has_upper(const char *s) {
    for (; *s; s++)
        if (isupper((unsigned char)*s)) return 1;
    return 0;
}

static int same(char p, char t, int cs) {
    if (cs) return p == t;
    return tolower((unsigned char)p) == tolower((unsigned char)t);
}

/* DP scratch, reused across calls. Thread-local: filtering runs on worker threads. */
static _Thread_local int *scratch;
static _Thread_local size_t scratch_cap;

static int *scratch_get(size_t n) {
    if (n > scratch_cap) {
        int *p = realloc(scratch, n * sizeof *p);
        if (!p) return NULL;
        scratch = p;
        scratch_cap = n;
    }
    return scratch;
}

static int max2(int a, int b) { return a > b ? a : b; }

NV_API int nv_fuzzy_score(const char *pattern, const char *text) {
    if (!pattern || !text) return -1;
    size_t m = strlen(pattern), n = strlen(text);
    if (m == 0) return 0;
    if (m > n) return -1;
    int cs = has_upper(pattern);

    /* Feasibility + window. The DP runs over the whole span from the earliest
     * possible match start to the last occurrence of the final pattern
     * character, so the optimal alignment is found, not just the first one. */
    size_t first[MAX_PATTERN];
    size_t k = 0, start = 0;
    for (size_t i = 0; i < n && k < m; i++) {
        if (same(pattern[k], text[i], cs)) {
            if (k < MAX_PATTERN) first[k] = i;
            if (k == 0) start = i;
            k++;
        }
    }
    if (k < m) return -1;

    size_t end = n;
    while (end-- > 0 && !same(pattern[m - 1], text[end], cs)) {}

    size_t W = end - start + 1;

    int *buf = (m <= MAX_PATTERN && W <= MAX_WINDOW) ? scratch_get(2 * m * W + W) : NULL;
    if (!buf) /* pathological input: flat score */
        return SCORE_MATCH * (int)m;

    int *H = buf, *C = buf + m * W, *bon = buf + 2 * m * W;

    for (size_t w = 0; w < W; w++) {
        size_t idx = start + w;
        int prev = idx ? class_of(text[idx - 1]) : C_DELIM;
        bon[w] = bonus_for(prev, class_of(text[idx]));
    }
    for (size_t i = 0; i < m; i++) first[i] -= start; /* window-relative */

    for (size_t i = 0; i < m; i++) {
        int in_gap = 0, hleft = 0;
        int *Hr = H + i * W, *Cr = C + i * W;
        for (size_t w = 0; w < W; w++) {
            if (w < first[i]) {
                Hr[w] = Cr[w] = 0;
                continue;
            }
            int match = same(pattern[i], text[start + w], cs);
            int gap = in_gap ? PENALTY_GAP_EXT : PENALTY_GAP_START;
            int score, cons = 0;

            if (i == 0) {
                if (match) {
                    score = SCORE_MATCH + bon[w] * FIRST_MULT;
                    cons = 1;
                    in_gap = 0;
                } else {
                    score = max2(hleft - gap, 0);
                    in_gap = 1;
                }
            } else {
                int s1 = 0, s2 = hleft - gap;
                if (match) {
                    s1 = H[(i - 1) * W + w - 1] + SCORE_MATCH;
                    cons = C[(i - 1) * W + w - 1] + 1;
                    int b = bon[w];
                    if (cons > 1) {
                        int fb = bon[w - (size_t)cons + 1];
                        if (b >= BONUS_BOUNDARY && b > fb)
                            cons = 1;
                        else
                            b = max2(b, max2(BONUS_CONSECUTIVE, fb));
                    }
                    if (s1 + b < s2) {
                        s1 += bon[w];
                        cons = 0;
                    } else {
                        s1 += b;
                    }
                }
                in_gap = s1 < s2;
                score = max2(max2(s1, s2), 0);
            }
            Hr[w] = score;
            Cr[w] = cons;
            hleft = score;
        }
    }

    int best = 0;
    for (size_t w = 0; w < W; w++) best = max2(best, H[(m - 1) * W + w]);
    return best;
}
