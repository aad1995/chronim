import std/[unittest, asyncdispatch, json]
import chronim
suite "CDP sync smoke test":
  test "CDP connects to Chrome":
    let options = %*{"host": "localhost", "port": 9222}
    let emitter = waitFor CDP(options)
    check not emitter.isNil

#[
Make sure Chrome is running:
chrome --remote-debugging-port=9222

Run your test with Nim:
nimble test
or
nim c -r tests/test_google.nim
]#