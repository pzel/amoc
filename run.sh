#!/bin/sh
WD=$(dirname $0)

if [ "$#" -ne 3 ]; then
    echo "illegal number of parameters"
    echo 'specify "scenario name" "From" "To"'
    exit 1
fi

(cd "$WD" && ./rebar3 compile && erl -noshell -config priv/app -env ERL_FULLSWEEP_AFTER 2 -pa _build/default/lib/*/ebin ./scenarios_ebin -s amoc do $1 $2 $3)
