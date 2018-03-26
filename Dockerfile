FROM docker.sunet.se/eduix/eduix-base:latest

# Copying the Dockerfile to the image as documentation
COPY Dockerfile /
COPY setup.sh /opt/sunet/setup.sh
RUN /opt/sunet/setup.sh

WORKDIR /
