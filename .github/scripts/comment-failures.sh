#!/bin/sh

current_branch() {
  git branch | grep '^\*' | cut -b 3-
}

get_number() {
  curl -s -H "Authorization: token ${A2IKM_GITHUB_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/pulls" \
    | jq ".[] | select (.head.ref == \"$(current_branch)\") | .number"
}

get_existing_comment_url() {
  curl -s -H "Authorization: token ${A2IKM_GITHUB_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    | jq --raw-output ".[] | select (.body | contains(\"$signature\")) | .url"
}

create_comment() {
  curl -s -X POST -H "Authorization: token ${A2IKM_GITHUB_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    -d "{\"body\":\"$(date)\n\n$signature\"}"
}

update_comment() {
  curl -s -X PATCH -H "Authorization: token ${A2IKM_GITHUB_API_TOKEN}" "$comment_url" \
    -d "{\"body\":\"$(date)\n\n$signature\"}"
}

script_name=$(basename "$0")
signature="failures for ${GITHUB_SHA}\ncommented by $script_name"

number=$(get_number)
if [ -z "$number" ]; then
  exit
fi

comment_url=$(get_existing_comment_url)
if [ -n "$comment_url" ]; then
  update_comment
else
  create_comment
fi
