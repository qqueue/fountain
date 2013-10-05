require! Bacon: \baconjs

# unique error object to distinguish errors in @cooldown
error = {}

# Replicator[a]
module.exports = class Replicator
  ({
    initial-replica # a
    scanner         # a -> Response -> a
    next-request    # a -> Date -> Request
    rate-limit      # Milliseconds
    get             # Request -> Stream Response
    is-error        # Response -> Boolean
  }) ->
    # Stream ()
    # emits events when we're ready to make the next request
    # Uses Bacon.Bus so we can kick off the initial event with `push`
    @ready = new Bacon.Bus

    # Stream Response
    # Uses Bacon.Bus since we have a circular dependency:
    # response -> replica -> request -> response
    @responses = new Bacon.Bus

    # Property a
    # This is kept up to date by the Request/Response/Cooldown cycle
    # other clients can observe this property however they choose
    @replica = @responses.scan initial-replica, scanner

    # after the last response is finished, wait until cooled down before making
    # the next response. On errors, back off exponentially (capped at 1 minute)
    # until we get a successful request.
    # Bacon.Errors are mapped to a unique value so we can detect them.
    @cooldown = @responses.map-error(-> error)
      .scan rate-limit, (last-limit, res) ->
        if res is error or is-error res
          last-limit * 2 <? 60_000ms
        else
          rate-limit

    # send a ready event @cooldown milliseconds after the last request.
    # Since @cooldown is scanning @responses, we can just delay
    # @cooldown.changes by its own value for this effect.
    @ready.plug @cooldown.changes!flat-map (cooldown) ->
      Bacon.later cooldown, true

    # Stream Request
    # The next request to make given the current replica and the current time.
    # The current time is a parameter since the most wanted request to make
    # next depends on when that request can be made, e.g. if we have a horribly
    # out of date board catalog, we want to fetch a fresh catalog before trying
    # to fetch threads since all the threads are probably 404 by now.
    @requests =
      @replica.sampled-by @ready
        .map (current-replica) ->
          next-request current-replica, new Date

    # Actually make the requests.
    @responses.plug @requests.flat-map (request) ->
      get request

  # the client can now send an event on @ready to kick off the loop
  start: !-> @ready.push true
