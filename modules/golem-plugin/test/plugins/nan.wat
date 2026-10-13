;; Returns the eight bytes of a NaN made by 0/0 with its sign flipped.
(module
  (memory (export "memory") 1)
  (data (i32.const 16) "\82\80\80")
  (func (export "golem_abi_version") (result i32) (i32.const 3))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 3)))
  (func (export "golem_invoke") (param i32 i32) (result i64)
    (f64.store (i32.const 2048)
      (f64.neg (f64.div (f64.const 0) (f64.const 0))))
    (i64.or (i64.shl (i64.const 2048) (i64.const 32)) (i64.const 8))))
