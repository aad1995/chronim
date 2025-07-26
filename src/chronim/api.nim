import std/[json, tables, strformat]

type
  ChromeType = Table[string, JsonNode]
  ProtocolType = ref object
    domains: seq[Table[string, JsonNode]]

proc arrayToObject(parameters: seq[Table[string, JsonNode]]): Table[string, Table[string, JsonNode]] =
  var keyValue = initTable[string, Table[string, JsonNode]]()
  for parameter in parameters:
    if parameter.hasKey("name"):
      let name = parameter["name"].getStr()
      var paramCopy = parameter
      paramCopy.del("name")
      keyValue[name] = paramCopy
  return keyValue

proc decorate(to: var Table[string, JsonNode], category: string, object: Table[string, JsonNode]) =
  to["category"] = %category
  for field in object.keys:
    if field == "name":
      continue
    if (category == "type" and field == "properties") or field == "parameters":
      let arr = object[field]
      var arrSeq: seq[Table[string, JsonNode]]
      for item in arr.getElems():
        arrSeq.add(item.getFields())
      to[field] = %arrayToObject(arrSeq)
    else:
      to[field] = object[field]

proc addCommand(chrome: var ChromeType, domainName: string, command: Table[string, JsonNode]) =
  let commandName = fmt"{domainName}.{command["name"].getStr()}"
  let handler = %proc(params: JsonNode, sessionId: string, callback: proc()) =
    discard chrome["send"].getProc()(commandName, params, sessionId, callback)
  var handlerObj = initTable[string, JsonNode]()
  decorate(handlerObj, "command", command)
  handlerObj["handler"] = handler
  chrome[commandName] = %handlerObj
  if not chrome.hasKey(domainName):
    chrome[domainName] = %initTable[string, JsonNode]()
  chrome[domainName][command["name"].getStr()] = %handlerObj

proc addEvent(chrome: var ChromeType, domainName: string, event: Table[string, JsonNode]) =
  let eventName = fmt"{domainName}.{event["name"].getStr()}"
  let handler = %proc(sessionId: string, handler: proc()) =
    var actualHandler = handler
    var actualSessionId = sessionId
    if sessionId == "":
      actualHandler = sessionId
      actualSessionId = ""
    let rawEventName = if actualSessionId != "": fmt"{eventName}.{actualSessionId}" else: eventName
    if not isNil(actualHandler):
      discard chrome["on"].getProc()(rawEventName, actualHandler)
      return proc() = discard chrome["removeListener"].getProc()(rawEventName, actualHandler)
    else:
      return chrome["once"].getProc()(rawEventName)
  var handlerObj = initTable[string, JsonNode]()
  decorate(handlerObj, "event", event)
  handlerObj["handler"] = handler
  chrome[eventName] = %handlerObj
  if not chrome.hasKey(domainName):
    chrome[domainName] = %initTable[string, JsonNode]()
  chrome[domainName][event["name"].getStr()] = %handlerObj

proc addType(chrome: var ChromeType, domainName: string, typ: Table[string, JsonNode]) =
  let typeName = fmt"{domainName}.{typ["id"].getStr()}"
  var help = initTable[string, JsonNode]()
  decorate(help, "type", typ)
  chrome[typeName] = %help
  if not chrome.hasKey(domainName):
    chrome[domainName] = %initTable[string, JsonNode]()
  chrome[domainName][typ["id"].getStr()] = %help

proc prepare*(object: var ChromeType, protocol: ProtocolType) =
  object["protocol"] = %protocol
  for domain in protocol.domains:
    let domainName = domain["domain"].getStr()
    object[domainName] = %initTable[string, JsonNode]()
    for command in domain.getOrDefault("commands", %[]).getElems():
      addCommand(object, domainName, command.getFields())
    for event in domain.getOrDefault("events", %[]).getElems():
      addEvent(object, domainName, event.getFields())
    for typ in domain.getOrDefault("types", %[]).getElems():
      addType(object, domainName, typ.getFields())
    object[domainName]["on"] = %proc(eventName: string, handler: proc()) =
      discard object[domainName][eventName].getProc()(handler)