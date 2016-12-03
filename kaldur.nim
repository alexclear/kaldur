import jester, asyncdispatch, htmlgen, os, osproc, times, strutils, algorithm, parsecfg, streams

var
  collectorThread: Thread[string]
  folderThread: Thread[string]
  svgCreatorThread: Thread[string]
  chanToFolders: Channel[int]
  chanToSVGCreators: Channel[int]
  confStaticDir : string

proc foldStacks(staticDir: string) {.thread.} =
  while true:
    let timestamp = recv(chanToFolders)
    let errCode = execCmd("perf script -i " & staticDir & "/perf" & $timestamp &
      ".data | /root/FlameGraph/stackcollapse-perf.pl > " & staticDir & "/out" &
      $timestamp & ".perf-folded")
    if errCode != 0:
      quit(QuitFailure)
    removeFile( staticDir & "/perf" & $timestamp & ".data")
    send(chanToSVGCreators, timestamp)

proc collectOnCPUMetrics(staticDir: string) {.thread.} =
  while true:
    let currentTime = toInt(epochTime())
    let errCode = execCmd("perf record -F 99 -o " & staticDir & "/perf" &
      $currentTime & ".data -a -g -- sleep 60")
    if errCode != 0:
      quit(QuitFailure)
    send(chanToFolders, currentTime)

proc svgCreator(staticDir: string) {.thread.} =
  while true:
    let timestamp = recv(chanToSVGCreators)
    let errCode = execCmd("/root/FlameGraph/flamegraph.pl " & staticDir & "/out" &
      $timestamp & ".perf-folded > " & staticDir & "/perf" & $timestamp & ".svg")
    if errCode != 0:
      quit(QuitFailure)

var config = loadConfig("kaldur.ini")
confStaticDir = config.getSectionValue("Global","staticdir")
if confStaticDir == "":
  echo("Global/staticdir is not found!")
  quit(QuitFailure)
else:
  echo("staticdir is: " & confStaticDir)

proc configRoutes(staticDir: string) =
  routes:
    get "/":
      var paths: seq[string]
      var files = ""
      request.setStaticDir(staticDir)
      paths = @[]
      for path in walkDirRec(staticDir, {pcFile}):
        if path.endsWith(".svg"):
          paths.add(rsplit(path, "/", 1)[1])
      sort(paths, system.cmp, order = SortOrder.Descending)
      for path in paths:
        files = files & a(href="/" & path, path) & "<BR/>"
      resp h1("You can find your flamegraphs below") & "<BR/>" & files

configRoutes(confStaticDir)
open(chanToFolders)
open(chanToSVGCreators)
createThread(collectorThread, collectOnCPUMetrics, confStaticDir)
createThread(folderThread, foldStacks, confStaticDir)
createThread(svgCreatorThread, svgCreator, confStaticDir)
while true:
  try:
    runForever()
  except:
    echo "Exception: " & getCurrentExceptionMsg()
