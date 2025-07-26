import std/[asyncdispatch, json, tables, strutils, websocket, uri, os, sequtils]
import api, devtools

const
  DefaultHost = "localhost"
  DefaultPort = 9222

type
  ProtocolError = object of CatchableError
    request: JsonNode
    response: JsonNode

  CallbackProc = proc(error: bool, response: JsonNode)
  ChromeNotifier = ref object of RootObj
    emit: proc(event: string, params: JsonNode, sessionId: string = "")

  Chrome* = ref object of RootObj
    host*: string
    port*: int
    secure*: bool
    useHostName*: bool
    alterPath*: proc(path: string): string
    protocol*: JsonNode
    local*: bool
    target*: JsonNode
    _notifier*: ChromeNotifier
    _callbacks*: Table[int, CallbackProc]
    _nextCommandId*: int
    webSocketUrl*: string
    _ws*: AsyncWebSocket

proc newProtocolError(request, response: JsonNode): ref ProtocolError =
  var msg = if response.hasKey("message"): response["message"].getStr() else: "Protocol Error"
  if response.hasKey("data"):
    msg &= " (" & response["data"].getStr() & ")"
  result = ProtocolError.newException(msg)
  result.request = request
  result.response = response

proc defaultTarget(targets: seq[JsonNode]): JsonNode =
  var backup: JsonNode
  for target in targets:
    if target.hasKey("webSocketDebuggerUrl"):
      if backup.isNil:
        backup = target
      if target.hasKey("type") and target["type"].getStr() == "page":
        return target
  if not backup.isNil:
    return backup
  raise newException(ValueError, "No inspectable targets")

proc newChrome*(options: JsonNode, notifier: ChromeNotifier): Chrome =
  let opts = if options.isNil: %*{} else: options
  let userTarget =
    if opts.hasKey("target"):
      opts["target"]
    else:
      nil
  result = Chrome(
    host: if opts.hasKey("host"): opts["host"].getStr() else: DefaultHost,
    port: if opts.hasKey("port"): opts["port"].getInt() else: DefaultPort,
    secure: if opts.hasKey("secure"): opts["secure"].getBool() else: false,
    useHostName: if opts.hasKey("useHostName"): opts["useHostName"].getBool() else: false,
    alterPath: (if opts.hasKey("alterPath") and opts["alterPath"].kind == JProc: 
                  cast[proc(path: string): string](opts["alterPath"].getProc())
                else: proc(path: string): string = path),
    protocol: if opts.hasKey("protocol"): opts["protocol"] else: nil,
    local: if opts.hasKey("local"): opts["local"].getBool() else: false,
    target: userTarget,
    _notifier: notifier,
    _callbacks: initTable[int, CallbackProc](),
    _nextCommandId: 1,
    webSocketUrl: "",
    _ws: nil
  )
  asyncSpawn result._start()

proc send(self: Chrome, hmethod: string, params: JsonNode = nil, sessionId: string = "", callback: CallbackProc = nil): Future[JsonNode] {.async.} =
  var cb = callback
  if cb == nil:
    var fut = newFuture[JsonNode]()
    cb = proc(error: bool, response: JsonNode) =
      if error:
        let req = %*{"method": hmethod, "params": params, "sessionId": sessionId}
        fut.fail(newProtocolError(req, response))
      else:
        fut.complete(response)
    self._enqueueCommand(hmethod, params, sessionId, cb)
    return await fut
  else:
    self._enqueueCommand(hmethod, params, sessionId, cb)
    return nil

proc close(self: Chrome, callback: proc() = nil): Future[void] {.async.} =
  proc closeWebSocket(cb: proc()) =
    if self._ws == nil or self._ws.readyState == Closed:
      cb()
    else:
      self._ws.onClose = proc() =
        self._ws = nil
        self._handleConnectionClose()
        cb()
      self._ws.close()
  if callback != nil:
    closeWebSocket(callback)
  else:
    var fut = newFuture[void]()
    closeWebSocket(proc() = fut.complete())
    await fut

proc _start(self: Chrome) {.async.} =
  var options = %*{
    "host": self.host,
    "port": self.port,
    "secure": self.secure,
    "useHostName": self.useHostName
  }
  if not isNil(self.alterPath):
    options["alterPath"] = %*self.alterPath

  try:
    let url = await self._fetchDebuggerURL(options)
    var urlObj = parseUri(url)
    urlObj.path = self.alterPath(urlObj.path)
    self.webSocketUrl = $urlObj
    options["host"] = %*urlObj.hostname
    if urlObj.port.len > 0:
      options["port"] = %*parseInt(urlObj.port)
    let protocol = await self._fetchProtocol(options)
    api.prepare(self, protocol)
    await self._connectToWebSocket()
    asyncSpawn self._notifier.emit("connect", %*{}, "")
  except CatchableError as err:
    self._notifier.emit("error", %*err.msg, "")

proc _fetchDebuggerURL(self: Chrome, options: JsonNode): Future[string] {.async.} =
  let userTarget = self.target

  if userTarget.isNil:
    let targets = await devtools.List(options)
    let obj = defaultTarget(targets.getElems())
    return obj["webSocketDebuggerUrl"].getStr()
  elif userTarget.kind == JString:
    var idOrUrl = userTarget.getStr()
    if idOrUrl.startsWith("/"):
      idOrUrl = "ws://" & self.host & ":" & $self.port & idOrUrl
    if idOrUrl.startsWith("ws:") or idOrUrl.startsWith("wss:"):
      return idOrUrl
    else:
      let targets = await devtools.List(options)
      for target in targets.getElems():
        if target.hasKey("id") and target["id"].getStr() == idOrUrl:
          return target["webSocketDebuggerUrl"].getStr()
      raise newException(ValueError, "Target not found")
  elif userTarget.kind == JObject:
    return userTarget["webSocketDebuggerUrl"].getStr()
  else:
    raise newException(ValueError, "Unsupported or missing target type")

proc _fetchProtocol(self: Chrome, options: JsonNode): Future[JsonNode] {.async.} =
  if not self.protocol.isNil:
    return self.protocol
  else:
    options["local"] = %*self.local
    return await devtools.Protocol(options)

proc _connectToWebSocket(self: Chrome): Future[void] {.async.} =
  try:
    var wsUrl = self.webSocketUrl
    if self.secure:
      wsUrl = wsUrl.replace("ws:", "wss:")
    self._ws = await newAsyncWebSocket(wsUrl)
    self._ws.onMessage = proc(data: string) =
      let message = parseJson(data)
      self._handleMessage(message)
    self._ws.onClose = proc() =
      self._handleConnectionClose()
      self._notifier.emit("disconnect", %*{}, "")
    self._ws.onError = proc(err: ref Exception) =
      self._notifier.emit("error", %*err.msg, "")
  except CatchableError as err:
    raise err

proc _handleConnectionClose(self: Chrome) =
  let err = newException(IOError, "WebSocket connection closed")
  for id, cb in self._callbacks:
    cb(true, %*{"message": err.msg})
  self._callbacks.clear()

proc _handleMessage(self: Chrome, message: JsonNode) =
  if message.hasKey("id"):
    let id = message["id"].getInt()
    if self._callbacks.hasKey(id):
      let cb = self._callbacks[id]
      if message.hasKey("error"):
        cb(true, message["error"])
      else:
        cb(false, if message.hasKey("result"): message["result"] else: %*{})
      self._callbacks.del(id)
      if self._callbacks.len == 0:
        self._notifier.emit("ready", %*{}, "")
  elif message.hasKey("method"):
    let hmethod = message["method"].getStr()
    let params = if message.hasKey("params"): message["params"] else: %*{}
    let sessionId = if message.hasKey("sessionId"): message["sessionId"].getStr() else: ""
    self._notifier.emit("event", message, "")
    self._notifier.emit(hmethod, params, sessionId)
    if sessionId.len > 0:
      self._notifier.emit(hmethod & "." & sessionId, params, sessionId)

proc _enqueueCommand(self: Chrome, hmethod: string, params: JsonNode, sessionId: string, callback: CallbackProc) =
  let id = self._nextCommandId
  self._nextCommandId.inc()
  let message = %*{
    "id": id,
    "method": hmethod,
    "sessionId": sessionId,
    "params": if params.isNil: %*{} else: params
  }
  self._ws.send($message)
  self._callbacks[id] = callback
