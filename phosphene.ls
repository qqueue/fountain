require! {request, express}

express!
  ..get '/:board/thumbs/:no/:file' (req, res) !->
    {board, file, no: tno} = req.params
    console.log "proxing #file from thread #tno in #board"

    res.header 'expires' new Date(Date.now! + 60_000).toUTCString!
    request.get do
      url: "http://thumbs.4chan.org/a/thumb/#file"
      headers:
        \Referer : "http://boards.4chan.org/a/res/#tno"
        \User-Agent : 'Phosphene/0.0.0'
    .pipe res
    .on \error !-> res.send 502
  ..get '/:board/src/:no/:file' (req, res) !->
    {board, file, no: tno} = req.params
    console.log "proxing full #file from thread #tno in #board"
    request.get do
      url: "http://i.4cdn.org/#board/src/#file"
      headers:
        \Referer : "http://boards.4chan.org/#board/res/#tno"
        \User-Agent : 'Phosphene/0.0.0'
    .pipe res
    .on \error !-> res.send 502
  ..get '/:board/static/:file' (req, res) !->
    {board, file} = req.params
    console.log "proxing static image #file for #board"
    request.get do
      url: "http://s.4cdn.org/image/#file"
      headers:
        \Referer : "http://boards.4chan.org/#board/"
        \User-Agent : 'Phosphene/0.0.0'
    .pipe res
    .on \error !-> res.send 502
  .listen 3700



