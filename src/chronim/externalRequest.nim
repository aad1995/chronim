import std/[asyncdispatch, net, httpclient, times, strutils, nativesockets, json, uri]

const
  REQUEST_TIMEOUT = 10000 # ms

type
  Options* = object
    host: string
    port: int
    path: string
    method: string
    headers: Table[string, string]
    body: string
    useHostName: bool
    scheme: string

proc dnsLookup(host: string): Future[string] {.async.} =
  let addrInfo = getAddrInfo(host, Port(0))
  if addrInfo.len == 0:
    raise newException(IOError, "DNS lookup failed for " & host)
  return $addrInfo[0].address

proc externalRequest*(
    transport: AsyncHttpClient,
    options: var Options,
    callback: proc(err: ref Exception, data: string)
) {.async.} =
  var reqHost = options.host
  if not options.useHostName:
    try:
      let address = await dnsLookup(options.host)
      reqHost = address
    except Exception as err:
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
    case options.method.toUpperAscii()
    of "POST":
      resp = await transport.request(url, httpMethod = HttpPost, headers = reqHeaders, body = options.body, timeout = REQUEST_TIMEOUT)
    of "PUT":
      resp = await transport.request(url, httpMethod = HttpPut, headers = reqHeaders, body = options.body, timeout = REQUEST_TIMEOUT)
    of "DELETE":
      resp = await transport.request(url, httpMethod = HttpDelete, headers = reqHeaders, body = options.body, timeout = REQUEST_TIMEOUT)
    else:
      resp = await transport.request(url, httpMethod = HttpGet, headers = reqHeaders, timeout = REQUEST_TIMEOUT)

    let data = await resp.body
    if resp.code == Http200:
      callback(nil, data)
    else:
      callback(newException(IOError, data), "")
  except Exception as err:
    callback(err, "")