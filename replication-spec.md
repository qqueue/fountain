# Replication Protocol Specification

Fountain replicates a 4chan board into memory, but can only do so by polling
parts of 4chan's API at the highest rate permitted by the API guidelines (1
second).  Many instances of Fountain will thus hit 4chan's API pretty hard.

Thus, Fountain exposes its state as an EventStream over HTTP for other
instances of Fountain to use as a much more efficient alternative to direct
4chan replication. Updates from the parent instance will be pushed to the child
instance in near-real-time without incurring an increased load on 4chan or
requiring the same complicated polling logic in all clients.

## State Representation

The current state of a Fountain instance is a JSON/YAML-serializable structure:

```yaml

last-modified: int, unix timestamp in millis
last-polled: int, unix timestamp in millis
threads:
  - last-modified: int, unix timestamp in millis
    ...{thread-specific attributes according to the 4chan API}
    posts:
      - ...{OP, attributes according to the 4chan API}
      - ...{replies, attributes according to the 4chan API}
```

`last-modified` is equal to the value of the `last-modified` header returned by
4chan or the date of the last reply in the thread (since catalog pages don't
give last-modified times for individual threads).

`last-polled` is the time of the last successful poll against 4chan.

## Events

Discrete data events are valid rfc6902 application/json-patch+json documents
that can be applied in receive order.

Events that have ordering dependence are ordered, but independent events are 
emitted in an undefined order, e.g. deletions.

## Event Ids

Event Id semantics according to Server Sent Events are respected. However, due
to the polling nature of 4chan replication, individual events will likely not
have new event ids, thus clients SHOULD be prepared to accept a small number of
duplicate events upon reconnectionn with a Fountain event stream.

# HTTP Endpoint

An instance of Fountain responds to the root HTTP path `/` with
a `text/event-stream` streaming response. If the `Last-Event-Id` header is not
present or the instance of Fountain does not have record of the event
specified, the stream starts with an `init` event containing the entire replica
of 4chan at the time of connection.
