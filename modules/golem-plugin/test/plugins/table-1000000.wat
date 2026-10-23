;; A fixed-response plugin with a table of exactly 1 000 000 elements: the
;; host's limit on table elements (docs/adr ADR 0035, ADR 0068), so it can be
;; instantiated. The test fills in the placeholders as for fixed.wat.
(module
  (table 1000000 funcref)
  (memory (export "memory") 1)
  (global $heap (mut i32) (i32.const 8192))
  (data (i32.const 16) "{{DESCRIBE}}")
  (data (i32.const 1024) "{{RESPONSE}}")
  (func (export "golem_abi_version") (result i32) (i32.const {{ABI}}))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const {{DESCRIBE_LEN}})))
  (func (export "golem_invoke") (param i32 i32) (result i64)
    (i64.or (i64.shl (i64.const 1024) (i64.const 32)) (i64.const {{RESPONSE_LEN}}))))
