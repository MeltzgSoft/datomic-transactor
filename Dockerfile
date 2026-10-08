# syntax=docker/dockerfile:1
FROM alpine:latest AS unzipper

RUN apk add unzip curl && \
  mkdir -p /opt/ && \
  curl -fSL --create-dirs --output-dir /opt -O https://datomic-pro-downloads.s3.amazonaws.com/1.0.7705/datomic-pro-1.0.7705.zip && \
  DATOMIC_ZIP=$(ls -1 /opt | grep -m1 '\.zip$') && \
  unzip /opt/$DATOMIC_ZIP -d /opt && \
  rm /opt/$DATOMIC_ZIP && \
  mv /opt/$(ls -1 /opt | grep -m1 '^datomic') /opt/datomic

FROM clojure:tools-deps

RUN apt-get update && \
  apt-get install -y --no-install-recommends gettext-base postgresql-client && \
  rm -rf /var/lib/apt/lists/*

COPY --from=unzipper /opt/datomic /opt/datomic
WORKDIR /opt/datomic

COPY transactor.properties.template /opt/datomic/transactor.properties.template
COPY entrypoint.sh /entrypoint.sh

EXPOSE 4334
ENTRYPOINT ["/entrypoint.sh"]
