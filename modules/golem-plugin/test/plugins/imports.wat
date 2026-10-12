;; Asks for a host function: must be rejected when loading.
(module
  (import "env" "now" (func $now (result i64)))
  (memory (export "memory") 1)
  (func (export "golem_abi_version") (result i32) (i32.const 2)))
