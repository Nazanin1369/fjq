from out import prettyPrint, writeOut
from selector import parse, match, Node
import sequtils
import terminal
import memfiles
import ropes
import streams
import threadpool
import json
import os
import options
import sugar



proc isEndOfJson(txt: string) : int = 
  result = 0
  for x in txt:
    case x:
      of  '{':  inc result
      of  '}':  dec result
      else:  discard

type 
  JQInputKind = enum memFile, standardInput
  JQInput = ref object 
    case kind: JQInputKind
      of memFile: memFile: MemFile
      of standardInput: input: File


iterator lines(jqInput: JQInput): string =  
  case jqInput.kind: 
    of standardInput: 
      let f = jQInput.input
      while  not f.endOfFile:
        yield f.readLine
    of memFile: 
      let memFile = jQInput.memFile
      for line in lines(memFile):
        yield line


var input: JQInput
var expr = "."

if paramCount() > 0:
  expr = paramStr(1)

if paramCount() > 1:
  input = JQInput(kind: memFile, memfile: memfiles.open(paramStr(2), mode = fmReadWrite, mappedSize = -1))
else:
  input = JQInput(kind: standardInput, input: stdin)


let parsedExpr = expr.parse

proc createTask(input: seq[MemSlice], parsedExpr: seq[Node]): seq[Stream] {.gcsafe.} = 
  var k: seq[Stream] = @[] 
  for line in input:
    let node = parsedExpr.match(parseJson($line))
    if node.isSome():
      for x in node.get():
        let strm = newStringStream("")
        strm.prettyPrint(x, 2)
        strm.setPosition(0)
        k.add(strm)

  return k

proc flush(st: Stream, rtotal: seq[FlowVar[seq[Stream]]]) =
  for x in rtotal:
    let output = ^x
    for y in output:
      st.write(y.readAll())
      st.write("\n")


if paramCount() > 1:
  input = JQInput(kind: memFile, memfile: memfiles.open(paramStr(2), mode = fmReadWrite, mappedSize = -1))
else:
  input = JQInput(kind: standardInput, input: stdin)


if not isatty(stdout) and input.kind == memFile:
  let st  =  newFileStream(stdout)
  var rtotal: seq[FlowVar[seq[Stream]]] = @[]
  var count = 0
  var send: seq[MemSlice]= @[]
  for x in memSlices(input.memfile):
    send.add(x)
    if count >= 4000:
      rtotal.add(spawn(createTask(send, parsedExpr))) 
      send.setLen(0)
      count = 0

    if rtotal.len > 10:
      flush(st, rtotal)
      rtotal.setLen(0)

    inc count

  if send.len > 0:
    rtotal.add(spawn(createTask(send, parsedExpr))) 


  flush(st, rtotal)


else:
  var state =  0
  var txt = rope("") 
  let output = stdout 
  for line in lines(input):
    txt = txt & line 
    state = state +  isEndOfJson(line)
    if state == 0:
      let node = parsedExpr.match(parseJson($txt))
      if node.isSome():
        for x in node.get():
          prettyPrint(stdout, x, 2)
          stdout.writeOut(fgWhite, "\n")
      txt = rope("") 