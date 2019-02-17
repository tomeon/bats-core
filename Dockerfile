ARG bashver=latest

FROM bash:${bashver}

RUN apk add -U --no-cache perl python ruby

RUN ln -s /opt/bats/bin/bats /usr/sbin/bats

COPY . /opt/bats/

ENTRYPOINT ["bash", "/usr/sbin/bats"]
