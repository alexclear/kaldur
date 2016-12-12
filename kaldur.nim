import prometheus, jester, asyncdispatch, htmlgen, os, osproc, times, strutils, algorithm, parsecfg, streams

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
    let time = getLocalTime(fromSeconds(timestamp))
    createDir(staticDir & "/" & format(time, "yyyyMMdd"))
    let errCode = execCmd("/root/FlameGraph/flamegraph.pl " & staticDir & "/out" &
      $timestamp & ".perf-folded > " & staticDir & "/" & format(time, "yyyyMMdd") & "/perf" & $timestamp & ".svg")
    if errCode != 0:
      quit(QuitFailure)
    removeFile( staticDir & "/out" & $timestamp & ".perf-folded")

var config = loadConfig("kaldur.ini")
confStaticDir = config.getSectionValue("Global","staticdir")
if confStaticDir == "":
  echo("Global/staticdir is not found!")
  quit(QuitFailure)
else:
  echo("staticdir is: " & confStaticDir)

proc configRoutes(staticDir: string) =
  var localCounter = newCounter("http_reqs_counter", "Number of HTTP requests")
  routes:
    get "/metrics":
      resp exportAllMetrics(), "text/plain; charset=utf-8"
    get "/":
      let start = epochTime()
      var paths: seq[string]
      var files = ""
      localCounter.increment()
      request.setStaticDir(staticDir)
      echo("After request.setStaticDir()... " & $(epochTime() - start))
      paths = @[]
      let currentTime = getLocalTime(getTime())
      let currentDir = staticDir & "/" & format(currentTime, "yyyyMMdd")
      createDir(currentDir)
      for path in walkDirRec(currentDir, {pcFile}):
        if path.endsWith(".svg"):
          paths.add(rsplit(path, "/", 1)[1])
      echo("After walkDirRec... " & $(epochTime() - start))
      sort(paths, system.cmp, order = SortOrder.Descending)
      echo("After sort... " & $(epochTime() - start))
      var buffer: string
      for path in paths:
        buffer = path
        delete(buffer, 0, 3)
        let epochstr = rsplit(buffer, ".", 1)[0];
        let time = getLocalTime(fromSeconds(parseInt(epochstr)))
        files = files & a(href="/" & format(currentTime, "yyyyMMdd") & "/" & path, path) & " [" & format(time, "ddd MMM dd HH:mm:ss ZZZ yyyy") & "]<BR/>\n"
      echo("After processing paths array... " & $(epochTime() - start))
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
