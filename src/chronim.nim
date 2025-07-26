import std/[asyncdispatch, os, json]
import chronim/[devtools, chrome, eventemitter]

when defined(linux) or defined(macosx):
  setEnv("RES_OPTIONS", "inet6=off")

proc CDP*(options: JsonNode = nil, callback: EventHandler = nil): Future[EventEmitter] {.async.} =
  let notifier = newEventEmitter()
  if callback != nil:
    asyncSpawn proc() =
      await sleepAsync(0)
      discard newChrome(options, notifier)
    notifier.once("connect", callback)
    return notifier
  else:
    var fut = newFuture[EventEmitter]()
    notifier.once("connect", proc(args: seq[JsonNode]) = fut.complete(notifier))
    notifier.once("error", proc(args: seq[JsonNode]) =
      let msg = if args.len > 0: args[0].getStr() else: "Unknown error"
      fut.fail(newException(IOError, msg))
    )
    discard newChrome(options, notifier)
    return await fut

