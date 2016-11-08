import jester, asyncdispatch, htmlgen, os, osproc, times

var
  collectorThread: Thread[void]
  folderThread: Thread[void]
  chanToFolder: Channel[int]

proc foldStacks() {.thread.} =
  write(stderr, "Folder...\n")
  while true:
    let timestamp = recv(chanToFolder)
    write(stderr, "Folder... " & $timestamp & "\n")
    let errCode = execCmd("perf script -i /var/lib/kaldur/perf" & $timestamp & ".data | /root/FlameGraph/stackcollapse-perf.pl > /var/lib/kaldur/out" & $timestamp & ".perf-folded")
    write(stderr, "Folder finished, error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    removeFile("/var/lib/kaldur/perf" & $timestamp & ".data")

proc collectOnCPUMetrics() {.thread.} =
  while true:
    write(stderr, "Collecting on-CPU flamegraphs...\n")
    let currentTime = toInt(epochTime())
    write(stderr, "On-CPU... " & $currentTime & "\n")
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" & $currentTime & ".data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    write(stderr, "Sending an identifier to the channel..." & $chanToFolder & " " & $currentTime & "\n")
    send(chanToFolder, currentTime)
    write(stderr, "Message sent!\n")

routes:
  get "/":
    resp h1("Hello world")

open(chanToFolder) 
createThread(collectorThread, collectOnCPUMetrics)
createThread(folderThread, foldStacks)
runForever()
