require! {
  Bacon: \baconjs
  \./Limiter
  \./request
  Yotsuba: \./yotsuba
  fs
  colors
  _: \prelude-ls
  #req: \request
  agent: \webkit-devtools-agent
  lynx
  memwatch
}

stats = new lynx \localhost 8125 scope: \fountain

memwatch.on \leak !->
  stats.increment 'leak'
  console.log it

# inc_gc/full_gc/compactions are all counting from 0
# which is not as useful as a rate, so keep track of last seen
last-inc-gc = 0
last-full-gc = 0
last-heap-compactions = 0

memwatch.on \stats !->
  stats.count "mem.inc_gc" diff if (diff = it.inc_gc - last-inc-gc) > 0
  last-inc-gc := it.inc_gc

  stats.count "mem.full_gc" diff if (diff = it.full_gc - last-full-gc) > 0
  last-full-gc := it.full_gc

  if (diff = it.heap_compactions - last-heap-compactions) > 0
    stats.count "mem.heap_compactions" diff
  last-heap-compactions := it.heap_compactions

  # still not really sure what usage trend is, gauge anyway
  stats.gauge "mem.usage_trend" it.usage_trend

  stats.gauge "mem.current_base" it.current_base
  stats.gauge "mem.min" it.min
  stats.gauge "mem.max" it.max

  for k, v of process.memory-usage! # rss, heapTotal, heapUsed
    stats.gauge "mem.#k" v

text-content = ->
  return '' if not it?
  it.replace /<br>/g '\n' .replace /<[^>]+?>/g ''
    .replace /&gt;/g '>' .replace /&quot;/g '"'
    .replace /&#039;/g \' .replace /&lt;/g '<'
    .replace /&amp;/g '&'

export y = new Yotsuba do
  \a
  if fs.exists-sync \a.json then JSON.parse fs.read-file-sync \a.json

#if init?
  #posts = []

  #for n, thread of init.threads
    #posts.push ...thread.posts

  #ops = []
  #for posts
    #ops.push JSON.stringify {
      #index:
        #_index: "yotsuba"
        #_timestamp: ..time * 1000
        #_type: \post
        #_id: ..no
        #_parent: if ..resto is not 0 then that
    #}
    #ops.push JSON.stringify ..

  #req.put do
    #url: "http://localhost:9200/yotsuba/_bulk"
    #body: ops.join \\n
    #(err, res, body) ->
      #throw err if err
      #

export l = new Limiter 1000ms request.get, (.status-code >= 500)

#y.responses.plug l.responses
l.responses.on-value (res) !->
  set-timeout (!-> y.responses.push res), 0

l.responses.on-error !->
  stats.increment 'responses.error'

#l.requests.plug y.requests
y.requests.on-value (req) !->
  set-timeout (!-> l.requests.push req), 0

#y.ready.plug l.ready
l.ready.on-value (ready) !->
  set-timeout (!-> y.ready.push ready), 0

#l.requests.on-value !-> console.log "requesting #{it.path}".green
l.responses.filter (.status-code is not 200)
  .on-value !-> console.log "response: #{it.status-code}".red.bold

y.board.on-value !({diff}: board) ->
  threads = _.values board.threads
  missing = board.stale.map ->
    t = board.threads[it]
    return 0 unless t?
    t.replies - t.posts.length + 1

  if diff.new-threads.length > 0
    stats.count 'new-threads' diff.new-threads.length
    console.log "#{diff.new-threads.length} new threads \
                 #{diff.new-threads.map (.no)}".blue.bold
  if diff.new-posts.length > 0
    stats.count 'new-posts' diff.new-posts.length
    for size in diff.new-posts.filter (.fsize?) .map (.fsize)
      stats.increment 'new-images'
      stats.timing 'image-size' size
    console.log "#{diff.new-posts.length} new posts".blue.bold
  if diff.deleted-threads.length > 0
    stats.count 'deleted-threads' diff.deleted-threads.length
    console.log "#{diff.deleted-threads.length} deleted threads: \
                 #{diff.deleted-threads}".red.bold
  if diff.changed-threads.length > 0
    stats.increment 'changed-threads'
    console.log "#{diff.changed-threads.length} changed threads".red.bold
  if diff.deleted-posts.length > 0
    stats.count 'deleted-posts' diff.deleted-posts.length
    console.log "#{diff.deleted-posts.length} deleted posts: \
                 #{diff.deleted-posts.map (.no)}".red.bold
  if diff.changed-posts.length > 0
    stats.count 'changed-posts' diff.changed-posts.length
    console.log "#{diff.changed-posts.length} changed posts".red.bold
  stats.gauge 'threads' threads.length
  stats.gauge 'posts' _.sum threads.map (.posts.length)
  stats.gauge 'images' _.sum threads.map (.images)
  stats.gauge do
    'image-size'
    _.sum(threads.map -> _.sum it.posts.map (.fsize || 0)) / 1_000_000
  #console.log "#{threads.length} threads, \
    ##{_.sum threads.map (.posts.length)} posts, \
    ##{_.sum threads.map (.images)} images (
    ##{_.sum(threads.map -> _.sum it.posts.map (.fsize || 0)) / 1_000_000}Mb)
    #".white.bold

  s = board.stale.length
  if s > 0
    stats.gauge 'stale-threads' s
    console.log "#{board.stale.length} stale threads".red.bold

  m = _.sum missing
  if m > 0
    stats.gauge 'missing-posts' m
    console.log "#m missing".red.bold

  for it in diff.new-posts
    latency = Date.now! - it.time * 1000
    stats.timing 'post-latency' latency
    if latency > 60_000
      console.log "================".red
      console.log "latent: #latency".red
      console.log "#{JSON.stringify it , , 3}".red
  for it in diff.changed-posts
    console.log "!!!!!!!!!!!!!!!!".red
    console.log "#{JSON.stringify it , , 3}".red

#y.board.changes!on-value !({diff}) ->
  #for it in diff.new-posts
    #req.put do
      #url: "http://localhost:9200/yotsuba/post/#{it.no}
            #?_parent=#{it.resto}&_timestamp=#{it.time * 1000}"
      #json: it
      #(err, res, body) ->
        #console.log err if err
        #console.log body if not (200 <= res.status-code <= 300)

l.ready.push true

require("net")
  .createServer (socket) !->
    repl = require('repl')
    repl.start do
      prompt: 'fountain> '
      input: socket
      output: socket
      use-global: true
      terminal: true
    .on \exit !-> socket.end!
  .listen 5000, "localhost"

stringify = ->
  JSON.stringify it .replace /\n/g '\\n'

require! express
do express
  # we have to make zlib flush synchronously or it'll buffer
  # our event streams
  ..use express.compress { flush: require \zlib .Z_SYNC_FLUSH }
  ..get \/stream (req, res) !->
    console.log "got request to stream"
    req.socket.set-timeout Infinity

    # XXX if we implicitly set the headers as an object in
    # write-head, then the compression middleware won't see
    # our content type and will thus not compress our stream.
    # Kind of annoying, since set-header is more verbose.
    res.set-header 'Content-Type', \text/event-stream
    res.set-header 'Transfer-Encoding', \identity
    res.set-header 'Cache-Control', \no-cache
    res.set-header 'Connection', \keep-alive
    res.set-header 'Access-Control-Allow-Origin', '*'
    res.write-head 200

    # TODO keep track of changes to rewind last-event-id
    res.write ':hi\n\n'

    # send initial state over the wire
    # TODO figure out how to do this nicely without pushing 8MB of state
    # in one event.
    if req.param \init
      y.board.sampled-by Bacon.once! .on-value !->
        res.write "event: init\n
                   data: #{stringify it.threads}\n\n"

    console.log "opened event-stream!".white.bold
    close = Bacon.from-callback res, \on \close
      ..on-value !-> console.log "closed event-stream!".white.bold
    err = Bacon.from-callback res, \on \error
      ..on-value console.error
    y.board.changes!take-until Bacon.merge-all(close, err) .on-value !->
      if it.diff.new-posts.length > 0
        res.write "event: new-posts\n
                   data: #{stringify it.diff.new-posts}\n\n"
      if it.diff.deleted-posts.length > 0
        res.write "event: deleted-posts\n
                   data: #{stringify it.diff.deleted-posts}\n\n"
      if it.diff.new-threads.length > 0
        res.write "event: new-threads\n
                   data: #{stringify it.diff.new-threads}\n\n"
      if it.diff.deleted-threads.length > 0
        res.write "event: deleted-threads\n
                   data: #{stringify it.diff.deleted-threads}\n\n"

    Bacon.interval 10_000ms .take-until close .on-value !->
      res.write ":ping\n\n"
  ..listen 3500

Bacon.from-event-target process, \SIGINT .map y.board .on-value ->
  console.log "saving state..."
  fs.write-file-sync \a.json JSON.stringify(it, null, "  ")
  process.exit 0

