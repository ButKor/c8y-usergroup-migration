FROM ghcr.io/reubenmiller/c8y-shell
COPY devices_role_migration.sh /script.sh
USER root
RUN chmod +x /script.sh
USER c8yuser
ENTRYPOINT ["/script.sh"]