$ = document~get-element-by-id
L = document~create-element

div = $ \posts

new EventSource \http://localhost:3500/stream
  ..add-event-listener \new-posts !->
      #last-pos = window.scrollY
      scroll = (window.scrollMaxY - window.scrollY) < 30
      if window.scrollMaxY - window.scrollY
        # prevent browser scrolling
        window.scroll-by 0, -1
      JSON.parse it.data .sort((a, b) -> a.no - b.no).for-each !->
        div.append-child <| with L \div
          ..class-list.add \post
          ..class-list.add \new
          ..append-child <| with L \h1
              if it.sub?
                ..append-child <| with L \span
                  ..innerHTML = it.sub
              if it.name
                ..append-child <| with L(if it.email? then \a else \span)
                  ..class-list.add \name
                  ..text-content = it.name
                  if it.email?
                    ..href = 'mailto:' + it.email
              if it.trip?
                ..append-child <| with L \span
                  ..class-list.add \trip
                  ..text-content = it.trip
              ..append-child <| with L \span
                ..class-list.add \rightinfo
                ..append-child <| with L \time
                  ..set-attribute \datetime new Date it.time * 1000
                  ..text-content = relative-date new Date it.time * 1000
                  keep-up-to-date ..
                ..append-child <| with L \a
                  ..target = \_blank
                  ..href =
                    "http://boards.4chan.org/a/res/
                    #{if it.resto then "#that\#p" else ''}#{it.no}"
                  ..text-content =
                    " #{if it.resto then "#that\#p" else ''}#{it.no}"
          if it.filename?
            ..append-child <| with L \div
              ..class-list.add \fileinfo
              ..text-content = it.filename + it.ext + " #{it.w}x#{it.h} #{it.fsize}B"
            ..append-child <| with L \a
              ..class-list.add \thumb
              ..target = \_blank
              ..href = "http://localhost:3700/src/#{it.no}/#{it.tim}#{it.ext}"
              ..append-child <| with L \img
                if it.spoiler
                  ..src = '/spoiler-a1.png'
                else
                  ..width = it.tn_w
                  ..height = it.tn_h
                  ..src = "http://localhost:3700/thumbs/#{it.no}/#{it.tim}s.jpg"
          if it.com?
            ..append-child <| with L \p
              ..innerHTML = it.com
              for ..query-selector-all \.quotelink
                ..target = \_blank
                ..href = "https://boards.4chan.org/a/res/#{..get-attribute \href}"
          ..append-child <| with L \div
            ..class-list.add \footer
      #window.scroll-to window.scrollX, last-pos
      old-height = window.scrollMaxY
      while div.child-element-count > 50
        div.remove-child div.first-element-child
      window.scroll-by 0, -(old-height - window.scrollMaxY)
      if scroll
        set-timeout do
          function scroll
            diff = window.scrollMaxY - window.scrollY
            if diff > 1
              window.scroll-by 0, Math.ceil diff / 20
              set-timeout scroll, 17ms
          17ms
      defer 100ms !->
        for document.query-selector-all \.new
          ..class-list.remove \new

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


