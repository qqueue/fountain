require! {
  Bacon: \baconjs
  _: \prelude-ls
  colors
}

# The implementations for reconciling changes from catalog/thread fetches
# are factored to be more easily correct at the expense of garbage collection
# and computation. Future refactorings can focus on efficiency once
# correctness is unit-tested.

class Diff
  (
    @new-threads
    @deleted-threads
    # e.g. sticky/locked. If thread merely has reply differences, it's not
    # counted as 'changed'.
    @changed-threads # see format in Thread.attribute-diff

    @new-posts # includes new thread OPs
    # because the catalog page doesn't show a last-modified date for
    # a given thread, deleted/changed posts is best-effort, e.g.
    # if the same number of images get added and deleted within a poll,
    # the total number of images will look the same and thus
    # the thread state won't look stale to us. Posts with changed comments
    # won't change _any_ observable properties, so these will usually be missed.
    @deleted-posts # does not include posts from deleted therads
    @changed-posts # e.g. deleted image, BANNED FOR THIS POST
  ) ->

  append: (other) !->
    @new-threads     .push ...other.new-threads
    @deleted-threads .push ...other.deleted-threads
    @changed-threads .push ...other.changed-threads
    @new-posts       .push ...other.new-posts
    @deleted-posts   .push ...other.deleted-posts
    @changed-posts   .push ...other.changed-posts

# 4chan-API-canonical named classes, so debugging and memory profiling
# is easier.

class Post
  ({@no, @resto, @now, @time, @tim, @id, @name, @trip, @email, @sub, @com, \
    @capcode, @country, @country_name, @filename, @ext, @fsize, @md5, @w, @h, \
    @tn_w, @tn_h, @filedeleted, @spoiler}) ->

  equals: (other) ->
    return false unless other?
    for k, v of this
      if other[k] is not v
        return false
    return true

# Combination of catalog thread format plus thread API ({posts}, with op first)
class Thread
  ({@no, @time, @bumplimit, @imagelimit, @sticky, @closed, @replies, @images},
    posts) ->
      @posts = [new Post post for post in posts]

  equals-attributes: (other) ->
    for k, v of this
      unless k is \posts or k is \replies or k is \images
        if other[k] is not v
          return false

    return true

  @attribute-diff = (left, right) ->
    diff = []
    for k of left
      unless k is \posts or k is \replies or k is \images
        if left[k] is not right[k]
          diff.push {key: k, left: left[k], right: right[k]}
    return diff

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

# [Post], [Post] -> Diff
diff-posts = (old, nu) ->
  added = []; changed = []; deleted = [];

  old-by-id = {}
  for old
    old-by-id[..no] = ..

  for post in nu
    if old-by-id[post.no]?
      unless that.equals post
        changed.push post
      delete old-by-id[post.no]
    else
      added.push post

  for n, post of old-by-id
    deleted.push post

  return new Diff do
    [] [] [] # thread differences
    added, deleted, changed

most-wanted-thread = (state) ->
  most = void
  most-missing = -Infinity
  m = []

  for thread-no in state.stale
    thread = state.threads[thread-no]
    continue unless thread?
    missing = thread.replies - thread.posts.length + 1
    m.push missing
    if missing > most-missing
      most = thread
      most-missing = missing

  console.log m.sort((-)).join ' '

  return most

debug-thread = (nu, old, board-diff) ->
  diff = nu.posts.length - old.posts.length
  if diff > 0 and board-diff.new-posts.length is not diff
    console.error "expecting #diff more replies, got \
                   #{board-diff.new-posts.length}".yellow.bold
  if diff < 0 and board-diff.deleted-posts.length is not -diff
    console.error "expecting -#diff less replies, got \
                    #{board-diff.deleted-posts.length}".yellow.bold

  if board-diff.new-posts.length is 0
  and board-diff.changed-posts.length is 0
  and board-diff.deleted-posts.length is 0
    console.error """
      Wasted thread poll!
      length diff: old #{old.posts.length} cur #{nu.posts.length}
      replies diff: old #{old.replies} cur #{nu.replies}
      """.yellow.bold

# Thread, Catalog-Thread -> Bool
# Whether old.reples[0...-5] ++ nu.last_replies reflects the actual state
# of the thread according to the thread attributes. If reconcilable, then
# we can update the thread by doing the concatenation, otherwise we have
# to re-fetch the thread page. Most changes should fall into this category.
reconcilable = (old, stub) ->
  old.replies is (old.posts.length - 1) and
  0 <= (stub.replies - old.replies) <= 5 and
  0 <= (stub.images  - old.images)  <= 5 and
  aligned old, stub

# CatalogThread, Thread -> Bool
# whether the stub.last_replies correctly aligns with old.posts according
# to the reply count difference.
#
# This detects edge cases such as 1 post deletion and 2 new posts happening
# at the same time, which will look like a +1 reply difference, but won't be
# aligned at the +1 level:
#
# expected:
#   old : [1 2 3 4 5 ]
#   new : [1 2 3 4 5 6]
#   stub:   [2 3 4 5 6]
#
# edge case:
#   old: [1 2 3 4 5]
#   new: [1 3 4 5 6 7] (2 is deleted)
#   stub:  [3 4 5 6 7]
#
aligned = (old, stub) ->
  count-diff = stub.replies - old.replies

  expected-overlap = (stub.last_replies || []).slice 0, -count-diff || 9e9
  actual-overlap   = old.posts.slice 1 .slice -(5 - count-diff)

  if actual-overlap.length is not expected-overlap.length
    console.log "unreconcilable: #{stub.no}"
    console.log "old      " old.posts.map (.no)
    console.log "last5    " stub.last_replies.map (.no)
    console.log "Expected " expected-overlap.map (.no)
    console.log "Actual   " actual-overlap.map (.no)
    console.log "old " old.replies, " new ", stub.replies
    return false

  for post, i in actual-overlap
    if post.no is not expected-overlap[i].no
      console.log "unreconcilable: #{stub.no}"
      console.log "old      " old.posts.map (.no)
      console.log "last5    " stub.last_replies.map (.no)
      console.log "Expected " expected-overlap.map (.no)
      console.log "Actual   " actual-overlap.map (.no)
      console.log "old " old.replies, " new ", stub.replies
      return false
  return true

# {no: Thread}, Catalog -> (threads: {no: Thread}, stale: [thread-no])
merge-catalog = (old-threads, catalog) ->
  new-threads = {}
  stale = []

  # for each page's threads [{threads: []}, ...]
  for {threads} in catalog then for stub in threads
    thread-no = stub.no

    if (old = old-threads[thread-no])?
      if reconcilable old, stub
        new-threads[thread-no] = new Thread do
          stub
          # graft last_replies on top of existing old posts
          [old.posts.0] ++ \
          old.posts.slice(1).slice(0, -(stub.last_replies?length) || 9e9) ++ \
          (stub.last_replies || [])
      else
        stale.push stub.no
        # we can't trust the new data, so use old thread.
        new-threads[thread-no] = old
    else
      if stub.omitted_posts > 0
        # we don't have all the posts, so we need to fetch the thread page.
        stale.push thread-no
      new-threads[thread-no] = Thread.from-catalog stub

  return {threads: new-threads, stale}

diff-threads = (old, nu) ->
  diff = new Diff [], [], [], [], [], []

  for thread-no, old-thread of old
    if (nu-thread = nu[thread-no])?
      diff.append do
        diff-posts old-thread.posts, nu-thread.posts
      if not old-thread.equals-attributes nu-thread
        diff.changed-threads.push do
          Thread.attribute-diff old-thread, nu-thread
    else
      diff.deleted-threads.push thread-no

  for thread-no, nu-thread of nu
    unless old[thread-no]?
      diff.new-threads.push nu-thread
      diff.new-posts.push ...nu-thread.posts

  return diff

filter = (key, obj) ->
  with {}
    for k, v of obj when k is not key
      ..[k] = v

replace = (key, val, obj) ->
  with {}
    for k, v of obj when k is not key
      ..[k] = v
    ..[key] = val

class State
  ({
    @diff # Diff
    threads # {thread-no: thread}
    # TODO record bump order, which is not derivable from threads otherwise.
    # we'll probably want a string-diff algorithm to generate
    # minimum-edit-distance mappings when bump order does change.
    @last-modified # Date
    # threads which need a full thread page poll.
    @stale # [thread-no]
    @last-poll # Date
    @last-catalog-poll # Date
  }) ->
    @threads = {}
    for thread-no, thread of threads
      @threads[thread-no] = new Thread thread, thread.posts

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

    init = {
      diff: new Diff [], [], [], [], [] ,[]
      threads: {}
      last-modified: new Date
      stale: []
      last-poll: new Date 0
      last-catalog-poll: new Date 0
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

    # Property State
    @board = Bacon.update new State(init),
      [@catalog-responses] (old, {body: catalog}: res) ->
        {threads: new-threads, stale} = merge-catalog old.threads, catalog
        new State do
          diff: diff-threads old.threads, new-threads
          threads: new-threads
          last-modified: new Date res.headers[\last-modified]
          stale: stale
          last-poll: new Date
          last-catalog-poll: new Date
      [@thread-responses] (old, {body: thread}: res) ->
        new-thread = Thread.from-api-thread thread
        old-thread = old.threads[new-thread.no]
        diff = diff-posts old-thread.posts, new-thread.posts

        debug-thread new-thread, old-thread, diff

        new-threads = replace new-thread.no, new-thread, old.threads

        last-modified = new Date res.headers[\last-modified]
        new State do
          diff: diff
          threads: new-threads
          last-modified:
            if old.last-modified > last-modified
              # e.g. just fetching a stale thread
              old.last-modified
            else
              last-modified
          stale: old.stale.filter (is not new-thread.no)
          last-poll: new Date
          last-catalog-poll: old.last-catalog-poll

      [@thread-responses-not-found] (old, res) ->
        {thread-no} = res.req
        new State do
          diff: new Diff [], [thread-no], [], [], [], []
          threads: with {...old.threads} then delete ..[thread.no]
          last-modified: old.last-modified
          stale: old.stale.filter (is not thread-no)
          last-poll: new Date
          last-catalog-poll: old.last-catalog-poll

      [@responses-not-modified] (old) ->
        new State do
          diff: new Diff [], [], [], [], [], []
          threads: old.threads
          last-modified: old.last-modified
          stale: old.stale
          last-poll: new Date
          last-catalog-poll: new Date

    @changes = @board.changes!

    # Stream Request
    # This Stream should be plugged into a receiver such as the Limiter in order
    # to perform the actual requests.
    @requests = @board.sampled-by @ready .map (state) ->
      # if there's a stale thread and the catalog is still fresh
      thread = most-wanted-thread state
      if thread? and Date.now! - state.last-catalog-poll < 10000ms
        type: \thread
        thread-no: thread.no
        path: "/#board-name/res/#{thread.no}.json"
      else
        type: \catalog
        path: "/#board-name/catalog.json"
        headers:
          \If-Modified-Since : new Date(state.last-modified)toUTCString!

# unit tests

require! {assert, util}

posts = (...nos) -> nos.map -> new Post {no: it}

assert-aligned = (should, old-replies, nu-replies, old, last5) ->
  assert do
    should is aligned do
      * replies: old-replies, posts:          old.map -> new Post {no: it}
      * replies: nu-replies , last_replies: last5.map -> new Post {no: it}
    """
    expected #{if should then '' else 'non-'}alignment:
      #old-replies: #old
      #nu-replies: #last5""".red.bold

(.for-each (args) !-> assert-aligned.apply void, args) [] =
  * true, 1, 1
    [0 1]
    [  1]
  * true, 0, 1
    [0]
    [  1]
  * true, 5, 5,
    [0 1 2 3 4 5]
    [  1 2 3 4 5]
  * true, 5, 6,
    [0 1 2 3 4 5]
    [    2 3 4 5 6]
  * true, 5, 9,
    [0 1 2 3 4 5]
    [          5 6 7 8 9]
  * true, 10, 10
    [0 1 2 3 4 5 6 7 8 9 10]
    [            6 7 8 9 10]
  * false, 5, 6
    [0 1 2 3 4 5]
    #0 1 x 3 4 5 6 7
    [    3 4 5 6 7]
  * true, 213, 214
    [ 71175, 81480, 81509, 81535, 81619, 82267 ]
    [ 81509, 81535, 81619, 82267, 82340 ]

assert-deep-equal = (actual, expected) !->
  assert.deep-equal actual, expected, """

    actual:
    #{util.inspect actual, {depth: 10}}

    expected:
    #{util.inspect expected, {depth: 10}}
  """.red

assert-deep-equal do
  diff-posts do
    []
    [new Post {no: 1}]
  new Diff [] [] [] [new Post {no: 1}] [] []
assert-deep-equal do
  diff-posts do
    [new Post {no: 1}]
    []
  new Diff [] [] [] [] [new Post {no: 1}] []
assert-deep-equal do
  diff-posts do
    [new Post {no: 1}]
    [new Post {no: 1, filedeleted: true}]
  new Diff [] [] [] [] [] [new Post {no: 1, filedeleted: true}]

assert-deep-equal do
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    [
      threads: [
        {no: 0, last_replies: [], replies: 0, images: 0}
      ]
    ]
  {
    threads: { 0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}] }
    stale: []
  }

assert-deep-equal do
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    [
      threads: [
        {no: 0, last_replies: [{no: 1}], replies: 1, images: 0}
      ]
    ]
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 1, images: 0}
        [new Post({no: 0}), new Post({no: 1})]
    }
    stale: []
  }

assert-deep-equal do
  merge-catalog do
    {}
    [
      threads: [
        {no: 0, last_replies: [{no: 1}], replies: 1, images: 0}
      ]
    ]
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 1, images: 0}
        [new Post({no: 0}), new Post({no: 1})]
    }
    stale: []
  }

assert-deep-equal do
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 1, images: 0}, [new Post {no: 0}]
    }
    [
      threads: []
    ]
  {
    threads: {}
    stale: []
  }

assert-deep-equal do
  merge-catalog do
    {
      0: new Thread do
        {no: 0, replies: 5, images: 0}
        posts 0 1 2 3 4 5
    }
    [
      threads: [
        {
          no: 0
          last_replies: posts 3 4 5 6 7
          replies: 6
          images: 0
        }
      ]
    ]
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 5, images: 0}
        posts 0 1 2 3 4 5
    }
    stale: [0] # expect unreconcilable
  }

assert-deep-equal do
  merge-catalog do
    {}
    [
      threads: [
        {
          no: 0
          last_replies: posts 3 4 5 6 7
          replies: 7
          images: 0
          omitted_posts: 2
        }
      ]
    ]
  {
    threads: {
      0: new Thread {no: 0, replies: 7, images: 0}, posts 0 3 4 5 6 7
    }
    stale: [0] # expect needs a fetch
  }

assert-deep-equal do
  diff-threads {} {}
  new Diff [] [] [] [] [] []

assert-deep-equal do
  diff-threads do
    {}
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
  new Diff do
    [new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]] [] []
    [new Post {no: 0}] [] []

assert-deep-equal do
  diff-threads do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    {}
  new Diff do
    [] ['0'] []
    [] [] []

assert-deep-equal do
  diff-threads do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    {
      0: new Thread {no: 0, replies: 1, images: 0}, posts 0 1
    }
  new Diff do
    [] [] []
    [new Post {no: 1}] [] []

assert-deep-equal do
  diff-threads do
    {
      0: new Thread do
        {no: 0, replies: 0, images: 0, sticky: true}
        [new Post {no: 0}]
    }
    {
      0: new Thread do
        {no: 0, replies: 0, images: 0, sticky: false}
        [new Post {no: 0}]
    }
  new Diff do
    [] [] [[{key: \sticky, left: true, right: false}]]
    [] [] []

console.error "passed!".green.bold
