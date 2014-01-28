require! {
  Bacon: \baconjs
  \./Limiter
  \./request
  Yotsuba: \./yotsuba
  fs
  colors
  jsdom
  _: \prelude-ls
  req: \request
}

document = jsdom.jsdom(null, null, {fetchExternalResources: false})

text-content = ->
  div = document.create-element \div
    ..innerHTML = (it || '')replace /<br>/g '\n'
  return div.textContent

y = new Yotsuba do
  \a
  init = if fs.exists-sync \a.json
    JSON.parse fs.read-file-sync \a.json

if init?
  posts = []

  for n, thread of init.threads
    posts.push ...thread.posts

  ops = []
  for posts
    ops.push JSON.stringify {
      index:
        _index: "yotsuba"
        _timestamp: ..time * 1000
        _type: \post
        _id: ..no
        _parent: if ..resto is not 0 then that
    }
    ops.push JSON.stringify ..

  req.put do
    url: "http://localhost:9200/yotsuba/_bulk"
    body: ops.join \\n
    (err, res, body) ->
      throw err if err

l = new Limiter 1000ms request.get, (.status-code >= 500)

y.responses.plug l.responses
l.requests.plug y.requests
y.ready.plug l.ready

l.requests.on-value !-> console.log "requesting #{it.path}".green
l.responses.filter (.status-code is not 200)
  .on-value !-> console.log "response: #{it.status-code}".red.bold

y.board.on-value !({diff}: board) ->
  threads = _.values board.threads
  missing = _.keys board.stale .map ->
    t = board.threads[it]
    return 0 unless t?
    t.replies - t.posts.length + 1

  if diff.new-threads.length > 0
    console.log "#{diff.new-threads.length} new threads".blue.bold
  if diff.new-posts.length > 0
    console.log "#{diff.new-posts.length} new posts".blue
  if diff.deleted-threads.length > 0
    console.log "#{diff.deleted-threads.length} deleted threads".red.bold
  if diff.deleted-posts.length > 0
    console.log "#{diff.deleted-posts.length} deleted posts".red.bold
  if diff.changed-posts.length > 0
    console.log "#{diff.changed-posts.length} changed posts".red.bold

  console.log "#{threads.length} threads, \
    #{_.sum threads.map (.posts.length)} posts".white.bold

  s = _.keys board.stale .length
  if s > 0
    console.log "#{_.keys board.stale .length} stale threads".red.bold

  m = _.sum missing
  if m > 0
    console.log "#{_.sum missing} missing".red.bold

  if diff.new-posts.length < 10
    for it in diff.new-posts
      console.log "================".grey
      console.log "#{if it.resto is 0 then "OP " else ''}#{it.name} #{it.now}"
      console.log "----------------".grey
      console.log text-content it.com

y.board.changes!on-value !({diff}) ->
  for it in diff.new-posts
    req.put do
      url: "http://localhost:9200/yotsuba/post/#{it.no}
            ?_parent=#{it.resto}&_timestamp=#{it.time * 1000}"
      json: it
      (err, res, body) ->
        console.log err if err
        console.log body if not (200 <= res.status-code <= 300)

l.ready.push true

require("net")
  .createServer (socket) ->
    repl = require('repl')
    repl.start("fountain> ", socket)
  .listen 5000, "localhost"

Bacon.from-event-target process, \SIGINT .map y.board .on-value ->
  console.log "saving state..."
  fs.write-file-sync \a.json JSON.stringify(it, null, "  ")
  process.exit 0

