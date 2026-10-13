;; Grows its memory until the host refuses, then traps.
(module
  (memory (export "memory") 1)
  (data (i32.const 16) "\82\80\80")
  (func (export "golem_abi_version") (result i32) (i32.const 3))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 3)))
  (func (export "golem_invoke") (param i32 i32) (result i64)
    (loop $grow
      (if (i32.eq (memory.grow (i32.const 256)) (i32.const -1))
        (then unreachable))
      (br $grow))
    (i64.const 0)))
