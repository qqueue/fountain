require! {
  Bacon: \baconjs
  https
  zlib
}

options =
  host: \a.4cdn.org
  headers:
    'User-Agent'      : 'Fountain/0.0.0'
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
      r = https.get req
      r.on \error !->
        cb it
      r.on \response (res) !->
        err, data <- slurp decode-content res
        if err?
          cb err
        else
          body = void
          if data? and data.length > 0
            try
              body = JSON.parse data
            catch
              cb e
              return

          cb null, {
            body
            req
            res.status-code
            res.headers
          }
