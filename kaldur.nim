import jester, asyncdispatch, htmlgen, os, osproc, times, strutils, algorithm

var
  collectorThread: Thread[void]
  folderThread: Thread[void]
  svgCreatorThread: Thread[void]
  chanToFolders: Channel[int]
  chanToSVGCreators: Channel[int]

proc foldStacks() {.thread.} =
  while true:
    let timestamp = recv(chanToFolders)
    let errCode = execCmd("perf script -i /var/lib/kaldur/perf" & $timestamp &
      ".data | /root/FlameGraph/stackcollapse-perf.pl > /var/lib/kaldur/out" &
      $timestamp & ".perf-folded")
    if errCode != 0:
      quit(QuitFailure)
    removeFile("/var/lib/kaldur/perf" & $timestamp & ".data")
    send(chanToSVGCreators, timestamp)

proc collectOnCPUMetrics() {.thread.} =
  while true:
    let currentTime = toInt(epochTime())
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" &
      $currentTime & ".data -a -g -- sleep 60")
    if errCode != 0:
      quit(QuitFailure)
    send(chanToFolders, currentTime)

proc svgCreator() {.thread.} =
  while true:
    let timestamp = recv(chanToSVGCreators)
    let errCode = execCmd("/root/FlameGraph/flamegraph.pl /var/lib/kaldur/out" &
      $timestamp & ".perf-folded > /var/lib/kaldur/perf" & $timestamp & ".svg")
    if errCode != 0:
      quit(QuitFailure)

routes:
  get "/":
    var paths: seq[string]
    var files = ""
    request.setStaticDir("/var/lib/kaldur")
    paths = @[]
    for path in walkDirRec("/var/lib/kaldur", {pcFile}):
      if path.endsWith(".svg"):
        paths.add(rsplit(path, "/", 1)[1])
    sort(paths, system.cmp, order = SortOrder.Descending)
    for path in paths:
      files = files & a(href="/" & path, path) & "<BR/>"
    resp h1("You can find your flamegraphs below") & "<BR/>" & files

open(chanToFolders)
open(chanToSVGCreators)
createThread(collectorThread, collectOnCPUMetrics)
createThread(folderThread, foldStacks)
createThread(svgCreatorThread, svgCreator)
runForever()
