;; A block command "grid" (docs/adr/0123) that answers every call with no
;; blocks and one SVG image "a" of 64 MiB and one byte, one more than the
;; images of an answer may have together:
;; [[[], [["a", "svg", <67108865 spaces>]]], []].
(module
  (memory (export "memory") 1100)
  (global $heap (mut i32) (i32.const 65536))
  ;; {"blocks": ["grid"]}
  (data (i32.const 16) "\a1\66blocks\81\64grid")
  ;; the bytes before the image: the head of a byte string of 0x04000001 bytes
  (data (i32.const 64) "\82\82\80\81\83\61a\63svg\5a\04\00\00\01")
  (func $alloc (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 14)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $out i32)
    (local.set $out (call $alloc (i32.const 67108882)))
    (memory.copy (local.get $out) (i32.const 64) (i32.const 16))
    (memory.fill (i32.add (local.get $out) (i32.const 16)) (i32.const 0x20) (i32.const 67108865))
    (i32.store8 (i32.add (local.get $out) (i32.const 67108881)) (i32.const 0x80))
    (i64.or (i64.shl (i64.extend_i32_u (local.get $out)) (i64.const 32)) (i64.const 67108882))))
