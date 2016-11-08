import jester, asyncdispatch, htmlgen, os, osproc, times

var
  thr: Thread[Channel[int]]
  thr1: Thread[Channel[int]]
  chan: Channel[int]

proc foldStacks(chan: Channel[int]) {.thread.} =
  var chan1 = chan
  write(stderr, "Folder...\n")
  while true:
    let timestamp = recv(chan1)
    write(stderr, "Folder... " & $timestamp & "\n")
    let errCode = execCmd("perf script -i /var/lib/kaldur/perf" & $timestamp & ".data | /root/FlameGraph/stackcollapse-perf.pl > /var/lib/kaldur/out" & $timestamp & ".perf-folded")
    write(stderr, "Folder finished, error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)

proc collectOnCPUMetrics(chan: Channel[int]) {.thread.} =
  var channel = chan
  while true:
    write(stderr, "Collecting on-CPU flamegraphs...\n")
    let currentTime = toInt(epochTime())
    write(stderr, "On-CPU... " & $currentTime & "\n")
    let errCode = execCmd("perf record -F 99 -o /var/lib/kaldur/perf" & $currentTime & ".data -a -g -- sleep 60")
    write(stderr, "Error code: " & $errCode & "\n")
    if errCode != 0:
      quit(QuitFailure)
    write(stderr, "Sending an identifier to the channel..." & $channel & " " & $currentTime & "\n")
    send(channel, currentTime)
    write(stderr, "Message sent!\n")

routes:
  get "/":
    resp h1("Hello world")

createThread(thr, collectOnCPUMetrics, chan)
createThread(thr1, foldStacks, chan)
runForever()
