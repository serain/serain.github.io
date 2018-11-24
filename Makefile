SHELL = /bin/sh

.DEFAULT_GOAL:publish

publish:
	export MEDIUM_USER_ID=$(shell pass social/medium_id) && \
	export MEDIUM_INTEGRATION_TOKEN=$(shell pass social/medium_token) && \
	jekyll build
	git commit :/.jekyll-crosspost_to_medium/medium_crossposted.yml -m "update medium published list"
	git push origin master
