require! {
  Bacon: \baconjs
  Replicator: \./replicate
  \./yotsuba
  fs
  colors
}

opts = yotsuba <<<
  initial-replica:
    if fs.exists-sync \state.json
      JSON.parse fs.read-file-sync \state.json
    else
      boards:
        a: null
      last-modified:
        a: new Date 0

r = new Replicator opts
  ..requests.on-value -> console.log "requesting #{it.path}".green
  #..responses.on-value -> console.log "got response!"

  ..replica.on-value ->
      console.log "#{it.diff?inserts.length} new replies, #{it.diff?deletes.length} deletes" 

  ..replica.on-value ->
    total = 0; missing = 0; threads = 0
    for name, board of it.boards
      for n, thread of board
        threads++
        total += thread.replies || 0
        missing += thread.missing || 0
    console.log "#name: #threads threads, #total posts, #missing missing".blue.bold

  {jsdom} = require \jsdom

  document = jsdom(null, null, {fetchExternalResources: false})

  text-content = ->
    div = document.create-element \div
      ..innerHTML = (it || '')replace /<br>/g '\n'
    return div.textContent

  ..replica.on-value !(replica) ->
    for it in replica.diff.inserts
      console.log "================".grey
      console.log "#{if it.bumplimit? then "OP" else ''}#{it.name} #{it.now}"
      console.log "----------------".grey
      console.log text-content it.com
      console.log "----------------".grey

  ..start!

Bacon.from-event-target process, \SIGINT .map r.replica .on-value ->
  console.log "saving state..."
  fs.write-file-sync \state.json JSON.stringify(it, null, "  ")
  process.exit 0

