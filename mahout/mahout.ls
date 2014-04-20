require! {fs, jsdom}

document = jsdom.jsdom(null, null, {fetchExternalResources: false})

text-content = ->
  div = document.create-element \div
    ..innerHTML = (it || '')replace /<br>/g '\n'
  return div.textContent

init = JSON.parse fs.read-file-sync \/tmp/org.hakase.fountain.a.json

for n, thread of init.threads
  fs.write-file-sync do
    "threads/#{thread.no}"
    thread.posts.map ->
      """
      #{it.sub or ''}
      #{it.filename or ''}
      #{text-content(it.com) - />>\d+/g}
      """
    .join \\n\n

