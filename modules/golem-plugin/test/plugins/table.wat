;; A table of 20 000 000 elements: beyond the host's limit on table
;; elements (docs/adr ADR 0035), so it cannot be instantiated.
(module
  (table 20000000 funcref)
  (memory (export "memory") 1)
  (func (export "golem_abi_version") (result i32) (i32.const 6))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64) (i64.const 0))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
