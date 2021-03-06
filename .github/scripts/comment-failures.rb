#!/usr/bin/env ruby

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "octokit", git: "https://github.com/a2ikm/octokit.rb.git", branch: "paginate-checks"
end

class CommentFailures
  API_TOKEN      = ENV["API_TOKEN"]           # GitHub API Token
  CHECK_SUITE_ID = ENV["CHECK_SUITE_ID"]      # id of check suite event which the workflow triggered, derived from github.event.workflow_run.check_suite_id
  HEAD_BRANCH    = ENV["HEAD_BRANCH"]         # branch name where the workflow ran, derived from github.event.workflow_run.head_branch
  HEAD_COMMIT    = ENV["HEAD_COMMIT"]         # commit hash where the workflow ran, derived from github.event.workflow_run.head_commit.id
  WORKFLOW       = ENV["WORKFLOW"]            # name of the workflow, derived from github.event.workflow.name
  REPOSITORY     = ENV["GITHUB_REPOSITORY"]   # repository name. i.e., rails/rails

  SIGNATURE = "GitHub Actions status on #{HEAD_COMMIT} generated by #{File.basename(__FILE__)}"
  SEPARATOR = "\n<!-- SEPARATOR -->\n"
  TAG       = "<!-- WORKFLOW:#{WORKFLOW} -->\n"

  def run
    if HEAD_BRANCH.nil? || HEAD_BRANCH.empty?
      puts "Invoked without pull request"
      exit
    end

    prs = find_pull_requests
    if prs.empty?
      puts "No open pull request found with `#{HEAD_BRANCH}` branch"
      exit
    end

    failed_runs = find_failed_check_runs
    section = generate_section(failed_runs)

    prs.each do |pr|
      if comment = find_comment(pr)
        update_comment(comment, section)
        puts "Updated comment"
      else
        create_comment(pr, section)
        puts "Created comment"
      end
    end
  end

  def client
    @client ||= Octokit::Client.new(access_token: API_TOKEN).tap do |client|
      client.auto_paginate = true
    end
  end

  def find_failed_check_runs
    client.check_runs_for_check_suite(REPOSITORY, CHECK_SUITE_ID, status: "completed", accept: "application/vnd.github.v3+json", per_page: 1)[:check_runs].select do |run|
      run[:conclusion] == "failure"
    end
  end

  def find_pull_requests
    user_or_org = REPOSITORY.split("/").first # expect only internal pull requests
    client.pull_requests(REPOSITORY, state: "open", head: "#{user_or_org}:#{HEAD_BRANCH}")
  end

  def find_comment(pr)
    client.issue_comments(REPOSITORY, pr[:number]).find { |c| c[:body].include?(SIGNATURE) }
  end

  def update_comment(comment, section)
    old_sections = split_body(comment[:body])
    new_sections = replace_or_append_section(section, old_sections)
    body = generate_body(new_sections)

    client.update_comment(REPOSITORY, comment[:id], body)
  end

  def create_comment(pr, section)
    body = generate_body([section])

    client.add_comment(REPOSITORY, pr[:number], body)
  end

  def generate_section(failed_runs)
    buffer = ""

    buffer << TAG
    buffer << "### #{WORKFLOW}\n"

    if failed_runs.empty?
      buffer << "No jobs failed :+1:"
    else
      buffer << "| job | url |\n"
      buffer << "|-----|-----|\n"

      failed_runs.each do |run|
        buffer << "| #{run[:output][:title]} | #{run[:html_url]} |\n"
      end
    end

    buffer
  end

  def replace_or_append_section(section, old_sections)
    replaced = false

    new_sections = old_sections.map do |old_section|
      if old_section.include?(TAG)
        replaced = true
        section
      else
        old_section
      end
    end

    unless replaced
      new_sections << section
    end

    new_sections
  end

  def generate_body(sections)
    ([SIGNATURE] + sections).join(SEPARATOR)
  end

  def split_body(body)
    body.split(SEPARATOR).reject { |section| section.include?(SIGNATURE) }
  end
end

CommentFailures.new.run
