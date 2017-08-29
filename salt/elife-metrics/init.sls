{% set app = pillar.elife_metrics %}
{% set deploy_user = pillar.elife.deploy_user.username %}

# this was part of some ssl issues iirc. no longer a problem
#elife-metrics-deps:
#    pkg.installed:
#        - pkgs: 
#            - libffi-dev

install-elife-metrics:
    file.directory:
        - name: /srv/elife-metrics/
        - user: {{ deploy_user }}
        - group: {{ deploy_user }}

    builder.git_latest:
        - user: {{ deploy_user }}
        - name: https://github.com/elifesciences/elife-metrics
        - rev: {{ salt['elife.cfg']('project.revision', 'project.branch', 'master') }}
        - branch: {{ salt['elife.branch']() }}
        - target: /srv/elife-metrics/
        - force_fetch: True
        - force_checkout: True
        - force_reset: True
        - require:
            - file: install-elife-metrics

cfg-file:
    file.managed:
        - user: {{ deploy_user }}
        - name: /srv/elife-metrics/app.cfg
        - source:
            - salt://elife-metrics/config/srv-elife-metrics-{{ salt['elife.cfg']('project.branch') }}.cfg
            - salt://elife-metrics/config/srv-elife-metrics-app.cfg
        - template: jinja
        - require:
            - install-elife-metrics

#
# logging
#

elife-metrics-log-file:
    file.managed:
        - name: /var/log/elife-metrics.log
        - user: {{ deploy_user }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660
        - require:
            - install-elife-metrics

# vagrant uses the 'dev' environment
elife-metrics-dev-log-file:
    file.managed:
        - name: /srv/elife-metrics/elife-metrics.log
        - user: {{ deploy_user }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660
        - require:
            - install-elife-metrics


elife-metrics-debugme-log-file:
    file.managed:
        - name: /srv/elife-metrics/debugme.log
        - user: {{ deploy_user }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660
        - require:
            - install-elife-metrics

elife-metrics-syslog-conf:
    file.managed:
        - name: /etc/syslog-ng/conf.d/elife-metrics.conf
        - source: salt://elife-metrics/config/etc-syslog-ng-conf.d-elife-metrics.conf
        - template: jinja
        - require:
            - pkg: syslog-ng
            - file: elife-metrics-log-file
        - watch_in:
            - service: syslog-ng


#
# db
#

elife-metrics-db-user:
    postgres_user.present:
        - name: {{ app.db.username }}
        - encrypted: True
        - password: {{ app.db.password }}
        - refresh_password: True
        - db_user: {{ pillar.elife.db_root.username }}
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        - db_password: {{ salt['elife.cfg']('project.rds_password') }}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% else %}
        - db_password: {{ pillar.elife.db_root.password }}
        {% endif %}
        - createdb: True
        - require:
            - postgres_user: postgresql-user

elife-metrics-db-exists:
    postgres_database.present:
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        # remote
        - name: {{ salt['elife.cfg']('project.rds_dbname') }}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% else %}
        # local
        - name: {{ app.db.name }}
        {% endif %}
        - db_user: {{ app.db.username }}
        - db_password: {{ app.db.password }}
        - require:
            - postgres_user: elife-metrics-db-user

db-perms-to-rds_superuser:
    cmd.script:
        - name: salt://elife/scripts/rds-perms.sh
        - template: jinja
        - defaults:
            user: {{ app.db.username }}
            pass: {{ app.db.password }}
        - require:
            - elife-metrics-db-exists

ubr-app-db-backup:
    file.managed:
        - name: /etc/ubr/elife-metrics-backup.yaml
        - source: salt://elife-metrics/config/etc-ubr-elife-metrics-backup.yaml
        - template: jinja
        - require:
            - elife-metrics-db-exists

#
# configure
# 

configure-elife-metrics:
    cmd.run:
        - user: {{ deploy_user }}
        - cwd: /srv/elife-metrics/
        - name: ./install.sh && ./manage.sh collectstatic --noinput
        - require:
            - install-elife-metrics
            - file: cfg-file
            - file: elife-metrics-log-file
            - postgres_user: elife-metrics-db-user

aws-credentials-deploy-user:
    file.managed:
        - name: /home/{{ deploy_user }}/.aws/credentials
        - user: {{ deploy_user }}
        - makedirs: True
        - source: salt://elife-metrics/config/home-deploy-user-.aws-credentials
        - template: jinja
        - require:
            - configure-elife-metrics

aws-credentials-www-data-user:
    file.managed:
        - name: /var/www/.aws/credentials
        - user: {{ pillar.elife.webserver.username }}
        - makedirs: True
        - source: salt://elife-metrics/config/var-www-.aws-credentials
        - template: jinja
        - require:
            - configure-elife-metrics

elife-metrics-auth:
    file.serialize:
        - name: /srv/elife-metrics//client-secrets.json
        - dataset_pillar: elife_metrics:client_secrets
        - formatter: json
        - user: {{ deploy_user }}
        - group: {{ deploy_user }}
        - require:
            - install-elife-metrics

load-pmcids:
    cmd.run:
        - user: {{ deploy_user }}
        - cwd: /srv/elife-metrics/
        - name: ./download-pmcids.sh && touch /home/elife/.pmcids-loaded.flag
        - creates: /home/elife/.pmcids-loaded.flag
        - onlyif:
            - test -f download-pmcids.sh
        - require:
            - configure-elife-metrics

#
# cron
#

# 00:00, every day
# only run on prod and adhoc instances
load-articles-every-day:
    {% if pillar.elife.env in ['dev', 'continuumtest', 'ci', 'end2end'] %}
    cron.absent:
    {% else %}
    cron.present:
    {% endif %}
        - user: {{ deploy_user }}
        - name: cd /srv/elife-metrics/ && ./import-metrics.sh
        - identifier: load-metrics-every-day
        - minute: 0
        - hour: 0
        - require:
            - postgres_database: elife-metrics-db-exists

logrotate-metrics-logs:
    file.managed:
        - name: /etc/logrotate.d/elife-metrics
        - source: salt://elife-metrics/config/etc-logrotate.d-elife-metrics
        - template: jinja
