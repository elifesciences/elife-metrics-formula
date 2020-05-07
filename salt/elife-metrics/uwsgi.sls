elife-metrics-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/elife-metrics.conf
        - template: jinja
        - source: salt://elife-metrics/config/etc-nginx-sitesenabled-elife-metrics.conf
        - require:
            - pkg: nginx-server
            - cmd: web-ssl-enabled
            - uwsgi-params # builder-base.uwsgi-params
        - watch_in:
            - nginx-server-service

elife-metrics-uwsgi-conf:
    file.managed:
        - name: /srv/elife-metrics/uwsgi.ini
        - source: salt://elife-metrics/config/srv-elife-metrics-uwsgi.ini
        - template: jinja
        - require:
            - install-elife-metrics

uwsgi-elife-metrics.socket:
    service.running:
        - enable: True
        - require_in:
            - uwsgi-elife-metrics

uwsgi-elife-metrics:
    service.running:
        - enable: True
        - require:
            - file: uwsgi-params
            - uwsgi-pkg
            - file: elife-metrics-uwsgi-conf
            - file: elife-metrics-nginx-conf
            - file: elife-metrics-log-file
            - file: elife-metrics-debugme-log-file
        - watch:
            - cfg-file
            - install-elife-metrics
            - service: nginx-server-service
