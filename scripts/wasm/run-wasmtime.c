/* The host of golem.wasm under the C API of wasmtime 50.0.1 (docs/adr/0238),
 * which scripts/fetch-wasmtime.sh fetches. run-wasmtime.sh builds it.
 *
 *   run-wasmtime compile WASM CWASM   compiles golem.wasm with Cranelift and
 *                                     writes the compiled module to CWASM
 *   run-wasmtime call CWASM           reads an input frame from stdin,
 *                                     passes it to golem_build_pdf of a new
 *                                     instance and writes the result frame
 *                                     to stdout, as run.mjs call does
 *
 * WASI has the argument golem.wasm alone, no environment variable and no
 * preopened directory; only stderr is that of the process. The calls are
 * those of run.mjs: _initialize, hs_init(0, 0), golem_alloc, golem_build_pdf,
 * golem_free, golem_result_len. The frames are read and written by
 * run.mjs frame and run.mjs result. A failure of wasmtime or a trap exits 3,
 * a usage error 2. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wasi.h>
#include <wasmtime.h>

static void fail(const char *what, wasmtime_error_t *error, wasm_trap_t *trap) {
  wasm_byte_vec_t message;
  fprintf(stderr, "run-wasmtime: %s", what);
  if (error != NULL) {
    wasmtime_error_message(error, &message);
    fprintf(stderr, ": %.*s", (int)message.size, message.data);
    wasm_byte_vec_delete(&message);
  } else if (trap != NULL) {
    wasm_trap_message(trap, &message);
    fprintf(stderr, ": %.*s", (int)message.size, message.data);
    wasm_byte_vec_delete(&message);
  }
  fprintf(stderr, "\n");
  exit(3);
}

/* All the bytes of a stream. */
static uint8_t *slurp(FILE *f, size_t *len) {
  size_t cap = 1 << 16, n = 0, got;
  uint8_t *buf = malloc(cap);
  if (buf == NULL) fail("out of memory", NULL, NULL);
  while ((got = fread(buf + n, 1, cap - n, f)) > 0) {
    n += got;
    if (n == cap) {
      cap *= 2;
      buf = realloc(buf, cap);
      if (buf == NULL) fail("out of memory", NULL, NULL);
    }
  }
  if (ferror(f)) fail("cannot read the input", NULL, NULL);
  *len = n;
  return buf;
}

static wasm_engine_t *engine(void) {
  wasm_config_t *config = wasm_config_new();
  wasmtime_config_wasm_exceptions_set(config, true);
  return wasm_engine_new_with_config(config);
}

static int compile(const char *wasm_path, const char *cwasm_path) {
  FILE *in = fopen(wasm_path, "rb"), *out;
  size_t len;
  uint8_t *wasm;
  wasm_engine_t *eng;
  wasmtime_module_t *module;
  wasmtime_error_t *error;
  wasm_byte_vec_t compiled;
  if (in == NULL) fail(wasm_path, NULL, NULL);
  wasm = slurp(in, &len);
  fclose(in);
  eng = engine();
  if ((error = wasmtime_module_new(eng, wasm, len, &module)) != NULL) fail("compile", error, NULL);
  if ((error = wasmtime_module_serialize(module, &compiled)) != NULL) fail("serialize", error, NULL);
  out = fopen(cwasm_path, "wb");
  if (out == NULL || fwrite(compiled.data, 1, compiled.size, out) != compiled.size || fclose(out) != 0) fail(cwasm_path, NULL, NULL);
  /* the process ends here: freeing the module and the engine of golem.wasm
   * takes wasmtime many seconds, and gives nothing back */
  return 0;
}

static wasmtime_context_t *context;
static wasmtime_instance_t instance;

static wasmtime_extern_t export_of(const char *name) {
  wasmtime_extern_t e;
  if (!wasmtime_instance_export_get(context, &instance, name, strlen(name), &e)) fail(name, NULL, NULL);
  return e;
}

/* Calls an export with i32 arguments; its one i32 result, or 0. */
static int32_t invoke(const char *name, const int32_t *args, size_t nargs, size_t nresults) {
  wasmtime_extern_t f = export_of(name);
  wasmtime_val_t params[2], result;
  wasm_trap_t *trap = NULL;
  wasmtime_error_t *error;
  size_t i;
  if (f.kind != WASMTIME_EXTERN_FUNC || nargs > 2 || nresults > 1) fail(name, NULL, NULL);
  for (i = 0; i < nargs; i++) {
    params[i].kind = WASMTIME_I32;
    params[i].of.i32 = args[i];
  }
  error = wasmtime_func_call(context, &f.of.func, params, nargs, &result, nresults, &trap);
  if (error != NULL || trap != NULL) fail(name, error, trap);
  return nresults == 1 ? result.of.i32 : 0;
}

static uint8_t *memory_at(uint32_t ptr, size_t len) {
  wasmtime_extern_t m = export_of("memory");
  if (m.kind != WASMTIME_EXTERN_MEMORY) fail("memory", NULL, NULL);
  if ((size_t)ptr + len > wasmtime_memory_data_size(context, &m.of.memory)) fail("a buffer beyond the memory", NULL, NULL);
  return wasmtime_memory_data(context, &m.of.memory) + ptr;
}

static int call(const char *cwasm_path) {
  wasm_engine_t *eng = engine();
  wasmtime_store_t *store = wasmtime_store_new(eng, NULL, NULL);
  wasmtime_module_t *module;
  wasmtime_linker_t *linker;
  wasmtime_error_t *error;
  wasm_trap_t *trap = NULL;
  wasi_config_t *wasi = wasi_config_new();
  const char *argv[] = {"golem.wasm"};
  int32_t a[2];
  uint32_t in_ptr, out_ptr, out_len;
  size_t len;
  uint8_t *input = slurp(stdin, &len);
  context = wasmtime_store_context(store);
  if ((error = wasmtime_module_deserialize_file(eng, cwasm_path, &module)) != NULL) fail("deserialize", error, NULL);
  linker = wasmtime_linker_new(eng);
  if ((error = wasmtime_linker_define_wasi(linker)) != NULL) fail("WASI", error, NULL);
  if (!wasi_config_set_argv(wasi, 1, argv)) fail("WASI argv", NULL, NULL);
  wasi_config_inherit_stderr(wasi);
  if ((error = wasmtime_context_set_wasi(context, wasi)) != NULL) fail("WASI", error, NULL);
  if ((error = wasmtime_linker_instantiate(linker, context, module, &instance, &trap)) != NULL || trap != NULL) fail("instantiate", error, trap);
  invoke("_initialize", NULL, 0, 0);
  a[0] = 0;
  a[1] = 0;
  invoke("hs_init", a, 2, 0);
  a[0] = (int32_t)len;
  in_ptr = (uint32_t)invoke("golem_alloc", a, 1, 1);
  if (len > 0) memcpy(memory_at(in_ptr, len), input, len);
  a[0] = (int32_t)in_ptr;
  a[1] = (int32_t)len;
  out_ptr = (uint32_t)invoke("golem_build_pdf", a, 2, 1);
  a[0] = (int32_t)in_ptr;
  invoke("golem_free", a, 1, 0);
  a[0] = (int32_t)out_ptr;
  out_len = (uint32_t)invoke("golem_result_len", a, 1, 1);
  if (fwrite(memory_at(out_ptr, out_len), 1, out_len, stdout) != out_len || fflush(stdout) != 0) fail("cannot write the result frame", NULL, NULL);
  /* as in compile, nothing is freed */
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 4 && strcmp(argv[1], "compile") == 0) return compile(argv[2], argv[3]);
  if (argc == 3 && strcmp(argv[1], "call") == 0) return call(argv[2]);
  fprintf(stderr, "usage: run-wasmtime compile WASM CWASM | run-wasmtime call CWASM\n");
  return 2;
}
