#!/bin/sh

set -ex

get_number() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/pulls" \
    | jq ".[] | select (.head.ref == \"${GH_HEAD_BRANCH}\") | .number"
}

get_existing_comment_url() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    | jq --raw-output ".[] | select (.body | contains(\"$signature\")) | .url"
}

create_comment() {
  curl -s -X POST -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/issues/${number}/comments" \
    -d "{\"body\":\"$(generate_body)\"}"
}

update_comment() {
  curl -s -X PATCH -H "Authorization: token ${GH_API_TOKEN}" "$comment_url" \
    -d "{\"body\":\"$(generate_body)\"}"
}

get_failed_check_runs() {
  curl -s -H "Authorization: token ${GH_API_TOKEN}" "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/check-suites/${GH_CHECK_SUITE_ID}/check-runs" \
    | jq --raw-output ".check_runs[] | select (.status == \"completed\" and .conclusion == \"failure\") | \"\(.output.title)\t\(.html_url)\""
}

generate_body() {
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
  exit;
fi

script_name=$(basename "$0")
signature="commented by $script_name"

number=$(get_number)
if [ -z "$number" ]; then
  echo "pull request not found with '${GH_HEAD_BRANCH}' branch"
  exit
fi

comment_url=$(get_existing_comment_url)
if [ -n "$comment_url" ]; then
  update_comment
else
  create_comment
fi
