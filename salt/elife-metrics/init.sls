{% set app = pillar.elife_metrics %}

{{ app.name }}-deps:
    pkg.installed:
        - pkgs: 
            - libffi-dev

install-{{ app.name }}:
    file.directory:
        - name: {{ app.install_path }}
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}

    builder.git_latest:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: https://github.com/elifesciences/{{ app.name }}
        - rev: {{ salt['elife.cfg']('project.revision', 'project.branch', 'master') }}
        - branch: {{ salt['elife.branch']() }}
        - target: {{ app.install_path }}
        - force_fetch: True
        - force_checkout: True
        - force_reset: True
        - require:
            - file: install-{{ app.name }}

cfg-file:
    file.managed:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: /srv/{{ app.name }}/app.cfg
        - source:
            - salt://{{ app.name }}/config/srv-{{ app.name }}-{{ pillar.elife.env }}.cfg
            - salt://{{ app.name }}/config/srv-{{ app.name }}-{{ salt['elife.cfg']('project.branch', 'develop') }}.cfg
            - salt://{{ app.name }}/config/srv-{{ app.name }}-app.cfg
        - template: jinja
        - require:
            - install-{{ app.name }}

#
# logging
#

{{ app.name }}-log-file:
    file.managed:
        - name: /var/log/{{ app.name }}.log
        - user: {{ pillar.elife.webserver.username }}
        - group: {{ pillar.elife.webserver.username }}
        - mode: 660

{{ app.name }}-syslog-conf:
    file.managed:
        - name: /etc/syslog-ng/conf.d/{{ app.name }}.conf
        - source: salt://{{ app.name }}/config/etc-syslog-ng-conf.d-{{ app.name }}.conf
        - template: jinja
        - require:
            - pkg: syslog-ng
            - file: {{ app.name }}-log-file
        - watch_in:
            - service: syslog-ng


#
# db
#

{{ app.name }}-db-user:
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

{{ app.name }}-db-exists:
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
            - postgres_user: {{ app.name }}-db-user


#
# configure
# 

configure-{{ app.name }}:
    cmd.run:
        - user: {{ pillar.elife.deploy_user.username }}
        - cwd: {{ app.install_path }}
        - name: ./install.sh && ./manage.sh collectstatic --noinput
        - require:
            - install-{{ app.name }}
            - file: cfg-file
            - pkg: {{ app.name }}-deps
            - file: {{ app.name }}-log-file
            - postgres_user: {{ app.name }}-db-user

{{ app.name }}-auth:
    file.serialize:
        - name: {{ app.install_path }}/client-secrets.json
        - dataset_pillar: elife_metrics:client_secrets
        - formatter: json
        - user: {{ pillar.elife.deploy_user.username }}
        - group: {{ pillar.elife.deploy_user.username }}
        - require:
            - install-{{ app.name }}


#
# cron
#

# 00:00, every day
load-articles-every-day:
    cron.present:
        - user: {{ pillar.elife.deploy_user.username }}
        - name: cd {{ app.install_path }} && ./import-metrics.sh
        - identifier: load-metrics-every-day
        - minute: 0
        - hour: 0
        - require:
            - postgres_database: {{ app.name }}-db-exists

