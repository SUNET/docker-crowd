FROM docker.sunet.se/eduix/eduix-base:latest

# Setup useful environment variables
ENV CROWD_HOME     /var/atlassian/application-data/crowd
ENV CROWD_INSTALL  /opt/atlassian/crowd
ARG CROWD_VERSION=3.1.2

LABEL name="Atlassian Crowd base image" Description="This image is used to build Atlassian Crowd" Vendor="Atlassian" Version="${CROWD_VERSION}"

ENV CROWD_DOWNLOAD_URL http://www.atlassian.com/software/crowd/downloads/binary/atlassian-crowd-${CROWD_VERSION}.tar.gz

ENV MYSQL_VERSION 5.1.38
ENV MYSQL_DRIVER_DOWNLOAD_URL http://dev.mysql.com/get/Downloads/Connector-J/mysql-connector-java-${MYSQL_VERSION}.tar.gz

ENV RUN_USER            atlassian
ENV RUN_GROUP           atlassian

# Install Atlassian Crowd and helper tools and setup initial home
# directory structure.
RUN set -x \
    && mkdir -p                           "${CROWD_HOME}" \
    && mkdir -p                           "${CROWD_INSTALL}" \
    && curl -Ls                           "${CROWD_DOWNLOAD_URL}" | tar -xz --directory "${CROWD_INSTALL}" --strip-components=1 --no-same-owner \
    && curl -Ls                           "${MYSQL_DRIVER_DOWNLOAD_URL}" | tar -xz --directory "${CROWD_INSTALL}/apache-tomcat/lib" --strip-components=1 --no-same-owner "mysql-connector-java-${MYSQL_VERSION}/mysql-connector-java-${MYSQL_VERSION}-bin.jar" \
    && echo -e                            "\ncrowd.home=${CROWD_HOME}" >> "${CROWD_INSTALL}/crowd-webapp/WEB-INF/classes/crowd-init.properties" 

# Remove extra webapps from Catalina
RUN rm -f                               "${CROWD_INSTALL}/apache-tomcat/conf/Catalina/localhost/openidclient.xml" \
    && rm -f                              "${CROWD_INSTALL}/apache-tomcat/conf/Catalina/localhost/openidserver.xml" 

# Create the start up script for Crowd
RUN echo '#!/bin/bash\n\
SERVER_XML="$CROWD_INSTALL/apache-tomcat/conf/server.xml"\n\
CURRENT_PROXY_NAME=`xmlstarlet sel -t -v "Server/Service/Connector[@port="8095"]/@proxyName" $SERVER_XML`\n\
if [ -w $SERVER_XML ]\n\
then\n\
  if [[ ! -z $PROXY_NAME ]] && [[ ! -z $CURRENT_PROXY_NAME ]]; then\n\
    xmlstarlet ed --inplace -u "Server/Service/Connector[@port='8095']/@proxyName" -v "$PROXY_NAME" -u "Server/Service/Connector[@port='8095']/@proxyPort" -v "$PROXY_PORT" -u "Server/Service/Connector[@port='8095']/@scheme" -v "$PROXY_SCHEME" $SERVER_XML\n\
  elif [ -z $CURRENT_PROXY_NAME ]; then\n\
    xmlstarlet ed --inplace -a "Server/Service/Connector[@port='8095']" -t attr -n scheme -v "$PROXY_SCHEME" -a "Server/Service/Connector[@port='8095']" -t attr -n proxyPort -v "$PROXY_PORT" -a "Server/Service/Connector[@port='8095']" -t attr -n proxyName -v "$PROXY_NAME" $SERVER_XML\n\
  else\n\
    xmlstarlet ed --inplace -d "Server/Service/Connector[@port='8095'/@proxyPort]" -d "Server/Service/Connector[@port='8095'/@proxyName]" -d "Server/Service/Connector[@port='8095'/@scheme]" $SERVER_XML\n\
  fi\n\
fi\n\
'"${CROWD_INSTALL}"'/apache-tomcat/bin/catalina.sh run' > /opt/atlassian/atlassian_app.sh

# Add crowd-shibboleth-filter. Have to run mvn package before building docker image
COPY shibboleth-filter-1.1.jar "${CROWD_INSTALL}/crowd-webapp/WEB-INF/lib/"
RUN set -x \
    && xmlstarlet ed -L -a "_:beans/security:http[@authentication-manager-ref='authenticationManager']/security:custom-filter[@position='FORM_LOGIN_FILTER']" -t elem -n 'security:custom-filter' -v "" \
       --var new '$prev' \
       -i '$new' -t attr -n 'after' -v 'FORM_LOGIN_FILTER' \
       -i '$new' -t attr -n 'ref' -v 'authenticationProcessingShibbolethFilter' \
       /opt/atlassian/crowd/crowd-webapp/WEB-INF/classes/applicationContext-CrowdSecurity.xml \
    && xmlstarlet ed -L -a "_:beans/security:http[@authentication-manager-ref='authenticationManager']/security:custom-filter[@position='LOGOUT_FILTER']" -t elem -n 'security:intercept-url' -v "" \
       --var new '$prev' \
       -i '$new' -t attr -n 'pattern' -v '/plugins/servlet/ssocookie' \
       -i '$new' -t attr -n 'access' -v 'IS_AUTHENTICATED_ANONYMOUSLY' \
       /opt/atlassian/crowd/crowd-webapp/WEB-INF/classes/applicationContext-CrowdSecurity.xml \
    && xmlstarlet ed -L -s "_:beans" -t elem -n 'bean' -v "" \
       -i "_:beans/bean[not(@id)]" -t attr -n class -v 'net.nordu.crowd.shibboleth.ShibbolethSSOFilter' \
       -i "_:beans/bean[not(@id)]" -t attr -n id -v 'authenticationProcessingShibbolethFilter' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'clientProperties' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'clientProperties' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'propertyManager' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'propertyManager' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'httpTokenHelper' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'httpTokenHelper' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'tokenAuthenticationManager' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'tokenAuthenticationManager' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'authenticationManager' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'authenticationManager' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'applicationService' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'applicationService' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'applicationManager' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'applicationManager' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'userAuthoritiesProvider' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'userAuthoritiesProvider' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'value' -v '/console/j_security_check' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'filterProcessesUrl' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'directoryManager' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'directoryManager' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v ""\
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'authenticationFailureHandler' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']" -t elem -n 'bean' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']/bean" -t attr -n 'class' -v 'com.atlassian.crowd.integration.springsecurity.UsernameStoringAuthenticationFailureHandler' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']/bean" -t elem -n 'constructor-arg' -v "" \
       -s '$prev' -t elem -n 'util:constant' -v "" \
       -s '$prev' -t attr -n 'static-field' -v "com.atlassian.crowd.integration.springsecurity.SecurityConstants.USERNAME_PARAMETER" \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']/bean" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']/bean/property" -t attr -n 'name' -v 'defaultFailureUrl' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationFailureHandler']/bean/property" -t attr -n 'value' -v '/console/login.action?error=true' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v ""\
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'authenticationSuccessHandler' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationSuccessHandler']" -t elem -n 'bean' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[@name='authenticationSuccessHandler']/bean" -t attr -n 'class' -v 'net.nordu.crowd.shibboleth.SavedRequestAwarePassThroughAuthenticationSuccessHandler' \
       -s "_:beans/bean[@id='authenticationProcessingShibbolethFilter']" -t elem -n 'property' -v "" \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'ref' -v 'requestToApplicationMapper' \
       -i "_:beans/bean[@id='authenticationProcessingShibbolethFilter']/property[not(@name)]" -t attr -n 'name' -v 'requestToApplicationMapper' \
       /opt/atlassian/crowd/crowd-webapp/WEB-INF/classes/applicationContext-CrowdSecurity.xml

# Set volume mount points for installation and home directory. Changes to the
# home directory needs to be persisted as well as parts of the installation
# directory due to eg. logs.
VOLUME ["${CROWD_INSTALL}", "${CROWD_HOME}"]

# Expose default HTTP connector port.
EXPOSE 8095

# Set the default working directory as the Crowd installation directory.
WORKDIR ${CROWD_INSTALL}

# Copying the Dockerfile to the image as documentation
COPY Dockerfile /

# Run Atlassian Crowd as a foreground process by default.
CMD ["/usr/bin/start_atlassian_app.sh"]
