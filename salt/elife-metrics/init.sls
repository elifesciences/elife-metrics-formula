{% set app = pillar.elife_metrics %}
{% set deploy_user = pillar.elife.deploy_user.username %}

elife-metrics-deps:
    pkg.installed:
        - pkgs:
            - sqlite3 # for accessing requests_cache db

install-elife-metrics:
    builder.git_latest:
        - name: git@github.com:elifesciences/elife-metrics
        - identity: {{ pillar.elife.projects_builder.key or '' }}
        - rev: {{ salt['elife.rev']() }}
        - branch: {{ salt['elife.branch']() }}
        - target: /srv/elife-metrics/
        - force_fetch: True
        - force_checkout: True
        - force_reset: True

    file.directory:
        - name: /srv/elife-metrics/
        - user: {{ deploy_user }}
        - group: {{ deploy_user }}
        - recurse:
            - user
            - group
        - require:
            - builder: install-elife-metrics


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

ubr-app-db-backup:
    file.managed:
        - name: /etc/ubr/elife-metrics-backup.yaml
        - source: salt://elife-metrics/config/etc-ubr-elife-metrics-backup.yaml
        - template: jinja

#
# configure
# 

configure-elife-metrics:
    cmd.run:
        - runas: {{ deploy_user }}
        - cwd: /srv/elife-metrics/
        - name: ./install.sh && ./manage.sh collectstatic --noinput
        - require:
            - install-elife-metrics
            - file: cfg-file
            - file: elife-metrics-log-file

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
        - runas: {{ deploy_user }}
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

# once a week, remove any partial files that are hanging around
# these are deliberate cache misses for periods that will return partial results
rm-partial-files-every-week:
    cron.present:
        - user: {{ deploy_user }}
        {% if pillar.elife.env == 'prod' %}
        - name: cd /ext/elife-metrics/output && find . -name '*\.partial' -delete
        {% else %}
        - name: cd /srv/elife-metrics/output && find . -name '*\.partial' -delete
        {% endif %}
        - identifier: rm-partial-files-every-week
        - special: "@weekly"

periodically-remove-expired-cache-entries:
    cron.present:
        - user: {{ deploy_user }}
        - name: cd /srv/elife-metrics/ && ./clear-expired-requests-cache.sh
        - identifier: rm-expired-cache-entries
        - special: "@weekly"

logrotate-metrics-logs:
    file.managed:
        - name: /etc/logrotate.d/elife-metrics
        - source: salt://elife-metrics/config/etc-logrotate.d-elife-metrics
        - template: jinja
