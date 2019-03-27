elife_metrics:
    name: elife-metrics
    install_path: /srv/elife-metrics

    secret: "dev.settings.do.not.use.in.prod.ever"

    ga_table_id: 12345678

    scopus:
        api_key: 12345567

    crossref:
        user: username
        pass: password

    sns:
        name: bus-metrics
        subscriber: null
        region: us-east-1

    aws:
        access_key_id: null
        secret_access_key: null
        region: us-east-1

    # credentials provided by Google to access API via oauth
    # https://developers.google.com/api-client-library/python/auth/api-keys
    # https://developers.google.com/api-client-library/python/guide/aaa_client_secrets
    client_secrets:
        private_key_id: foo
        private_key: baz
        client_id: bar
        client_email: bup
        type: service_account

elife:
    db:
        app:
            name: metrics

    # systemd/16.04+ only
    uwsgi:
        services:
            elife-metrics:
                folder: /srv/elife-metrics
