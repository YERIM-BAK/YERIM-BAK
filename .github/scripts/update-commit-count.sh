#!/usr/bin/env bash
set -euo pipefail

API="https://api.github.com"
if [ -z "${GH_PAT:-}" ]; then
  echo "GH_PAT is not set. Exiting. Please add a repository secret named GH_PAT with a Personal Access Token."
  exit 0
fi
AUTH_HEADER="Authorization: token ${GH_PAT}"

# Get authenticated user login
user=$(curl -s -H "$AUTH_HEADER" "$API/user" | jq -r .login)
if [ -z "$user" ] || [ "$user" = "null" ]; then
  echo "Failed to determine authenticated user. Check GH_PAT permissions."
  exit 1
fi

page=1
total=0

while :; do
  repos_json=$(curl -s -H "$AUTH_HEADER" "$API/user/repos?per_page=100&affiliation=owner&page=${page}")
  repo_count=$(echo "$repos_json" | jq 'length')
  if [ "$repo_count" -eq 0 ]; then
    break
  fi

  for i in $(seq 0 $((repo_count-1))); do
    repo_name=$(echo "$repos_json" | jq -r ".[$i].name")
    owner_login=$(echo "$repos_json" | jq -r ".[$i].owner.login")

    # Fetch contributors for the repo (includes private repos if token has access)
    contribs_json=$(curl -s -H "$AUTH_HEADER" "$API/repos/${owner_login}/${repo_name}/contributors?per_page=100")

    # contributions field is the number of commits attributed to the contributor
    contrib_count=$(echo "$contribs_json" | jq --arg user "$user" -r 'map(select(.login == $user))[0].contributions // 0')

    # If contributor not found via login (e.g., commits with different email), try searching commits by author login (may be rate-limited)
    if [ "$contrib_count" -eq 0 ]; then
      # Optionally implement additional search here; skipping to avoid rate limits.
      :
    fi

    total=$((total + contrib_count))
  done

  page=$((page + 1))
done

echo "Calculated total commits (from contributors endpoint): $total"

# Update README.md: replace the first occurrence of a line like 'Total Commits: <number>' or append if not found
if grep -qE "Total Commits:\s*[0-9]+" README.md; then
  tmp=$(mktemp)
  sed -E "0,/Total Commits:\s*[0-9]+/s//Total Commits: ${total}/" README.md > "$tmp"
  mv "$tmp" README.md
else
  # Try to insert after '## 👩‍💻 My GitHub Stats' if present
  if grep -q "My GitHub Stats" README.md; then
    tmp=$(mktemp)
    awk -v k="Total Commits: ${total}" '1 { print } /My GitHub Stats/ && !x { print "\n" k; x=1 }' README.md > "$tmp"
    mv "$tmp" README.md
  else
    echo -e "\nTotal Commits: ${total}" >> README.md
  fi
fi

echo "README updated with total commits: ${total}"