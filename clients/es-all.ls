require! {
  request
  EventSource: \eventsource
  jsdom
  async
}

document = jsdom.jsdom(null, null, {fetchExternalResources: false})

text-content = ->
  div = document.create-element \div
    ..innerHTML = (it || '')replace /<br>/g '\n'
  return div.textContent

{threads} = require \/tmp/org.hakase.fountain.a.json
reqs = []
for tno, thread of threads
  for post in thread.posts
    post.com_html = post.com
    post.com = text-content post.com_html
    post.sub = text-content post.sub
    post.name = text-content post.name

    ts = encodeURIComponent(new Date post.time * 1000 .toISOString!)

    reqs.push do
      url: "http://localhost:9200/yotsuba-a/post/#{post.no}
            ?parent=#{post.resto}&timestamp=#ts"
      json: post

console.log "requesting time!"
async.each-limit reqs, 4, (it, cb) !->
  console.log "requesting..."
  request.put it, (err, res, body) !->
    console.error "body" body
    console.error "error" err if err
    cb!

