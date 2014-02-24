import-scripts \lunr.js

index = lunr !->
  @field \sub
  @field \name
  @field \text # com without html
  @field \filename
  @field \ext

  @ref \no

queue = []

function index-next
  for i til 100
    doc = queue.shift!
    if doc?
      start = Date.now!
      res = index.index doc
      time = Date.now! - start

      post-message do
        verb: \index
        body: res
        latency: time
    else
      break
  set-timeout index-next, 0

set-timeout index-next, 0

{data} <-! add-event-listener \message

if data.verb is \index
  queue.push body
else
  start = Date.now!
  res = index[data.verb] data.body
  time = Date.now! - start

  post-message do
    verb: data.verb
    body: res
    latency: time

