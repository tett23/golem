/* The wasm host of golem-plugin (ADR 0001) on the wasmtime C API: no
   imports, no threads, canonical NaNs, no relaxed SIMD, fuel and memory
   limits, a limit on table elements, the types of results checked, a fresh
   instance per call (docs/adr ADR 0035). */
#include "golem_plugin.h"
#include <stdlib.h>
#include <string.h>
#include <wasmtime.h>

struct golem_plugin {
  wasm_engine_t *engine;
  wasmtime_module_t *module;
};

/* The most elements of the tables of one instance (docs/adr ADR 0035). */
#define GOLEM_TABLE_ELEMENTS 1000000

static char *copy_msg(const char *s, size_t n) {
  char *m = malloc(n + 1);
  if (m) { memcpy(m, s, n); m[n] = 0; }
  return m;
}

static char *error_text(wasmtime_error_t *e) {
  wasm_name_t msg;
  wasmtime_error_message(e, &msg);
  char *r = copy_msg(msg.data, msg.size);
  wasm_byte_vec_delete(&msg);
  wasmtime_error_delete(e);
  return r;
}

static char *trap_text(wasm_trap_t *t) {
  wasm_message_t msg;
  wasm_trap_message(t, &msg);
  char *r = copy_msg(msg.data, msg.size ? msg.size - 1 : 0);
  wasm_byte_vec_delete(&msg);
  return r;
}

static wasm_engine_t *new_engine(void) {
  wasm_config_t *c = wasm_config_new();
  wasmtime_config_consume_fuel_set(c, true);
  wasmtime_config_wasm_threads_set(c, false);
  wasmtime_config_shared_memory_set(c, false);
  wasmtime_config_wasm_relaxed_simd_set(c, false);
  wasmtime_config_cranelift_nan_canonicalization_set(c, true);
  wasmtime_config_parallel_compilation_set(c, false);
  return wasm_engine_new_with_config(c);
}

golem_plugin *golem_plugin_load(const uint8_t *wasm, size_t len, char **err) {
  golem_plugin *p = calloc(1, sizeof *p);
  if (!p) { *err = copy_msg("out of memory", 13); return NULL; }
  p->engine = new_engine();
  wasmtime_error_t *e = wasmtime_module_new(p->engine, wasm, len, &p->module);
  if (e) {
    *err = error_text(e);
    wasm_engine_delete(p->engine);
    free(p);
    return NULL;
  }
  return p;
}

void golem_plugin_free(golem_plugin *p) {
  if (!p) return;
  wasmtime_module_delete(p->module);
  wasm_engine_delete(p->engine);
  free(p);
}

int golem_plugin_import_count(golem_plugin *p) {
  wasm_importtype_vec_t imports;
  wasmtime_module_imports(p->module, &imports);
  int n = (int)imports.size;
  wasm_importtype_vec_delete(&imports);
  return n;
}

char *golem_plugin_import_name(golem_plugin *p, int i) {
  wasm_importtype_vec_t imports;
  wasmtime_module_imports(p->module, &imports);
  const wasm_name_t *m = wasm_importtype_module(imports.data[i]);
  const wasm_name_t *n = wasm_importtype_name(imports.data[i]);
  char *r = malloc(m->size + n->size + 2);
  if (!r) { wasm_importtype_vec_delete(&imports); return copy_msg("?", 1); }
  memcpy(r, m->data, m->size);
  r[m->size] = '.';
  memcpy(r + m->size + 1, n->data, n->size);
  r[m->size + 1 + n->size] = 0;
  wasm_importtype_vec_delete(&imports);
  return r;
}

static int get_func(wasmtime_context_t *cx, wasmtime_instance_t *inst, const char *name, wasmtime_func_t *out) {
  wasmtime_extern_t ext;
  if (!wasmtime_instance_export_get(cx, inst, name, strlen(name), &ext) || ext.kind != WASMTIME_EXTERN_FUNC) return 0;
  *out = ext.of.func;
  return 1;
}

/* Calls f and checks that its one result has the kind the ABI wants. */
static int call(wasmtime_context_t *cx, wasmtime_func_t *f, const char *name, wasmtime_valkind_t kind,
                wasmtime_val_t *args, size_t nargs, wasmtime_val_t *res, char **err) {
  wasm_trap_t *trap = NULL;
  wasmtime_error_t *e = wasmtime_func_call(cx, f, args, nargs, res, 1, &trap);
  if (e) { *err = error_text(e); return GOLEM_TRAP; }
  if (trap) {
    wasmtime_trap_code_t code;
    int fuel = wasmtime_trap_code(trap, &code) && code == WASMTIME_TRAP_CODE_OUT_OF_FUEL;
    *err = trap_text(trap);
    wasm_trap_delete(trap);
    return fuel ? GOLEM_OUT_OF_FUEL : GOLEM_TRAP;
  }
  /* the name of the function, in ASCII; the host words the message */
  if (res->kind != kind) { *err = copy_msg(name, strlen(name)); return GOLEM_BAD_TYPE; }
  return GOLEM_OK;
}

static int read_result(wasmtime_context_t *cx, wasmtime_instance_t *inst, uint64_t packed,
                       uint8_t **out, size_t *out_len, char **err) {
  wasmtime_extern_t ext;
  if (!wasmtime_instance_export_get(cx, inst, "memory", 6, &ext) || ext.kind != WASMTIME_EXTERN_MEMORY) {
    *err = copy_msg("memory", 6);
    return GOLEM_MISSING_EXPORT;
  }
  uint8_t *data = wasmtime_memory_data(cx, &ext.of.memory);
  size_t size = wasmtime_memory_data_size(cx, &ext.of.memory);
  uint64_t pos = packed >> 32, len = packed & 0xffffffffu;
  if (pos + len > size) { *err = copy_msg("result out of bounds", 20); return GOLEM_BAD_RESULT; }
  *out = malloc(len ? len : 1);
  if (!*out) { *err = copy_msg("out of memory", 13); return GOLEM_TRAP; }
  memcpy(*out, data + pos, len);
  *out_len = (size_t)len;
  return GOLEM_OK;
}

int golem_plugin_call(golem_plugin *p, int mode, uint64_t fuel, int64_t memory_limit,
                      const uint8_t *input, size_t in_len, uint8_t **out, size_t *out_len,
                      uint32_t *out_u32, char **err) {
  wasmtime_store_t *store = wasmtime_store_new(p->engine, NULL, NULL);
  wasmtime_store_limiter(store, memory_limit, GOLEM_TABLE_ELEMENTS, 1, 1, 1);
  wasmtime_context_t *cx = wasmtime_store_context(store);
  wasmtime_context_set_fuel(cx, fuel);
  wasmtime_instance_t inst;
  wasm_trap_t *trap = NULL;
  int status = GOLEM_OK;
  wasmtime_error_t *e = wasmtime_instance_new(cx, p->module, NULL, 0, &inst, &trap);
  if (e) { *err = error_text(e); status = GOLEM_INSTANTIATE; goto done; }
  if (trap) { *err = trap_text(trap); wasm_trap_delete(trap); status = GOLEM_INSTANTIATE; goto done; }
  wasmtime_func_t f;
  wasmtime_val_t res;
  if (mode == 0) {
    if (!get_func(cx, &inst, "golem_abi_version", &f)) { *err = copy_msg("golem_abi_version", 17); status = GOLEM_MISSING_EXPORT; goto done; }
    status = call(cx, &f, "golem_abi_version", WASMTIME_I32, NULL, 0, &res, err);
    if (status == GOLEM_OK) *out_u32 = (uint32_t)res.of.i32;
  } else if (mode == 1) {
    if (!get_func(cx, &inst, "golem_describe", &f)) { *err = copy_msg("golem_describe", 14); status = GOLEM_MISSING_EXPORT; goto done; }
    status = call(cx, &f, "golem_describe", WASMTIME_I64, NULL, 0, &res, err);
    if (status == GOLEM_OK) status = read_result(cx, &inst, (uint64_t)res.of.i64, out, out_len, err);
  } else {
    wasmtime_func_t alloc;
    if (!get_func(cx, &inst, "golem_alloc", &alloc) || !get_func(cx, &inst, "golem_invoke", &f)) {
      *err = copy_msg("golem_alloc/golem_invoke", 24); status = GOLEM_MISSING_EXPORT; goto done;
    }
    wasmtime_val_t a;
    a.kind = WASMTIME_I32;
    a.of.i32 = (int32_t)in_len;
    status = call(cx, &alloc, "golem_alloc", WASMTIME_I32, &a, 1, &res, err);
    if (status != GOLEM_OK) goto done;
    uint32_t ptr = (uint32_t)res.of.i32;
    wasmtime_extern_t ext;
    if (!wasmtime_instance_export_get(cx, &inst, "memory", 6, &ext) || ext.kind != WASMTIME_EXTERN_MEMORY) {
      *err = copy_msg("memory", 6); status = GOLEM_MISSING_EXPORT; goto done;
    }
    size_t size = wasmtime_memory_data_size(cx, &ext.of.memory);
    if ((size_t)ptr + in_len > size) { *err = copy_msg("golem_alloc out of bounds", 25); status = GOLEM_BAD_RESULT; goto done; }
    memcpy(wasmtime_memory_data(cx, &ext.of.memory) + ptr, input, in_len);
    wasmtime_val_t args[2];
    args[0].kind = WASMTIME_I32; args[0].of.i32 = (int32_t)ptr;
    args[1].kind = WASMTIME_I32; args[1].of.i32 = (int32_t)in_len;
    status = call(cx, &f, "golem_invoke", WASMTIME_I64, args, 2, &res, err);
    if (status == GOLEM_OK) status = read_result(cx, &inst, (uint64_t)res.of.i64, out, out_len, err);
  }
done:
  wasmtime_store_delete(store);
  return status;
}

void golem_plugin_free_bytes(void *b) { free(b); }

uint8_t *golem_wat2wasm(const char *wat, size_t len, size_t *out_len, char **err) {
  wasm_byte_vec_t out;
  wasmtime_error_t *e = wasmtime_wat2wasm(wat, len, &out);
  if (e) { *err = error_text(e); return NULL; }
  uint8_t *r = malloc(out.size ? out.size : 1);
  if (!r) { wasm_byte_vec_delete(&out); *err = copy_msg("out of memory", 13); return NULL; }
  memcpy(r, out.data, out.size);
  *out_len = out.size;
  wasm_byte_vec_delete(&out);
  return r;
}
