require! {
  Bacon: \baconjs
  \./request
}

# A model of 4chan (through JSON) suitable for use with the Replicator.

export scanner = (state, res) -> with state
  {inserts, deletes} = ..diff =
    inserts: []
    deletes: [] # TODO detect pruning/deletion

  if res.status-code is 304
    console.log "304...".red
    return state

  board-name = res.req.board-name
  board = ..boards{}[board-name]

  if res.req.type is \catalog
    ..{}last-modified[board-name] = new Date res.headers[\last-modified]

    current-threads = {}
    pos = 0
    for {threads, page} in res.body
      for thread, i in threads
        current-threads[thread.no] = thread # for delete detection

        if (last = board[thread.no])?
          # res
          diff = thread.replies - last.replies

          new-posts = if diff > 0 then thread.last_replies.slice -diff else []
          inserts.push ...new-posts

          # TODO post deletions
          board[thread.no]
            ..[]last_replies.push ...new-posts

            .. <<< thread{replies, images, omitted_posts, omitted_replies}

            # TODO bad mutation
            ..page = page
            ..page-position = i
            ..position = pos++

          # TODO also bad :(
          thread.missing = thread.replies - (thread.last_replies?length or 0)
        else
          # insert
          board[thread.no] = thread
            # TODO bad mutation
            ..page = page
            ..page-position = i
            ..position = pos++
            ..board = board-name

          inserts.push thread
          inserts.push ...thread.last_replies

          thread.missing = thread.replies - (thread.last_replies?length or 0)

    for n, thread of board
      if not current-threads[n]?
        # delete
        deletes.push thread
        deletes.push ...thread.last_replies
        delete board[n]
  else # thread
    thread = res.body
    thread-no = res.req.thread-no
    if res.status-code is 404
      # delete
      deletes.push ...(board[thread-no]?last_replies || [])
      delete board[thread-no]
    else
      # update
      console.log "updating thread #{thread-no}"

      op = thread.posts.0

      old = board[thread-no]
      old-posts = {}
      old-posts[thread-no] = true
      for old.last_replies
        old-posts[..no] = true

      for thread.posts
        unless old-posts[..no]
          inserts.push ..

      board[thread-no] = op <<<
        last_replies: thread.posts.slice 1
        # TODO dunno board position at this point
        # should be
        missing: 0

most-wanted-thread = (state) ->
  most = void
  for name, board of state.boards
    for n, thread of board
      # TODO page
      if thread.missing > (most?missing or 0)
        most = thread
  most

export next-request = (state, time) ->
  for name, board of state.boards
    if typeof state.last-modified[name] is \string
      state.last-modified[name] = new Date state.last-modified[name]
    if time - state.last-modified[name] > 5000ms
      return
        type: \catalog
        board-name: name
        path: "/#name/catalog.json"
        headers:
          \If-Modified-Since : state.last-modified[name]toISOString!
  # else
  thread = most-wanted-thread state
  if thread?
    type: \thread
    thread-no: thread.no
    board-name: thread.board
    path: "/#{thread.board}/res/#{thread.no}.json"
  else
    # request a catalog
    oldest = Object.keys state.boards .reduce (oldest, board) ->
      if state.last-modified[oldest] > state.last-modified[board]
        board
      else
        oldest
    return
      type: \catalog
      board-name: oldest
      path: "/#oldest/catalog.json"
      headers:
        \If-Modified-Since : state.last-modified[oldest]toISOString!

export
  rate-limit = 1000ms
  request.get
  is-error = (res) -> 500 <= res.status-code < 600

