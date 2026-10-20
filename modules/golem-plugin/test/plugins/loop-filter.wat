;; Provides the filter "spin", which loops forever in golem_invoke:
;; stopped by fuel.
(module
  (memory (export "memory") 1)
  ;; [[], ["spin"], []]
  (data (i32.const 16) "\83\80\81\64spin\80")
  (func (export "golem_abi_version") (result i32) (i32.const 7))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 9)))
  (func (export "golem_invoke") (param i32 i32) (result i64) (local $i i64)
    (loop $forever
      (local.set $i (i64.add (local.get $i) (i64.const 1)))
      (br $forever))
    (i64.const 0)))
