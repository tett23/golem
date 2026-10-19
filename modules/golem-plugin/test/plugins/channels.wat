;; Two channels of a plugin (golem-doc ADR 0007): glossary, in reading
;; order without locators, and people, in document order with locators.
;; The command term sends its slot to glossary, person to people; each
;; answers the slot, then an item of the call's span whose body is the slot.
;; The first positional argument is the key, the second the reading; a
;; missing one is null. Request: [0, name, args, [slot], span].
(module
  (memory (export "memory") 4)
  (global $heap (mut i32) (i32.const 65536))
  ;; [["term", "person"], [], [["glossary", 1, false], ["people", 0, true]]]
  (data (i32.const 16) "\83\82\64term\66person\80\82\83\68glossary\01\f4\83\66people\00\f5")
  (data (i32.const 64) "\68glossary")
  (data (i32.const 80) "\66people")
  (func (export "golem_abi_version") (result i32) (i32.const 7))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 38)))
  ;; the length of the head of the CBOR item at p
  (func $head (param $p i32) (result i32) (local $ai i32)
    (local.set $ai (i32.and (i32.load8_u (local.get $p)) (i32.const 31)))
    (if (i32.lt_u (local.get $ai) (i32.const 24)) (then (return (i32.const 1))))
    (if (i32.eq (local.get $ai) (i32.const 24)) (then (return (i32.const 2))))
    (if (i32.eq (local.get $ai) (i32.const 25)) (then (return (i32.const 3))))
    (if (i32.eq (local.get $ai) (i32.const 26)) (then (return (i32.const 5))))
    (i32.const 9))
  ;; the argument of the head at p (lengths and counts below 2^32)
  (func $arg (param $p i32) (result i32) (local $ai i32)
    (local.set $ai (i32.and (i32.load8_u (local.get $p)) (i32.const 31)))
    (if (i32.lt_u (local.get $ai) (i32.const 24)) (then (return (local.get $ai))))
    (if (i32.eq (local.get $ai) (i32.const 24))
      (then (return (i32.load8_u (i32.add (local.get $p) (i32.const 1))))))
    (if (i32.eq (local.get $ai) (i32.const 25))
      (then (return (i32.or
        (i32.shl (i32.load8_u (i32.add (local.get $p) (i32.const 1))) (i32.const 8))
        (i32.load8_u (i32.add (local.get $p) (i32.const 2)))))))
    (i32.or
      (i32.or
        (i32.shl (i32.load8_u (i32.add (local.get $p) (i32.const 1))) (i32.const 24))
        (i32.shl (i32.load8_u (i32.add (local.get $p) (i32.const 2))) (i32.const 16)))
      (i32.or
        (i32.shl (i32.load8_u (i32.add (local.get $p) (i32.const 3))) (i32.const 8))
        (i32.load8_u (i32.add (local.get $p) (i32.const 4))))))
  ;; the byte after the CBOR item at p
  (func $skip (param $p i32) (result i32) (local $mt i32) (local $n i32) (local $q i32)
    (local.set $mt (i32.shr_u (i32.load8_u (local.get $p)) (i32.const 5)))
    (local.set $q (i32.add (local.get $p) (call $head (local.get $p))))
    (if (i32.or (i32.eq (local.get $mt) (i32.const 2)) (i32.eq (local.get $mt) (i32.const 3)))
      (then (return (i32.add (local.get $q) (call $arg (local.get $p))))))
    (if (i32.eq (local.get $mt) (i32.const 6)) (then (return (call $skip (local.get $q)))))
    (if (i32.or (i32.eq (local.get $mt) (i32.const 4)) (i32.eq (local.get $mt) (i32.const 5)))
      (then
        (local.set $n (call $arg (local.get $p)))
        (if (i32.eq (local.get $mt) (i32.const 5)) (then (local.set $n (i32.shl (local.get $n) (i32.const 1)))))
        (block $done
          (loop $next
            (br_if $done (i32.eqz (local.get $n)))
            (local.set $q (call $skip (local.get $q)))
            (local.set $n (i32.sub (local.get $n) (i32.const 1)))
            (br $next)))))
    (local.get $q))
  ;; copies [from, to) to dst and returns the byte after it
  (func $copy (param $dst i32) (param $from i32) (param $to i32) (result i32)
    (memory.copy (local.get $dst) (local.get $from) (i32.sub (local.get $to) (local.get $from)))
    (i32.add (local.get $dst) (i32.sub (local.get $to) (local.get $from))))
  ;; the value of the argument at a ([0, value]), or null at o
  (func $value (param $o i32) (param $a i32) (result i32)
    (call $copy (local.get $o) (i32.add (local.get $a) (i32.const 2)) (call $skip (local.get $a))))
  (func $null (param $o i32) (result i32)
    (i32.store8 (local.get $o) (i32.const 0xf6))
    (i32.add (local.get $o) (i32.const 1)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $name i32) (local $args i32) (local $slots i32) (local $span i32)
    (local $nargs i32) (local $a1 i32) (local $a2 i32) (local $slot i32) (local $slotEnd i32) (local $o i32)
    (local.set $name (i32.add (local.get $ptr) (i32.const 2)))
    (local.set $args (call $skip (local.get $name)))
    (local.set $slots (call $skip (local.get $args)))
    (local.set $span (call $skip (local.get $slots)))
    (local.set $nargs (call $arg (local.get $args)))
    (local.set $a1 (i32.add (local.get $args) (i32.const 1)))
    (local.set $a2 (call $skip (local.get $a1)))
    (local.set $slot (i32.add (local.get $slots) (i32.const 1)))
    (local.set $slotEnd (call $skip (local.get $slot)))
    ;; [[the inlines of the slot..., item], []]
    (i32.store8 (i32.const 4096) (i32.const 0x82))
    (i32.store8 (i32.const 4097) (i32.add (i32.const 0x81) (call $arg (local.get $slot))))
    (local.set $o (call $copy (i32.const 4098)
      (i32.add (local.get $slot) (call $head (local.get $slot))) (local.get $slotEnd)))
    ;; [19, span, channel, key, reading, slot]
    (i32.store8 (local.get $o) (i32.const 0x86))
    (i32.store8 (i32.add (local.get $o) (i32.const 1)) (i32.const 0x13))
    (local.set $o (call $copy (i32.add (local.get $o) (i32.const 2))
      (local.get $span) (i32.add (local.get $ptr) (local.get $len))))
    (if (i32.eq (i32.load8_u (local.get $name)) (i32.const 0x64))
      (then (local.set $o (call $copy (local.get $o) (i32.const 64) (i32.const 73))))
      (else (local.set $o (call $copy (local.get $o) (i32.const 80) (i32.const 87)))))
    (if (i32.ge_u (local.get $nargs) (i32.const 1))
      (then (local.set $o (call $value (local.get $o) (local.get $a1))))
      (else (local.set $o (call $null (local.get $o)))))
    (if (i32.ge_u (local.get $nargs) (i32.const 2))
      (then (local.set $o (call $value (local.get $o) (local.get $a2))))
      (else (local.set $o (call $null (local.get $o)))))
    (local.set $o (call $copy (local.get $o) (local.get $slot) (local.get $slotEnd)))
    (i32.store8 (local.get $o) (i32.const 0x80))
    (i64.or (i64.shl (i64.const 4096) (i64.const 32))
      (i64.extend_i32_u (i32.sub (i32.add (local.get $o) (i32.const 1)) (i32.const 4096))))))
