;; A plugin that declares the channels index, a reserved name, and
;; Glossary, a malformed one (golem-doc ADR 0007): G06012 when it is loaded.
(module
  (memory (export "memory") 1)
  (global $heap (mut i32) (i32.const 1024))
  ;; [[], [], [["index", 0, false], ["Glossary", 0, false]]]
  (data (i32.const 16) "\83\80\80\82\83\65index\00\f4\83\68Glossary\00\f4")
  (func (export "golem_abi_version") (result i32) (i32.const 7))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 25)))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
