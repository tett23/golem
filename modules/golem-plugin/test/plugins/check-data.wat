;; fixed.wat with golem_check_data (docs/adr/0120): a plugin that
;; answers every command request and every check of its data with a fixed
;; response. The test fills in the placeholders: the CBOR of
;; golem_describe, the response of golem_invoke and the one of
;; golem_check_data.
(module
  (memory (export "memory") 1)
  (global $heap (mut i32) (i32.const 8192))
  (data (i32.const 16) "{{DESCRIBE}}")
  (data (i32.const 1024) "{{RESPONSE}}")
  (data (i32.const 4096) "{{CHECK}}")
  (func (export "golem_abi_version") (result i32) (i32.const 9))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const {{DESCRIBE_LEN}})))
  (func (export "golem_invoke") (param i32 i32) (result i64)
    (i64.or (i64.shl (i64.const 1024) (i64.const 32)) (i64.const {{RESPONSE_LEN}})))
  (func (export "golem_check_data") (param i32 i32) (result i64)
    (i64.or (i64.shl (i64.const 4096) (i64.const 32)) (i64.const {{CHECK_LEN}}))))
