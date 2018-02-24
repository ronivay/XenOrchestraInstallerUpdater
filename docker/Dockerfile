FROM centos:latest

MAINTAINER Roni Väyrynen <roni@vayrynen.info>

# Install set of dependencies to support running Xen-Orchestra

# Node v8
RUN curl -s -L https://rpm.nodesource.com/setup_8.x | bash -

# yarn for installing node packages
RUN curl -s -o /etc/yum.repos.d/yarn.repo https://dl.yarnpkg.com/rpm/yarn.repo
RUN yum -y install yarn

# epel-release for various packages not available from base repo
RUN yum -y install epel-release

# build dependencies, git for fetching source and redis server for storing data
RUN yum -y install gcc gcc-c++ make openssl-devel redis libpng-devel python git

# monit to keep an eye on processes
RUN yum -y install monit
ADD monit-services /etc/monit.d/services

# Fetch Xen-Orchestra sources from git stable branch
RUN git clone -b master https://github.com/vatesfr/xen-orchestra /etc/xen-orchestra

# Run build tasks against sources
RUN cd /etc/xen-orchestra && yarn && yarn build

# Fix path for xo-web content in xo-server configuration
RUN sed -i "s/#'\/': '\/path\/to\/xo-web\/dist\//'\/': '..\/xo-web\/dist\//" /etc/xen-orchestra/packages/xo-server/sample.config.yaml

# Move edited config sample to place
RUN mv /etc/xen-orchestra/packages/xo-server/sample.config.yaml /etc/xen-orchestra/packages/xo-server/.xo-server.yaml

# Install forever for starting/stopping Xen-Orchestra
RUN npm install forever -g

WORKDIR /etc/xen-orchestra/xo-server

EXPOSE 80

CMD ["/usr/bin/monit"]
