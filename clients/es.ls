require! {
  request
  EventSource: \eventsource
  jsdom
}

document = jsdom.jsdom(null, null, {fetchExternalResources: false})

text-content = ->
  div = document.create-element \div
    ..innerHTML = (it || '')replace /<br>/g '\n'
  return div.textContent

es = new EventSource \http://localhost:3500/v1/a/stream
  ..add-event-listener \error !->
      console.error "error" it
  ..add-event-listener \new-posts !->
    posts = JSON.parse it.data
    for post in posts
      post.com_html = post.com
      post.com = text-content post.com_html
      post.sub = text-content post.sub
      post.name = text-content post.name

      ts = encodeURIComponent(new Date post.time * 1000 .toISOString!)

      request.put do
        url: "http://localhost:9200/yotsuba-a/post/#{post.no}
              ?parent=#{post.resto}&timestamp=#ts"
        json: post
        (err, res, body) ->
          console.error "body" body
          console.error "error" err if err

    console.error "submitted #{posts.length} posts"


