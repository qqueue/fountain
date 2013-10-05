require! {
  fs
  request
}

state = JSON.parse fs.read-file-sync \state.json

posts = []

for n, thread of state.boards.a
  posts.push thread{
    com
    sub
    filename
    name
    time
    \no
    email
    trip
    capcode
    ext
    fsize
    w
    h
    tn_w
    tn_h
    tim
    md5
    filedeleted
    spoiler
    resto
  }

  posts.push ...thread.last_replies

ops = []
for posts
  ops.push JSON.stringify {
    index:
      _index: "yotsuba"
      _type: \post
      _id: ..no
      _parent: if ..resto is not 0 then that
  }
  ops.push JSON.stringify ..

console.log ops.join \\n
