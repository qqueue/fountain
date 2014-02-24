$ = document~get-element-by-id
L = document~create-element

div = $ \threads

es = new EventSource \http://localhost:3500/v1/a/stream?init=true
init = Bacon.from-event-target es, \init

svg = d3.select \#svg

init.on-value !->
  es.close!
  it = JSON.parse it.data
  console.log "event!"
  posts = []
  t = {}
  i = 0
  filter = 100
  for tno, thread of it
    continue unless thread.replies > filter
    t[tno] = i++
    for post in thread.posts
      posts.push post

  posts.sort (a, b) -> a.no - b.no

  earliest = posts.0.time
  latest = posts[*-1].time

  x-scale = d3.scale.linear!
    .domain [earliest, latest]
    .range [0 5600]

  slices = 500

  buckets = [{} for i til slices]
  step = (latest - earliest) / slices
  todo = posts.slice!
  :outer for i from 1 to slices
    b = buckets[i-1]
    thresh = earliest + step * i
    b.thresh = thresh - step
    while todo.length > 0
      p = todo.shift!
      if p.time < thresh
        tno = p.resto || p.no
        if b[tno]?
          b[tno]++
        else
          b[tno] = 1
      else
        todo.unshift p
        continue outer


  layers = []
  for tno, thread of it
    continue unless thread.replies > filter
    l = []
    for b in buckets
      l.push x: b.thresh, y: b[tno] || 0

    layers.push l

  stack = d3.layout.stack!
    .offset \zero
    .order \default

  stack layers

  s = []
  for i til slices
    s.push d3.max layers.map -> it[i].y + it[i].y0

  w-max = d3.max s
  console.log s
  console.log w-max

  y-scale = d3.scale.linear!
    .domain [0, w-max]
    .range [1600 100]

  area = d3.svg.area!
    .x x-scale << (.x)
    .y0 y-scale << (.y0)
    .y1 y-scale << -> it.y0 + it.y


  console.log "drawing"

  svg.select-all \.thread .data layers
    ..exit!remove!
    ..enter!append \path
      ..attr \class \thread
      ..attr \d area

