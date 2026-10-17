#ifndef GOLEM_PLUGIN_H
#define GOLEM_PLUGIN_H
#include <stddef.h>
#include <stdint.h>

typedef struct golem_plugin golem_plugin;

/* Status codes of golem_plugin_call. */
#define GOLEM_OK 0
#define GOLEM_TRAP 1
#define GOLEM_OUT_OF_FUEL 2
#define GOLEM_MISSING_EXPORT 3
#define GOLEM_BAD_RESULT 4
#define GOLEM_INSTANTIATE 5
/* a function returned a value of another type than the ABI says (docs/adr ADR 0035) */
#define GOLEM_BAD_TYPE 6

/* Compiles a module. On failure returns NULL and a malloc'd message. */
golem_plugin *golem_plugin_load(const uint8_t *wasm, size_t len, char **err);
void golem_plugin_free(golem_plugin *p);
/* Number of imports and the name of the i-th ("module.name", malloc'd). */
int golem_plugin_import_count(golem_plugin *p);
char *golem_plugin_import_name(golem_plugin *p, int i);

/* mode 0: golem_abi_version, result in *out_u32
   mode 1: golem_describe, bytes in *out
   mode 2: golem_invoke with input, bytes in *out
   A fresh store and instance for every call; fuel and memory limits.
   *out and *err are malloc'd (free with golem_plugin_free_bytes). */
int golem_plugin_call(golem_plugin *p, int mode, uint64_t fuel, int64_t memory_limit,
                      const uint8_t *input, size_t in_len, uint8_t **out, size_t *out_len,
                      uint32_t *out_u32, char **err);
void golem_plugin_free_bytes(void *b);

/* The binary form of a module in the text format. */
uint8_t *golem_wat2wasm(const char *wat, size_t len, size_t *out_len, char **err);
#endif
