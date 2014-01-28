require! {
  Bacon: \baconjs
  _: \prelude-ls
}

# diff is calculated along with state because it's more efficient
# than a second pass. XXX I wish Bacon.js had some better abstraction
# for this sort of "update, but calculate diff too" pattern
class BoardDiff then ->
  @new-threads = []
  @new-posts = [] # includes new thread OPs
  @deleted-threads = []

  # because the catalog page doesn't show a last-modified date for
  # a given thread, deleted/changed posts is best-effort, e.g.
  # if the same number of images get added and deleted within a poll,
  # the total number of images will look the same and thus
  # the thread state won't look stale to us. Posts with changed comments
  # won't change _any_ observable properties, so these will usually be missed.
  @deleted-posts = [] # does not include posts from deleted therads
  @changed-posts = [] # e.g. deleted image, BANNED FOR THIS POST

  @bump-order = {} # thread-no => [old idx, new idx]

# 4chan-API-canonical named classes, so debugging and memory profiling
# is easier.

class Post
  ({@no, @resto, @now, @time, @tim, @id, @name, @trip, @email, @sub, @com, \
    @capcode, @country, @country_name, @filename, @ext, @fsize, @md5, @w, @h, \
    @tn_w, @tn_h, @filedeleted, @spoiler}) ~>

  equals: (other) ->
    for k, v of this
      if other[k] is not v
        return false
    return true

# Combination of catalog thread format plus thread API ({posts}, with op first)
class Thread
  ({@no, @time, @bumplimit, @imagelimit, @sticky, @closed, @replies, @images},
    posts) ->
      @posts = posts.map Post

  @from-catalog = (catalog-thread, order) ->
    new Thread do
      catalog-thread
      # 4chan's thread object has all the OP information on it.
      [catalog-thread] ++ (catalog-thread.last_replies || [])

  @from-api-thread = (api-thread, order) ->
    op = api-thread.posts.0
    new Thread do
      # individual thread is {posts: [op, ...]}, but confusingly the op has
      # all the usual thread-related data on it e.g. reply count.
      op
      api-thread.posts

# [Post], [Post] -> {added, changed, deleted}
diff-posts = (old-posts, new-posts) ->
  added = []; changed = []; deleted = [];

  old-posts-by-id = {}
  for old-posts
    old-posts-by-id[..no] = ..

  for post in new-posts
    if old-posts-by-id[post.no]?
      unless that.equals post
        changed.push post
      delete old-posts-by-id[post.no]
    else
      added.push post

  for n, post of old-posts-by-id
    deleted.push post

  return {added, changed, deleted}

most-wanted-thread = (board) ->
  most = void
  most-missing = -Infinity
  for thread-no of board.stale
    thread = board.threads[thread-no]
    continue unless thread?
    missing = thread.replies - thread.posts.length + 1
    if missing > most-missing
      most = thread
      most-missing = missing

  most

debug-thread = (new-thread, old-thread, board-diff) ->
  diff = new-thread.replies - old-thread.replies
  if diff > 0 and board-diff.new-posts.length is not diff
    console.error "expecting #diff more replies, got \
                   #{board-diff.new-posts.length}".yellow.bold
  if diff < 0 and board-diff.deleted-posts.length is not -diff
    console.error "expecting -#diff less replies, got \
                    #{board-diff.deleted-posts.length}".yellow.bold

  if board-diff.new-posts.length is 0 and board-diff.changed-posts.length is 0
  and board-diff.deleted-posts.length is 0
    console.error """
      Wasted thread poll!
      length diff: prev #{prev.posts.length} cur #{thread.posts.length}
      replies diff: prev #{prev.replies} cur #{thread-data.replies}
      """.yellow.bold

# 4chan replicator through the JSON API
#
# @requests, @responses, and @ready attachment buses are suitable for use with
# the Limiter in order to respect 4chan's API rules.
#
# Since 4chan doesn't have a single endpoint that gives the entire view of
# a given board, we either have to poll the catalog until all the threads with
# more than 5 posts since we started are pruned, or we can poll less frequently
# to start and request individual threads.
#
# Eventually, we should get to a state where we can keep up with all the
# changes just from the catalog endpoint, only ocassionally having to pull
# a full thread to find out which posts were deleted (or if a thread is so
# popular that there are more than 5 posts before we poll again).
#
module.exports = class Yotsuba
  (
    board-name # String, e.g. 'a'

    # initial board state
    init ? {
      diff: new BoardDiff
      threads: {} # thread-no: thread
      bump-order: [] # thread-no, in bump order
      last-modified: new Date
      stale: {} # set of thread-no, to mark threads that need to be polled
    }
  ) ->
    # Bus Response
    # responses from the Limiter should be plugged in here.
    @responses = new Bacon.Bus

    # Bus ()
    # The Limiter's ready stream should be plugged in here so we can detect
    # when to push the next request on the requests stream.
    @ready = new Bacon.Bus

    okay = @responses.filter (.status-code is 200)

    @catalog-responses = okay.filter (.req.type is \catalog)
    @thread-responses  = okay.filter (.req.type is \thread)

    @thread-responses-not-found = @responses
      .filter (.status-code is 404)
      .filter (.req.type is \thread)

    @responses-not-modified = @responses.filter (.status-code is 304)

    updater = (mutator) ->
      (board, update) -> with board
        # reset diff
        ..diff = new BoardDiff
        # call mutator with board as `this`
        mutator.call .., update
        # board is now mutated
        ..last-check = new Date

    for thread-no, thread of init.threads
      if thread.replies is not (thread.posts.length - 1)
        console.error "thread #{thread-no} had #{thread.posts.length - 1} posts, \
                      but was supposed to have #{thread.replies}!".red.bold
        console.log thread if not thread.replies?
        delete init.threads[thread-no]

    # Property Board, see init parameter for structure
    @board = Bacon.update init,
      [@catalog-responses] updater ({body: catalog}: res) !->
        @last-modified = new Date res.headers[\last-modified]

        prev-threads = @threads
        # all non-deleted threads are moved here and prev-threads is
        # mutated so it will only contain deleted threads after the for loop
        @threads = {}

        order = 0
        # for each page's threads [{threads: []}, ...]
        for {threads} in catalog then for thread in threads
          thread-no = thread.no

          last5 = thread.last_replies
          new-posts = []

          if (prev = prev-threads[thread-no])?
            reply-count-diff = thread.replies - prev.replies

            if 0 < reply-count-diff <= 5
              expected-new-posts = last5.slice -(reply-count-diff)
              expected-already-present-posts = last5.slice 0, -reply-count-diff
              overlapping-prev-posts =
                prev.posts.slice 1 .slice -(5 - reply-count-diff)

              if not @stale[thread-no]
                for post, i in expected-already-present-posts
                  prev-post = overlapping-prev-posts[i]
                  if post.no is not prev-post.no
                    # then some post before this one got deleted, so
                    # we have to mark this thread as stale and abort
                    console.log "#{thread-no} overlapping posts don't match, expecting \
                                  #{reply-count-diff} new replies, already present:
                                  #{expected-already-present-posts.length}".red
                    console.log expected-already-present-posts.map (.no)
                    console.log overlapping-prev-posts.map (.no)

                    console.log "last_replies: #{last5.map (.no)}"
                    console.log "expected new: #{expected-new-posts.map (.no)}"
                    console.log "prev last 5: #{prev.posts.slice -5 .map (.no)}"
                    console.log "prev alleged replies: #{prev.replies}"
                    console.log "prev actual replies: #{prev.posts.length - 1}"
                    console.log "curr replies: #{thread.replies}"

                    @stale[thread-no] = true
                    break
                  else # the same
                    if post.filedeleted is not prev-post.filedeleted \
                       or post.com is not prev-post.com
                      @diff.changed-posts.push post

              if not @stale[thread-no]
                new-posts = expected-new-posts
                for new-posts
                  if not ..?
                    console.error "error! #{expected-new-posts}".red.bold
                @diff.new-posts.push ...new-posts
                new-posts-with-images = new-posts.filter (.filename?) .length

                expected-images-diff = thread.images - prev.images

                if new-posts-with-images is not expected-images-diff
                  console.log "#thread-no images got deleted expected: \
                                #{expected-images-diff} \
                                got: #{new-posts-with-images}".red
                  # some images got deleted
                  @stale[thread-no] = true

            else if reply-count-diff < 0
              # some replies got deleted
              # so just wait till we poll the thread to pick up the changes
              console.log "#thread-no replies got deleted diff: \
                          #{thread.replies} - #{prev.replies} = \
                          #{reply-count-diff}".red
              @stale[thread-no] = true

            # set new thread
            delete prev-threads[thread-no]
            @threads[thread-no] = prev
              old-order = ..order
              new-order = order++
              if new-order is not old-order
                @diff.bump-order[thread-no] = [old-order, new-order]
              ..order = new-order
              ..posts.push ...new-posts
              .. <<< thread{
                bumplimit, imagelimit, replies, images, sticky, closed
              }
          else
            # new thread
            new-thread = Thread.from-catalog thread
              @threads[thread-no] = ..

              @diff.new-posts.push .....posts
              @diff.new-threads.push ..

              if thread.omitted_posts > 0
                @stale[thread-no] = true

        # now all that remain are deleted
        for thread-no, thread of prev-threads
          @diff.deleted-threads.push thread
          delete @stale[thread-no]

      [@thread-responses] updater ({body: thread}) !->
        new-thread = Thread.from-api-thread thread
        old-thread = @threads[thread-no]

        post-diff = diff-posts @threads[thread-no], new-thread
        @diff.changed-posts = post-diff.changed
        @diff.new-posts = post-diff.added
        @diff.deleted-posts = post-diff.deleted
        
        # no longer stale
        delete @stale[thread-no]

        debug-thread new-thread, old-thread, @diff

      [@thread-responses-not-found] updater (res) !->
        {thread-no} = res.req
        @diff.deleted-threads.push delete @threads[thread-no]
        delete @stale[thread-no]

      [@responses-not-modified] updater -> # nothing, just update times

    @changes = @board.changes!

    # Stream Request
    # This Stream should be plugged into a receiver such as the Limiter in order
    # to perform the actual requests.
    @requests = @board.sampled-by @ready .map (board) ->
      # if there's a stale thread and the catalog is still fresh
      thread = most-wanted-thread board
      if thread? and Date.now! - board.last-modified < 10000ms
        type: \thread
        thread-no: thread.no
        path: "/#board-name/res/#{thread.no}.json"
      else
        # new catalog
        type: \catalog
        path: "/#board-name/catalog.json"
        headers:
          \If-Modified-Since : new Date(board.last-modified)toISOString!
