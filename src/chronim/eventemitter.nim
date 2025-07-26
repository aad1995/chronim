import tables, sequtils

type
  EventHandler = proc(args: seq[JsonNode]) {.gcsafe.}
  EventEmitter* = ref object
    handlers: Table[string, seq[EventHandler]]

proc newEventEmitter*(): EventEmitter =
  EventEmitter(handlers: initTable[string, seq[EventHandler]]())

proc on*(self: EventEmitter, event: string, handler: EventHandler) =
  if not self.handlers.hasKey(event):
    self.handlers[event] = @[]
  self.handlers[event].add(handler)

proc once*(self: EventEmitter, event: string, handler: EventHandler) =
  var wrapper: EventHandler
  wrapper = proc(args: seq[JsonNode]) =
    handler(args)
    # Remove after first call
    self.handlers[event] = self.handlers[event].filterIt(it != wrapper)
  self.on(event, wrapper)

proc emit*(self: EventEmitter, event: string, args: seq[JsonNode] = @[]) =
  if self.handlers.hasKey(event):
    for handler in self.handlers[event]:
      handler(args)