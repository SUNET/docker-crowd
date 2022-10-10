#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND noninteractive

# Update the image and install the needed tools
apt-get update && \
    apt-get -y dist-upgrade && \
    apt-get install -y \
        ssl-cert\
    && apt-get -y autoremove \
    && apt-get autoclean

# Do some more cleanup to save space
rm -rf /var/lib/apt/lists/*

# Install Atlassian Crowd and helper tools and setup initial home
# directory structure.
mkdir -p                                  "${CROWD_HOME}" \
    && chmod -R 700                       "${CROWD_HOME}" \
    && chown ${RUN_USER}:${RUN_GROUP}     "${CROWD_HOME}" \
    && mkdir -p                           "${CROWD_INSTALL}" \
    && curl -Ls                           "${CROWD_DOWNLOAD_URL}" \
            -o /opt/crowd.tar.gz 
if [[ "${CROWD_SHA256_CHECKSUM}" != "$(sha256sum /opt/crowd.tar.gz | cut -d' ' -f1)" ]]; then
    echo "ERROR: SHA256 checksum of downloaded Crowd installation package does not match!"
    exit 1
fi
tar -xzf /opt/crowd.tar.gz --directory "${CROWD_INSTALL}" --strip-components=1 --no-same-owner \
    && rm -f /opt/crowd.tar.gz \
    && chown -R ${RUN_USER}:${RUN_GROUP}     "${CROWD_INSTALL}/apache-tomcat/bin" \
    && chown -R ${RUN_USER}:${RUN_GROUP}     "${CROWD_INSTALL}/apache-tomcat/work" \
    && chown -R ${RUN_USER}:${RUN_GROUP}     "${CROWD_INSTALL}/apache-tomcat/temp" \
    && chown -R ${RUN_USER}:${RUN_GROUP}     "${CROWD_INSTALL}/apache-tomcat/logs" \
    && chown ${RUN_USER}:${RUN_GROUP}        "${CROWD_INSTALL}/apache-tomcat/conf/server.xml" \
    && echo -e                            "\ncrowd.home=${CROWD_HOME}" >> "${CROWD_INSTALL}/crowd-webapp/WEB-INF/classes/crowd-init.properties"   

# Remove extra webapps from Catalina
rm -f                               "${CROWD_INSTALL}/apache-tomcat/conf/Catalina/localhost/openidclient.xml" \
    && rm -f                              "${CROWD_INSTALL}/apache-tomcat/conf/Catalina/localhost/openidserver.xml" 

# Create the start up script for Crowd
cat>/opt/atlassian/atlassian_app.sh<<'EOF'
#!/bin/bash
SERVER_XML="$CROWD_INSTALL/apache-tomcat/conf/server.xml"
if [ -w "${SERVER_XML}" ]
then
  CURRENT_PROXY_NAME=$(xmlstarlet sel -t -v "Server/Service/Connector[@port="8095"]/@proxyName" "${SERVER_XML}")

  if [[ ! -z "${PROXY_NAME}" ]] && [[ ! -z "${CURRENT_PROXY_NAME}" ]]; then
    xmlstarlet ed --inplace -u "Server/Service/Connector[@port='8095']/@proxyName" -v "${PROXY_NAME}" -u "Server/Service/Connector[@port='8095']/@proxyPort" -v "${PROXY_PORT}" -u "Server/Service/Connector[@port='8095']/@scheme" -v "${PROXY_SCHEME}" "${SERVER_XML}"
  elif [ -z "${PROXY_NAME}" ]; then
    xmlstarlet ed --inplace -d "Server/Service/Connector[@port='8095'/@proxyPort]" -d "Server/Service/Connector[@port='8095'/@proxyName]" -d "Server/Service/Connector[@port='8095'/@scheme]" "${SERVER_XML}"
  elif [ -z "${CURRENT_PROXY_NAME}" ]; then
    xmlstarlet ed --inplace -a "Server/Service/Connector[@port='8095']" -t attr -n scheme -v "${PROXY_SCHEME}" -a "Server/Service/Connector[@port='8095']" -t attr -n proxyPort -v "${PROXY_PORT}" -a "Server/Service/Connector[@port='8095']" -t attr -n proxyName -v "${PROXY_NAME}" "${SERVER_XML}"
  fi

  CURRENT_SECURE_COOKIE=$(xmlstarlet sel -t -v "Server/Service/Connector[@port="8095"]/@secure" "${SERVER_XML}")

  if [ ! -z "${SECURE_COOKIE}" ]; then
    if [ -z "${CURRENT_SECURE_COOKIE}"]; then
      xmlstarlet ed --inplace -a "Server/Service/Connector[@port='8095']" -t attr -n secure -v "${SECURE_COOKIE}" "${SERVER_XML}"
    else
      xmlstarlet ed --inplace -u "Server/Service/Connector[@port='8095']/@secure" -v "${SECURE_COOKIE}" "${SERVER_XML}"
    fi
  fi
fi

"${CROWD_INSTALL}/apache-tomcat/bin/catalina.sh" run
EOF
chmod +x /opt/atlassian/atlassian_app.sh

# Add Spring bean configuration for the shibboleth filter
xmlstarlet ed -L -a "_:beans/security:http[@authentication-manager-ref='authenticationManager']/security:custom-filter[@position='FORM_LOGIN_FILTER']" -t elem -n 'security:custom-filter' -v "" \
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
