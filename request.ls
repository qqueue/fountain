require! {
  Bacon: \baconjs
  http
  zlib
}

options =
  host: \a.4cdn.org
  headers:
    'User-Agent'      : 'Fountain/0.1.0'
    'Accept-Encoding' : 'gzip, deflate'
    'Accept'          : 'application/json'

events = Bacon.from-event-target

function once target, event, transform
  events target, event, transform .take 1

function decode-content res
  if /gzip|deflate/.test res.headers\content-encoding
    res.pipe zlib.createUnzip!
  else
    res

function slurp node-stream, cb
  node-stream.set-encoding \utf-8 # decode bytes as string

  # i.e. events node-stream, \data .take-until \end .reduce (+)
  # Unfortunately, bacon.js has some memory leak problems, so
  # we use a simpler more-canonical buffer, joined on end
  buffer = []
  node-stream.on \data !-> buffer.push it
  node-stream.on \end !-> cb void, buffer.join ''
  node-stream.on \error cb

export
  get = (req) ->
    req.{}headers <<< options.headers
    req <<< options{host}

    Bacon.from-node-callback (cb) !->
      start = Date.now!
      r = http.get req
      console.log "request sent...".blue
      r.set-timeout 8000ms
      r.on \error !->
        console.log "request error...".blue
        cb it
      r.on \response (res) !->
        res.set-timeout 16000ms
        console.log "response received".blue
        err, data <- slurp decode-content res
        console.log "slurped".blue
        if err?
          console.log "slurp error!".blue
          cb err
        else
          console.log "parsing body...".blue
          body = void
          if data? and data.length > 0
            console.log "have nonempty body, trying...".blue
            try
              body = JSON.parse data
              console.log "parsed body!".blue
            catch
              console.log "couldn't parse body #e".blue
              cb e
              return

          console.log "#{res.status-code} in #{Date.now! - start}ms".blue

          cb null, {
            body
            req
            res.status-code
            res.headers
          }
