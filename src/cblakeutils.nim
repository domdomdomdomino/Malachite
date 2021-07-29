# cblakeutils.nim
import memfiles

proc last*(ms: MemSlice): char =
  cast[ptr char](cast[int](ms.data) +% ms.size - 1)[]

proc align(ms: MemSlice): MemSlice =
  result = ms
  while result.size > 0 and result.last != '\n':
    result.size.inc

proc split*(n: int, path: string):
    tuple[mf: MemFile; parts: seq[MemSlice]] =
  if n < 2: raise newException(ValueError, "n < 2")
  let mf = memfiles.open(path)
  var parts = newSeq[MemSlice](n)
  let step = mf.size div n
  parts[0] = align(MemSlice(data: mf.mem, size: step))
  for c in 1 ..< max(1, n - 1):
    let d = cast[pointer](cast[int](parts[c-1].data) +%
                          parts[c-1].size)
    parts[c] = align(MemSlice(data: d, size: step))
  let d = cast[int](parts[^2].data) +% parts[^2].size
  parts[^1].data = cast[pointer](d)
  parts[^1].size = mf.size - (d -% cast[int](mf.mem))
  result = (mf, parts)

type NumberedToks* = tuple[liNo: int; ms: MemSlice]

iterator nSplit*(ms: MemSlice, delim: char): NumberedToks =
  proc memchr(s: pointer, c: char, n: csize): pointer
    {.importc: "memchr", header:"<string.h>".}
  var left = ms.size # assert ms.last == delim
  var res: NumberedToks
  res.ms.data = cast[pointer](ms.data)
  var e = memchr(res.ms.data, '\n', left)
  if e == nil: raise newException(IOError, "Bad Format")
  res.ms.size = cast[int](e) -% cast[int](res.ms.data)
  while e != nil and left > 0:
    res.liNo.inc
    yield res
    left.dec res.ms.size + 1
    res.ms.data = cast[pointer](cast[int](res.ms.data) +%
                                (res.ms.size + 1))
    e = memchr(res.ms.data, '\n', left)
    res.ms.size = cast[int](e) -% cast[int](res.ms.data)
