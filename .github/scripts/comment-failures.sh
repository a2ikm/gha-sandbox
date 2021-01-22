#!/bin/sh

set -ex

get_number() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/pulls" \
    | jq ".[] | select (.head.ref == \"${GH_HEAD_BRANCH}\") | .number"
}

get_existing_comment() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    | jq --raw-output ".[] | select (.body | contains(\"$signature\"))"
}

create_comment() {
  local body=$(update_body "")
  if [ -z "$body" ]; then
    exit
  fi
  curl -s -X POST -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    -d "{\"body\":\"$body\"}"
}

update_comment() {
  local url=$(echo $comment | jq ".url")
  local body=$(echo $comment | jq ".body")

  body=$(update_body $body)
  if [ -z "$body" ]; then
    exit
  fi
  curl -s -X PATCH -H "Authorization: token ${GH_API_TOKEN}" "$url" \
    -d "{\"body\":\"$body\"}"
}

get_failed_check_runs() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/check-suites/${GH_CHECK_SUITE_ID}/check-runs" \
    | jq --raw-output ".check_runs[] | select (.status == \"completed\" and .conclusion == \"failure\") | \"\(.output.title)\t\(.html_url)\""
}

update_body() {
  local body=$1
  failed_check_runs=$(get_failed_check_runs)
  if [ -z "$failed_check_runs" ]; then
    exit
  fi

  echo "<!-- BEGIN ${GH_WORKFLOW} -->"
  echo "### ${GH_WORKFLOW}"
  for check_run in $failed_check_runs; do
    echo "- ${check_run}"
  done
  echo "<!-- END ${GH_WORKFLOW} -->"

  echo
  echo $signature
}


if [ -z "${GH_HEAD_BRANCH}" ]; then
  echo "Invoked without pull request"
  exit
fi

script_name=$(basename "$0")
signature="commented by $script_name"

number=$(get_number)
if [ -z "$number" ]; then
  echo "pull request not found with '${GH_HEAD_BRANCH}' branch"
  exit
fi

comment=$(get_existing_comment)
if [ -n "$comment" ]; then
  update_comment
else
  create_comment
fi
