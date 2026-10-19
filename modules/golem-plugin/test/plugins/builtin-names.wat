;; Provides the commands "ruby" (a built-in command a plugin may override)
;; and "note" (one it may not), and no filters. Never invoked: the
;; collisions stop the build before evaluation.
(module
  (memory (export "memory") 1)
  ;; [["ruby", "note"], [], []]
  (data (i32.const 16) "\83\82\64ruby\64note\80\80")
  (func (export "golem_abi_version") (result i32) (i32.const 7))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 14)))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
