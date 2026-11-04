;; A filter "same" that returns the document it receives, and a command
;; "broken" that answers with an empty response (invalid).
;; Filter request: [1, name, document, data] with a name shorter than 24
;; bytes and no data, so the document starts at byte 3 + name length and
;; ends one byte (the empty data, 0x80) before the request (docs/adr/0105).
(module
  (memory (export "memory") 2)
  (global $heap (mut i32) (i32.const 65536))
  ;; {"filters": ["same"], "commands": ["broken"]}
  (data (i32.const 16) "\a2\67filters\81\64same\68commands\81\66broken")
  (func (export "golem_abi_version") (result i32) (i32.const 8))
  (func (export "golem_alloc") (param $n i32) (result i32) (local $p i32)
    (local.set $p (global.get $heap))
    (global.set $heap (i32.add (global.get $heap) (local.get $n)))
    (local.get $p))
  (func (export "golem_dealloc") (param i32 i32))
  (func (export "golem_describe") (result i64)
    (i64.or (i64.shl (i64.const 16) (i64.const 32)) (i64.const 32)))
  (func (export "golem_invoke") (param $ptr i32) (param $len i32) (result i64)
    (local $skip i32) (local $doc i32)
    ;; a command request starts with [0, ...]: answer nothing
    (if (i32.eqz (i32.load8_u (i32.add (local.get $ptr) (i32.const 1))))
      (then (return (i64.const 0))))
    (local.set $skip (i32.add (i32.const 3)
      (i32.and (i32.load8_u (i32.add (local.get $ptr) (i32.const 2))) (i32.const 31))))
    (local.set $doc (i32.sub (i32.sub (local.get $len) (local.get $skip)) (i32.const 1)))
    ;; response = [document, []] at 1024
    (i32.store8 (i32.const 1024) (i32.const 0x82))
    (memory.copy (i32.const 1025) (i32.add (local.get $ptr) (local.get $skip)) (local.get $doc))
    (i32.store8 (i32.add (i32.const 1025) (local.get $doc)) (i32.const 0x80))
    (i64.or (i64.shl (i64.const 1024) (i64.const 32))
      (i64.extend_i32_u (i32.add (local.get $doc) (i32.const 2))))))
