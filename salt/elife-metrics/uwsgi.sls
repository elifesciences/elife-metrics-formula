elife-metrics-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/elife-metrics.conf
        - template: jinja
        - source: salt://elife-metrics/config/etc-nginx-sitesenabled-elife-metrics.conf
        - require:
            - pkg: nginx-server
{% if salt['elife.cfg']('cfn.outputs.DomainName') %}
            - cmd: web-ssl-enabled
{% endif %}

# we used to redirect all traffic to https but don't anymore
# now we simply block all external traffic on port 80
remove-unencrypted-redirect:
    file.absent:
        - name: /etc/nginx/sites-enabled/unencrypted-redirect.conf

elife-metrics-uwsgi-conf:
    file.managed:
        - name: /srv/elife-metrics/uwsgi.ini
        - source: salt://elife-metrics/config/srv-elife-metrics-uwsgi.ini
        - template: jinja
        - require:
            - install-elife-metrics

uwsgi-elife-metrics:
    file.managed:
        - name: /etc/init/uwsgi-elife-metrics.conf
        - source: salt://elife-metrics/config/etc-init-uwsgi-elife-metrics.conf
        - template: jinja
        - mode: 755

    service.running:
        - enable: True
        - require:
            - file: uwsgi-params
            - pip: uwsgi-pkg
            - file: uwsgi-elife-metrics
            - file: elife-metrics-uwsgi-conf
            - file: elife-metrics-nginx-conf
            - file: elife-metrics-log-file
        - watch:
            - install-elife-metrics
            - service: nginx-server-service
