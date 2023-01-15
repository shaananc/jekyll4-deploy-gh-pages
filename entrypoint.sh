#!/bin/bash

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

DEST="${JEKYLL_DESTINATION:-_site}"
REPO="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
BRANCH="gh-pages"
BUNDLE_BUILD__SASSC=--disable-march-tune-native

echo "Installing gems..."

bundle config path vendor/bundle
bundle install --jobs 4 --retry 3

echo "Building Jekyll site..."

if [ ! -z $YARN_ENV ]; then
  echo "Installing javascript packages..."
  yarn
fi

JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll build

if [[ -z "${ALGOLIA_API_KEY}" ]]; then
  echo "No Algolia API key provided"
else
  JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll algolia
fi

#mkdir -p ~/.ssh && touch ~/.ssh/known_hosts && true
#ssh-keyscan github.com >>~/.ssh/known_hosts
git config core.sshCommand 'ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

cat _config.yml | yq '.past_versions[]' -r | while read -r version; do
  echo "Building Jekyll site for version ${version}..."
  bash $SCRIPT_DIR/build-version.sh ${version}
  #JEKYLL_ENV=production NODE_ENV=production bundle exec jekyll build --config _config.yml,_config.${version}.yml
done

publishdate=$(date +%m-%d-%Y)
echo $publishdate >publishdate.log

echo "Publishing..."

cd ${DEST}

git init
git config user.name "${GITHUB_ACTOR}"
git config user.email "${GITHUB_ACTOR}@users.noreply.github.com"
git add .
git commit -m "published by GitHub Actions"
git push --force ${REPO} master:${BRANCH}
