FROM docker.sunet.se/eduix/eduix-base:latest

# Setup useful environment variables
ENV CROWD_HOME     /var/atlassian/application-data/crowd
ENV CROWD_INSTALL  /opt/atlassian/crowd
ARG CROWD_VERSION=3.1.2
ARG CROWD_SHA256_CHECKSUM=71be4e94ff253b3b76ef4dfbb14fdbeb643ab0adc113d8df64472034e807d45e

LABEL name="Atlassian Crowd base image" Description="This image is used to build Atlassian Crowd" Vendor="Atlassian" Version="${CROWD_VERSION}"

ENV CROWD_DOWNLOAD_URL http://www.atlassian.com/software/crowd/downloads/binary/atlassian-crowd-${CROWD_VERSION}.tar.gz

ENV RUN_USER            atlassian
ENV RUN_GROUP           atlassian

# Copying the Dockerfile to the image as documentation
COPY Dockerfile /
COPY setup.sh /opt/sunet/setup.sh
RUN /opt/sunet/setup.sh

# Add crowd-shibboleth-filter. Have to run mvn package before building docker image
COPY shibboleth-filter-1.1.jar "${CROWD_INSTALL}/crowd-webapp/WEB-INF/lib/"

# Set volume mount points for installation and home directory. Changes to the
# home directory needs to be persisted as well as parts of the installation
# directory due to eg. logs.
VOLUME ["${CROWD_INSTALL}", "${CROWD_HOME}"]

# Expose default HTTP connector port.
EXPOSE 8095

USER atlassian

# Set the default working directory as the Crowd installation directory.
WORKDIR ${CROWD_INSTALL}

# Run Atlassian Crowd as a foreground process by default.
CMD ["/usr/bin/start_atlassian_app.sh"]
