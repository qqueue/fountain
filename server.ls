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
}

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

#l.requests.plug y.requests
y.requests.on-value (req) !->
  set-timeout (!-> l.requests.push req), 0

#y.ready.plug l.ready
l.ready.on-value (ready) !->
  set-timeout (!-> y.ready.push ready), 0

l.requests.on-value !-> console.log "requesting #{it.path}".green
l.responses.filter (.status-code is not 200)
  .on-value !-> console.log "response: #{it.status-code}".red.bold

y.board.on-value !({diff}: board) ->
  threads = _.values board.threads
  missing = board.stale.map ->
    t = board.threads[it]
    return 0 unless t?
    t.replies - t.posts.length + 1

  if diff.new-threads.length > 0
    console.log "#{diff.new-threads.length} new threads \
                 #{diff.new-threads.map (.no)}".blue.bold
  if diff.new-posts.length > 0
    console.log "#{diff.new-posts.length} new posts".blue.bold
  if diff.deleted-threads.length > 0
    console.log "#{diff.deleted-threads.length} deleted threads: \
                 #{diff.deleted-threads}".red.bold
  if diff.deleted-posts.length > 0
    console.log "#{diff.deleted-posts.length} deleted posts: \
                 #{diff.deleted-posts.map (.no)}".red.bold
  if diff.changed-posts.length > 0
    console.log "#{diff.changed-posts.length} changed posts".red.bold

  console.log "#{threads.length} threads, \
    #{_.sum threads.map (.posts.length)} posts, \
    #{_.sum threads.map (.images)} images (
    #{_.sum(threads.map -> _.sum it.posts.map (.fsize || 0)) / 1_000_000}Mb)
    ".white.bold

  s = board.stale.length
  if s > 0
    console.log "#{board.stale.length} stale threads".red.bold

  m = _.sum missing
  if m > 0
    console.log "#m missing".red.bold

  for it in diff.new-posts
    console.log "================".grey
    console.log "#{if it.resto is 0 then "OP " else ''}#{it.name} #{it.now} \
                 latency: #{Date.now! - it.time * 1000}ms"
    console.log "----------------".grey
    console.log text-content it.com
  for it in diff.changed-posts
    console.log "!!!!!!!!!!!!!!!!".red
    console.log "#{if it.resto is 0 then "OP " else ''}#{it.name} #{it.now}"
    console.log "----------------".red
    console.log text-content it.red

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

Bacon.from-event-target process, \SIGINT .map y.board .on-value ->
  console.log "saving state..."
  fs.write-file-sync \a.json JSON.stringify(it, null, "  ")
  process.exit 0

