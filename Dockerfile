ARG MONGO_TAG=4.2
FROM mongo:$MONGO_TAG
RUN mkhomedir_helper mongodb
COPY ./docker-entrypoint-initdb.d/ /docker-entrypoint-initdb.d/
