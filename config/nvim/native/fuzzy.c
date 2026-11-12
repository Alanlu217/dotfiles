#include "common.h"
#include <ctype.h>
#include <string.h>

__attribute__((visibility("default")))
int fuzzy_match(const char *pattern, const char *str) {
    if (!pattern || !*pattern) return 1; // Empty pattern matches everything
    if (!str) return 0;

    int score = 0;
    int consecutive = 0;
    const char *p = pattern;
    const char *s = str;

    while (*p && *s) {
        char pc = tolower((unsigned char)*p);
        char sc = tolower((unsigned char)*s);

        if (pc == sc) {
            score += 1 + consecutive * 2; // Reward consecutive matches
            // Reward matches after path separators or snake_case boundaries
            if (s == str || *(s - 1) == '/' || *(s - 1) == '_' || *(s - 1) == '-') {
                score += 5;
            }
            consecutive++;
            p++;
        } else {
            consecutive = 0;
        }
        s++;
    }

    // If we didn't consume the entire pattern, it's not a match
    if (*p != '\0') {
        return 0;
    }

    return score;
}
