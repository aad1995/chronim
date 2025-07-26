import std/[json, tables, strformat]

type
  ChromeType* = ref object
    protocol*: JsonNode
    domains*: Table[string, JsonNode]

  ProtocolType* = ref object
    domains*: seq[Table[string, JsonNode]]

# Converts array of parameter objects to table keyed by "name"
proc arrayToObject(parameters: seq[OrderedTable[string, JsonNode]]): Table[string, OrderedTable[string, JsonNode]] =
  var keyValue = initTable[string, OrderedTable[string, JsonNode]]()
  for parameter in parameters:
    if parameter.hasKey("name"):
      let name = parameter["name"].getStr()
      var paramCopy = parameter
      paramCopy.del("name")
      keyValue[name] = paramCopy
  return keyValue


# Decorate result dictionary with fields of protocol JSON element
proc decorate(to: var Table[string, JsonNode], category: string, obj: Table[string, JsonNode]) =
  to["category"] = %category
  for field in obj.keys:
    if field == "name":
      continue
    if (category == "type" and field == "properties") or field == "parameters":
      let arr = obj[field]
      var arrSeq: seq[OrderedTable[string, JsonNode]]
      for item in arr.getElems():
        arrSeq.add(item.getFields())
      to[field] = %arrayToObject(arrSeq)
    else:
      to[field] = obj[field]

proc addCommand(chrome: ChromeType, domainName: string, command: Table[string, JsonNode]) =
  let coStr = command["name"].getStr()
  let commandName = fmt"{domainName}.{coStr}"
  var commandObj = initTable[string, JsonNode]()
  decorate(commandObj, "command", command)
  chrome.domains[commandName] = %commandObj
  # Add per-domain command map
  if not chrome.domains.hasKey(domainName):
    chrome.domains[domainName] = %initTable[string, JsonNode]()
  chrome.domains[domainName][command["name"].getStr()] = %commandObj

proc addEvent(chrome: ChromeType, domainName: string, event: Table[string, JsonNode]) =
  let evStr = event["name"].getStr()
  let eventName = fmt"{domainName}.{evStr}"
  var eventObj = initTable[string, JsonNode]()
  decorate(eventObj, "event", event)
  chrome.domains[eventName] = %eventObj
  if not chrome.domains.hasKey(domainName):
    chrome.domains[domainName] = %initTable[string, JsonNode]()
  chrome.domains[domainName][event["name"].getStr()] = %eventObj

proc addType(chrome: ChromeType, domainName: string, typ: Table[string, JsonNode]) =
  let typStr = typ["id"].getStr()
  let typeName = fmt"{domainName}.{typStr}"
  var typeObj = initTable[string, JsonNode]()
  decorate(typeObj, "type", typ)
  chrome.domains[typeName] = %typeObj
  if not chrome.domains.hasKey(domainName):
    chrome.domains[domainName] = %initTable[string, JsonNode]()
  chrome.domains[domainName][typ["id"].getStr()] = %typeObj

# Main protocol pre processor.
proc prepare*(chrome: ChromeType, protocol: ProtocolType) =
  chrome.protocol = %protocol
  for domain in protocol.domains:
    let domainName = domain["domain"].getStr()
    chrome.domains[domainName] = %initTable[string, JsonNode]()
    for command in domain.getOrDefault("commands", %[]).getElems():
      let fields = command.getFields()
      var tableFields = initTable[string, JsonNode]()
      for k, v in fields:
        tableFields[k] = v
      addCommand(chrome, domainName, tableFields)
    for event in domain.getOrDefault("events", %[]).getElems():
      let fields = event.getFields()
      var tableFields = initTable[string, JsonNode]()
      for k, v in fields:
        tableFields[k] = v
      addEvent(chrome, domainName, tableFields)
    for typ in domain.getOrDefault("types", %[]).getElems():
      let fields = typ.getFields()
      var tableFields = initTable[string, JsonNode]()
      for k, v in fields:
        tableFields[k] = v
      addType(chrome, domainName, tableFields)
