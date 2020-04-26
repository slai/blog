# Data for slai.github.io

The files here are used to publish into the `public` git submodule, which is the repository _slai.github.io_ is served out of.

## Development

1. Download and extract https://github.com/gohugoio/hugo/releases into `hugo/`

2. `git submodule update --init --recursive` to download the theme and publish repositories

3. `hugo/hugo server`

## Publish

```sh
hugo/hugo

cd public
git add .
git commit
git push origin master
```

Don't forget to commit the data changes in this repository.
