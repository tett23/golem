;; root ADR 0473 A2: echo the host's body CBOR without rebuilding its blocks.
;; body-one / body-two assert that the host passed exactly one / two blocks.
;; Requests have no arguments and the fixed eight-byte command names above:
;; 87 02 68 <name> 80 <body> <span> <context> <data>, so body starts at byte 12.
;; skip reads only valid, definite-length CBOR produced by the host, bounded
;; by this test's two-page memory. It is not a decoder for untrusted CBOR.
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 65536))
  ;; {"blocks": ["body-one", "body-two"]}
  (data (i32.const 16) "\a1\66blocks\82\68body-one\68body-two")
  (func (export "golem_abi_version") (result i32) (i32.const 9))
  (func $alloc (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 27)))
  ;; The end of one host-generated CBOR value: its header, bytes or children.
  (func $skip (param $p i32) (result i32)
    (local $major i32) (local $arg i32) (local $width i32) (local $n i32)
    (local.set $major (i32.shr_u (i32.load8_u (local.get $p)) (i32.const 5)))
    (local.set $arg (i32.and (i32.load8_u (local.get $p)) (i32.const 31)))
    (local.set $p (i32.add (local.get $p) (i32.const 1)))
    (if (i32.ge_u (local.get $arg) (i32.const 24))
      (then
        (if (i32.gt_u (local.get $arg) (i32.const 27)) (then unreachable))
        (local.set $width (i32.shl (i32.const 1) (i32.sub (local.get $arg) (i32.const 24))))
        (local.set $arg (i32.const 0))
        (loop $bytes
          (local.set $arg (i32.or (i32.shl (local.get $arg) (i32.const 8)) (i32.load8_u (local.get $p))))
          (local.set $p (i32.add (local.get $p) (i32.const 1)))
          (local.set $width (i32.sub (local.get $width) (i32.const 1)))
          (br_if $bytes (local.get $width)))))
    (if (i32.or (i32.eq (local.get $major) (i32.const 2)) (i32.eq (local.get $major) (i32.const 3)))
      (then (return (i32.add (local.get $p) (local.get $arg)))))
    (if (i32.or (i32.eq (local.get $major) (i32.const 4)) (i32.eq (local.get $major) (i32.const 5)))
      (then
        (local.set $n (local.get $arg))
        (if (i32.eq (local.get $major) (i32.const 5))
          (then (local.set $n (i32.mul (local.get $n) (i32.const 2)))))
        (block $done
          (loop $children
            (br_if $done (i32.eqz (local.get $n)))
            (local.set $p (call $skip (local.get $p)))
            (local.set $n (i32.sub (local.get $n) (i32.const 1)))
            (br $children)))))
    (if (i32.eq (local.get $major) (i32.const 6))
      (then (local.set $p (call $skip (local.get $p)))))
    (local.get $p))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $body i32) (local $size i32) (local $count i32) (local $out i32)
    (local.set $body (i32.add (local.get $ptr) (i32.const 12)))
    (local.set $count (if (result i32) (i32.eq (i32.load8_u (i32.add (local.get $ptr) (i32.const 10))) (i32.const 101))
      (then (i32.const 1)) (else (i32.const 2))))
    (if (i32.ne (i32.load8_u (local.get $body)) (i32.add (i32.const 128) (local.get $count)))
      (then unreachable))
    (local.set $size (i32.sub (call $skip (local.get $body)) (local.get $body)))
    (local.set $out (call $alloc (i32.add (local.get $size) (i32.const 4))))
    ;; [[body, []], []]: original blocks, no images, no diagnostics.
    (i32.store8 (local.get $out) (i32.const 130))
    (i32.store8 (i32.add (local.get $out) (i32.const 1)) (i32.const 130))
    (memory.copy (i32.add (local.get $out) (i32.const 2)) (local.get $body) (local.get $size))
    (i32.store8 (i32.add (i32.add (local.get $out) (i32.const 2)) (local.get $size)) (i32.const 128))
    (i32.store8 (i32.add (i32.add (local.get $out) (i32.const 3)) (local.get $size)) (i32.const 128))
    (i64.or (i64.shl (i64.extend_i32_u (local.get $out)) (i64.const 32))
      (i64.extend_i32_u (i32.add (local.get $size) (i32.const 4))))))
