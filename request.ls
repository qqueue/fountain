require! {
  Bacon: \baconjs
  https
  zlib
}

options =
  host: \api.4chan.org
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

function slurp node-stream
  node-stream.set-encoding \utf-8 # decode bytes as string

  events node-stream, \data
    .take-until events node-stream, \end
    .reduce "" (+)

export
  get = (req) ->
    req.{}headers <<< options.headers
    req <<< options{host}

    r = https.get req

    Bacon.merge-all do
      once r, \error -> new Bacon.Error it
      once r, \response .flat-map (res) ->
        Bacon.combine-template {
          body: slurp decode-content res .map ->
            try
              JSON.parse it
            catch
              console.log "parse error" it
              new Bacon.Error it
          req
          res.status-code
          res.headers
        }
