{% set app = pillar.elife_metrics %}

{{ app.name }}-nginx-conf:
    file.managed:
        - name: /etc/nginx/sites-enabled/{{ app.name }}.conf
        - template: jinja
{% if pillar.elife.dev %}
        - source: salt://{{ app.name }}/config/etc-nginx-sitesavailable-{{ app.name }}-http.conf
{% else %}
        - source: salt://{{ app.name }}/config/etc-nginx-sitesavailable-{{ app.name }}-https.conf
        - require:
            - cmd: acme-fetch-certs
{% endif %}

{{ app.name }}-uwsgi-conf:
    file.managed:
        - name: {{ app.install_path }}/uwsgi.ini
        - source: salt://{{ app.name }}/config/srv-{{ app.name }}-uwsgi.ini
        - template: jinja
        - require:
            - git: install-{{ app.name }}

{{ app.name }}-uwsgi-service:
    file.managed:
        - name: /etc/init.d/uwsgi-{{ app.name }}
        - source: salt://{{ app.name }}/config/etc-init.d-uwsgi-{{ app.name }}
        - template: jinja
        - mode: 755

    service.running:
        - name: uwsgi-{{ app.name }}
        - enable: True
        - require:
            - file: uwsgi-params
            - pip: uwsgi-pkg
            
            - file: {{ app.name }}-uwsgi-service
            - file: {{ app.name }}-uwsgi-conf
            - file: {{ app.name }}-nginx-conf
            - file: {{ app.name }}-log-file

        - watch:
            - git: install-{{ app.name }}
            # restart uwsgi if nginx service changes 
            - service: nginx-server-service
