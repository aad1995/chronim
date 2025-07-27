import std/[asyncdispatch, json, tables, uri, strutils]
import ws
import api, devtools, eventemitter

const
  DefaultHost = "localhost"
  DefaultPort = 9222

type
  ProtocolError = object of CatchableError
    request: JsonNode
    response: JsonNode

  CallbackProc = proc(error: bool, response: JsonNode)

  Chrome* = ref object of ChromeType
    host*: string
    port*: int
    secure*: bool
    useHostName*: bool
    alterPath*: proc(path: string): string
    local*: bool
    target*: JsonNode
    n_notifier*: EventEmitter
    n_callbacks*: Table[int, CallbackProc]
    n_nextCommandId*: int
    webSocketUrl*: string
    n_ws*: WebSocket

# Path alteration procs
proc identityPath(path: string): string = path
proc customPath(path: string): string = "/prefix" & path
let DefaultAlterPath = identityPath

let alterPathTable = {
  "identity": identityPath,
  "custom": customPath
}.toTable

proc jsonNodeToDevToolsOptions(options: JsonNode): DevToolsOptions =
  result.host = if options.hasKey("host"): options["host"].getStr() else: ""
  result.port = if options.hasKey("port"): options["port"].getInt() else: 9222
  result.hmethod = if options.hasKey("hmethod"): options["hmethod"].getStr() else: "GET"
  result.useHostName = if options.hasKey("useHostName"): options["useHostName"].getBool() else: false
  result.secure = if options.hasKey("secure"): options["secure"].getBool() else: false
  result.local = if options.hasKey("local"): options["local"].getBool() else: false
  result.url = if options.hasKey("url"): options["url"].getStr() else: ""
  result.id = if options.hasKey("id"): options["id"].getStr() else: ""
  # alterPath selection:
  if options.hasKey("alterPath") and options["alterPath"].kind == JString:
    let apKey = options["alterPath"].getStr()
    if apKey in alterPathTable:
      result.alterPath = alterPathTable[apKey]
    else:
      result.alterPath = DefaultAlterPath
  else:
    result.alterPath = DefaultAlterPath

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
      if backup.isNil: backup = target
      if target.hasKey("type") and target["type"].getStr() == "page":
        return target
  if not backup.isNil: return backup
  raise newException(ValueError, "No inspectable targets")



proc n_fetchDebuggerURL(self: Chrome, options: JsonNode): Future[string] {.async.} =
  let userTarget = self.target

  if userTarget.isNil:
    let targets = await ListPromise(jsonNodeToDevToolsOptions(options))
    let obj = defaultTarget(targets.getElems())
    return obj["webSocketDebuggerUrl"].getStr()
  elif userTarget.kind == JString:
    var idOrUrl = userTarget.getStr()
    if idOrUrl.startsWith("/"):
      idOrUrl = "ws://" & self.host & ":" & $self.port & idOrUrl
    if idOrUrl.startsWith("ws:") or idOrUrl.startsWith("wss:"):
      return idOrUrl
    else:
      let targets = await ListPromise(jsonNodeToDevToolsOptions(options))
      for target in targets.getElems():
        if target.hasKey("id") and target["id"].getStr() == idOrUrl:
          return target["webSocketDebuggerUrl"].getStr()
      raise newException(ValueError, "Target not found")
  elif userTarget.kind == JObject:
    return userTarget["webSocketDebuggerUrl"].getStr()
  else:
    raise newException(ValueError, "Unsupported or missing target type")

proc n_fetchProtocol(self: Chrome, options: JsonNode): Future[JsonNode] {.async.} =
  if not self.protocol.isNil:
    return self.protocol
  else:
    options["local"] = %*self.local
    return await ProtocolPromise(jsonNodeToDevToolsOptions(options))

proc n_handleConnectionClose(self: Chrome) =
  let err = newException(IOError, "WebSocket connection closed")
  for id, cb in self.n_callbacks:
    cb(true, %*{"message": err.msg})
  self.n_callbacks.clear()

proc n_handleMessage(self: Chrome, message: JsonNode) =
  if message.hasKey("id"):
    let id = message["id"].getInt()
    if self.n_callbacks.hasKey(id):
      let cb = self.n_callbacks[id]
      if message.hasKey("error"):
        cb(true, message["error"])
      else:
        cb(false, if message.hasKey("result"): message["result"] else: %*{})
      self.n_callbacks.del(id)
      if self.n_callbacks.len == 0:
        self.n_notifier.emit("ready", %*{}, "")
  elif message.hasKey("method"):
    let hmethod = message["method"].getStr()
    let params = if message.hasKey("params"): message["params"] else: %*{}
    let sessionId = if message.hasKey("sessionId"): message["sessionId"].getStr() else: ""
    self.n_notifier.emit("event", message, "")
    self.n_notifier.emit(hmethod, params, sessionId)
    if sessionId.len > 0:
      self.n_notifier.emit(hmethod & "." & sessionId, params, sessionId)

proc n_connectToWebSocket(self: Chrome): Future[void] {.async.} =
  try:
    var wsUrl = self.webSocketUrl
    if self.secure:
      wsUrl = wsUrl.replace("ws:", "wss:")
    self.n_ws = await newWebSocket(wsUrl)
    try:
      while self.n_ws.readyState == Open:
        let data = await self.n_ws.receiveStrPacket()
        let message = parseJson(data)
        self.n_handleMessage(message)
    except WebSocketClosedError:
      self.n_handleConnectionClose()
      self.n_notifier.emit("disconnect", %*{}, "")
    except WebSocketError as err:
      self.n_notifier.emit("error", %*err.msg, "")
  except CatchableError as err:
    raise err

proc n_enqueueCommand(self: Chrome, hmethod: string, params: JsonNode, sessionId: string, callback: CallbackProc) =
  let id = self.n_nextCommandId
  self.n_nextCommandId.inc()
  let message = %*{
    "id": id,
    "method": hmethod,
    "sessionId": sessionId,
    "params": if params.isNil: %*{} else: params
  }
  discard self.n_ws.send($message)
  self.n_callbacks[id] = callback

proc n_start(self: Chrome) {.async.} =
  ## Start the Chrome debugger protocol connection.
  var options = %*{
    "host": self.host,
    "port": self.port,
    "secure": self.secure,
    "useHostName": self.useHostName
  }
  # NOTE: Do NOT try to serialize `alterPath` to JSON.

  try:
    let url = await self.n_fetchDebuggerURL(options)
    var urlObj = parseUri(url)
    urlObj.path = self.alterPath(urlObj.path)
    self.webSocketUrl = $urlObj
    options["host"] = %urlObj.hostname
    if urlObj.port.len > 0:
      options["port"] = %parseInt(urlObj.port)
    let protocol = await self.n_fetchProtocol(options)
    api.prepare(ChromeType(self), protocol)
    await self.n_connectToWebSocket()
    self.n_notifier.emit("connect", %*{}, "")
  except CatchableError as err:
    self.n_notifier.emit("error", %*err.msg, "")

proc newChrome*(options: JsonNode, notifier: EventEmitter): Chrome =
  ## Create and start a new Chrome debug protocol client.
  let opts = if options.isNil: %*{} else: options
  let userTarget =
    if opts.hasKey("target"): opts["target"]
    else: nil

  let alterPathProc =
    if opts.hasKey("alterPath") and opts["alterPath"].kind == JString:
      let key = opts["alterPath"].getStr()
      alterPathTable.getOrDefault(key, DefaultAlterPath)
    else:
      DefaultAlterPath

  result = Chrome(
    host:       if opts.hasKey("host"): opts["host"].getStr() else: DefaultHost,
    port:       if opts.hasKey("port"): opts["port"].getInt() else: DefaultPort,
    secure:     if opts.hasKey("secure"): opts["secure"].getBool() else: false,
    useHostName: if opts.hasKey("useHostName"): opts["useHostName"].getBool() else: false,
    alterPath:   alterPathProc,
    protocol:    if opts.hasKey("protocol"): opts["protocol"] else: nil,
    local:       if opts.hasKey("local"): opts["local"].getBool() else: false,
    target:      userTarget,
    n_notifier:  notifier,
    n_callbacks: initTable[int, CallbackProc](),
    n_nextCommandId: 1,
    webSocketUrl: "",
    n_ws: nil
  )
  discard result.n_start() 

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
    self.n_enqueueCommand(hmethod, params, sessionId, cb)
    return await fut
  else:
    self.n_enqueueCommand(hmethod, params, sessionId, cb)
    return nil

proc close(self: Chrome, callback: proc() = nil): Future[void] {.async.} =
  proc closeWebSocket(cb: proc()) =
    if self.n_ws == nil or self.n_ws.readyState == Closed:
      cb()
    else:
      self.n_ws.close()
      self.n_ws = nil
      self.n_handleConnectionClose()
      cb()
  if callback != nil:
    closeWebSocket(callback)
  else:
    var fut = newFuture[void]()
    closeWebSocket(proc() = fut.complete())
    await fut