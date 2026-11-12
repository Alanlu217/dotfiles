#include <stdio.h>
#include <stdlib.h>
#include "common.h"

int main(int argc, char **argv) {
    printf("=== Testing Native Core (Version: %s) ===\n", native_core_version());

    // 1. Test Fuzzy Matcher standalone
    const char *pattern = "ffi";
    const char *target = "lua/core/ffi.lua";
    int score = fuzzy_match(pattern, target);
    printf("Fuzzy match ('%s' against '%s') -> Score: %d\n", pattern, target, score);

    const char *bad_target = "README.md";
    int bad_score = fuzzy_match(pattern, bad_target);
    printf("Fuzzy match ('%s' against '%s') -> Score: %d\n", pattern, bad_target, bad_score);

    // 2. Test Directory Search
    const char *query = argc > 1 ? argv[1] : "";
    printf("\nSearching directory '.' with query: '%s'\n", query);
    
    char *results = search_directory(".", query);
    if (results) {
        printf("--- Results ---\n%s--------------\n", results);
        free_string(results);
    } else {
        printf("Search returned NULL or no results.\n");
    }

    return 0;
}
