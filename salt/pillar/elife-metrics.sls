elife_metrics:
    name: elife-metrics
    install_path: /srv/elife-metrics
    
    db:
        name: metrics
        username: dummy
        password: dummy
        host: 127.0.0.1
        port: 5432
        
    secret: "dev.settings.do.not.use.in.prod.ever"
    ga_table_id: 12345678
    scopus:
        api_key: 12345567
    crossref:
        user: username
        pass: password

    # credentials provided by Google to access API via oauth
    # https://developers.google.com/api-client-library/python/auth/api-keys
    # https://developers.google.com/api-client-library/python/guide/aaa_client_secrets
    client_secrets:
        private_key_id: foo
        private_key: baz
        client_id: bar
        client_email: bup
        type: service_account
