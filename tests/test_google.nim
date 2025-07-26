import std/[unittest, asyncdispatch, json]
import chronim
suite "CDP smoke test":
  asyncTest "browse to google.com":
    let options = %*{"host": "localhost", "port": 9222}
    let emitter = await CDP(options)
    var loaded = false
    let chromeObj = getChromeInstance(emitter) # Or however your API works
    discard await chromeObj.send("Page.enable")
    emitter.on("Page.loadEventFired", proc(params: JsonNode, sessionId: string) =
      loaded = true
    )
    discard await chromeObj.send("Page.navigate", %*{"url": "https://www.google.com"})
    var tries = 0
    while not loaded and tries < 100:
      await sleepAsync(100)
      inc tries
    check loaded

#[
Make sure Chrome is running:
chrome --remote-debugging-port=9222

Run your test with Nim:
nimble test
or
nim c -r tests/test_google.nim
]#