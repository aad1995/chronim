import std/[unittest, asyncdispatch, json]
import chronim 

suite "CDPTests":
  asyncTest "navigate to google.com":
    let options = %*{"host": "localhost", "port": 9222}
    let emitter = await CDP(options)
    var pageLoaded = false

    let chromeObj = getChromeInstance(emitter) # Implement this or extract it from emitter

    discard await chromeObj.send("Page.enable")
    emitter.on("Page.loadEventFired", proc(params: JsonNode, sessionId: string) =
      echo "Page loaded: ", params.pretty
      pageLoaded = true
    )

    discard await chromeObj.send("Page.navigate", %*{"url": "https://www.google.com"})

    # Wait for the event or timeout
    var tries = 0
    while not pageLoaded and tries < 100:
      await sleepAsync(100)
      inc tries

    check pageLoaded
#[
Make sure Chrome is running:
chrome --remote-debugging-port=9222

Run your test with Nim:
nimble test
or
nim c -r tests/test_google.nim
]#