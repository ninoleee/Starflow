#!/bin/sh

set -eu

relpath() {
    current="${2:+$1}"
    target="${2:-$1}"
    target="/${target##/}"
    current="/${current##/}"
    appendix="${target##/}"
    relative=''
    while appendix="${target#"$current"/}" && [ "$current" != '/' ] && [ "$appendix" = "$target" ]; do
        current="${current%/*}"
        relative="$relative${relative:+/}.."
    done
    relative="$relative${relative:+${appendix:+/}}${appendix#/}"
    printf '%s\n' "${relative#/}"
}

find "$1" -mindepth 1 -maxdepth 1 -type d | while read -r source; do
    slug="$(basename "$source")"
    name="$(printf '%s' "$slug" | cut -d '-' -f 1 -f 3)"
    source_relative="$(relpath "$2" "$source")"
    ln -s "$source_relative" "$2/$name"
done
