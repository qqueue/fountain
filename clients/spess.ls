$ = document~get-element-by-id
L = document~create-element

BOARD = (location.hash ||= \#a).substring 1

div = $ \threads

es = new EventSource "http://localhost:3500/v1/#BOARD/stream"
new-post = Bacon.from-event-target es, \new-posts
  .map (.data) >> JSON~parse
  .flat-map ->
    Bacon.from-array it.sort (a, b) -> a.no - b.no

tick = Bacon.interval 1000ms

new-post-drip =
  Bacon.when do
    [tick, new-post] (, post) -> post
    [tick] !-> # nothing
  .filter -> it?

randpos = ->
  w = document.document-element.client-width
  h = document.document-element.client-height

  x: Math.floor Math.random! * (w - 600)
  y: Math.floor Math.random! * (h - 500)
  z: 0

threads = Bacon.update {},
  [new-post-drip] (old, post) ->
    nu = {...old}
    if post.resto is not 0
      nu[post.resto] ?= {pos: randpos!, no: post.resto, posts: []}
        ..posts.=slice(-4) ++ post
    else
      nu[post.no] = {no: post.no, pos: randpos!, posts: [post]}
    return nu
  [Bacon.from-event-target es, \deleted-posts] (old, it) ->
    posts = JSON.parse it.data
    nu = {...old}
    for post in posts
      if post.resto
        thread = nu[post.resto]
        if thread?
          thread
            ..posts.=filter (.no is not post.no)
            ..replies--
            ..images-- if post.filename?
    return nu
  [Bacon.from-event-target es, \deleted-threads] (old, it) ->
    threads = JSON.parse it.data
    nu = {...old}
    for thread-no in threads
      delete nu[thread-no]
    return nu
  [tick] (old) ->
    now = Date.now! / 1000ms
    nu = {}
    for tno, thread of old
      if (now - thread.posts[*-1]time) < 120s
        nu[tno] = thread
    return nu

z-pos = 0
document.add-event-listener \wheel !->
  z-pos += it.deltaY * 10
  console.log z-pos
  el.select-all \.thread
    .style \transform transform
    .style \-webkit-transform transform

transform = ({{x, y, z}: pos}) ->
  w = document.document-element.client-width
  cx = x + @client-width / 2

  yd = Math.floor (w/2 - cx) / (w / 2) * 10

  "translate3d(#{x}px, #{y}px, #{z - z-pos}px) \
  rotateY(#{yd}deg)"

drag = d3.behavior.drag!
  .origin (.pos)
  .on \dragstart !->
    @class-list.add \drag
  .on \dragend !->
    @class-list.remove \drag
  .on \drag ({{z}: pos}: it) !->
    {x, y} = pos{x, y} = d3.event
    @style['-webkit-transform'] = transform.call this, it
    @style.transform = transform.call this, it

el = d3.select \#threads

del = document.document-element

threads.on-value !(threads) ->
  arr = Object.keys threads .map (threads.)

  latest = d3.max arr, (.posts[*-1].time)

  sorted = arr.sort ({[..., a]: posts}, {[..., b]: posts}) ->
    if a.time > b.time
      1
    else if a.time < b.time
      -1
    else
      if a.no > b.no
        1
      else
        -1
  for t, i in sorted
    t.z-index = i

  el.select-all \.thread .data arr, (.no)
    ..exit!
      ..transition!duration 1000ms
        ..style \opacity 0
        ..remove!
    ..enter!append \div
      ..attr \id (.no)
      ..attr \class \thread
      ..style \transform ({{x, y}: pos}: it) ->
        "translate3d(#{x}px, #{y}px, 800px)"
      ..style \-webkit-transform ({{x, y}: pos}: it) ->
        "translate3d(#{x}px, #{y}px, 800px)"
      ..call drag
    ..style \z-index (.z-index)
    ..select-all '.post:not(.dead)' \
      .data (.posts), (.no)
      ..exit!
        ..classed \dead true
        ..each !->
          @add-event-listener \transitionend !->
            if @parent-node
              @parent-node.remove-child this
          @add-event-listener \webkittransitionend !->
            if @parent-node
              @parent-node.remove-child this
      ..enter!append \div
        ..attr \class 'post new'
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
                "http://boards.4chan.org/#BOARD/res/
                #{if it.resto then "#that\#p" else ''}#{it.no}"
              ..text (.no)
        ..filter (.filename?)
          ..append \div .html ->
            it.filename + it.ext + " #{it.w}x#{it.h} #{humanized it.fsize}"
          ..append \img
            ..attr \class \thumb
            ..attr \src ->
              if it.spoiler
                "http://localhost:3700/#BOARD/static/spoiler-a1.png"
              else
                "http://localhost:3700/#BOARD/thumbs/#{it.no}/#{it.tim}s.jpg"
            ..attr \width -> if it.spoiler then 100 else it.tn_w
            ..attr \height -> if it.spoiler then 100 else it.tn_h
        ..append \p
          ..html (.com)
          ..each !->
            for @query-selector-all \.quotelink
              ..target = \_blank
              ..href = "https://boards.4chan.org/#BOARD/res/#{..get-attribute \href}"
        ..append \div
          ..attr \class \footer
        ..each !->
          set-timeout (!~> @class-list.remove \new), 100ms
    ..each !->
      it.pos.z = -(latest - it.posts[*-1].time) / 90s * 800
    ..style \transform transform
function humanized bytes
  if bytes < 1024
    "#bytes B"
  else if (kbytes = Math.round bytes / 1024) < 1024
    "#kbytes KB"
  else
    "#{(kbytes / 1024)toString!substring 0 3} MB"

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


