import std/[json, tables, strformat]

type
  CallbackProc = proc(error: bool, response: JsonNode)
  ChromeNotifier* = ref object of RootObj
    emit: proc(event: string, params: JsonNode, sessionId: string = "")
  ChromeType* = ref object of RootObj
    protocol*: JsonNode
    domains*: JsonNode

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

proc addCommand(domains: var JsonNode, domainName: string, command: Table[string, JsonNode]) =
  let coStr = command["name"].getStr()
  let commandName = fmt"{domainName}.{coStr}"
  var commandObj = initTable[string, JsonNode]()
  decorate(commandObj, "command", command)
  # Top-level flat entry
  domains[commandName] = %commandObj
  # Nested per-domain map
  if not domains.hasKey(domainName):
    domains[domainName] = %newJObject()
  domains[domainName][coStr] = %commandObj

proc addEvent(domains: var JsonNode, domainName: string, event: Table[string, JsonNode]) =
  let evStr = event["name"].getStr()
  let eventName = fmt"{domainName}.{evStr}"
  var eventObj = initTable[string, JsonNode]()
  decorate(eventObj, "event", event)
  domains[eventName] = %eventObj
  if not domains.hasKey(domainName):
    domains[domainName] = %newJObject()
  domains[domainName][evStr] = %eventObj

proc addType(domains: var JsonNode, domainName: string, typ: Table[string, JsonNode]) =
  let typStr = typ["id"].getStr()
  let typeName = fmt"{domainName}.{typStr}"
  var typeObj = initTable[string, JsonNode]()
  decorate(typeObj, "type", typ)
  domains[typeName] = %typeObj
  if not domains.hasKey(domainName):
    domains[domainName] = %newJObject()
  domains[domainName][typStr] = %typeObj

# Main protocol pre processor.
proc prepare*(chrome: ChromeType, protocol: JsonNode) =
  chrome.protocol = protocol
  chrome.domains = %newJObject()
  for domain in protocol["domains"]:
    let domainName = domain["domain"].getStr()
    chrome.domains[domainName] = %newJObject()
    if domain.hasKey("commands"):
      for command in domain["commands"]:
        let fields = command.getFields()
        var tableFields = initTable[string, JsonNode]()
        for k, v in fields: tableFields[k] = v
        addCommand(chrome.domains, domainName, tableFields)
    if domain.hasKey("events"):
      for event in domain["events"]:
        let fields = event.getFields()
        var tableFields = initTable[string, JsonNode]()
        for k, v in fields: tableFields[k] = v
        addEvent(chrome.domains, domainName, tableFields)
    if domain.hasKey("types"):
      for typ in domain["types"]:
        let fields = typ.getFields()
        var tableFields = initTable[string, JsonNode]()
        for k, v in fields: tableFields[k] = v
        addType(chrome.domains, domainName, tableFields)
