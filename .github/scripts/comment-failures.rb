#!/usr/bin/env ruby

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "json"
  gem "octokit"
end

GITHUB_REPOSITORY = ENV["GITHUB_REPOSITORY"]
GH_API_TOKEN      = ENV["GH_API_TOKEN"]
GH_CHECK_SUITE_ID = ENV["GH_CHECK_SUITE_ID"]
GH_HEAD_BRANCH    = ENV["GH_HEAD_BRANCH"]
GH_WORKFLOW       = ENV["GH_WORKFLOW"]

CLIENT = Octokit::Client.new(access_token: GH_API_TOKEN).tap do |client|
  client.auto_paginate = true
end

SIGNATURE = "commented by #{File.basename(__FILE__)}"
SEPARATOR = "\n<!-- SEPARATOR -->\n"
TAG       = "<!-- WORKFLOW:#{GH_WORKFLOW} -->\n"

def find_failed_check_runs
  CLIENT.check_runs_for_check_suite(GITHUB_REPOSITORY, GH_CHECK_SUITE_ID, accept: "application/vnd.github.v3+json")[:check_runs].select do |run|
    run[:status] == "completed" && run[:conclusion] == "failure"
  end
end

def find_pull_request
  CLIENT.pull_requests(GITHUB_REPOSITORY).find { |pr| pr[:head][:ref] == GH_HEAD_BRANCH && pr[:state] == "open" }
end

def find_comment(number)
  CLIENT.issue_comments(GITHUB_REPOSITORY, number).find { |c| c[:body].include?(SIGNATURE) }
end

def generate_section(failed_runs)
  buffer = ""

  buffer << TAG
  buffer << "### #{GH_WORKFLOW}\n"
  buffer << "| job | url |\n"
  buffer << "|-----|-----|\n"

  failed_runs.each do |run|
    buffer << "| #{run[:output][:title]} | #{run[:html_url]}\n"
  end

  buffer
end

def update_body(failed_runs, old_body)
  old_body.split(SEPARATOR).map do |section|
    if section.include?(TAG)
      generate_section(failed_runs)
    else
      section
    end
  end.join(SEPARATOR)
end

def update_comment(number, failed_runs, comment)
  body = update_body(failed_runs, comment[:body])
  CLIENT.update_comment(GITHUB_REPOSITORY, comment[:id], body)
end

def create_body(failed_runs)
  [
    generate_section(failed_runs),
    SIGNATURE,
  ].join("\n<!-- SEPARATOR -->\n")
end

def create_comment(number, failed_runs)
  body = create_body(failed_runs)
  CLIENT.add_comment(GITHUB_REPOSITORY, number, body)
end

if GH_HEAD_BRANCH.nil? || GH_HEAD_BRANCH.empty?
  puts "Invoked without pull request"
  exit
end

failed_runs = find_failed_check_runs
if failed_runs.empty?
  puts "All jobs passed"
  exit
end

pr = find_pull_request
if pr.nil?
  puts "No open pull request found with `#{GH_HEAD_BRANCH}` branch"
  exit
end

number = pr[:number]

if comment = find_comment(number)
  update_comment(number, failed_runs, comment)
else
  create_comment(number, failed_runs)
end
