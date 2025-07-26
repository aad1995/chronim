import std/[asyncdispatch, os, json]
import chronim/[devtools, chrome, eventemitter]

when defined(linux) or defined(macosx):
  setEnv("RES_OPTIONS", "inet6=off")

# EventHandler is proc(params: JsonNode, sessionId: string)
proc CDP*(
  options: JsonNode = nil,
  callback: EventHandler = nil
): Future[EventEmitter] {.async.} =
  let notifier = newEventEmitter()
  if callback != nil:
    notifier.once("connect", callback)
    asyncSpawn (proc() {.async.} =
      await sleepAsync(0)
      discard await newChrome(options, notifier)
    )()
    return notifier
  else:
    var fut = newFuture[EventEmitter]()
    notifier.once("connect", proc(params: JsonNode, sessionId: string) =
      fut.complete(notifier)
    )
    notifier.once("error", proc(params: JsonNode, sessionId: string) =
      let msg =
        if params.kind == JString: params.getStr()
        elif params.kind == JObject and params.hasKey("message"): params["message"].getStr()
        else: "Unknown error"
      fut.fail(newException(IOError, msg))
    )
    discard await newChrome(options, notifier)
    return await fut
