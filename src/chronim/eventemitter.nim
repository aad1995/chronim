import std/[tables, sequtils, json]

type
  EventHandler* = proc(params: JsonNode, sessionId: string)
  EventEmitter* = ref object of RootObj
    handlers: Table[string, seq[EventHandler]]

proc newEventEmitter*(): EventEmitter =
  EventEmitter(handlers: initTable[string, seq[EventHandler]]())

proc on*(self: EventEmitter, event: string, handler: EventHandler) =
  if not self.handlers.hasKey(event):
    self.handlers[event] = @[]
  self.handlers[event].add(handler)

proc once*(self: EventEmitter, event: string, handler: EventHandler) =
  var wrapper: EventHandler
  wrapper = proc(params: JsonNode, sessionId: string) =
    handler(params, sessionId)
    # Remove after first call
    if self.handlers.hasKey(event):
      self.handlers[event] = self.handlers[event].filterIt(it != wrapper)
  self.on(event, wrapper)

proc emit*(self: EventEmitter, event: string, params: JsonNode, sessionId: string = "") =
  if self.handlers.hasKey(event):
    for handler in self.handlers[event]:
      handler(params, sessionId)
