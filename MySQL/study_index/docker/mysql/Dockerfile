FROM mysql:8.4

ENV MYSQL_DATABASE=study_index \
    MYSQL_USER=study_index_user \
    MYSQL_PASSWORD=study_index_pass \
    MYSQL_ROOT_PASSWORD=root_password

COPY init.sql /docker-entrypoint-initdb.d/