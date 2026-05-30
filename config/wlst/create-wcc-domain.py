# WLST script: create a WebCenter Content 14.1.2 domain with one AdminServer
# and one UCM_server1 managed server, JDBC datasources pointed at RCU schemas.
#
# Invoked from create-domain.sh inside the WCC container.
#
# IMPORTANT: template path and JDBC driver class names below match the layout
# documented by Oracle's fmw-kubernetes WCC scripts. If your image's
# ORACLE_HOME layout differs, list templates with:
#   find /u01/oracle -name 'wcc_template*.jar' -o -name 'wccontent*.jar'
# and adjust TEMPLATE_PATH.

import os
import sys

ORACLE_HOME      = os.environ.get('ORACLE_HOME', '/u01/oracle')
DOMAIN_NAME      = os.environ['DOMAIN_NAME']
DOMAIN_HOME      = os.environ['DOMAIN_HOME']
ADMIN_USERNAME   = os.environ['ADMIN_USERNAME']
ADMIN_PASSWORD   = os.environ['ADMIN_PASSWORD']
DB_CONN          = os.environ['DB_CONNECTION_STRING']     # e.g. db:1521/FREEPDB1
RCU_PREFIX       = os.environ['RCU_PREFIX']
RCU_PASSWORD     = os.environ['RCU_SCHEMA_PASSWORD']
PRODUCTION_MODE  = os.environ.get('PRODUCTION_MODE', 'false').lower() == 'true'

# Base template (Infrastructure / JRF) + WCC extension template.
BASE_TEMPLATE = ORACLE_HOME + '/wlserver/common/templates/wls/wls.jar'
JRF_TEMPLATE  = ORACLE_HOME + '/oracle_common/common/templates/wls/oracle.jrf_template.jar'
WCC_TEMPLATE  = ORACLE_HOME + '/wccontent/common/templates/wls/oracle.ucm.cs_template.jar'

print('>> Creating base domain from %s' % BASE_TEMPLATE)
readTemplate(BASE_TEMPLATE)

# AdminServer
cd('/Servers/AdminServer')
set('ListenAddress', '')
set('ListenPort', 7001)

# Domain admin user
cd('/Security/base_domain/User/weblogic')
cmo.setName(ADMIN_USERNAME)
cmo.setPassword(ADMIN_PASSWORD)

setOption('OverwriteDomain', 'true')
setOption('ServerStartMode', 'prod' if PRODUCTION_MODE else 'dev')

print('>> Writing base domain to %s' % DOMAIN_HOME)
writeDomain(DOMAIN_HOME)
closeTemplate()

# Re-open the freshly-written domain to extend it with JRF + WCC templates.
print('>> Extending with JRF + WCC templates')
readDomain(DOMAIN_HOME)
addTemplate(JRF_TEMPLATE)
addTemplate(WCC_TEMPLATE)

# Create UCM_server1 managed server.
cd('/')
create('UCM_server1', 'Server')
cd('/Servers/UCM_server1')
set('ListenAddress', '')
set('ListenPort', 16200)

# Point all JRF + WCC JDBC datasources at the RCU schemas.
# Datasource names are conventional; verify with `ls $DOMAIN_HOME/config/jdbc/`
# after first creation if any lookup fails.
def point_ds(ds_name, schema_suffix):
    try:
        cd('/JDBCSystemResource/' + ds_name + '/JdbcResource/' + ds_name +
           '/JDBCDriverParams/NO_NAME_0')
        set('URL', 'jdbc:oracle:thin:@//' + DB_CONN)
        set('PasswordEncrypted', RCU_PASSWORD)
        cd('Properties/NO_NAME_0/Property/user')
        cmo.setValue(RCU_PREFIX + '_' + schema_suffix)
    except Exception as e:
        print('   skip ' + ds_name + ' (' + str(e) + ')')

for ds, schema in [
    ('LocalSvcTblDataSource',   'STB'),
    ('opss-data-source',        'OPSS'),
    ('opss-audit-DBDS',         'IAU_APPEND'),
    ('opss-audit-viewDS',       'IAU_VIEWER'),
    ('mds-owsm',                'MDS'),
    ('CSDS',                    'OCS'),
]:
    point_ds(ds, schema)

cd('/')
updateDomain()
closeDomain()

print('>> Domain extension complete.')
