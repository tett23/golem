;; A command "echo" that answers with the bytes of its request, so that a
;; test reads the CBOR the host sent (docs/adr ADR 0101).
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 65536))
  ;; [["echo"], [], []]
  (data (i32.const 16) "\83\81\64echo\80\80")
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 9)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (i64.or (i64.shl (i64.extend_i32_u (local.get $ptr)) (i64.const 32))
      (i64.extend_i32_u (local.get $len)))))
