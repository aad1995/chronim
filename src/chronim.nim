import std/[asyncdispatch, json]
import chronim/[chrome, eventemitter]

when defined(linux) or defined(macosx):
  setEnv("RES_OPTIONS", "inet6=off")


proc CDP*(
  options: JsonNode = nil,
  callback: EventHandler = nil
): Future[(Chrome, EventEmitter)] {.async.} =
  let notifier = newEventEmitter()
  let chrome = newChrome(options, notifier)
  if callback != nil:
    notifier.once("connect", callback)
    asyncCheck (proc() {.async.} =
      discard chrome
    )()
    return (chrome, notifier)
  else:
    var fut = newFuture[(Chrome, EventEmitter)]()
    notifier.once("connect", proc(params: JsonNode, sessionId: string) =
      fut.complete((chrome, notifier))
    )
    notifier.once("error", proc(params: JsonNode, sessionId: string) =
      let msg =
        if params.kind == JString: params.getStr()
        elif params.kind == JObject and params.hasKey("message"): params["message"].getStr()
        else: "Unknown error"
      fut.fail(newException(IOError, msg))
    )
    discard chrome
    return await fut