# Malachite.nim

import std/[osproc, threadpool, strutils, os,
            strscans, parseutils, strformat, math, terminal], cblakeutils
import memfiles except open
import docopt
#import gintro/[gtk, gobject, gio]
  
#[ `Test data for original 30GB file`.
1..24_633, Ball
24_634..939_501, Mineral
939_502..964_134, Ball
964_135..1_886_558, Mineral
1_886_559..1_910_920, Ball
1_910_921..0, Mineral
]#

const compResistance = 119_000_000

type
  Material = enum
    Ball, Mineral, None

  MaterialRange = object
    rng: Slice[float]
    matType: Material

  NoMaterialID = object of ValueError # Called when a `None` is found

  NoMatchingEnum = object of ValueError # Called when the user input doesn't
                                        # match the contents of `Material`

  ForceTotal = object
    bbTotal, bmTotal, mmTotal: int
    bbImpact, bmImpact, mmImpact: int
    bbImpactF, bmImpactF, mmImpactF: float
    abrasion, headerCount: float

proc `$`(m: Material): string =
  result = 
    case m:
    of Ball: "Ball"
    of Mineral: "Mineral"
    else: "None"

proc `$`(m: MaterialRange): string =
  result = $m.rng & ", " & $m.matType

proc `$`(a: ForceTotal): string =
  let parsedHeaderCount: string =
    if floor(a.headerCount / 9) == (a.headerCount / 9):
      $int(floor(a.headerCount / 9))
    else:
      $(a.headerCount / 9) &
        """

<<FILE WAS NOT READ SUCCESSFULLY.
  BAD AMOUNT OF HEADERS FOUND:
    THE AMOUNT OF HEADER LINES FOUND WAS NOT DIVISIBLE BY 9.
    THIS MEANS THAT THERE IS SOMETHING WRONG WITH THE SIMULATION FILE,
      OR THAT THE WAY THAT THE HEADERS ARE BEING READ IS WRONG.
  PLEASE CONTACT DEVELOPER IMMEDIATELY.>>"""

  result = 
    "Accumulated values of particles.txt are:\n" &
    "\tBallBall:\n" &
    "\t\tTotal Contacts: " & $a.bbTotal & '\n' &
    "\t\tImpacts: " & $a.bbImpact & '\n' &
    "\t\tTotal Impact Force: " & $a.bbImpactF & '\n' &
    "\tBallMineral:\n" &
    "\t\tTotal Contacts: " & $a.bmTotal & '\n' &
    "\t\tImpacts: " & $a.bmImpact & '\n' &
    "\t\tTotal Impact Force: " & $a.bmImpactF & '\n' &
    "\tMineralMineral:\n" &
    "\t\tTotal Contacts: " & $a.mmTotal & '\n' &
    "\t\tImpacts: " & $a.mmImpact & '\n' &
    "\t\tTotal Impact Force: " & $a.mmImpactF & '\n' &
    "\tTotal Wear: " & $a.abrasion & "\n\n" &
    "Number of headers counted: " & parsedHeaderCount & '\n'

proc parseInput(input: string): seq[MaterialRange] =
  for line in input.split('\n'): 
    var
      lowR, highR: int
      kind: string
    
    if line.scanf("$i..$i, $+", lowR, highR, kind):
      let matType = # kind.parseEnum[: Material]()
        try:
          kind.parseEnum[: Material]():
        except ValueError:
          echo ">>> Error with the type <<" & kind & ">>."
          raise newException(NoMatchingEnum,
                            "The type above doesn't match either 'Ball' or 'Mineral'.\n" &
                            "Make sure you wrote the type properly.")
      let fHighR =
        if highR == 0: Inf else: highR.float # Using `0` to represent infinty
      result.add MaterialRange(rng: lowR.float..fHighr, matType: matType)      

proc collisionType(ids: array[2, float], ranges: seq[MaterialRange]): 
  (Material, Material) =
  var set1, set2: bool
  for rng in ranges:
    if ids[0] in rng.rng:
      result[0] = rng.matType
      set1 = true
    if ids[1] in rng.rng:
      result[1] = rng.matType
      set2 = true
    if set1 == true and set2 == true:
      break
  if set1 == false or set2 == false:
    result = (None, None)

proc isHeader(line: string): bool =
  ## Checks if the line is a "header" line.
  ## Headers are found all through the particles.txt file.
  if line[0] == 'I' or count(line, ' ') < 2: # Count spaces in line, with less than 3 numbers there'll be less than 2 spaces.
    true
  else: false

proc makeProgressBar(prog: float): string =
  var diff = 100.0

  result.add("[")

  for i in 0..prog.int:
    diff -= 1
    if i mod 5 == 0:
      result.add("#")

  for i in 0..diff.int:
    if i mod 5 == 0:
      result.add("-")

  result.add(&"] ({formatFloat(prog, ffDecimal, 2)}%)\r")

proc vectorModulus(fx, fy, fz: float): float =
  ## Calculates the modulus of a vector.
  result = sqrt(fx^2 + fy^2 + fz^2)

proc archard(area, magnitude: float): float =
  ## Determines the wear of the material using the Archard equation.
  const
    kMinMin = 0.005
    H = 90.0
  result = sqrt(4 * area / 3.1416) * kMinMin * magnitude * H

proc fHertz(force, area: float): float =
  ## Fracture per Hertz.
  result = 3.0 * force / (2.0 * 3.1416 * (area / 3.1416))
    
proc doLines(acc: ptr ForceTotal, c: int, ms: MemSlice, ranges: seq[MaterialRange]) =
  const 
    colIds = {0'i16, 1'i16}
    colForces = {3'i16, 4'i16, 5'i16, 6'i16, 7'i16, 8'i16, 9'i16}
  var 
    ids: array[2, float]        # particle ids
    forces: array[4..10, float] # cfc forces
    line: string                # re-used buffer

  for i, s in ms.nSplit('\n'):
    line.setLen s.size
    copyMem line[0].addr, s.data, s.size
    if line.isHeader:
      acc.headerCount += 1.0
      continue
    
    var j = 0'i8                # fill ids & forces
    for col in line.split:
      if j in colIds: ids[j] = col.parseFloat
      elif j in colForces: forces[j+1] = col.parseFloat
      j.inc

    let 
      cType = ids.collisionType(ranges)
      magnitude = vectorModulus(forces[4], forces[5], forces[6])
      force = fHertz(magnitude, forces[10])

    if cType == (Ball, Ball):
      acc.bbTotal.inc
      if force > compResistance:
        acc.bbImpact.inc
        acc.bbImpactF += force

    elif cType == (Ball, Mineral) or
         cType == (Mineral, Ball):
       acc.bmTotal.inc
       if force > compResistance:
        acc.bmImpact.inc
        acc.bmImpactF += force
    
    elif cType == (Mineral, Mineral):
      acc.mmTotal.inc
      if force > compResistance:
        acc.mmImpact.inc
        acc.mmImpactF += force

    else: 
      echo ">>> Error in the following ID pair: ", $ids
      raise newException(NoMaterialID, 
                        "One of material IDs above wasn't caught by the collisionType procedure. " &
                        "Make sure you entered the Material ranges correctly.")

    acc.abrasion += archard(forces[10], magnitude)

    if c == 0 and i mod 500_000 == 0: # progress report
      let 
        did = cast[int](s.data) -% cast[int](ms.data)
        percent = did/ms.size*100
      stdout.eraseLine()
      stdout.write(makeProgressBar(percent) & '\r')
      stdout.flushFile()

proc total(accs: seq[ForceTotal]): ForceTotal =
  for a in accs:
    result.bbTotal += a.bbTotal
    result.bbImpact += a.bbImpact
    result.bbImpactF += a.bbImpactF
    result.bmTotal += a.bmTotal
    result.bmImpact += a.bmImpact
    result.bmImpactF += a.bmImpactF
    result.mmTotal += a.mmTotal
    result.mmImpact += a.mmImpact
    result.mmImpactF += a.mmImpactF
    result.abrasion += a.abrasion
    result.headerCount += a.headerCount

proc malachite(input, path: string) =
  ## Starts the processing based on the input from the user 
  ## and the number of cores of the computer.

  let 
    nThr0 = parseInt(getEnv("NT", "0"))
    nThr = if nThr0 == 0: countProcessors() else: nThr0
    userInput = parseInput(input)

  echo "These were the ranges passed by the user:\n"
  for u in userInput:
    echo $u
  echo ""

  echo "Calculating using ", $nThr, " cores.\n"

  var 
    (mf, parts) = nThr.split(path)
    accs = newSeq[ForceTotal](nThr)

  echo "Processing has started, please wait. . ."

  for c, part in parts:
    spawn doLines(accs[c].addr, c, part, userInput)

  threadpool.sync()

  echo makeProgressBar(100.0)

  echo "Done processing!\n"

  let results = total(accs)

  writeFile("results.txt", $results)

  echo $results, "\n\nThe result of the calculations have been written to the \"results.txt\" file.",
       "\nThank you for using Malachite."

#######
# TUI #
#######

const
  splash = """
  __  __       _            _     _ _
 |  \/  | __ _| | __ _  ___| |__ (_) |_ ___
 | |\/| |/ _` | |/ _` |/ __| '_ \| | __/ _ \
 | |  | | (_| | | (_| | (__| | | | | ||  __/
 |_|  |_|\__,_|_|\__,_|\___|_| |_|_|\__\___|

===========================================
 MIT License

 Copyright (c) 2021 domdomdomdomino
============================================

 Input must be written in this form:
////////////////////////////////////////////
 1..1_000, Ball
 1_001..0, Material
////////////////////////////////////////////
 The only valid types are 'Ball' and
 'Mineral', and '0' is used in the right
 side of the '..' operand to represent
 positive infinity. Press enter on an empty
 line to finish writing input.

 It is your responsability to make sure that
 the ranges you input don't overlap and that
 they also cover all the IDs.

 WARNING: Malachite cannot process files
  with a prime number of lines. Please
  contact the developer if you get an
  error in the `doLines` proc regarding
  `BadFormat`.
"""
  doc = """

Malachite.

Usage:
  Malachite <file>
  Malachite -l <file>
  Malachite [options]

Options:
  -h --help         Show this screen
  -l                Loads the input from the last session

"""

proc splashScreen() =
  echo splash
  if fileExists(absolutePath("last_session.txt")):
    let contents = readFile(absolutePath("last_session.txt"))
    echo """
############################################
 Your last input was:

""" & contents & """

############################################
"""
  else:
    let f = open("last_session.txt", fmWrite)
    defer: f.close()

proc reader(): string =
  var input: string
  while true:
    stdout.write ">>> "
    let i = readLine(stdin)

    if i == "":
      break
    else:
      input = input & i & "\n"
  writefile("last_session.txt", input)
  return input

when isMainModule:
  # splashScreen()
  # malachite(reader())
  let args = docopt(doc)

  if args["<file>"] and not args["-l"]:
    let path = $args["<file>"]
    if path == "nil":
      echo doc
    elif not fileExists(path):
      raise newException(OSError, "'"& path & "' file does not exist.")
    else:
      splashScreen()
      malachite(reader(), path)
  elif args["-l"]:
    let path = $args["<file>"]
    if path == "nil":
      echo doc
    elif not fileExists(path):
      raise newException(OSError, "'"& path & "' file does not exist.")
    else:
      if fileExists(absolutePath("last_session.txt")):
        let ls = readFile(absolutePath("last_session.txt"))
        if ls != "":
          malachite(ls, path)
        else:
          raise newException(OSError, "The 'last_session.txt' file is empty.")
      else:
        raise newException(OSError, "The 'last_session.txt' file does not exist.")
  else:
    echo $args
    echo doc
