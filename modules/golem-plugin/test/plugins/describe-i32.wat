;; golem_describe returns an i32 where the ABI wants an i64 (docs/adr ADR
;; 0035): the host checks the type of the result instead of reading the
;; other half of the value.
(module
  (memory (export "memory") 1)
  (func (export "golem_abi_version") (result i32) (i32.const 6))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i32) (i32.const 3))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
