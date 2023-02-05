#!/bin/bash

#set -e
set -x

#source .env

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

DEST="/tmp/_site"
REPO="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
BRANCH="gh-pages"
BUNDLE_BUILD__SASSC=--disable-march-tune-native
API_ENDPOINT="https://api.github.com/repos/$GITHUB_REPOSITORY"
GZIP="-9"

# add ssh key from $DEPLOY_KEY
mkdir -p ~/.ssh && true
echo "$DEPLOY_KEY" >~/.ssh/id_ed25519_deploy
chmod 600 ~/.ssh/id_ed25519_deploy
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519_deploy && true

function build_release() {
  BRANCH_NAME=$1-release
  ALGOLIA=$2
  echo "Installing gems..."

  bundle config path vendor/bundle
  bundle config build.ffi --disable-system-libffi
  bundle install --jobs 4 --retry 3

  echo "Building Jekyll site..."

  if [ ! -z $YARN_ENV ]; then
    echo "Installing javascript packages..."
    yarn
  fi

  JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll build --config _config.yml,_config.$1.yml

  # if ALGOLIA is set to true then run algolia
  if [ "$ALGOLIA" = "true" ]; then
    echo "Running Algolia..."
    if [[ -z "${ALGOLIA_API_KEY}" ]]; then
      echo "No Algolia API key provided"
    else
      JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll algolia
    fi
  fi

  # Define the tag for the release
  TAG=$BRANCH_NAME

  #GITHUB_TOKEN=$(cat .github-token)

  # Define the name of the file to be uploaded
  FILENAME="$BRANCH_NAME.tar.gz"

  # Get the ID of the release with the same name, if it exists
  RELEASE_ID=$(curl -s -H "Authorization: Token $GITHUB_TOKEN" \
    $API_ENDPOINT/releases/tags/$TAG | jq '.id')

  # If the release exists, delete it
  if [ "$RELEASE_ID" != "null" ]; then
    curl -X DELETE -H "Authorization: Token $GITHUB_TOKEN" \
      $API_ENDPOINT/releases/$RELEASE_ID
  fi

  # Package up the current directory into a tar archive
  tar -czf $FILENAME _site

  # Create the release using curl
  RESPONSE=$(curl --data '{"tag_name": "'"$TAG"'", "name": "'"$TAG"'", "draft": false, "prerelease": false}' \
    -H "Authorization: Token $GITHUB_TOKEN" \
    -H "Content-Type: application/json" \
    -X POST $API_ENDPOINT/releases)

  echo $RESPONSE >response.log

  RELEASE_ID=$(jq .id <<<$RESPONSE)

  # Upload the tar archive to the latest release
  curl -H "Authorization: Token $GITHUB_TOKEN" \
    -H "Content-Type: application/gzip" \
    --data-binary "@$FILENAME" \
    "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$FILENAME"

}

function fetch_other_release() {
  version=$1
  releasename=$1"-release"
  echo "Fetching Jekyll site for version ${version}..."
  # Define the name of the file to download
  #FILENAME="$version.tar.gz"

  # Get the ID of the release with the specified tag
  RELEASE_ID=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    $API_ENDPOINT/releases/tags/$releasename | jq '.id')

  echo "Release id is $RELEASE_ID"

  if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
    echo "Release $version does not exist"
    return 1
  fi

  echo "Release $version exists with id $RELEASE_ID"

  # Fetch the asset URL for the specified file
  ASSET_URL=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    $API_ENDPOINT/releases/$RELEASE_ID/assets | jq -r ".[].url")

  # Download the specified file
  echo "Downloading $ASSET_URL"
  FILENAME=$(curl -w "%{filename_effective}" -LOJ -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/octet-stream" $ASSET_URL)
  echo "Downloaded $FILENAME"
  # untar the file to /tmp and move the result _site to a folder named after the version
  return 0
}

publishdate=$(date +%m-%d-%Y)
echo "Creating release for current branch"

# Define the API endpoint for creating a release
NEW_BRANCH_NAME=$(git branch --show-current)
OLD_BRANCH_NAME=$NEW_BRANCH_NAME
# if BRANCH_NAME is main then set the tag to current_version in config.yml
if [ "$NEW_BRANCH_NAME" = "main" ]; then
  NEW_BRANCH_NAME=$(cat _config.yml | yq '.current_version' -r)
fi

build_release $NEW_BRANCH_NAME true
mkdir -p $DEST
mkdir -p /tmp/$NEW_BRANCH_NAME
tar -xzf $NEW_BRANCH_NAME-release.tar.gz -C /tmp/$NEW_BRANCH_NAME
mv /tmp/$NEW_BRANCH_NAME/_site $DEST/$NEW_BRANCH_NAME
rm $NEW_BRANCH_NAME-release.tar.gz

cat _config.yml | yq '.past_versions[]' -r | while read -r version; do
  echo "Fetching release for version $version"
  fetch_other_release $version
  # check if the fetch was successful
  if [ $? -eq 1 ]; then
    echo "Creating release for version $version"
    git checkout $version
    build_release $version false
    git checkout $OLD_BRANCH_NAME
  fi

  mkdir -p /tmp/$version
  tar -xzf $version-release.tar.gz -C /tmp/$version
  mv /tmp/$version/_site $DEST/$version
  rm $version-release.tar.gz

done

echo $publishdate >publishdate.log

echo "Publishing..."

#cd ${DEST}

# git init
# git config user.name "${GITHUB_ACTOR}"
# git config user.email "${GITHUB_ACTOR}@users.noreply.github.com"
# git add .
# git commit -m "published by GitHub Actions"
# git push --force ${REPO} master:${BRANCH}

git config --global --add safe.directory /github/workspace
git checkout main
CURRENT_VERSION=$(cat _config.yml | yq '.current_version' -r)
cp $DEST/$CURRENT_VERSION/redirect.html $DEST/index.html

mkdir -p /tmp/gh-pages
tar -czf /tmp/github-pages $DEST/*
