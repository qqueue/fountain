$ = document~get-element-by-id
L = document~create-element

es = new EventSource \http://localhost:3500/stream?init=true
new-posts = Bacon.from-event-target es, \new-posts

indexer = new Worker \indexer.js

index-res = Bacon.from-event-target indexer, \message (.data)
  ..on-value !->
    if it.verb is \add
      console.log \indexed

posts-idx = {}

threads = Bacon.update {},
  [Bacon.from-event-target es, \init] (old, it) ->
    threads = JSON.parse it.data

    console.log \init

    for tno, thread of threads
      for post in thread.posts
        post.text = text-content post.com
        indexer.post-message verb: \add, body: post
        posts-idx[post.no] = post

    console.log \init

    return threads
  [new-posts] (old, it) ->
    posts = JSON.parse(it.data).sort (a, b) -> a.no - b.no
    nu = {...old}
    for post in posts
      if post.resto is not 0
        nu[post.resto]
          ..posts.push post
          ..replies++
          ..images++ if post.filename?
      post.text = text-content post.com
      indexer.post-message verb: \add, body: post
      posts-idx[post.no] = post
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
      indexer.post-message verb: \remove body: post
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

threads.on-value !-> # XXX kick off thread subscription

search-el = $ \search
count-el = $ \count
el = d3.select \#posts

search-term = Bacon.from-event-target search-el, \input
  .debounce 500ms
  .map -> search-el.value
  .to-property search-el.value

do-search = !->
  console.log "searching #it"
  indexer.post-message do
    verb: \search
    body: ""+it

next-search = Bacon.merge-all do
  search-term.changes!
  search-term.sampled-by new-posts

awaiting-search = false

next-search.on-value !->
  if not awaiting-search
    awaiting-search := true
    do-search it
  else
    console.log "search dropped, still waiting for previous"

matching-posts = index-res.filter (.verb is \search)
matching-posts.on-value !->
  awaiting-search := false
  console.log "got #{it.body.length} results in #{it.latency}ms"
  count-el.text-content = "got #{it.body.length} results in #{it.latency}ms"
  p = it.body.map (.ref) >> (posts-idx.) .slice 0 100
  el.select-all '.post' .data p, (.no)
    ..exit!remove!
    ..enter!append \div
      ..attr \class 'post'
      ..append \div
        ..append \span
          ..attr \class \sub
          ..html (.sub || '')
        ..append \span
          ..attr \class \name
          ..html (.name || '')
        ..append \span
          ..attr \class \rightinfo
          ..append \time
            ..attr \datetime -> new Date it.time * 1000ms
            ..each !->
              @text-content = relative-date new Date it.time * 1000
              keep-up-to-date this
          ..append \span
            .text ' '
          ..append \a
            ..attr \class \no
            ..attr \target \_blank
            ..attr \href ->
              "http://boards.4chan.org/a/res/
              #{if it.resto then "#that\#p" else ''}#{it.no}"
            ..text (.no)
      ..filter (.filename?)
        ..append \div .html ->
          it.filename + it.ext + " #{it.w}x#{it.h} #{humanized it.fsize}"
        ..append \img
          ..attr \class \thumb
          ..attr \src ->
            if it.spoiler
              '/spoiler-a1.png'
            else
              "http://localhost:3700/thumbs/#{it.no}/#{it.tim}s.jpg"
          ..attr \width -> if it.spoiler then 100 else it.tn_w
          ..attr \height -> if it.spoiler then 100 else it.tn_h
      ..append \p
        ..html (.com)
        ..each !->
          for @query-selector-all \.quotelink
            ..target = \_blank
            ..href = "https://boards.4chan.org/a/res/#{..get-attribute \href}"
      ..append \div
        ..attr \class \footer

function humanized bytes
  if bytes < 1024
    "#bytes B"
  else if (kbytes = Math.round bytes / 1024) < 1024
    "#kbytes KB"
  else
    "#{(kbytes / 1024)toString!substring 0 3} MB"

function text-content
  d = L \div
    ..innerHTML = (it || '').replace /<br>/g '\n'
  d.text-content

const YEAR   = 3.156e10_ms , HALFYEAR   = YEAR   / 2
      MONTH  = 2.62974e9_ms, HALFMONTH  = MONTH  / 2
      DAY    = 86_400_000ms, HALFDAY    = DAY    / 2
      HOUR   = 3_600_000ms , HALFHOUR   = HOUR   / 2
      MINUTE = 60_000ms    , HALFMINUTE = MINUTE / 2
      SECOND = 1000ms      , HALFSECOND = SECOND / 2

const MONTHS = <[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]>

# each time element adds a function to update itself to the stale list once it
# becomes inaccurate.  the stale list is flushed and stale times are updated
# whenever the DOM changes otherwise, which keeps the times as up to date as
# possible without incurring separate DOM reflows.
stale = []

export defer = (delay, fn) ->
  if typeof delay is \function
    fn = delay
    delay = 4ms # minimum by HTML5
    args = Array::slice.call @@, 2
  else
    args = Array::slice.call @@, 1

  setTimeout.apply null, [fn, delay].concat args
#
# safer, extended version of setInterval. fn is called with a context object
# that has methods to manage the repetition. Shares a prototype for
# performance, but the constructor is meant to be called as a verb and is thus
# lowercase.
export repeat = class
  # options are optional
  (@delay, options, fn) ~>
    if typeof options is \function
      fn = options
      options = {}

    @fn = fn
    @timeoutee = !~>
      @fn ...
      @repeat! if @auto and not @stopped

    @auto = if options.auto? then options.auto else true
    @start! unless options.start is false

  stop: !->
    @stopped = true
    clearTimeout @timeout

  # the args of start are passed to the timeoutee
  start: !(...args) ->
    @stop! # for safety
    @timeout = setTimeout.apply null, [@timeoutee, @delay].concat args
    @stopped = false

  restart: ::start

  # makes more sense with auto: false
  repeat: ::start


export debounce-leading = (delay, fn) ->
  var timeout
  reset = !-> timeout := null
  -> unless timeout
    fn ...
    timeout := defer delay, reset

export flush = !->
  now = Date.now!
  for stale then .. now
  stale.length = 0

  periodic.restart!

# flush even in absence of other reflows
export periodic = repeat SECOND, {-auto}, flush

# keep an html <time> element up to date
export keep-up-to-date = !(el) ->
  time = new Date el.getAttribute \datetime

  update = !(now) ->
    if document.contains el # el still on page
      el.textContent = relative-date time, now
      make-timeout now - time.getTime!

  add-to-stale = !-> stale.push update

  make-timeout = !(diff) ->
    # calculate when relative date will be stale again
    # delay is time until the next half unit, since relative dates uses
    # banker's rounding
    delay = switch
      case diff < MINUTE
        SECOND - (diff + HALFSECOND) % SECOND
      case diff < HOUR
        MINUTE - (diff + HALFMINUTE) % MINUTE
      case diff < DAY
        HOUR - (diff - HALFHOUR) % HOUR
      case diff < MONTH
        DAY - (diff - HALFDAY) % DAY
      case diff < YEAR
        MONTH - (diff - HALFMONTH) % MONTH
      default
        YEAR - (diff - HALFYEAR) % YEAR
    defer delay, add-to-stale

  make-timeout Date.now! - time.getTime!

pad = -> if it < 10 then "0#it" else it

# twitter-style relative dates +
# stackoverflow-style absolute dates, for a good balance
# of relative placement and screenshotability.
export relative-date = (date, relative-to = Date.now!) ->
  diff = relative-to - date.getTime!
  absdiff = Math.abs diff
  switch
  case absdiff < MINUTE
    number = absdiff / SECOND
    unit = \s
  case absdiff < HOUR
    number = absdiff / MINUTE
    unit = \m
  case absdiff < DAY
    number = absdiff / HOUR
    unit = \h
  case absdiff < MONTH
    number = absdiff / DAY
    unit = \d
  case absdiff < YEAR
    number = absdiff / MONTH
    unit = \mo
  default
    number = absdiff / YEAR
    unit = \y

  "#{Math.round number}#unit \
   (#{pad date.getHours!}:#{pad date.getMinutes!} \
   #{date.getDate!} #{MONTHS[date.getMonth!]} #{date.getFullYear! - 2000})"


