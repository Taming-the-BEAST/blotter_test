FROM ruby:3.0
LABEL authors="jugne"

# Install Node.js 18.x (LTS) - Required for Pagefind
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash -

RUN apt-get update -y && apt-get install -y --no-install-recommends  \
    build-essential \
    curl \
    git \
    libaio-dev \
    nodejs \
    texlive-latex-base texlive-fonts-recommended texlive-fonts-extra texlive-latex-extra \
    && rm -rf /var/lib/apt/lists/*

ENV PAGE_HOME /page

RUN mkdir -p $PAGE_HOME
WORKDIR $PAGE_HOME

# Install Ruby dependencies
COPY ./Gemfile* $PAGE_HOME/
RUN gem install bundler -v "2.3.13"
RUN bundle install

# Install Node.js dependencies (including Pagefind)
COPY package*.json $PAGE_HOME/
RUN npm install

# Verify installations
RUN ruby --version && \
    node --version && \
    npm --version && \
    npx pagefind --version
