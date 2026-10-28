;; A command "nan" and a filter "nan" that answer with a deferred
;; expression [1, span, NaN], a float without a finite value (G06100,
;; docs/adr ADR 0101). A command request starts with [0, ...], a filter
;; request with [1, ...].
(module
  (memory (export "memory") 1)
  (global $heap (mut i32) (i32.const 8192))
  ;; [["nan"], ["nan"], []]
  (data (i32.const 16) "\83\81\63nan\81\63nan\80")
  ;; [[[11, [0, 0, 0], [1, [0, 0, 0], NaN]]], []]
  (data (i32.const 1024) "\82\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7e\00\80")
  ;; [[8, 0, [[[0, 0, 0], null, [10, null, [the inline above]]]]], []]
  (data (i32.const 2048) "\82\83\08\00\81\83\83\00\00\00\f6\83\0a\f6\81\83\0b\83\00\00\00\83\01\83\00\00\00\f9\7e\00\80")
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 12)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (if (i32.eqz (i32.load8_u (i32.add (local.get $ptr) (i32.const 1))))
      (then (return (i64.or (i64.shl (i64.const 1024) (i64.const 32)) (i64.const 18)))))
    (i64.or (i64.shl (i64.const 2048) (i64.const 32)) (i64.const 31))))
