;; A command "datum" that takes the data "table" (docs/adr/0105) and
;; answers with its bytes as one text at the span of the call.
;; Without the data it answers with no inlines and its own error
;; no-table at the span of the call. The data is found by the first [name, bytes] pair
;; named "table" in the request (82 65 "table"); the request of [datum]
;; has no other.
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 65536))
  ;; {"data": ["table"], "commands": ["datum"]}
  (data (i32.const 16) "\a2\64data\81\65table\68commands\81\65datum")
  ;; the pair the request carries the data in
  (data (i32.const 64) "\82\65table")
  ;; [[], [["no-table", 0, span, "no table"]]]: before and after the span
  (data (i32.const 128) "\82\80\81\84\68no-table\00")
  (data (i32.const 160) "\68no table")
  (func $alloc (export "golem_alloc") (param $n i32) (result i32) (local $p i32) (local $end i32)
    (local.set $p (global.get $heap))
    (local.set $end (i32.add (local.get $p) (local.get $n)))
    (if (i32.gt_u (local.get $end) (i32.mul (memory.size) (i32.const 65536)))
      (then
        (if (i32.lt_s
              (memory.grow (i32.sub (i32.shr_u (i32.add (local.get $end) (i32.const 65535)) (i32.const 16)) (memory.size)))
              (i32.const 0))
          (then (unreachable)))))
    (global.set $heap (local.get $end))
    (local.get $p))
  ;; copies n bytes from src to dst; the end of dst
  (func $copy (param $dst i32) (param $src i32) (param $n i32) (result i32) (local $j i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $j) (local.get $n)))
        (i32.store8 (i32.add (local.get $dst) (local.get $j)) (i32.load8_u (i32.add (local.get $src) (local.get $j))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $next)))
    (i32.add (local.get $dst) (local.get $n)))
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 29)))
  ;; the 7 bytes at $at are the pair's head
  (func $isPair (param $at i32) (result i32) (local $i i32)
    (block $no
      (loop $next
        (br_if $no (i32.ne (i32.load8_u (i32.add (local.get $at) (local.get $i)))
                           (i32.load8_u (i32.add (i32.const 64) (local.get $i)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br_if $next (i32.lt_u (local.get $i) (i32.const 7))))
      (return (i32.const 1)))
    (i32.const 0))
  (func $be (param $at i32) (param $k i32) (result i32) (local $v i32) (local $i i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (local.get $k)))
        (local.set $v (i32.or (i32.shl (local.get $v) (i32.const 8))
                              (i32.load8_u (i32.add (local.get $at) (local.get $i)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (local.get $v))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $i i32) (local $h i32) (local $b i32) (local $k i32) (local $n i32) (local $src i32)
    (local $out i32) (local $o i32) (local $j i32) (local $sl i32)
    ;; find the pair
    (local.set $h (i32.const -1))
    (block $found
      (loop $scan
        (br_if $found (i32.gt_u (i32.add (local.get $i) (i32.const 7)) (local.get $len)))
        (if (call $isPair (i32.add (local.get $ptr) (local.get $i)))
          (then (local.set $h (i32.add (local.get $ptr) (i32.add (local.get $i) (i32.const 7)))) (br $found)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $scan)))
    ;; without the data the request ends with the span, 80 (the context, docs/adr/0121) and 80
    (if (i32.eq (local.get $h) (i32.const -1))
      (then
        (local.set $sl (i32.sub (local.get $len) (i32.const 12)))
        (local.set $out (call $alloc (i32.add (local.get $sl) (i32.const 23))))
        (local.set $o (call $copy (local.get $out) (i32.const 128) (i32.const 14)))
        (local.set $o (call $copy (local.get $o) (i32.add (local.get $ptr) (i32.const 10)) (local.get $sl)))
        (local.set $o (call $copy (local.get $o) (i32.const 160) (i32.const 9)))
        (return (i64.or (i64.shl (i64.extend_i32_u (local.get $out)) (i64.const 32))
          (i64.extend_i32_u (i32.sub (local.get $o) (local.get $out)))))))
    ;; the head of the byte string: its length in the byte or in 1, 2 or 4 bytes after it
    (local.set $b (i32.load8_u (local.get $h)))
    (if (i32.lt_u (local.get $b) (i32.const 0x58))
      (then (local.set $n (i32.sub (local.get $b) (i32.const 0x40))))
      (else
        (local.set $k (i32.shl (i32.const 1) (i32.sub (local.get $b) (i32.const 0x58))))
        (local.set $n (call $be (i32.add (local.get $h) (i32.const 1)) (local.get $k)))))
    (local.set $src (i32.add (local.get $h) (i32.add (local.get $k) (i32.const 1))))
    ;; [[[0, span, text]], []], the span of the call: the request of
    ;; [datum] is 87 00 65 "datum" 80 80, the span, 80 (the context,
    ;; docs/adr/0121), then 81 and the pair
    (local.set $sl (i32.sub (local.get $i) (i32.const 12)))
    (local.set $out (call $alloc (i32.add (local.get $n) (i32.add (local.get $sl) (i32.const 16)))))
    (i32.store8 (local.get $out) (i32.const 0x82))
    (i32.store8 (i32.add (local.get $out) (i32.const 1)) (i32.const 0x81))
    (i32.store8 (i32.add (local.get $out) (i32.const 2)) (i32.const 0x83))
    (i32.store8 (i32.add (local.get $out) (i32.const 3)) (i32.const 0x00))
    (local.set $j (i32.const 0))
    (block $spanned
      (loop $span
        (br_if $spanned (i32.ge_u (local.get $j) (local.get $sl)))
        (i32.store8 (i32.add (local.get $out) (i32.add (local.get $j) (i32.const 4)))
          (i32.load8_u (i32.add (local.get $ptr) (i32.add (local.get $j) (i32.const 10)))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $span)))
    ;; the same head with the major type of a text string
    (local.set $o (i32.add (local.get $out) (i32.add (local.get $sl) (i32.const 4))))
    (local.set $j (i32.const 0))
    (block $copied
      (loop $copy
        (br_if $copied (i32.gt_u (local.get $j) (local.get $k)))
        (i32.store8 (i32.add (local.get $o) (local.get $j))
          (i32.add (i32.load8_u (i32.add (local.get $h) (local.get $j)))
                   (select (i32.const 0x20) (i32.const 0) (i32.eqz (local.get $j)))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $copy)))
    (local.set $o (i32.add (local.get $o) (i32.add (local.get $k) (i32.const 1))))
    (local.set $j (i32.const 0))
    (block $done
      (loop $bytes
        (br_if $done (i32.ge_u (local.get $j) (local.get $n)))
        (i32.store8 (i32.add (local.get $o) (local.get $j)) (i32.load8_u (i32.add (local.get $src) (local.get $j))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br $bytes)))
    (local.set $o (i32.add (local.get $o) (local.get $n)))
    (i32.store8 (local.get $o) (i32.const 0x80))
    (i64.or (i64.shl (i64.extend_i32_u (local.get $out)) (i64.const 32))
      (i64.extend_i32_u (i32.add (i32.sub (local.get $o) (local.get $out)) (i32.const 1))))))
