#ifndef COMMON_H
#define COMMON_H

// Versioning
const char* native_core_version(void);

// Utilities
void free_string(char *ptr);
const char* native_core_version(void);
char* search_directory(const char *root_path, const char *query);

// Fuzzy Matcher
int fuzzy_match(const char *pattern, const char *str);

#endif
