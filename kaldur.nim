import jester, asyncdispatch, htmlgen, os, osproc, times

var
  collectorThread: Thread[void]
  folderThread: Thread[void]
  svgCreatorThread: Thread[void]
  chanToFolders: Channel[int]
  chanToSVGCreators: Channel[int]

proc foldStacks() {.thread.} =
  write(stderr, "Folder...\n")
  while true:
    let timestamp = recv(chanToFolders)
    write(stderr, "Folder... " & $timestamp & "\n")
    let errCode = execCmd("perf script -i /var/lib/kaldur/perf" & $timestamp &
      ".data | /root/FlameGraph/stackcollapse-perf.pl > /var/lib/kaldur/out" &
      $timestamp & ".perf-folded")
    write(stderr, "Folder finished, error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    removeFile("/var/lib/kaldur/perf" & $timestamp & ".data")
    send(chanToSVGCreators, timestamp)

proc collectOnCPUMetrics() {.thread.} =
  while true:
    write(stderr, "Collecting on-CPU flamegraphs...\n")
    let currentTime = toInt(epochTime())
    write(stderr, "On-CPU... " & $currentTime & "\n")
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" &
      $currentTime & ".data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    write(stderr, "Sending an identifier to the channel..." &
      $chanToFolders & " " & $currentTime & "\n")
    send(chanToFolders, currentTime)
    write(stderr, "Message sent!\n")

proc svgCreator() {.thread.} =
  while true:
    let timestamp = recv(chanToSVGCreators)
    write(stderr, "SVG Creator... " & $timestamp & "\n")
    let errCode = execCmd("/root/FlameGraph/flamegraph.pl /var/lib/kaldur/out" &
      $timestamp & ".perf-folded > /var/lib/kaldur/perf" & $timestamp & ".svg")
    write(stderr, "SVG Creator finished, error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)

routes:
  get "/":
    resp h1("Hello world")

open(chanToFolders) 
open(chanToSVGCreators) 
createThread(collectorThread, collectOnCPUMetrics)
createThread(folderThread, foldStacks)
createThread(svgCreatorThread, svgCreator)
runForever()
