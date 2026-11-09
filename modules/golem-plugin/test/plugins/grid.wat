;; A block command "grid" (docs/adr/0122) that answers @grid, without
;; arguments or body, with one paragraph "表" at the span of the call.
;; The request is 87 02 64 "grid" 80 80, the span, then 80 (no context)
;; and 80 (no data), so the span is the bytes from 9 to two before the
;; end. The response is
;; [[[[span, null, null, [10, null, [[0, span, "表"]]]]], []], []]: the blocks
;; and no images (docs/adr/0123), then no diagnostics.
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 65536))
  ;; {"blocks": ["grid"]}
  (data (i32.const 16) "\a1\66blocks\81\64grid")
  ;; the bytes before the first span, between the spans and after the second
  (data (i32.const 64) "\82\82\81\84")
  (data (i32.const 80) "\f6\f6\83\0a\f6\81\83\00")
  (data (i32.const 96) "\63\e8\a1\a8\80\80")
  (func $alloc (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_abi_version") (result i32) (i32.const 9))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 14)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $sl i32) (local $out i32) (local $o i32)
    (local.set $sl (i32.sub (local.get $len) (i32.const 11)))
    (local.set $out (call $alloc (i32.add (i32.mul (local.get $sl) (i32.const 2)) (i32.const 18))))
    (memory.copy (local.get $out) (i32.const 64) (i32.const 4))
    (local.set $o (i32.add (local.get $out) (i32.const 4)))
    (memory.copy (local.get $o) (i32.add (local.get $ptr) (i32.const 9)) (local.get $sl))
    (local.set $o (i32.add (local.get $o) (local.get $sl)))
    (memory.copy (local.get $o) (i32.const 80) (i32.const 8))
    (local.set $o (i32.add (local.get $o) (i32.const 8)))
    (memory.copy (local.get $o) (i32.add (local.get $ptr) (i32.const 9)) (local.get $sl))
    (local.set $o (i32.add (local.get $o) (local.get $sl)))
    (memory.copy (local.get $o) (i32.const 96) (i32.const 6))
    (local.set $o (i32.add (local.get $o) (i32.const 6)))
    (i64.or (i64.shl (i64.extend_i32_u (local.get $out)) (i64.const 32))
      (i64.extend_i32_u (i32.sub (local.get $o) (local.get $out))))))
