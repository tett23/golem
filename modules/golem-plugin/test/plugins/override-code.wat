;; Provides the command "code" (a built-in command a plugin may override,
;; docs/adr ADR 0031) and no filters. Never invoked.
(module
  (memory (export "memory") 1)
  ;; [["code"], []]
  (data (i32.const 16) "\82\81\64code\80")
  (func (export "golem_abi_version") (result i32) (i32.const 7))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 8)))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
