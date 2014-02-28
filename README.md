# fountain: drink deep from the spring of 4chan

Fountain is a streaming API server for 4chan, similar to the Twitter firehose.
Fountain replicates 4chan through the official 4chan API, then exposes
discrete events as Server-Sent-Events or whitespace-delimited JSON.

Among other things, you can use fountain to [lurk every thread][drinker], or
[stress test your browser's CSS 3D transforms][spess]. Other more interesting
uses could be machine learning/sentiment analysis, as well as live-updating
thread watchers in userscripts.

If you're just interested in the API and not running fountain yourself, I host
a publicly-accessible server at `fountain.hakase.org` that streams /a/ and /g/.
If you want to stream other boards or have heavy usage requirements, you can
run also fountain locally or on your own server.

Fountain has been in development for the past couple months, and is
currently in fairly rough condition code-wise; I'm releasing it in this state
because I suspect moot is going to make an official version of "streaming
4chan" available soon, and I want to be able to say that I did it first.

However, despite the current state of the code, fountain is pretty feature
complete and stable when running. Depending on what moot's new thing is
and when it's released, I expect to clean up the code and finalize the API for
a stable release in the next few weeks.

[drinker]: http://fountain.hakase.org/demo/client.html#g
[spess]: http://fountain.hakase.org/demo/spess.html#a

# Quickstart

These examples will hit `fountain.hakase.org`. Change the host to
`localhost:3500` if you want to hit your local copy.

## Browser

```js
var es = new EventSource('http://fountain.hakase.org/v1/a/stream');
es.addEventListener('new-posts', function (e) {
  var posts = JSON.parse(e.data);

  posts.forEach(function (it) {
    var d = document.createElement('div');
    d.innerHTML = it.com;
    document.body.appendChild(d);
  });
});

```

For more complete examples (written in LiveScript), check out the `clients`
directory, or the hosted versions at

http://fountain.hakase.org/demo/

## Command line

View the raw json stream:

    curl --compressed -s http://fountain.hakase.org/v1/a/json

Prettify with [jq][]:

    curl --compressed -s http://fountain.hakase.org/v1/a/json |\
    jq --unbuffered '.'

Stalk moot on /g/:

    curl --compressed -s http://fountain.hakase.org/v1/g/json |\
    jq --unbuffered 'select(.name and (.name == "moot"))'

View images on /a/ as ANSI art (requires `img2txt` from [libcaca][], and
zsh for its temporary file process substitution `=()` syntax):

```sh
#!/usr/bin/env zsh

BOARD=a

curl --compressed -s http://fountain.hakase.org/v1/$BOARD/json |\
while read -r line; do
  if [[ -n "$line" ]]; then
    (jq -r 'select(.tim) | [.tim, (if .resto == 0 then .no else .resto end)]|@sh' <<< "$line") \
    | while read tim tno; do
      echo;
      img2txt -W 80 -f utf8 -d fstein \
        =(curl -s http://phosphene.hakase.org/$BOARD/thumbs/$tno/${tim}s.jpg);
    done;
  fi;
done
```

The ANSI art demo is also hosted on `fountain.hakase.org:4747` for /a/ and `4848` for /g/:

    nc fountain.hakase.org 4747

[jq]: http://stedolan.github.io/jq/
[libcaca]: http://caca.zoy.org/wiki/libcaca 

# API

- `GET /v1/<board-name>/stream`
  - returns a [`text/event-stream`][0] with the following event types:
    - `new-posts`: `data` is a JSON-serialized array of posts as defined by
      the [4chan API][1]. The OPs of new threads will be present in this event.
    - `deleted-posts`: `data` is a JSON-serialized array of strings identifying the
      `no` of deleted posts. Only _individual_ post deletions will show up here.
      Posts of deleted threads will not be present in this stream
    - `changed-posts`: `data` is a JSON-serialized array of posts in 4chan API format.
      `changed-posts` events are emitted for events such as moderation, deleted images,
      or "USER WAS BANNED FOR THIS POST".
    - `new-threads`: `data` is a JSON-serialized array of threads in 4chan API format,
      i.e., thread-level data + a `posts` field which contains an array of posts, the
      first of which is the OP of the thread. Note that the OP will also be emitted in
      the `new-posts` event.
    - `deleted-threads`: `data` is a JSON-serialized array of strings identifying the
      `no` of deleted threads.
    - `changed-threads`: `data` is a JSON-serialized array of thread-level data for
      changed threads, e.g. stickiness changes.
    - If the query parameter `catalog` is set the `true`, one additional event will
      be emitted at the beginning of the stream called `catalog`, the `data` being
      a JSON-serialized hash of thread `no` to the 4chan API thread data for each
      active thread at the time of the request, as well as a the `posts` array containing
      only the OP of the thread.
    - Events--especially changed post events--are provided on a "best-effort"
      basis due the to inexact nature of 4chan replication. `new-posts` posts
      are _usually_ ordered by `no` and _most_ post deletions will be picked up,
      but there will be holes, especially if fountain loses network connectivity.
    - `Last-Event-Id` is currently ignored, so if your client disconnects, you
      will miss events. TODO fix this
  - `GET /v1/<board-name>/json`
    - returns a `application/json+stream` that emits a JSON-serialized post for
      each `new-post` event, separated by whitespace. _Only_ new post events are
      emitted on this stream.

[0]: http://www.w3.org/TR/eventsource/
[1]: https://github.com/4chan/4chan-API/

# Server Operation

Fountain is an node.js-based HTTP server. Install the dependencies with

    npm install

You'll have to install LiveScript globally (TODO fix this):

    sudo npm install -g LiveScript

Compile the LiveScript to javascript with:

    lsc -cb *.ls clients/*.ls

Then run with

    npm start

By default, fountain will replicate and stream /a/ on port 3500. To change
settings, set the appropriate environment variables:

    BOARD="g" PORT="3600" npm start

Fountain takes about ~3 minutes to replicate an entire board's threads. After
this "initial sync", fountain is able to keep in sync with 4chan with
a median of 5 seconds latency between 4chan timestamp and emission of a
`new-post` event.

Fountain runs unit tests on start time, so it'll spit out a whole bunch
of output. Don't worry, it's running normally. TODO fix this

## "Save file"

Fountain operates by holding an entire board in memory, i.e., it does not require
a backing persistent database. However, if the process is killed, the memory state
is lost. With the ~3 minute initial sync time, restarts are thus not as seamless as
I'd like.

As a hack, fountain will dump its state to `/tmp/org.hakase.fountain.<board-name>.json`
every 30 seconds, and upon receiving SIGINT or SIGPIPE before exiting. When starting,
fountain attempts to read from the same file. This papers over most temporary
hiccups as well as development restarts, while still not requiring a database server.

## Phosphene

Phosphene is a companion server to fountain that proxies requests for
thumbnails to get around 4chan's referer checks. The demos assume that
phosphene is running on localhost:3700, which it will do by default:

    npm run phosphene

## Ops

Fountain's normal memory usage averages around 120M allocated and 60M resident
set, mainly due to holding an entire 4chan board in memory.

Fountain logs to STDOUT with ANSI colors. Pipe through `ts` from `moreutils` if
you want timestamped logging.

Fountain also spits out a whole bunch of metrics in [StatsD][] format at
`localhost:8125` over UDP. If you care to run a StatsD server and a backend
like graphite, you can collect some interesting data.

[StatsD]: https://github.com/etsy/statsd

# Implementation

Fountain employs a similar polling strategy to [`Asagi`][4], Foolz's board dumper.
However, fountain achieves tighter sync latency by polling `catalog.json`, from
which new posts can be found most of the time.

Fountain is written in a dataflow-like style using [Bacon.js][5].

TODO elaborate

[4]: https://github.com/eksopl/asagi
[5]: https://github.com/baconjs/bacon.js

# Development

Development is coordinated through the Github repository:

http://github.com/qqueue/fountain

Please submit bug reports and pull requests there.

# moot Information

Fountain uses the User-Agent `Fountain/0.1.0' and respects the 1 req/s rate limit.
pls no bully.
