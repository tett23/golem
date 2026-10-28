;; Commands "nan", "inf" and "ninf" and filters of the same names that
;; answer with a deferred expression [1, span, x], a float without a
;; finite value (G06100, docs/adr ADR 0101): NaN, Infinity and -Infinity.
;; A command request starts with [0, name, ...], a filter request with
;; [1, name, ...]; the name tells the value.
(module
  (memory (export "memory") 1)
  (global $heap (mut i32) (i32.const 8192))
  ;; [["nan", "inf", "ninf"], ["nan", "inf", "ninf"], []]
  (data (i32.const 16) "\83\83\63nan\63inf\64ninf\83\63nan\63inf\64ninf\80")
  ;; [[[11, [0, 0, 0], [1, [0, 0, 0], NaN]]], []]
  (data (i32.const 1024) "\82\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7e\00\80")
  ;; [[8, 0, [[[0, 0, 0], null, [10, null, [the inline above]]]]], []]
  (data (i32.const 2048) "\82\83\08\00\81\83\83\00\00\00\f6\83\0a\f6\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7e\00\80")
  ;; the two answers again with Infinity
  (data (i32.const 3072) "\82\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7c\00\80")
  (data (i32.const 4096) "\82\83\08\00\81\83\83\00\00\00\f6\83\0a\f6\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7c\00\80")
  ;; and with -Infinity
  (data (i32.const 5120) "\82\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\fc\00\80")
  (data (i32.const 6144) "\82\83\08\00\81\83\83\00\00\00\f6\83\0a\f6\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\fc\00\80")
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 30)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64) (local $at i32)
    ;; the answer of the command: "nan" (3 letters, n), "inf" (i), "ninf" (4 letters)
    (local.set $at (i32.const 1024))
    (if (i32.eq (i32.load8_u (i32.add (local.get $ptr) (i32.const 3))) (i32.const 0x69))
      (then (local.set $at (i32.const 3072))))
    (if (i32.eq (i32.load8_u (i32.add (local.get $ptr) (i32.const 2))) (i32.const 0x64))
      (then (local.set $at (i32.const 5120))))
    (if (i32.eqz (i32.load8_u (i32.add (local.get $ptr) (i32.const 1))))
      (then (return (i64.or (i64.shl (i64.extend_i32_u (local.get $at)) (i64.const 32)) (i64.const 18)))))
    ;; the answer of the filter is 1024 bytes after it
    (i64.or (i64.shl (i64.extend_i32_u (i32.add (local.get $at) (i32.const 1024))) (i64.const 32)) (i64.const 31))))
