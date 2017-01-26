newrelic-license-configuration:
    cmd.run:
        - cwd: /srv/elife-metrics
        - name: venv/bin/newrelic-admin generate-config {{ pillar.elife.newrelic.license }} newrelic.ini
        - user: {{ pillar.elife.deploy_user.username }}
        - require: 
            - configure-elife-metrics

newrelic-ini-configuration-appname:
    file.replace:
        - name: /srv/elife-metrics/newrelic.ini
        - pattern: '^app_name.*'
        - repl: app_name = {{ salt['elife.cfg']('project.stackname', 'cfn.stack_id', 'Python application') }}
        - require:
            - newrelic-license-configuration
        - listen_in:
            - service: uwsgi-elife-metrics

# deprecated, remove when the file has been removed
newrelic-logfile-agent:
    file.absent:
        - name: /tmp/newrelic-python-agent.log
        - require:
            - newrelic-license-configuration

newrelic-logfile-agent-in-ini-configuration:
    file.replace:
        - name: /srv/elife-metrics/newrelic.ini
        - pattern: '^#?log_file.*'
        - repl: log_file = stderr
        - require:
            - newrelic-license-configuration
            - newrelic-logfile-agent
        - listen_in:
            - service: uwsgi-elife-metrics
