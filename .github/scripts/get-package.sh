#!/usr/bin/env bash
set -euo pipefail
name=$1
shift
dest="downloads/$name"
mkdir -p "$dest"
for attempt in {1..50}; do
  row=$(gh api --method GET "repos/$GITHUB_REPOSITORY/actions/artifacts" -f name="$name" -F per_page=25 \
    --jq '[.artifacts[] | select(.expired == false and .workflow_run.head_branch == "build/platform-downloads")] | first | if . == null then "" else "\(.workflow_run.id) \(.workflow_run.head_sha)" end')
  if [[ -n "$row" ]]; then
    read -r run sha <<< "$row"
    if git cat-file -e "$sha^{commit}" && git diff --quiet "$sha" HEAD -- lib pubspec.yaml pubspec.lock assets "$@"; then
      echo "Installing $name from run $run, source $sha"
      gh run download "$run" --repo "$GITHUB_REPOSITORY" --name "$name" --dir "$dest"
      exit 0
    fi
  fi
  sleep 20
done
echo "No matching package for $name" >&2
exit 1
