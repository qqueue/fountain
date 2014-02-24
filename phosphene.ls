require! {request, express}

express!
  ..get '/thumbs/:no/:file' (req, res) !->
    {file, no: tno} = req.params
    console.log "proxing #file from thread #tno"

    res.header 'expires' new Date(Date.now! + 60_000).toUTCString!
    request.get do
      url: "http://thumbs.4chan.org/a/thumb/#file"
      headers:
        \Referer : "http://boards.4chan.org/a/res/#tno"
        \User-Agent : 'Phosphene/0.0.0'
    .pipe res
    .on \error !-> res.send 502
  ..get '/src/:no/:file' (req, res) !->
    {file, no: tno} = req.params
    console.log "proxing full #file from thread #tno"
    request.get do
      url: "http://i.4cdn.org/a/src/#file"
      headers:
        \Referer : "http://boards.4chan.org/a/res/#tno"
        \User-Agent : 'Phosphene/0.0.0'
    .pipe res
    .on \error !-> res.send 502
  .listen 3700



