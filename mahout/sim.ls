require! {fs, jsdom}

document = jsdom.jsdom(null, null, {fetchExternalResources: false})

text-content = ->
  div = document.create-element \div
    ..innerHTML = (it || '')replace /<br>/g '\n'
  return div.textContent

idx = fs.read-file-sync \idx |> (.toString!trim!split /\n/)
sim = fs.read-file-sync \similar  |> (.toString!trim!split /\n/)

index = idx.reduce do
  (i, it) ->
    [,key, value] = /Key: (\d+): Value: seq\/(\d+)/.exec it
    i <<< (+key): +value
  {}

similar = sim.reduce do
  (i, it) ->
    [,key, value] = /Key: (\d+): Value: {([^}]+)}/.exec it
    sims = value.split /,/ .map (.match /(\d+):/ .1) .filter (is not key)
      .map -> index[it]
    i <<< (index[key]): sims
  {}

a = fs.read-file-sync \a.json |> JSON.parse

for thread-no, sims of similar
  op = a.threads[thread-no].posts.0.com |> text-content
  sim-ops = sims.map ->
    a.threads[it].posts.0.com |> text-content

  console.log "Similar"
  console.log [op] ++ sim-ops
  console.log "====================================="




