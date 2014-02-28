#!/usr/bin/env zsh
# Simple inetd-able ANSI image streamer using the JSON-formatted
# stream from fountain.hakase.org.
#
# requires img2txt from libcaca / caca-utils
# and jq.

BOARD=$1

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
