FROM ruby:3.1.2-bullseye
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
build-essential curl git nodejs
RUN gem install rails -v '7.0.3.1'
RUN gem install bundler
WORKDIR /app
ADD Gemfile Gemfile.lock /app/
RUN bundle install


ENV WAIT_VERSION 2.7.2
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/$WAIT_VERSION/wait /wait
RUN chmod +x /wait
