rm -rf _site
bundle exec jekyll build
rsync -arvz --exclude=publish.sh --verbose --progress ./_site/ namecheap:~/www/
