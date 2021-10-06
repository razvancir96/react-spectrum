#!/bin/bash

port=4000
original_registry=`npm get registry`
registry="http://localhost:$port"
output="output.out"
ci=false

if [ "$1" = "ci" ];
then
  ci=true
fi

function cleanup {
  if [ "$ci" = false ];
  then
    lsof -ti tcp:4000 | xargs kill
    # Clean up generated dists if run locally
    rm -rf **/dist
    rm -rf storage/ ~/.config/verdaccio/storage/ $output
    git tag -d $(git tag -l)
    git fetch
    git reset --hard HEAD~1
    npm set registry $original_registry
  else
    # lsof doesn't work in circleci
    netstat -tpln | awk -F'[[:space:]/:]+' '$5 == 4000 {print $(NF-2)}' | xargs kill
  fi
}

# Generate dists for the packages
make build

# Start verdaccio and send it to the background
yarn verdaccio --listen $port &>${output}&

# Wait for verdaccio to start
grep -q 'http address' <(tail -f $output)

# Login as test user
yarn npm-cli-login -u abc -p abc -e 'abc@abc.com' -r $registry

if [ "$ci" = true ];
then
  git config --global user.email octobot@github.com
  git config --global user.name GitHub Actions
fi

# Bump all package versions (allow publish from current branch but don't push tags or commit)
yarn lerna version minor --force-publish --allow-branch `git branch --show-current` --no-push --yes


if [ "$ci" = true ];
then
# Get rid of npmrc file generated by install since it will block lerna publish
  git checkout -- .
fi

# Publish packages to verdaccio
yarn lerna publish from-package --registry $registry --yes

npm set registry $registry

if [ "$ci" = true ];
then
  # build prod docs
  make website-production
  # Rename the dist folder from dist/production/docs to dist/verdaccio/docs
  # If building the sample app, move the contents of the build folder to dist/verdaccio/build or something
  mkdir dist/`git rev-parse HEAD`
  mkdir dist/`git rev-parse HEAD`/verdaccio
  mv dist/production/docs dist/`git rev-parse HEAD`/verdaccio
else
  # Wait for user input to do cleanup
  read -n 1 -p "Press a key to close server and cleanup"
fi

cleanup