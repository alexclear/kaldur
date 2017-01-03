import prometheus, jester, asyncdispatch, htmlgen, os, osproc, times, strutils, algorithm, parsecfg, streams, logging

type
  ThreadContext = ref object of RootObj
    staticDir: string

const
  bucketMargins = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 110.0, 120.0, 130.0, 140.0, 150.0, 160.0, 170.0, 180.0, 190.0, 200.0, 210.0, 220.0, 230.0, 240.0, 250.0, 260.0, 270.0, 280.0, 290.0, 300.0, 310.0, 320.0, 330.0, 340.0, 350.0, 360.0, 370.0, 380.0, 390.0, 400.0, 410.0, 420.0, 430.0, 440.0, 450.0, 460.0, 470.0, 480.0, 490.0, 500.0, 510.0, 520.0, 530.0, 540.0, 550.0, 560.0, 570.0, 580.0, 590.0, 600.0, 610.0, 620.0, 630.0, 640.0, 650.0, 660.0, 670.0, 680.0, 690.0, 700.0, 710.0, 720.0, 730.0, 740.0, 750.0, 760.0, 770.0, 780.0, 790.0, 800.0, 810.0, 820.0, 830.0, 840.0, 850.0, 860.0, 870.0, 880.0, 890.0, 900.0, 910.0, 920.0, 930.0, 940.0, 950.0, 960.0, 970.0, 980.0, 990.0, 1000.0, 1100.0, 1200.0, 1300.0, 1400.0, 1500.0, 1600.0, 1700.0, 1800.0, 1900.0, 2000.0, 2250.0, 2500.0, 2750.0, 3000.0, 4000.0, 5000.0, 6000.0, 7000.0, 8000.0, 9000.0, 10000.0, 12000.0, 14000.0, 16000.0, 18000.0, 20000.0, 25000.0, 30000.0, 35000.0, 40000.0, 50000.0, 60000.0, 70000.0, 90000.0, 120000.0, 180000.0, 240000.0]

var
  collectorThread: Thread[string]
  folderThread: Thread[ThreadContext]
  svgCreatorThread: Thread[string]
  statsThread: Thread[void]
  chanToFolders: Channel[int]
  chanToSVGCreators: Channel[int]
  httpReqsChan: Channel[int]
  statRequestChan: Channel[int]
  folderLatencyHistogramChan: Channel[float]
  httpLatencyHistogramChan: Channel[float]
  promChan: Channel[Prometheus]
  confStaticDir: string
  confPort: int

proc foldStacks(context: ThreadContext) {.thread.} =
  while true:
    let timestamp = recv(chanToFolders)
    let start = epochTime()
    let errCode = execCmd("perf script -i " & context.staticDir & "/perf" & $timestamp &
      ".data | /root/FlameGraph/stackcollapse-perf.pl > " & context.staticDir & "/out" &
      $timestamp & ".perf-folded")
    send(folderLatencyHistogramChan, (epochTime() - start)*1000)
    if errCode != 0:
      quit(QuitFailure)
    removeFile( context.staticDir & "/perf" & $timestamp & ".data")
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

proc statsProc() {.thread.} =
  let prom = newPrometheus()
  var localCounter = prom.newCounter("kaldur_http_reqs_counter", "Number of HTTP requests.")
  var latencyHistogram = prom.newHistogram("kaldur_http_reqs_latency", "Latency of HTTP requests in millis.", bucketMargins)
  var folderLatencyHistogram = prom.newHistogram("kaldur_foldstacks_execcmd_time", "Time of execCmd in foldStacks.", bucketMargins)
  var result: bool
  var latency: float
  while true:
    let (result1, _) = tryRecv(httpReqsChan)
    if result1:
      localCounter.increment()
    (result, latency) = tryRecv(httpLatencyHistogramChan)
    if result:
      latencyHistogram.observe(latency)
    (result, latency) = tryRecv(folderLatencyHistogramChan)
    if result:
      folderLatencyHistogram.observe(latency)
    let (result2, _) = tryRecv(statRequestChan)
    if result2:
      send(promChan, prom)
    sleep(20)

var config = loadConfig("kaldur.ini")
confStaticDir = config.getSectionValue("Global","staticdir")
if confStaticDir == "":
  echo("Global/staticdir is not found!")
  quit(QuitFailure)
else:
  echo("staticdir is: " & confStaticDir)
let confPortStr = config.getSectionValue("Global","port")
if confPortStr == "":
  confPort = 5000
else:
  confPort = parseInt(confPortStr)

if not existsDir(confStaticDir):
  echo("Please create " & confStaticDir & " directory!")
  quit(QuitFailure)

proc configRoutes(staticDir: string, port: int) =
  settings:
    port = (Port) port
    staticDir = staticDir
  routes:
    get "/metrics":
      send(httpReqsChan, 1)
      send(statRequestChan, 1)
      let prom = recv(promChan)
      resp prom.exportAllMetrics(), "text/plain; charset=utf-8"
    get "/":
      let start = epochTime()
      var paths: seq[string]
      var files = ""
      send(httpReqsChan, 1)
      request.setStaticDir(staticDir)
      paths = @[]
      let currentTime = getLocalTime(getTime())
      let currentDir = staticDir & "/" & format(currentTime, "yyyyMMdd")
      createDir(currentDir)
      for path in walkDirRec(currentDir, {pcFile}):
        if path.endsWith(".svg"):
          paths.add(rsplit(path, "/", 1)[1])
      sort(paths, system.cmp, order = SortOrder.Descending)
      var buffer: string
      for path in paths:
        buffer = path
        delete(buffer, 0, 3)
        let epochstr = rsplit(buffer, ".", 1)[0];
        let time = getLocalTime(fromSeconds(parseInt(epochstr)))
        files = files & a(href="/" & format(currentTime, "yyyyMMdd") & "/" & path, path) & " [" & format(time, "ddd MMM dd HH:mm:ss ZZZ yyyy") & "]<BR/>\n"
      send(httpLatencyHistogramChan, (epochTime() - start)*1000)
      resp h1("You can find your flamegraphs below") & "<BR/>" & files

configRoutes(confStaticDir, confPort)
open(chanToFolders)
open(chanToSVGCreators)
open(folderLatencyHistogramChan)
open(httpLatencyHistogramChan)
open(httpReqsChan)
open(statRequestChan)
open(promChan)
createThread(statsThread, statsProc)
createThread(collectorThread, collectOnCPUMetrics, confStaticDir)
createThread(folderThread, foldStacks, ThreadContext(staticDir: confStaticDir))
createThread(svgCreatorThread, svgCreator, confStaticDir)
setLogFilter(lvlInfo)
while true:
  try:
    runForever()
  except:
    echo "Exception: " & getCurrentExceptionMsg()
