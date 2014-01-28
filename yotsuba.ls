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
      threads: {} # thread-no:
        # bump-order: catalog order, respecting sage
        # last-modified: Date, determined from last post
        # posts: [], 4chan API format, i.e. array with OP first
        # index: {post-no => post index}
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
                    console.log "prev actul replies: #{prev.posts.length - 1}"
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
                  console.log "#thread-no images got deleted expected: #{expected-images-diff} \
                                got: #{new-posts-with-images}".red
                  # some images got deleted
                  @stale[thread-no] = true

            else if reply-count-diff < 0
              # some replies got deleted
              # so just wait till we poll the thread to pick up the changes
              console.log "#thread-no replies got deleted diff: #{thread.replies} - #{prev.replies} = #{reply-count-diff}".red
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
            op = thread{
              \no, resto, now, time, tim,
              id, name, trip, email, sub, com, capcode, country, country_name,
              filename, ext, fsize, md5, w, h, tn_w, tn_h, filedeleted, spoiler
            }
            new-thread = {}
              ..posts = [op] ++ (thread.last_replies || [])
              ..order = order++
              .. <<< thread{
                \no, time,
                bumplimit, imagelimit, sticky, closed
                custom_spoiler, replies, images
              }
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
        thread-data = thread.posts.0
        op = thread.posts.0.{
          \no, resto, now, time, tim,
          id, name, trip, email, sub, com, capcode, country, country_name,
          filename, ext, fsize, md5, w, h, tn_w, tn_h, filedeleted, spoiler
        }
        thread-no = op.no

        # this should always exist since we only know about threads from the
        # catalog, thus at least the OP should be here
        prev = @threads[thread-no]

        prev-post-idx = {}
        for post in prev.posts
          prev-post-idx[post.no] = post

        # calculate differences
        cur-post-idx = {}
        for post, i in thread.posts
          cur-post-idx[post.no] = post
          if prev-post-idx[post.no]?
            if that.filedeleted is not post.filedeleted \
               or that.com is not post.com
              @diff.changed-posts.push post
          else
            @diff.new-posts.push post

        for post in prev.posts
          if not cur-post-idx[post.no]?
            @diff.deleted-posts.push post

        diff = thread-data.replies - prev.replies
        if diff > 0 and @diff.new-posts.length is not diff
          console.error "expecting #{diff} more replies, got #{@diff.new-posts.length}".yellow.bold
        if diff < 0 and @diff.deleted-posts.length is not -diff
          console.error "expecting #{-diff} less replies, got #{@diff.deleted-posts.length}".yellow.bold

        # update thread
        prev
          ..posts = [op] ++ thread.posts.slice 1
          if (..posts.length - 1) is not thread-data.replies
            console.error "has #{..posts.length}, expecting #{thread-data.replies}!".red.bold
          .. <<< thread-data{
            bumplimit, imagelimit, replies, images, sticky, closed
          }

        # no longer stale
        delete @stale[thread-no]

        if @diff.new-posts.length is 0 and @diff.changed-posts.length is 0 \
           and @diff.deleted-posts.length is 0
          console.error "Wasted thread poll!".yellow.bold
          console.error "length diff: prev #{prev.posts.length} cur #{thread.posts.length}".yellow.bold
          console.error "replies diff: prev #{prev.replies} cur #{thread-data.replies}".yellow.bold

      [@thread-responses-not-found] updater (res) !->
        {thread-no} = res.req
        @diff.deleted-threads.push delete @threads[thread-no]
        delete @stale[thread-no]

      [@responses-not-modified] updater -> # nothing, just update times

    @changes = @board.changes!

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
