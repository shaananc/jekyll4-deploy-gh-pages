#!/bin/bash
set -euo pipefail
IFS=$'\n\t'
set -x

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

DEST="/tmp/_site"
REPO="git@github.com:${GITHUB_REPOSITORY}.git"
BRANCH="gh-pages"
BUNDLE_BUILD__SASSC=--disable-march-tune-native
API_ENDPOINT="https://api.github.com/repos/$GITHUB_REPOSITORY"
GZIP="-9"

# ---------- SSH setup ----------
mkdir -p ~/.ssh /root/.ssh || true
echo "${DEPLOY_KEY}" > ~/.ssh/id_ed25519_deploy
chmod 600 ~/.ssh/id_ed25519_deploy
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_deploy || true
touch ~/.ssh/known_hosts /root/.ssh/known_hosts
ssh-keygen -R github.com || true
curl -sL https://api.github.com/meta | jq -r '.ssh_keys | .[]' | sed -e 's/^/github.com /' >>~/.ssh/known_hosts
cp ~/.ssh/known_hosts /root/.ssh/known_hosts

# ---------- Functions ----------
build_release() {
  local BRANCH_NAME="$1-release"
  local ALGOLIA="${2:-false}"

  echo "Installing gems..."
  bundle config path vendor/bundle
  bundle config build.ffi --disable-system-libffi
  bundle install --jobs 4 --retry 3

  if [[ -n "${YARN_ENV:-}" ]]; then
    echo "Installing javascript packages..."
    yarn
  fi

  echo "Building Jekyll site for $1..."
  JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll build --config "_config.yml,_config.$1.yml"

  # Optional: Algolia indexing
  if [[ "$ALGOLIA" == "true" ]]; then
    if [[ -z "${ALGOLIA_API_KEY:-}" ]]; then
      echo "No Algolia API key provided"
    else
      JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll algolia --config "_config.yml,_config.$1.yml"
    fi
  fi

  local TAG="$BRANCH_NAME"
  local FILENAME="$BRANCH_NAME.tar.gz"

  # Delete existing release with same tag (if any)
  local EXISTING_ID
  EXISTING_ID="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$API_ENDPOINT/releases/tags/$TAG" | jq '.id')"
  if [[ "$EXISTING_ID" != "null" ]]; then
    curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" \
      "$API_ENDPOINT/releases/$EXISTING_ID" >/dev/null
  fi

  # Package only _site
  tar -czf "$FILENAME" _site

  # Create release
  local RESPONSE
  RESPONSE="$(
    curl -sS -H "Authorization: token $GITHUB_TOKEN" \
      -H "Content-Type: application/json" \
      -X POST "$API_ENDPOINT/releases" \
      --data "{\"tag_name\":\"$TAG\",\"name\":\"$TAG\",\"draft\":false,\"prerelease\":false}"
  )"
  echo "$RESPONSE" > response.log
  local RELEASE_ID
  RELEASE_ID="$(jq .id <<<"$RESPONSE")"

  # Upload asset (deterministic name)
  curl --retry 5 --retry-all-errors -sS \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/gzip" \
    --data-binary "@$FILENAME" \
    "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$FILENAME" >/dev/null
}

fetch_other_release() {
  local version="$1"
  local releasename="${version}-release"
  echo "Fetching release for version ${version}..."

  local RELEASE_ID
  RELEASE_ID="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$API_ENDPOINT/releases/tags/$releasename" | jq '.id')"

  echo "Release id is $RELEASE_ID"
  if [[ -z "$RELEASE_ID" || "$RELEASE_ID" == "null" ]]; then
    echo "Release $version does not exist"
    return 1
  fi

  # Pick asset by exact name
  local wanted="${releasename}.tar.gz"
  local ASSET_URL
  ASSET_URL="$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "$API_ENDPOINT/releases/$RELEASE_ID/assets" \
    | jq -r --arg wanted "$wanted" '.[] | select(.name==$wanted) | .url')"

  if [[ -z "$ASSET_URL" || "$ASSET_URL" == "null" ]]; then
    echo "No asset named $wanted on release $version"
    return 1
  fi

  echo "Downloading $wanted"
  curl -sS -L -H "Authorization: token $GITHUB_TOKEN" \
       -H "Accept: application/octet-stream" \
       -o "$wanted" "$ASSET_URL"

  echo "Downloaded $wanted"
}

# ---------- Prep / branch resolution ----------
publishdate=$(date +%m-%d-%Y)
echo "Creating release for current branch"

git config --global --add safe.directory /github/workspace
git fetch origin main

NEW_BRANCH_NAME="$(git branch --show-current)"
OLD_BRANCH_NAME="$NEW_BRANCH_NAME"

git checkout main
git pull --ff-only
git checkout "$NEW_BRANCH_NAME"

# If on main, resolve to current_version from config
if [[ "$NEW_BRANCH_NAME" == "main" ]]; then
  NEW_BRANCH_NAME="$(git show main:_config.yml | yq '.current_version' -r)"
fi

# ---------- Build current version ----------
build_release "$NEW_BRANCH_NAME" true
mkdir -p "$DEST" "/tmp/$NEW_BRANCH_NAME"
tar -xzf "$NEW_BRANCH_NAME-release.tar.gz" -C "/tmp/$NEW_BRANCH_NAME"
mv "/tmp/$NEW_BRANCH_NAME/_site" "$DEST/$NEW_BRANCH_NAME"
rm -f "$NEW_BRANCH_NAME-release.tar.gz"

# ---------- Build/fetch past versions ----------
while IFS= read -r version; do
  [[ "$version" == "$NEW_BRANCH_NAME" ]] && { echo "Skipping $version (current)"; continue; }

  echo "Handling past version $version"
  if ! fetch_other_release "$version"; then
    echo "Release missing; building $version…"
    git checkout -f "$version"
    build_release "$version" false
    git checkout -f "$OLD_BRANCH_NAME"
  fi

  mkdir -p "/tmp/$version"
  tar -xzf "$version-release.tar.gz" -C "/tmp/$version"
  mv "/tmp/$version/_site" "$DEST/$version"
  rm -f "$version-release.tar.gz"
done < <(git show main:_config.yml | yq '.past_versions[]' -r)

echo "$publishdate" > publishdate.log

# ---------- Top-level helpers ----------
git checkout -f main
CURRENT_VERSION="$(yq '.current_version' -r < _config.yml)"

# Copy a few convenience files from current version into root (optional)
for f in redirect.html skip.html aap.html CNAME; do
  [[ -f "$DEST/$CURRENT_VERSION/$f" ]] && cp "$DEST/$CURRENT_VERSION/$f" "$DEST/${f/redirect.html/index.html}"
done

# ---------- Publish: ALWAYS commit/push $DEST root ----------
PUBLISH_DIR="$DEST"

git config --global init.defaultBranch main
git -C "$PUBLISH_DIR" init
git -C "$PUBLISH_DIR" config user.name "${GITHUB_ACTOR}"
git -C "$PUBLISH_DIR" config user.email "${GITHUB_ACTOR}@users.noreply.github.com"

git -C "$PUBLISH_DIR" add -A
git -C "$PUBLISH_DIR" commit -m "published by GitHub Actions" || true

git config --global pack.window 1
git config --global http.postBuffer 524288000
git -C "$PUBLISH_DIR" branch -M main

# reset origin if exists
git -C "$PUBLISH_DIR" remote remove origin 2>/dev/null || true
git -C "$PUBLISH_DIR" remote add origin "$REPO"

# Push to gh-pages
git -C "$PUBLISH_DIR" push --force origin main:"${BRANCH}"

echo "Publish complete."