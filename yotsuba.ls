require! {
  Bacon: \baconjs
  _: \prelude-ls
  colors
}

_no = (.no)

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

  check: ->
    unless @replies is (@posts.length - 1)
      console.log "Unmatched Thread #{@no}: expected #{@replies} replies, got #{@posts.length - 1}".magenta.bold
    return @replies is (@posts.length - 1)

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

  @from-api-thread = (api-thread) ->
    op = api-thread.posts.0

    console.log "Unmatched Thread #{op.no}: expected #{op.replies} replies, got #{api-thread.posts.length - 1}".rainbow.bold unless op.replies is (api-thread.posts.length - 1)

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
  if old.replies is not (old.posts.length - 1)
    console.log "stale: expecting #{old.replies} replies, got #{old.posts.length - 1}"
    return false

  unless 0 <= (stub.replies - old.replies) <= 5
    console.log "got #{stub.replies - old.replies} reply difference, unreconcilable"
    return false
  unless 0 <= (stub.images - old.images) <= 5
    console.log "got #{stub.images - old.images} image difference, unreconcilable"
    return false

  unless aligned old, stub
    console.log "apparently not aligned"
    return false

  return true
  #old.replies is (old.posts.length - 1) and
  #0 <= (stub.replies - old.replies) <= 5 and
  #0 <= (stub.images  - old.images)  <= 5 and
  #aligned old, stub

# Thread, CatalogThread -> Bool
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
    console.log "old      " old.posts.map _no
    console.log "last5    " stub.last_replies.map _no
    console.log "Expected " expected-overlap.map _no
    console.log "Actual   " actual-overlap.map _no
    console.log "old " old.replies, " new ", stub.replies
    return false

  for post, i in actual-overlap
    if post.no is not expected-overlap[i].no
      console.log "unreconcilable: #{stub.no}"
      console.log "old      " old.posts.map _no
      console.log "last5    " stub.last_replies.map _no
      console.log "Expected " expected-overlap.map _no
      console.log "Actual   " actual-overlap.map _no
      console.log "old " old.replies, " new ", stub.replies
      return false
  return true

# Thread, CatalogThread -> [Post]
# Correctly grafts last_replies onto the full posts array according to
# the reply count.
graft = (old, stub) ->
  expected-length = stub.replies + 1 # including op
  last_replies = stub.last_replies || []
  old-contrib = old.posts.slice(0, (expected-length - last_replies.length))
  return old-contrib ++ last_replies

# Thread, CatalogThread, Long(unix timestamp) -> Bool
# Whether the stub returned from the catalog is out of sync from our
# last known state and is missing posts.
#
# Apparently, `catalog.json` is served by some sort of round-robin DNS because
# we frequently get threads which are missing tail replies that we saw from
# a previous fetch (usually just one missing reply). Thus, we use a heuristic
# to avoid wasting a fetch cycle on a thread just to find that nothing has
# changed: if the apparently deleted post(s) are less than 10 seconds old, it's
# very unlikely that they were legitimately deleted, thus we assume that they're
# actually not deleted and continue on our merry way.
regressed = (old, stub, now) ->
  negative-diff = old.replies - stub.replies

  # if we're missing posts and we can check for them in last_replies
  if 0 < negative-diff <= 5
    last_replies = stub.last_replies ? [] # 4chan nulls empty last_replies

    should-be-aligned =
      old.posts.slice 1
        .slice -(negative-diff + last_replies.length)

    should-be-present-in-stub =
      should-be-aligned.slice 0 last_replies.length
    apparently-deleted = should-be-aligned.slice -negative-diff

    console.log """
    should-be-aligned:         #{should-be-aligned.map _no}
    should-be-present-in-stub: #{should-be-present-in-stub.map _no}
    apparently-deleted:        #{apparently-deleted.map _no}
    """.cyan

    for post, i in should-be-present-in-stub
      if post.no is not last_replies[i].no
        console.log "misalignement, isn't regressed".cyan
        return false

    for post in apparently-deleted
      if (now - post.time * 1000ms) > 10_000ms
        console.log "time diff #{now - post.time}, isn't regressed".cyan
        return false

    # every apparently deleted post was 'deleted' in the last 10 seconds,
    # so assume the catalog is just out of sync this time, i.e. regressed.
    console.log "apparently regressed #{old.no}".cyan.bold
    return true
  else
    # we're either not missing posts, or we're missing more posts than we
    # can check for and we should therefore mark the thread as stale.
    return false

# {no: Thread}, Catalog, Long(unix timestamp) ->
#   (threads: {no: Thread}, stale: [thread-no])
merge-catalog = (old-threads, catalog, now) ->
  new-threads = {}
  stale = []

  # for each page's threads [{threads: []}, ...]
  for {threads} in catalog then for stub in threads
    thread-no = stub.no

    if (old = old-threads[thread-no])?
      if regressed old, stub, now
        # use old thread, catalog is lying.
        new-threads[thread-no] = old
      else if reconcilable old, stub

        g = graft old, stub

        unless stub.replies + 1 == g.length
          console.log """
          mismatch!
          expecting #{g.map _no}
          to be #{stub.replies + 1} long, is actually #{g.length}.

          old: #{old.posts.map _no}
          old-replies: #{old.replies}
          new-replies: #{stub.replies}
          new-last5: #{stub.last_replies.map _no}
          """.red.bold

        new-threads[thread-no] = new Thread do
          stub
          # graft last_replies on top of existing old posts
          g

        unless new-threads[thread-no].check!
          console.log """
          expected last5: #{(stub.last_replies || []).map _no}
          actual   last5: #{new-threads[thread-no].posts.slice(-5).map _no}
          """.magenta.bold
      else
        console.log """
        I think #thread-no is stale because it had
        #{old.replies} replies and now it has #{stub.replies} replies
        #{old.images} images and now it has #{stub.images} images
        old last5: #{old.posts.slice -5 .map _no}
        new last5: #{(stub.last_replies || []).map _no}
        """.yellow.bold

        stale.push stub.no
        # we can't trust the new data, so use old thread.
        new-threads[thread-no] = old
    else
      if stub.omitted_posts > 0
        # we don't have all the posts, so we need to fetch the thread page.
        console.log "I think #thread-no is new and it has #{stub.omitted_posts} \
                     omitted_posts, so it's stale".yellow.bold
        stale.push thread-no
      new-threads[thread-no] = Thread.from-catalog stub

  for thread-no, old-thread of old-threads
    unless new-threads[thread-no]?
      # When 4chan prunes threads, we are also subject to the "regressions"
      # experienced by replies i.e. a thread will be deleted, but come back
      # from the next round-robined version of the catalog, as a zombie.
      # Thus, instead of deleting threads from the catalog, we only mark the
      # thread as stale so we can check the more canonical `thread.json` for
      # a 404. This sort of wastes a thread pull, but it does prevent
      # a zombie thread from showing up more throroughly.
      stale.push thread-no
      new-threads[thread-no] = old-thread

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

    # else, don't bother marking as deleted. merge-catalog will
    # mark it as stale and the thread fetch should then 404, which will
    # take care of it. See note in `merge-catalog`.
    # diff.deleted-threads.push thread-no

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

update-catalog = (old, {body: catalog}: res) ->
  last-modified =  new Date res.headers[\last-modified]
  {threads: new-threads, stale} =
    merge-catalog old.threads, catalog, last-modified
  new State do
    diff: diff-threads old.threads, new-threads
    threads: new-threads
    last-modified: new Date res.headers[\last-modified]
    stale: stale
    last-poll: new Date
    last-catalog-poll: new Date

update-thread = (old, {body: thread}: res) ->
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

update-thread-not-found = (old, res) ->
  {thread-no} = res.req
  new State do
    diff: new Diff [], [thread-no], [], [], [], []
    threads: with {...old.threads} then delete ..[thread-no]
    last-modified: old.last-modified
    stale: old.stale.filter (is not thread-no)
    last-poll: new Date
    last-catalog-poll: old.last-catalog-poll

update-not-modified = (old) ->
  new State do
    diff: new Diff [], [], [], [], [], []
    threads: old.threads
    last-modified: old.last-modified
    stale: old.stale
    last-poll: new Date
    last-catalog-poll: new Date

next-request = (board-name, state) -->
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

is-catalog = (.req.type is \catalog)
is-thread = (.req.type is \thread)
is-status = (status) -> (.status-code is status)

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

    okay = @responses.filter is-status 200

    @catalog-responses = okay.filter is-catalog
    @thread-responses  = okay.filter is-thread

    @thread-responses-not-found = @responses
      .filter is-status 404
      .filter is-thread

    @responses-not-modified = @responses.filter is-status 304

    # Property State
    @board = Bacon.update new State(init),
      [@catalog-responses] update-catalog
      [@thread-responses] update-thread
      [@thread-responses-not-found] update-thread-not-found
      [@responses-not-modified] update-not-modified

    @changes = @board.changes!

    # Stream Request
    # This Stream should be plugged into a receiver such as the Limiter in order
    # to perform the actual requests.
    @requests = @board.sampled-by @ready .map next-request board-name

# unit tests

require! {assert, util}

posts = (...nos) -> nos.map -> new Post {no: it}
tposts = (...nos) -> nos.map -> new Post {no: it, time: 0}

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

assert-deep-equal = (desc, actual, expected) !->
  assert.deep-equal actual, expected, """
    failed: #desc

    actual:
    #{util.inspect actual, {depth: 10}}

    expected:
    #{util.inspect expected, {depth: 10}}
  """.red

assert-deep-equal "graft, no-op",
  graft do
    {posts: [0 1 2 3 4 5]}
    {replies: 5, last_replies: [1 2 3 4 5]}
  [0 1 2 3 4 5]

assert-deep-equal "graft, small add",
  graft do
    {posts: [0]}
    {replies: 1, last_replies: [1]}
  [0 1]

assert-deep-equal "graft, add + omission",
  graft do
    {posts: [0 1 2 3 4]}
    {replies: 5, last_replies: [1 2 3 4 5]}
  [0 1 2 3 4 5]

assert-deep-equal "diff-posts add",
  diff-posts do
    []
    [new Post {no: 1}]
  new Diff [] [] [] [new Post {no: 1}] [] []
assert-deep-equal "diff-posts remove",
  diff-posts do
    [new Post {no: 1}]
    []
  new Diff [] [] [] [] [new Post {no: 1}] []
assert-deep-equal "diff-posts changed",
  diff-posts do
    [new Post {no: 1}]
    [new Post {no: 1, filedeleted: true}]
  new Diff [] [] [] [] [] [new Post {no: 1, filedeleted: true}]

assert-deep-equal "merge-catalog no-op",
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    [
      threads: [
        {no: 0, last_replies: [], replies: 0, images: 0}
      ]
    ]
    0
  {
    threads: { 0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}] }
    stale: []
  }

assert-deep-equal "merge-catalog new post",
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    [
      threads: [
        {no: 0, last_replies: [{no: 1}], replies: 1, images: 0}
      ]
    ]
    0
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 1, images: 0}
        [new Post({no: 0}), new Post({no: 1})]
    }
    stale: []
  }

assert-deep-equal "merge-catalog new thread",
  merge-catalog do
    {}
    [
      threads: [
        {no: 0, last_replies: [{no: 1}], replies: 1, images: 0}
      ]
    ]
    0
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 1, images: 0}
        [new Post({no: 0}), new Post({no: 1})]
    }
    stale: []
  }

assert-deep-equal "merge-catalog remove thread",
  merge-catalog do
    {
      0: new Thread {no: 0, replies: 1, images: 0}, [new Post {no: 0}]
    }
    [
      threads: []
    ]
    0
  {
    threads: {
      0: new Thread {no: 0, replies: 1, images: 0}, [new Post {no: 0}]
    }
    # expect thread to be marked for 404 check to avoid zombie threads
    stale: ['0']
  }

assert-deep-equal "merge-catalog unreconcilable",
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
    0
  {
    threads: {
      0: new Thread do
        {no: 0, replies: 5, images: 0}
        posts 0 1 2 3 4 5
    }
    stale: [0] # expect unreconcilable
  }

assert-deep-equal "merge-catalog omitted_posts",
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
    0
  {
    threads: {
      0: new Thread {no: 0, replies: 7, images: 0}, posts 0 3 4 5 6 7
    }
    stale: [0] # expect needs a fetch
  }

assert-deep-equal "merge-catalog thread regression",
  merge-catalog do
    {
      0: {
        no: 0 replies: 9, images: 0
        posts:
          tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15_000}]
      }
    }
    [
      threads: [{no: 0 replies: 8, images: 0, last_replies: tposts 4 5 6 7 8}]
    ]
    20_000
  {
    threads: {
      0: {
        no: 0 replies: 9, images: 0
        posts:
          tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15_000}]
      }
    }
    stale: [] # don't expect fetch
  }

assert-deep-equal "merge-catalog legitimate (old) deletion",
  merge-catalog do
    {
      0: {
        no: 0 replies: 9, images: 0
        posts:
          tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15}]
      }
    }
    [
      threads: [{no: 0 replies: 8, images: 0, last_replies: tposts 4 5 6 7 8}]
    ]
    100_000
  {
    threads: {
      0: {
        no: 0 replies: 9, images: 0
        posts:
          tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15}]
      }
    }
    stale: [0] # expect a fetch
  }

assert-deep-equal "diff-threads no-op",
  diff-threads {} {}
  new Diff [] [] [] [] [] []

assert-deep-equal "diff-threads add",
  diff-threads do
    {}
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
  new Diff do
    [new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]] [] []
    [new Post {no: 0}] [] []

assert-deep-equal "diff-threads delete",
  diff-threads do
    {
      0: new Thread {no: 0, replies: 0, images: 0}, [new Post {no: 0}]
    }
    {}
  new Diff do
    # XXX expect no deletion reported, due to merge-catalog's
    # zombie-thread-prevention behavior. `merge-catalog` and `diff-threads`
    # should be merged to remove this implicit coupling.
    [] [] []
    [] [] []

assert-deep-equal "diff-threads add post",
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

assert-deep-equal "diff-threads attributes",
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


assert-deep-equal "regressed: no-op",
  regressed do
    {no: 0 replies: 5, images: 0, posts: tposts 0 1 2 3 4 5}
    {no: 0 replies: 5, images: 0, last_replies: tposts 0 1 2 3 4 5}
  false

assert-deep-equal "regressed: missing 1 new reply",
  regressed do
    {
      no: 0 replies: 1, images: 0
      posts: [new Post {no: 1, time: 15_000}]
    }
    # 4chan omits empty last_replies
    {no: 0 replies: 0, images: 0, last_replies: void}
    20_000
  true

assert-deep-equal "regressed: missing 2 new replies",
  regressed do
    {
      no: 0 replies: 1, images: 0
      posts: [new Post {no: 1, time: 15_000}; new Post {no: 2, time: 16}]
    }
    {no: 0 replies: 0, images: 0, last_replies: []}
    20_000
  true

assert-deep-equal "regressed: missing 1 new reply, with longer thread",
  regressed do
    {
      no: 0 replies: 9, images: 0
      posts:
        tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15}]
    }
    {no: 0 replies: 8, images: 0, last_replies: tposts 4 5 6 7 8}
    20_000
  true

assert-deep-equal "regressed: legitimate (old) tail deletion, not regressed",
  regressed do
    {
      no: 0 replies: 9, images: 0
      posts:
        tposts(0 1 2 3 4 5 6 7 8) ++ [new Post {no: 9, time: 15}]
    }
    {no: 0 replies: 8, images: 0, last_replies: tposts 4 5 6 7 8}
    100_000
  false

console.error "passed!".green.bold
