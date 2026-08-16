#!/usr/bin/env bash

set -euo pipefail

die()
{
	echo "error: $*" >&2
	exit 1
}

validate_sha()
{
	local sha=$1

	[[ $sha =~ ^[0-9a-f]{40}$ ]] || die "invalid commit SHA: '$sha'"
}

check_target()
{
	local state_file=$1
	local repo=$2
	local branch=$3
	local previous_sha
	local target_sha

	target_sha=$(git ls-remote "$repo" "refs/heads/$branch" | awk 'NR == 1 { print $1 }')
	validate_sha "$target_sha"

	git fetch --no-tags origin \
		'+refs/heads/main:refs/remotes/origin/main'
	previous_sha=$(git show "origin/main:$state_file") ||
		die "cannot read $state_file from origin/main"
	validate_sha "$previous_sha"

	echo "target_sha=$target_sha" >> "$GITHUB_OUTPUT"
	if [[ $previous_sha == "$target_sha" ]]; then
		echo "changed=false" >> "$GITHUB_OUTPUT"
		echo "Commit ID has not changed. No action needed :P"
	else
		echo "changed=true" >> "$GITHUB_OUTPUT"
		echo "Commit ID changed: $previous_sha -> $target_sha"
	fi
}

record_target()
{
	local state_file=$1
	local target_sha=$2
	local current_sha
	local attempt

	validate_sha "$target_sha"
	git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
	git config user.name "github-actions[bot]"

	for attempt in 1 2 3 4 5; do
		if ! git fetch --no-tags origin \
			'+refs/heads/main:refs/remotes/origin/main'; then
			echo "Fetch attempt $attempt failed" >&2
		else
			git checkout --detach --force origin/main
			current_sha=$(cat "$state_file" 2>/dev/null || true)
			if [[ $current_sha == "$target_sha" ]]; then
				echo "$state_file already records $target_sha"
				return 0
			fi

			printf '%s\n' "$target_sha" > "$state_file"
			git add -- "$state_file"
			git commit -m "Update previous commit ID"
			if git push origin HEAD:main; then
				echo "Recorded successful commit $target_sha in $state_file"
				return 0
			fi

			echo "Push attempt $attempt lost a race; retrying" >&2
		fi
		sleep "$attempt"
	done

	die "failed to update $state_file after 5 attempts"
}

[[ $# -ge 1 ]] || die "usage: $0 <check|record> ..."

case $1 in
check)
	[[ $# -eq 4 ]] || die "usage: $0 check <state-file> <repo> <branch>"
	check_target "$2" "$3" "$4"
	;;
record)
	[[ $# -eq 3 ]] || die "usage: $0 record <state-file> <target-sha>"
	record_target "$2" "$3"
	;;
*)
	die "unknown command: $1"
	;;
esac
