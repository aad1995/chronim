import std/[asyncdispatch, net, httpclient, strutils, nativesockets, uri, tables, strformat]


type
  Options* = object
    host*: string
    port*: int
    path*: string
    hmethod*: string
    headers*: Table[string, string]
    body*: string
    useHostName*: bool
    scheme*: string

proc dnsLookup(host: string): string =
  let addrInfo = getAddrInfo(host, Port(0))
  if addrInfo == nil:
    raise newException(IOError, "DNS lookup failed for " & host)
  let addressStr = $addrInfo.ai_addr[]
  freeAddrInfo(addrInfo)
  return addressStr


proc externalRequest*(
    transport: AsyncHttpClient,
    options: Options,
    callback: proc(err: ref Exception, data: string) {.gcsafe.}
) {.async.} =
  var reqHost = options.host
  if not options.useHostName:
    try:
      reqHost = dnsLookup(options.host)
    except CatchableError as err:
      callback(err, "")
      return

  let scheme = if options.scheme.len > 0: options.scheme else: "http"
  let portStr = if options.port > 0: ":" & $options.port else: ""
  let pathStr = if options.path.len > 0: options.path else: "/"
  let url = fmt"{scheme}://{reqHost}{portStr}{pathStr}"

  var reqHeaders = newHttpHeaders()
  for k, v in options.headers:
    reqHeaders.add(k, v)

  try:
    var resp: AsyncResponse
    case options.hmethod.toUpperAscii()
    of "POST":
      resp = await transport.request(url, httpMethod = HttpPost, headers = reqHeaders, body = options.body)
    of "PUT":
      resp = await transport.request(url, httpMethod = HttpPut, headers = reqHeaders, body = options.body)
    of "DELETE":
      resp = await transport.request(url, httpMethod = HttpDelete, headers = reqHeaders, body = options.body)
    else:
      resp = await transport.request(url, httpMethod = HttpGet, headers = reqHeaders)

    let data = await resp.body
    if resp.code in {Http200, Http201, Http204}:
      callback(nil, data)
    else:
      callback(newException(IOError, "HTTP " & $resp.code & ": " & data), "")
  except CatchableError as err:
    callback(err, "")
