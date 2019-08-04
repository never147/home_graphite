#!/bin/bash
set -ev

sed -i -e "s/UNSAFE_DEFAULT/`date | md5sum | cut -d ' ' -f 1`/" \
        ${GRAPHITE_HOME}/webapp/graphite/local_settings.py

cd ${GRAPHITE_STORAGE}
mkdir -p rrd whisper ceres lists log/webapp

# Setup the Django database
cd ${GRAPHITE_HOME}/webapp/graphite/
PYTHONPATH=${GRAPHITE_HOME}/webapp django-admin.py migrate \
    --noinput --settings=graphite.settings --run-syncdb
PYTHONPATH=${GRAPHITE_HOME}/webapp django-admin.py loaddata \
    --settings=graphite.settings initial_data.json

chmod 775 ${GRAPHITE_STORAGE}
chown www-data:carbon ${GRAPHITE_STORAGE}
chown www-data:www-data ${GRAPHITE_STORAGE}/graphite.db
chown -R carbon ${GRAPHITE_STORAGE}/whisper
mkdir -p ${GRAPHITE_STORAGE}/log/apache2
chown -R www-data ${GRAPHITE_STORAGE}/log/webapp

sudo -u www-data /opt/graphite/bin/build-index.sh
service grafana-server start && sleep 5

curl -X POST -H 'Content-Type: application/json' -u 'admin:admin' \
  -d '{ "name": "graphite", "type": "graphite", "url": "https://127.0.0.1:443", "access": "proxy", "basicAuth": false }' \
  "http://127.0.0.1:3000/api/datasources"
curl -X POST -H 'Content-Type: application/json' -u 'admin:admin' \
  -d '{ "inputs": [{"name": "*", "pluginId": "graphite", "type": "datasource", "value": "graphite"}],  "overwrite": true, "path": "dashboards/carbon_metrics.json", "pluginId": "graphite" }' \
  "http://127.0.0.1:3000/api/dashboards/import"

# Start our processes
service carbon-cache start
service memcached start
service collectd start

#service apache2 start
#service statsite start
/usr/local/sbin/statsite -f /etc/statsite.conf &
service apache2 restart
#apache2ctl -DFOREGROUND
