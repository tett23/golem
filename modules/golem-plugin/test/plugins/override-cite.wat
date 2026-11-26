;; Provides the command "cite" (a built-in command a plugin may override
;; since root ADR 0471) and no filters. Never invoked.
(module
  (memory (export "memory") 1)
  ;; {"commands": ["cite"]}
  (data (i32.const 16) "\a1\68commands\81\64cite")
  (func (export "golem_abi_version") (result i32) (i32.const 9))
  (func (export "golem_alloc") (param i32) (result i32) (i32.const 4096))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 16)))
  (func (export "golem_invoke") (param i32 i32) (result i64) (i64.const 0)))
