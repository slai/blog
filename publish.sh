#!/bin/bash

set -euo pipefail

rm -r public/*
hugo/hugo

echo
echo "Run the following commands to complete deployment -"
echo "  cd public"
echo "  git checkout master"
echo "  git add ."
echo "  git commit"
echo "  git push origin master"
echo "  cd ../"
echo "  git commit public"
