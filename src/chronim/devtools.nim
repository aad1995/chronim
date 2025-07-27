import std/[asyncdispatch, httpclient, tables, json , strutils]
import externalRequest

const
  DefaultHost* = "localhost"
  DefaultPort* = 9222

type
  DevToolsOptions* = object
    host*: string
    port*: int
    hmethod*: string
    useHostName*: bool
    secure*: bool
    local*: bool
    url*: string
    id*: string
    alterPath*: proc(path: string): string {.gcsafe.}

proc devToolsInterface(
  path: string, options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  try:
    let schema = if options.secure: "https" else: "http"
    let host = if options.host.len > 0: options.host else: DefaultHost
    let port = if options.port != 0: options.port else: DefaultPort
    let urlPath = if not options.alterPath.isNil: options.alterPath(path) else: path
    var client = newAsyncHttpClient()
    let hmethod = if options.hmethod.len > 0: options.hmethod else: "GET"
    let useHostName = options.useHostName
    var reqOptions = Options(
    host: host,
    port: port,
    path: urlPath,
    hmethod: hmethod,
    headers: initTable[string, string](),
    body: "",
    useHostName: useHostName,
    scheme: schema)
    await externalRequest(client, reqOptions, callback)
  except Exception as e:
    callback(e, "")


proc Protocol(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  if options.local:
    try:
      let protocolObj = parseFile("protocol.json")
      callback(nil, $protocolObj)
    except Exception as e:
      callback(e, "")
    return
  await devToolsInterface("/json/protocol", options, proc(err: ref Exception, data: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, data)
  )

proc List(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/list", options, proc(err: ref Exception, tabs: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, tabs)
  )

proc New(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  var path = "/json/new"
  if options.url.len > 0:
    path &= "?" & options.url
  let hmethod = if options.hmethod.len > 0: options.hmethod else: "PUT"
  var opts = options
  opts.hmethod = hmethod
  await devToolsInterface(path, opts, proc(err: ref Exception, tab: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, tab)
  )

proc Activate(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/activate/" & options.id, options, proc(err: ref Exception, _: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, "")
  )

proc Close(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/close/" & options.id, options, proc(err: ref Exception, _: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, "")
  )

proc Version(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/version", options, proc(err: ref Exception, versionInfo: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, versionInfo)
  )


proc promisesWrapper*(
  mfunc: proc(options: DevToolsOptions,
      callback: proc(err: ref Exception, data: string) {.gcsafe, closure.}) {.async.}
): proc(options: DevToolsOptions): Future[JsonNode] =
  return proc(options: DevToolsOptions): Future[JsonNode] {.async.} =
    var fut = newFuture[JsonNode]()
    discard mfunc(options, proc(err: ref Exception, data: string) {.gcsafe.} =
      if err != nil:
        fut.fail(err)
      else:
        fut.complete(parseJson(data))
    )
    return await fut

# Promise-style APIs
let
  ProtocolPromise* = promisesWrapper(Protocol)
  ListPromise*     = promisesWrapper(List)
  NewPromise*      = promisesWrapper(New)
  ActivatePromise* = promisesWrapper(Activate)
  ClosePromise*    = promisesWrapper(Close)
  VersionPromise*  = promisesWrapper(Version)
