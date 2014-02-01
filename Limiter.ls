require! Bacon: \baconjs

# unique error object to distinguish errors in @cooldown
error = {}

# Request/Response rate limiter. Requests on the @requests stream are
# guaranteed not to be processed by `get` until at least `rate-limit` milliseconds
# after the last response.
#
# Errors emitted by the `get` response stream and responses that match
# `is-error` (e.g. 5xx HTTP responses) will increase the cooldown time
# before trying again to avoid hammering the server during heavy traffic.
module.exports = class Limiter
  (
    rate-limit      # Milliseconds
    get             # Request -> Stream Response
    is-error        # Response -> Boolean
  ) ->
    # Stream ()
    # emits events when we're ready to make the next request.
    # This is a Bacon.Bus so that we can make a circular dependency
    # from ready -> request -> response -> cooldown -> ready
    @ready = new Bacon.Bus

    # Stream Request
    # Clients than plug into this to make requests
    @requests = new Bacon.Bus

    # Make the requests when we're ready and we have a request.
    # Requests will queue up indefinitely if made indiscriminately, so clients
    # should listen on the @ready stream before pushing to the @requests stream.
    @ready-requests = Bacon.when [@ready, @requests] (_, req) -> req

    # Stream Response
    # Clients can observe this directly.
    @responses = @ready-requests.flat-map get

    @response-or-error = @responses.map-error ->
      console.log it
      error

    # after the last response is finished, wait until cooled down before making
    # the next response. On errors, back off exponentially
    # until we get a successful request.
    # Bacon.Errors are mapped to a unique value so we can detect them.
    @cooldown = @response-or-error
      .scan rate-limit, (last-limit, res) ->
        if res is error or is-error res
          console.log "got error, delaying by #{last-limit * 2 <? 32_000ms} ms".red
          last-limit * 2 <? 32_000ms
        else
          rate-limit

    # send a ready event @cooldown milliseconds after the last request.
    # XXX I'm convinced that cycles in the bacon cause memory leaks,
    # so introduce an 'air-gap'
    # @ready.plug <| @cooldown.sampled-by @responses .flat-map Bacon.later
    @cooldown.sampled-by @response-or-error .flat-map Bacon.later .on-value !~>
      set-timeout (~> @ready.push true), 0

