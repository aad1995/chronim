import std/[asyncdispatch, httpclient, json, strutils, tables, uri] , externalRequest

const
  DefaultHost = "localhost"
  DefaultPort = 9222

type
  DevToolsOptions = object
    host: string
    port: int
    method: string
    useHostName: bool
    secure: bool
    local: bool
    url: string
    id: string
    alterPath: proc(path: string): string


proc devToolsInterface(
    path: string,
    options: DevToolsOptions,
    callback: proc(err: ref Exception, data: string)
) {.async.} =
  let scheme = if options.secure: "https" else: "http"
  let host = if options.host.len > 0: options.host else: DefaultHost
  let port = if options.port > 0: options.port else: DefaultPort
  let method = if options.method.len > 0: options.method else: "GET"
  let useHostName = options.useHostName
  let finalPath = if not isNil(options.alterPath): options.alterPath(path) else: path

  var reqOptions = Options(
    host: host,
    port: port,
    path: finalPath,
    method: method,
    headers: initTable[string, string](),
    body: "",
    useHostName: useHostName,
    scheme: scheme
  )

  var client = newAsyncHttpClient()
  await externalRequest(client, reqOptions, callback)

proc promisesWrapper(
    func: proc(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.}
): proc(options: DevToolsOptions, callback: proc(err: ref Exception, data: string) = nil): Future[string] =
  return proc(options: DevToolsOptions, callback: proc(err: ref Exception, data: string) = nil): Future[string] {.async.} =
    if callback != nil:
      await func(options, callback)
      return ""
    else:
      var fut = newFuture[string]()
      await func(options, proc(err: ref Exception, data: string) =
        if err != nil:
          fut.fail(err)
        else:
          fut.complete(data)
      )
      return await fut

proc Protocol(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  if options.local:
    let localDescriptor = readFile("protocol.json")
    callback(nil, localDescriptor)
    return
  await devToolsInterface("/json/protocol", options, proc(err: ref Exception, descriptor: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, descriptor)
  )

proc List(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  await devToolsInterface("/json/list", options, proc(err: ref Exception, tabs: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, tabs)
  )

proc New(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  var path = "/json/new"
  if options.url.len > 0:
    path &= "?" & encodeUrl(options.url)
  var opts = options
  if opts.method.len == 0:
    opts.method = "PUT"
  await devToolsInterface(path, opts, proc(err: ref Exception, tab: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, tab)
  )

proc Activate(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  let path = "/json/activate/" & options.id
  await devToolsInterface(path, options, proc(err: ref Exception, _: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, "")
  )

proc Close(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  let path = "/json/close/" & options.id
  await devToolsInterface(path, options, proc(err: ref Exception, _: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, "")
  )

proc Version(options: DevToolsOptions, callback: proc(err: ref Exception, data: string)) {.async.} =
  await devToolsInterface("/json/version", options, proc(err: ref Exception, versionInfo: string) =
    if err != nil:
      callback(err, "")
    else:
      callback(nil, versionInfo)
  )

let ProtocolPromise = promisesWrapper(Protocol)
let ListPromise = promisesWrapper(List)
let NewPromise = promisesWrapper(New)
let ActivatePromise = promisesWrapper(Activate)
let ClosePromise = promisesWrapper(Close)
let VersionPromise = promisesWrapper(Version)

# Usage example:
# let fut = await ProtocolPromise(DevToolsOptions(host: "localhost", port: 9222), nil)
# echo fut

# Or with callback:
# await Protocol(DevToolsOptions(host: "localhost", port: 9222), proc(err: ref Exception, data: string) =
#   if err != nil:
#     echo "Error: ", err.msg
#   else:
#     echo "Data: ", data
# )