import std/[asyncdispatch, httpclient, json, tables, uri, os]
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
    # Remove alterPath from options sent over the wire
    alterPath*: proc(path: string): string {.gcsafe.}


# Wraps the externalRequest pattern
proc devToolsInterface*(
  path: string,
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  let scheme = if options.secure: "https" else: "http"
  let host = if options.host.len > 0: options.host else: DefaultHost
  let port = if options.port > 0: options.port else: DefaultPort
  let hmethod = if options.hmethod.len > 0: options.hmethod else: "GET"
  let useHostName = options.useHostName
  var finalPath = path
  if not isNil(options.alterPath):
    finalPath = options.alterPath(path)

  var reqOptions = Options(
    host: host,
    port: port,
    path: finalPath,
    hmethod: hmethod,
    headers: initTable[string, string](),
    body: "",
    useHostName: useHostName,
    scheme: scheme
  )

  var client = newAsyncHttpClient()
  await externalRequest(client, reqOptions, callback)

# Promises wrapper
proc promisesWrapper*(
  func: proc(options: DevToolsOptions, callback: proc(err: ref Exception, data: string) {.gcsafe.}) {.async.}
): proc(options: DevToolsOptions): Future[string] =
  return proc(options: DevToolsOptions): Future[string] {.async.} =
    var fut = newFuture[string]()
    await func(options, proc(err: ref Exception, data: string) {.gcsafe.} =
      if err != nil:
        fut.fail(err)
      else:
        fut.complete(data)
    )
    return await fut

# All callback-based API
proc Protocol*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  if options.local:
    let localDescriptor = readFile("protocol.json") # Or options.protocolFile or similar
    callback(nil, localDescriptor)
    return
  await devToolsInterface("/json/protocol", options, callback)

proc List*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/list", options, callback)

proc New*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  var path = "/json/new"
  if options.url.len > 0:
    path &= "?" & encodeUrl(options.url)
  var opts = options
  if opts.hmethod.len == 0:
    opts.hmethod = "PUT"
  await devToolsInterface(path, opts, callback)

proc Activate*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  let path = "/json/activate/" & options.id
  await devToolsInterface(path, options, callback)

proc Close*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  let path = "/json/close/" & options.id
  await devToolsInterface(path, options, callback)

proc Version*(
  options: DevToolsOptions,
  callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  await devToolsInterface("/json/version", options, callback)

# Promise-style APIs
let
  ProtocolPromise* = promisesWrapper(Protocol)
  ListPromise*     = promisesWrapper(List)
  NewPromise*      = promisesWrapper(New)
  ActivatePromise* = promisesWrapper(Activate)
  ClosePromise*    = promisesWrapper(Close)
  VersionPromise*  = promisesWrapper(Version)
