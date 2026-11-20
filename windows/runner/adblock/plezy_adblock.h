#pragma once

// C interface of the Rust ad block engine (windows/runner/adblock), built on
// Brave's adblock-rust. Strings are UTF-8; returned strings are freed with
// plezy_adblock_free_string.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PlezyAdblock PlezyAdblock;

// Builds an engine from a JSON config: {"lists":[{"path":..,"trusted":bool}],
// "userFilters":"..","resources":"path","cache":"path","cacheKey":".."}.
// Slow for large lists: call off the UI thread. Null on bad input.
PlezyAdblock* plezy_adblock_load(const char* config_json);
void plezy_adblock_free(PlezyAdblock* engine);
void plezy_adblock_free_string(char* text);

// 0 allow, 1 block, 2 replace with *redirect (a data: URL).
int plezy_adblock_check(const PlezyAdblock* engine, const char* url, const char* source_url,
                        const char* request_type, char** redirect);

// {"hide":[..],"exceptions":[..],"script":"..","generichide":bool}
char* plezy_adblock_url_cosmetic(const PlezyAdblock* engine, const char* url);

// {"c":[classes],"i":[ids],"e":[exceptions]} -> ["selector", ...]
char* plezy_adblock_hidden_selectors(const PlezyAdblock* engine, const char* query_json);

// Script for the start of every document of the page at url (site hiding
// rules and scriptlets), or null. *exceptions_json receives the generic hiding
// exceptions, *generichide whether generic hiding is off for the page.
char* plezy_adblock_page_script(const PlezyAdblock* engine, const char* url, char** exceptions_json,
                                int* generichide);

// Script adding generic hiding rules for {"c":[classes],"i":[ids]}, or null.
char* plezy_adblock_generic_script(const PlezyAdblock* engine, const char* class_ids_json,
                                   const char* exceptions_json);

#ifdef __cplusplus
}
#endif
