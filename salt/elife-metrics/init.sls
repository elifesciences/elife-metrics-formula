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
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660

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
        - name: {{ app.db.name }}
        - owner: {{ app.db.username }}
        - db_user: {{ app.db.username }}
        - db_password: {{ app.db.password }}
        {% if salt['elife.cfg']('cfn.outputs.RDSHost') %}
        - db_host: {{ salt['elife.cfg']('cfn.outputs.RDSHost') }}
        - db_port: {{ salt['elife.cfg']('cfn.outputs.RDSPort') }}
        {% endif %}
        - require:
            - postgres_user: elife-metrics-db-user


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
            #- pkg: elife-metrics-deps
            - file: elife-metrics-log-file
            - postgres_user: elife-metrics-db-user

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
        - name: ./download-pmcids.sh && touch .pmcids-loaded.flag
        - creates: .pmcids-loaded.flag
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

