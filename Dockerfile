FROM ubuntu:14.04

ENV GRAPHITE_HOME='/opt/graphite' \
    GRAPHITE_CONF="/opt/graphite/conf" \
    GRAPHITE_STORAGE="/opt/graphite/storage" \
    BUILD_ROOT=/usr/local/src/graphite

ENV GRAPHITE_RELEASE='1.0.2'

RUN apt-get update -y && \
    RUNLEVEL=1 apt-get install -y \
      libcairo2-dev libffi-dev pkg-config python-dev python-pip fontconfig \
      apache2 libapache2-mod-wsgi git-core collectd memcached gcc g++ make \
      libtool automake python-setuptools curl && \
    apt-get clean

RUN python -m pip install --upgrade pip setuptools

# Build and install Graphite/Carbon/Whisper and Statsite
COPY whisper $BUILD_ROOT/whisper
WORKDIR $BUILD_ROOT/whisper
RUN git checkout ${GRAPHITE_RELEASE}
RUN python setup.py install

COPY carbon $BUILD_ROOT/carbon
WORKDIR $BUILD_ROOT/carbon
RUN git checkout ${GRAPHITE_RELEASE}
RUN pip install -r requirements.txt && \
    python setup.py install

COPY graphite-web $BUILD_ROOT/graphite-web
WORKDIR $BUILD_ROOT/graphite-web
RUN git checkout ${GRAPHITE_RELEASE}
RUN pip install -r requirements.txt && python check-dependencies.py && \
    python setup.py install

COPY statsite $BUILD_ROOT/statsite
WORKDIR $BUILD_ROOT/statsite
RUN ./autogen.sh && ./configure && make && \
    cp statsite /usr/local/sbin/ && \
    cp sinks/graphite.py /usr/local/sbin/statsite-sink-graphite.py

# Update txamqp to support RabbitMQ 2.4+
RUN pip install txamqp==0.6.2 --upgrade

# Install configuration files for Graphite/Carbon and Apache
COPY templates/statsite/statsite.conf /etc/statsite.conf
RUN mkdir ${GRAPHITE_CONF}/examples && \
    mv ${GRAPHITE_CONF}/*.example ${GRAPHITE_CONF}/examples/
COPY templates/graphite/conf/* ${GRAPHITE_CONF}/
COPY templates/collectd/collectd.conf /etc/collectd/
COPY templates/apache/graphite.conf /etc/apache2/sites-available/
COPY templates/init/* /etc/init/
COPY templates/init.d/* /etc/init.d/

# Setup the correct Apache site and modules
RUN a2dissite 000-default && \
    a2ensite graphite && \
    a2enmod ssl && \
    a2enmod socache_shmcb && \
    a2enmod rewrite

# Install configuration files for Django
COPY templates/graphite/webapp/* ${GRAPHITE_HOME}/webapp/graphite/
#RUN sed -i -e "s/UNSAFE_DEFAULT/`date | md5sum | cut -d ' ' -f 1`/" \
#    ${GRAPHITE_HOME}/webapp/graphite/local_settings.py

# Setup the Django database
#WORKDIR ${GRAPHITE_HOME}/webapp/graphite/
#RUN PYTHONPATH=${GRAPHITE_HOME}/webapp django-admin.py migrate \
#      --noinput --settings=graphite.settings --run-syncdb
#RUN PYTHONPATH=${GRAPHITE_HOME}/webapp django-admin.py loaddata \
#      --settings=graphite.settings initial_data.json

# Add carbon system user and set permissions
RUN groupadd -g 998 carbon && \
    useradd -c "carbon user" -g 998 -u 998 -s /bin/false carbon && \
    chmod +x /etc/init.d/carbon-cache

# Setup hourly cron to rebuild Graphite index
COPY templates/graphite/cron/build-index /etc/cron.hourly/graphite-build-index
RUN chmod 755 /etc/cron.hourly/graphite-build-index

# Install Grafana
RUN echo 'deb https://packagecloud.io/grafana/stable/debian/ wheezy main' \
     > /etc/apt/sources.list.d/grafana.list

#RUN curl https://packagecloud.io/gpg.key | apt-key add - && \
RUN curl -L https://packagecloud.io/grafana/stable/gpgkey | apt-key add - && \
    apt-get install apt-transport-https && \
    apt-get update -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y grafana && \
    apt-get clean

EXPOSE 80/tcp
EXPOSE 443/tcp
EXPOSE 2003/tcp
EXPOSE 2004/tcp
EXPOSE 7002/tcp
EXPOSE 8125/tcp
EXPOSE 3000/tcp

VOLUME ${GRAPHITE_STORAGE}

# Start our processes
COPY startup.sh /
RUN chmod +x /startup.sh
ENTRYPOINT /startup.sh
