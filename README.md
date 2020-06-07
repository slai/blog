# Data for slai.github.io

The files here are used to publish into the `public` git submodule, which is the repository _slai.github.io_ is served out of.

## Development

1. Download and extract [Hugo v0.69.2](https://github.com/gohugoio/hugo/releases/tag/v0.69.2) into `hugo/`. Newer versions may work, or may be incompatible with the theme

2. `git submodule update --init --recursive` to download the theme and publish repositories

3. `hugo/hugo server`

## Publish

Use the `./publish.sh` script to publish.

Don't forget to commit the data changes in this repository.
