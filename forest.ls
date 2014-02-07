$ = document~get-element-by-id
L = document~create-element

div = $ \posts

es = new EventSource \http://localhost:3500/stream?init=true
new-posts = Bacon.from-event-target es, \new-posts

threads = Bacon.update {},
  [Bacon.from-event-target es, \init] (old, it) ->
    JSON.parse it.data
  [new-posts] (old, it) ->
    posts = JSON.parse(it.data).sort (a, b) -> a.no - b.no
    nu = {...old}
    for post in posts
      if post.resto?
        thread = nu[post.resto]
        if not thread?
          console.log post
        else
          thread
            ..posts.push post
            ..replies++
            ..images++ if post.filename?
    return nu
  [Bacon.from-event-target es, \deleted-posts] (old, it) ->
    posts = JSON.parse it.data
    nu = {...old}
    for post in posts
      if post.resto
        thread = nu[post.resto]
        if not thread?
          console.log post
        else
          thread
            ..posts.=filter (.no is not post.no)
            ..replies--
            ..images-- if post.filename?
    return nu
  [Bacon.from-event-target es, \new-threads] (old, it) ->
    threads = JSON.parse it.data
    nu = {...old}
    for thread in threads
      nu[thread.no] = thread
    return nu
  [Bacon.from-event-target es, \deleted-threads] (old, it) ->
    threads = JSON.parse it.data
    nu = {...old}
    for thread-no in threads
      delete nu[thread-no]
    return nu

el = d3.select \#threads

posts-last-hr = (thread) ->
  threshold = Date.now! / 1000 - 3600s
  thread.posts.filter ->
    it.time > threshold
  .length

threads.on-value !(threads) ->
  arr = Object.keys threads .map (threads.)
  max = d3.max arr, posts-last-hr
  el.select-all \.thread .data arr, (.no)
    ..exit!
      ..classed \thread false
      ..transition!duration 3000ms .style \opacity 0 .remove!
    ..enter!append \div
      ..attr \id (.no)
      ..attr \class \thread
      ..append \img
        ..attr \class \img
        ..each !->
          if it.posts.0.spoiler
            @src = '/spoiler-a1.png'
          else
            scale = Math.max 0.05, posts-last-hr(it) / max
            @width = it.posts.0.tn_w * scale
            @height = it.posts.0.tn_h * scale
            @src = "http://localhost:3700/thumbs/#{it.posts.0.no}/#{it.posts.0.tim}s.jpg"
      ..append \span .attr \class \size
    ..select \.size
      ..text -> "#{it.replies}R #{it.images}I"
    ..select \.img .each !->
      return if it.posts.0.spoiler
      scale = Math.max 0.05, posts-last-hr(it) / max
      @width = it.posts.0.tn_w * scale
      @height = it.posts.0.tn_h * scale


new-posts.on-value !->
  for post in JSON.parse it.data
    if post.resto?
      d3.select $ post.resto
        ..style \background-color \#feffbf
        ..transition!duration 5000ms
          ..style \background-color \#EEF2FF
          ..each \end !->
            d3.select this
              ..style \background-color null


